#ifndef CUVC_H
#define CUVC_H

#include <stdint.h>

/// Minimal USB Video Class control bridge built on IOKit.

typedef struct UVCDevice UVCDevice;

typedef struct {
    uint32_t locationID;
    uint16_t vendorID;
    uint16_t productID;
    char name[128];
} UVCDeviceInfo;

/// Units addressable by uvc_control.
enum {
    UVC_UNIT_CAMERA_TERMINAL = 0,
    UVC_UNIT_PROCESSING = 1,
};

/// Fills `out` with up to `max` attached UVC cameras. Returns the count.
int uvc_list_devices(UVCDeviceInfo *out, int max);

/// Opens the UVC camera at the given USB location. Returns NULL on failure.
UVCDevice *uvc_open(uint32_t locationID);
void uvc_close(UVCDevice *device);

/// Issues a class-specific control request (SET_CUR, GET_CUR, GET_MIN, ...).
/// Returns 0 on success.
int uvc_control(UVCDevice *device, int unit, uint8_t request, uint8_t selector,
                uint8_t *data, uint16_t length);

#endif
