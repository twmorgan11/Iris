import Foundation

enum ControlKind {
    case slider(scale: SliderScale, format: ValueFormat)
    /// An auto/manual switch. `offValue` is the raw value meaning "manual".
    case toggle(offValue: Int)
    case choice(labels: [String])
}

enum SliderScale { case linear, logarithmic }
enum ValueFormat { case percent, kelvin, shutter, zoom }

struct ControlSpec: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let unit: UVCUnit
    let selector: UInt8
    let size: Int
    var signed = false
    let kind: ControlKind
    /// The toggle that, when on, puts this control under automatic control.
    var autoID: String?
}

extension ControlSpec {
    // Processing unit
    static let brightness = ControlSpec(id: "brightness", title: "Brightness", symbol: "sun.max", unit: .processing,
                                        selector: 0x02, size: 2, signed: true, kind: .slider(scale: .linear, format: .percent))
    static let contrast = ControlSpec(id: "contrast", title: "Contrast", symbol: "circle.lefthalf.filled", unit: .processing,
                                      selector: 0x03, size: 2, kind: .slider(scale: .linear, format: .percent))
    static let saturation = ControlSpec(id: "saturation", title: "Saturation", symbol: "drop", unit: .processing,
                                        selector: 0x07, size: 2, kind: .slider(scale: .linear, format: .percent))
    static let sharpness = ControlSpec(id: "sharpness", title: "Sharpness", symbol: "triangle", unit: .processing,
                                       selector: 0x08, size: 2, kind: .slider(scale: .linear, format: .percent))
    static let gain = ControlSpec(id: "gain", title: "Gain", symbol: "plus.forwardslash.minus", unit: .processing,
                                  selector: 0x04, size: 2, kind: .slider(scale: .linear, format: .percent))
    static let backlight = ControlSpec(id: "backlight", title: "Backlight", symbol: "person.and.background.dotted", unit: .processing,
                                       selector: 0x01, size: 2, kind: .slider(scale: .linear, format: .percent))
    static let whiteBalanceAuto = ControlSpec(id: "whiteBalanceAuto", title: "Auto", symbol: "", unit: .processing,
                                              selector: 0x0B, size: 1, kind: .toggle(offValue: 0))
    static let whiteBalance = ControlSpec(id: "whiteBalance", title: "Temperature", symbol: "thermometer.medium", unit: .processing,
                                          selector: 0x0A, size: 2, kind: .slider(scale: .linear, format: .kelvin),
                                          autoID: "whiteBalanceAuto")
    static let powerLine = ControlSpec(id: "powerLine", title: "Anti-flicker", symbol: "lightbulb", unit: .processing,
                                       selector: 0x05, size: 1, kind: .choice(labels: ["Off", "50 Hz", "60 Hz", "Auto"]))

    // Camera terminal
    static let exposureAuto = ControlSpec(id: "exposureAuto", title: "Auto", symbol: "", unit: .camera,
                                          selector: 0x02, size: 1, kind: .toggle(offValue: 1))
    static let exposure = ControlSpec(id: "exposure", title: "Shutter", symbol: "camera.aperture", unit: .camera,
                                      selector: 0x04, size: 4, kind: .slider(scale: .logarithmic, format: .shutter),
                                      autoID: "exposureAuto")
    static let focusAuto = ControlSpec(id: "focusAuto", title: "Auto", symbol: "", unit: .camera,
                                       selector: 0x08, size: 1, kind: .toggle(offValue: 0))
    static let focus = ControlSpec(id: "focus", title: "Distance", symbol: "scope", unit: .camera,
                                   selector: 0x06, size: 2, kind: .slider(scale: .linear, format: .percent),
                                   autoID: "focusAuto")
    static let zoom = ControlSpec(id: "zoom", title: "Zoom", symbol: "plus.magnifyingglass", unit: .camera,
                                  selector: 0x0B, size: 2, kind: .slider(scale: .linear, format: .zoom))

    /// Toggles come first so that restoring manual values isn't overridden by auto modes.
    static let all: [ControlSpec] = [
        .whiteBalanceAuto, .exposureAuto, .focusAuto,
        .brightness, .contrast, .saturation, .sharpness, .gain, .backlight,
        .whiteBalance, .exposure, .focus, .zoom, .powerLine,
    ]
}

struct ControlState {
    let spec: ControlSpec
    var value: Int
    var min: Int
    var max: Int
    var defaultValue: Int
    var resolution: Int

    // MARK: Toggles

    var isOn: Bool {
        guard case .toggle(let off) = spec.kind else { return false }
        return value != off
    }

    /// Raw value that switches this control to automatic.
    var onValue: Int {
        guard case .toggle(let off) = spec.kind else { return value }
        if spec.id == ControlSpec.exposureAuto.id {
            // GET_RES is a bitmap of supported modes: 8 = aperture priority, 2 = full auto.
            if resolution & 0x08 != 0 { return 0x08 }
            if resolution & 0x02 != 0 { return 0x02 }
        }
        return defaultValue != off ? defaultValue : 1
    }

    // MARK: Sliders

    private var span: Double { Double(Swift.max(max - min, 1)) }

    private var scale: SliderScale {
        if case .slider(let scale, _) = spec.kind { return scale }
        return .linear
    }

    var normalized: Double {
        let offset = Double(value - min)
        switch scale {
        case .linear: return offset / span
        case .logarithmic: return log1p(offset) / log1p(span)
        }
    }

    func value(fromNormalized n: Double) -> Int {
        let offset: Double
        switch scale {
        case .linear: offset = n * span
        case .logarithmic: offset = expm1(n * log1p(span))
        }
        let step = Double(Swift.max(resolution, 1))
        let snapped = min + Int((offset / step).rounded() * step)
        return Swift.min(Swift.max(snapped, min), max)
    }

    var formatted: String {
        guard case .slider(_, let format) = spec.kind else { return "" }
        switch format {
        case .percent:
            return "\(Int((Double(value - min) / span * 100).rounded()))%"
        case .kelvin:
            return "\(value)K"
        case .shutter:
            // Units of 100 µs.
            let seconds = Double(value) / 10_000
            if seconds >= 1 { return String(format: "%.1fs", seconds) }
            return "1/\(Int((1 / seconds).rounded()))"
        case .zoom:
            guard min > 0 else { return "\(Int((Double(value - min) / span * 100).rounded()))%" }
            return String(format: "%.1f×", Double(value) / Double(min))
        }
    }
}
