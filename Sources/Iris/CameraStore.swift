import Foundation
import SwiftUI

@MainActor
final class CameraStore: ObservableObject {
    @Published private(set) var cameras: [CameraInfo] = []
    @Published private(set) var selected: CameraInfo?
    @Published private(set) var controls: [String: ControlState] = [:]
    @Published private(set) var isLoading = false

    private var device: UVCDevice?
    private let io = DispatchQueue(label: "iris.uvc", qos: .userInitiated)
    private var seenLocations: Set<UInt32> = []
    private var pollTimer: Timer?

    init() {
        refreshCameras()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshCameras() }
        }
    }

    // MARK: Cameras

    func refreshCameras() {
        let attached = CameraInfo.attached()
        let current = Set(attached.map(\.locationID))

        // Cameras forget their settings when unplugged; reapply saved ones on arrival.
        for camera in attached where !seenLocations.contains(camera.locationID) {
            restoreSavedSettings(on: camera)
        }
        seenLocations = current

        if attached != cameras { cameras = attached }
        if let selected, current.contains(selected.locationID) { return }
        select(attached.first)
    }

    func select(_ camera: CameraInfo?) {
        guard camera != selected || controls.isEmpty else { return }
        selected = camera
        controls = [:]
        guard let camera else { device = nil; return }

        isLoading = true
        io.async {
            let device = UVCDevice(locationID: camera.locationID)
            let states = device.map(Self.readControls) ?? [:]
            DispatchQueue.main.async {
                guard self.selected == camera else { return }
                self.device = device
                self.controls = states
                self.isLoading = false
            }
        }
    }

    /// Re-reads current values, e.g. when the menu opens.
    func reload() {
        guard let device, selected != nil else { return }
        io.async {
            let states = Self.readControls(device)
            DispatchQueue.main.async { if self.device === device { self.controls = states } }
        }
    }

    nonisolated private static func readControls(_ device: UVCDevice) -> [String: ControlState] {
        var states: [String: ControlState] = [:]
        for spec in ControlSpec.all {
            guard let cur = device.get(.getCur, spec) else { continue }
            let def = device.get(.getDef, spec) ?? cur
            let res = device.get(.getRes, spec) ?? 1
            let min, max: Int
            switch spec.kind {
            case .slider:
                guard let lo = device.get(.getMin, spec), let hi = device.get(.getMax, spec), hi > lo else { continue }
                (min, max) = (lo, hi)
            case .toggle:
                (min, max) = (0, 1)
            case .choice(let labels):
                min = device.get(.getMin, spec) ?? 0
                max = Swift.min(device.get(.getMax, spec) ?? labels.count - 1, labels.count - 1)
            }
            states[spec.id] = ControlState(spec: spec, value: cur, min: min, max: max, defaultValue: def, resolution: res)
        }
        return states
    }

    // MARK: Editing

    func setValue(_ value: Int, for id: String) {
        guard var state = controls[id], state.value != value, let device else { return }
        state.value = value
        controls[id] = state
        save()
        let spec = state.spec
        io.async { device.set(spec, value) }
    }

    func setAuto(_ on: Bool, for id: String) {
        guard let state = controls[id], case .toggle(let off) = state.spec.kind, let device else { return }
        setValue(on ? state.onValue : off, for: id)

        // Once manual, pick up whatever the camera had settled on.
        guard !on else { return }
        let dependents = controls.values.filter { $0.spec.autoID == id }.map(\.spec)
        io.async {
            let values = dependents.compactMap { spec in device.get(.getCur, spec).map { (spec.id, $0) } }
            DispatchQueue.main.async {
                for (id, value) in values { self.controls[id]?.value = value }
                self.save()
            }
        }
    }

    func resetAll() {
        guard let device, let selected else { return }
        let ordered = ControlSpec.all.compactMap { controls[$0.id] }
        for state in ordered { controls[state.spec.id]?.value = state.defaultValue }
        UserDefaults.standard.removeObject(forKey: selected.settingsKey)
        io.async { for state in ordered { device.set(state.spec, state.defaultValue) } }
    }

    // MARK: Persistence

    private func save() {
        guard let selected else { return }
        let values = controls.mapValues(\.value)
        UserDefaults.standard.set(values, forKey: selected.settingsKey)
    }

    private func restoreSavedSettings(on camera: CameraInfo) {
        guard let saved = UserDefaults.standard.dictionary(forKey: camera.settingsKey) as? [String: Int] else { return }
        let reuse = camera == selected ? device : nil
        io.async {
            guard let device = reuse ?? UVCDevice(locationID: camera.locationID) else { return }
            for spec in ControlSpec.all {
                guard let value = saved[spec.id] else { continue }
                if let autoID = spec.autoID, let auto = saved[autoID],
                   case .toggle(let off) = ControlSpec.all.first(where: { $0.id == autoID })?.kind, auto != off {
                    continue  // under automatic control; writing would be ignored or fight it
                }
                device.set(spec, value)
            }
        }
    }
}
