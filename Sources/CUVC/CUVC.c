#include "CUVC.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

typedef IOUSBDeviceInterface182 **DeviceInterface;

struct UVCDevice {
    DeviceInterface dev;
    uint8_t vcInterface;
    uint8_t cameraTerminalID;
    uint8_t processingUnitID;
};

// MARK: - Registry helpers

static bool read_number(io_registry_entry_t entry, const char *key, int64_t *out) {
    CFStringRef cfKey = CFStringCreateWithCString(kCFAllocatorDefault, key, kCFStringEncodingUTF8);
    CFTypeRef value = IORegistryEntryCreateCFProperty(entry, cfKey, kCFAllocatorDefault, 0);
    CFRelease(cfKey);
    if (!value) return false;
    bool ok = CFGetTypeID(value) == CFNumberGetTypeID() &&
              CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, out);
    CFRelease(value);
    return ok;
}

static bool read_string(io_registry_entry_t entry, const char *key, char *out, size_t len) {
    CFStringRef cfKey = CFStringCreateWithCString(kCFAllocatorDefault, key, kCFStringEncodingUTF8);
    CFTypeRef value = IORegistryEntryCreateCFProperty(entry, cfKey, kCFAllocatorDefault, 0);
    CFRelease(cfKey);
    if (!value) return false;
    bool ok = CFGetTypeID(value) == CFStringGetTypeID() &&
              CFStringGetCString((CFStringRef)value, out, (CFIndex)len, kCFStringEncodingUTF8);
    CFRelease(value);
    return ok;
}

// MARK: - Enumeration

int uvc_list_devices(UVCDeviceInfo *out, int max) {
    // Match Video Control interfaces (class 14, subclass 1) and walk up to their device.
    io_iterator_t iter;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostInterface"), &iter) != KERN_SUCCESS)
        return 0;

    int count = 0;
    io_service_t iface;
    while ((iface = IOIteratorNext(iter))) {
        int64_t cls = 0, sub = 0;
        if (count < max && read_number(iface, "bInterfaceClass", &cls) && cls == 0x0E &&
            read_number(iface, "bInterfaceSubClass", &sub) && sub == 0x01) {
            io_registry_entry_t device;
            if (IORegistryEntryGetParentEntry(iface, kIOServicePlane, &device) == KERN_SUCCESS) {
                int64_t loc = 0, vid = 0, pid = 0;
                read_number(device, "locationID", &loc);
                read_number(device, "idVendor", &vid);
                read_number(device, "idProduct", &pid);

                bool duplicate = false;
                for (int i = 0; i < count; i++)
                    if (out[i].locationID == (uint32_t)loc) duplicate = true;

                if (!duplicate) {
                    UVCDeviceInfo *info = &out[count++];
                    memset(info, 0, sizeof(*info));
                    info->locationID = (uint32_t)loc;
                    info->vendorID = (uint16_t)vid;
                    info->productID = (uint16_t)pid;
                    if (!read_string(device, "USB Product Name", info->name, sizeof(info->name)) &&
                        !read_string(device, "kUSBProductString", info->name, sizeof(info->name)))
                        strlcpy(info->name, "USB Camera", sizeof(info->name));
                }
                IOObjectRelease(device);
            }
        }
        IOObjectRelease(iface);
    }
    IOObjectRelease(iter);
    return count;
}

// MARK: - Device access

static DeviceInterface create_device_interface(io_service_t service) {
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    if (IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID,
                                          &plugin, &score) != KERN_SUCCESS || !plugin)
        return NULL;
    DeviceInterface dev = NULL;
    HRESULT result = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID182),
                                               (LPVOID *)&dev);
    IODestroyPlugInInterface(plugin);
    return result == S_OK ? dev : NULL;
}

static int device_request(DeviceInterface dev, uint8_t type, uint8_t request, uint16_t value,
                          uint16_t index, void *data, uint16_t length, uint32_t *transferred) {
    IOUSBDevRequestTO req = {
        .bmRequestType = type,
        .bRequest = request,
        .wValue = value,
        .wIndex = index,
        .wLength = length,
        .pData = data,
        .noDataTimeout = 500,
        .completionTimeout = 1000,
    };
    IOReturn kr = (*dev)->DeviceRequestTO(dev, &req);
    if (transferred) *transferred = req.wLenDone;
    return kr == kIOReturnSuccess ? 0 : (int)kr;
}

/// Reads the configuration descriptor to find the Video Control interface,
/// camera terminal and processing unit IDs.
static bool parse_descriptors(UVCDevice *d) {
    uint8_t header[9];
    uint32_t got = 0;
    if (device_request(d->dev, 0x80, 0x06, 0x0200, 0, header, sizeof(header), &got) != 0 || got < 9)
        return false;

    uint16_t total = (uint16_t)(header[2] | (header[3] << 8));
    uint8_t *buf = malloc(total);
    if (!buf) return false;
    if (device_request(d->dev, 0x80, 0x06, 0x0200, 0, buf, total, &got) != 0) {
        free(buf);
        return false;
    }

    bool inVideoControl = false, found = false;
    for (uint32_t i = 0; i + 2 <= got;) {
        uint8_t len = buf[i], type = buf[i + 1];
        if (len < 2 || i + len > got) break;

        if (type == 0x04 && len >= 9) {  // INTERFACE
            inVideoControl = buf[i + 5] == 0x0E && buf[i + 6] == 0x01;
            if (inVideoControl && !found) {
                d->vcInterface = buf[i + 2];
                found = true;
            }
        } else if (type == 0x24 && inVideoControl && len >= 4) {  // CS_INTERFACE
            uint8_t subtype = buf[i + 2];
            if (subtype == 0x02 && len >= 8) {  // INPUT_TERMINAL
                uint16_t terminalType = (uint16_t)(buf[i + 4] | (buf[i + 5] << 8));
                if (terminalType == 0x0201 && !d->cameraTerminalID) d->cameraTerminalID = buf[i + 3];
            } else if (subtype == 0x05 && !d->processingUnitID) {  // PROCESSING_UNIT
                d->processingUnitID = buf[i + 3];
            }
        }
        i += len;
    }
    free(buf);
    return found;
}

UVCDevice *uvc_open(uint32_t locationID) {
    io_iterator_t iter;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iter) != KERN_SUCCESS)
        return NULL;

    UVCDevice *result = NULL;
    io_service_t service;
    while ((service = IOIteratorNext(iter))) {
        int64_t loc = 0;
        if (!result && read_number(service, "locationID", &loc) && (uint32_t)loc == locationID) {
            DeviceInterface dev = create_device_interface(service);
            if (dev) {
                UVCDevice *d = calloc(1, sizeof(UVCDevice));
                d->dev = dev;
                if (parse_descriptors(d)) {
                    result = d;
                } else {
                    (*dev)->Release(dev);
                    free(d);
                }
            }
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iter);
    return result;
}

void uvc_close(UVCDevice *d) {
    if (!d) return;
    (*d->dev)->Release(d->dev);
    free(d);
}

int uvc_control(UVCDevice *d, int unit, uint8_t request, uint8_t selector, uint8_t *data, uint16_t length) {
    uint8_t unitID = unit == UVC_UNIT_CAMERA_TERMINAL ? d->cameraTerminalID : d->processingUnitID;
    if (!unitID) return -1;
    uint8_t type = (request & 0x80) ? 0xA1 : 0x21;  // class | interface, IN or OUT
    return device_request(d->dev, type, request, (uint16_t)(selector << 8),
                          (uint16_t)((unitID << 8) | d->vcInterface), data, length, NULL);
}
