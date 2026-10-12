import CUVC
import Foundation

enum UVCRequest: UInt8 {
    case setCur = 0x01
    case getCur = 0x81
    case getMin = 0x82
    case getMax = 0x83
    case getRes = 0x84
    case getDef = 0x87
}

enum UVCUnit: Int32 {
    case camera = 0
    case processing = 1
}

struct CameraInfo: Identifiable, Hashable {
    let locationID: UInt32
    let vendorID: UInt16
    let productID: UInt16
    let name: String

    var id: UInt32 { locationID }

    /// Stable across ports, so saved settings follow the camera.
    var settingsKey: String { String(format: "camera.%04x:%04x", vendorID, productID) }

    /// AVFoundation's uniqueID for USB cameras: 0x<location><vid><pid>.
    var captureDeviceID: String { String(format: "0x%08x%04x%04x", locationID, vendorID, productID) }

    static func attached() -> [CameraInfo] {
        var buffer = [UVCDeviceInfo](repeating: UVCDeviceInfo(), count: 16)
        let count = Int(uvc_list_devices(&buffer, Int32(buffer.count)))
        return buffer.prefix(count).map { info in
            var info = info
            let name = withUnsafeBytes(of: &info.name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            return CameraInfo(locationID: info.locationID, vendorID: info.vendorID, productID: info.productID, name: name)
        }
        .sorted { $0.name < $1.name }
    }
}

/// An open UVC device. Not thread-safe; use from a single queue.
final class UVCDevice {
    private let handle: OpaquePointer

    init?(locationID: UInt32) {
        guard let handle = uvc_open(locationID) else { return nil }
        self.handle = handle
    }

    deinit { uvc_close(handle) }

    func get(_ request: UVCRequest, _ spec: ControlSpec) -> Int? {
        var bytes = [UInt8](repeating: 0, count: spec.size)
        guard uvc_control(handle, spec.unit.rawValue, request.rawValue, spec.selector, &bytes, UInt16(spec.size)) == 0
        else { return nil }
        let raw = bytes.enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
        guard spec.signed else { return raw }
        let shift = 64 - spec.size * 8
        return (raw << shift) >> shift
    }

    @discardableResult
    func set(_ spec: ControlSpec, _ value: Int) -> Bool {
        var bytes = (0..<spec.size).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
        return uvc_control(handle, spec.unit.rawValue, UVCRequest.setCur.rawValue, spec.selector, &bytes, UInt16(spec.size)) == 0
    }
}
