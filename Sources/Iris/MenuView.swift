import ServiceManagement
import SwiftUI

/// Metrics matching the system's menu bar windows (Control Center, Video Effects).
private enum Metrics {
    static let width: CGFloat = 320
    static let inset: CGFloat = 14
    static let iconColumn: CGFloat = 26
    static let iconSpacing: CGFloat = 10
    /// How far a row's hover highlight extends past its content.
    static let highlightOutset: CGFloat = 6
    static let panelRadius = MenuBarController.cornerRadius
    static let previewInset: CGFloat = 8
    /// Concentric with the panel, given rows sit `inset - highlightOutset` from its edge.
    static let highlightRadius = panelRadius - (inset - highlightOutset)
}

struct ContentView: View {
    @EnvironmentObject private var store: CameraStore
    @AppStorage("showPreview") private var showPreview = false
    @StateObject private var menu = Flag()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showPreview, menu.value, let camera = store.selected {
                // Inset so its corners stay concentric with the panel's.
                CameraPreview(camera: camera)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.panelRadius - Metrics.previewInset, style: .continuous))
                    .padding(Metrics.previewInset)
                    .transition(.opacity)
            }

            if store.selected == nil {
                EmptyState()
            } else if store.controls.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                cameraSection
                MenuDivider()
                imageSection
                if let powerLine = store.controls["powerLine"] {
                    MenuDivider()
                    ChoiceRow(state: powerLine) { store.setValue($0, for: "powerLine") }
                }
            }

            MenuDivider()
            actions
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(width: Metrics.width)
        .animation(.smooth(duration: 0.25), value: showPreview)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            menu.value = true
            store.refreshCameras()
            store.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            menu.value = false
        }
    }

    // MARK: Sections

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            cameraPicker
            ToggleRow(title: "Preview", symbol: "video", isOn: showPreview) { showPreview.toggle() }
            autoRow("exposureAuto", title: "Auto Exposure", symbol: "camera.aperture", manual: "exposure")
            autoRow("whiteBalanceAuto", title: "Auto White Balance", symbol: "thermometer.medium", manual: "whiteBalance")
            autoRow("focusAuto", title: "Autofocus", symbol: "scope", manual: "focus")
            if let backlight = store.controls["backlight"], backlight.isSwitch {
                ToggleRow(title: "Backlight Compensation", symbol: "person.and.background.dotted", isOn: backlight.value == backlight.max) {
                    store.setValue(backlight.value == backlight.max ? backlight.min : backlight.max, for: "backlight")
                }
            }
        }
    }

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Image")
            ForEach(["brightness", "contrast", "saturation", "sharpness", "gain", "backlight", "zoom"], id: \.self) { id in
                if let state = store.controls[id], !state.isSwitch {
                    SliderRow(state: state) { store.setValue($0, for: id) }
                }
            }
        }
    }

    @ViewBuilder
    private var cameraPicker: some View {
        let name = store.selected?.name ?? "No Camera"
        if store.cameras.count > 1 {
            Menu {
                ForEach(store.cameras) { camera in
                    Toggle(camera.name, isOn: Binding(get: { camera == store.selected }, set: { _ in store.select(camera) }))
                }
            } label: {
                HStack {
                    SectionHeader(title: name, padded: false)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .padding(.horizontal, Metrics.inset)
            .padding(.top, 6)
            .padding(.bottom, 4)
        } else {
            SectionHeader(title: name)
        }
    }

    /// An auto/manual switch; turning it off reveals the manual slider beneath.
    @ViewBuilder
    private func autoRow(_ id: String, title: String, symbol: String, manual: String) -> some View {
        if let auto = store.controls[id] {
            ToggleRow(title: title, symbol: symbol, isOn: auto.isOn) {
                withAnimation(.smooth(duration: 0.2)) { store.setAuto(!auto.isOn, for: id) }
            }
            if !auto.isOn, let state = store.controls[manual] {
                SliderRow(state: state, showsIcon: false) { store.setValue($0, for: manual) }
                    .transition(.opacity)
            }
        } else if let state = store.controls[manual] {
            SliderRow(state: state) { store.setValue($0, for: manual) }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuItemRow(title: "Reset to Defaults") { store.resetAll() }
                .disabled(store.controls.isEmpty)
            LaunchAtLoginRow()
            MenuItemRow(title: "Quit Iris") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

// MARK: - Rows

struct SectionHeader: View {
    let title: String
    var padded = true

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, padded ? Metrics.inset : 0)
            .padding(.top, padded ? 6 : 0)
            .padding(.bottom, padded ? 4 : 0)
    }
}

struct MenuDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, Metrics.inset)
            .padding(.vertical, 6)
    }
}

/// A clickable full-width row with the system menu hover highlight.
struct HighlightRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @StateObject private var hover = Flag()
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.highlightOutset)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: Metrics.highlightRadius, style: .continuous)
                        .fill(Color.primary.opacity(hover.value && isEnabled ? 0.08 : 0))
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Metrics.inset - Metrics.highlightOutset)
        .onHover { hover.value = $0 }
    }
}

/// Video Effects-style toggle: a circular glyph that fills when on.
struct ToggleRow: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        HighlightRow(action: action) {
            HStack(spacing: Metrics.iconSpacing) {
                ZStack {
                    Circle().fill(isOn ? Color.green : Color.primary.opacity(0.1))
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .frame(width: Metrics.iconColumn, height: Metrics.iconColumn)
                Text(title).font(.system(size: 13))
            }
            .padding(.vertical, 3)
        }
    }
}

struct SliderRow: View {
    let state: ControlState
    var showsIcon = true
    let onChange: (Int) -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        let canReset = hover.value && state.value != state.defaultValue
        HStack(spacing: Metrics.iconSpacing) {
            ZStack {
                if showsIcon {
                    Image(systemName: state.spec.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .opacity(canReset ? 0 : 1)
                }
                if canReset {
                    Button {
                        onChange(state.defaultValue)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tint)
                            .frame(width: Metrics.iconColumn, height: Metrics.iconColumn)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset to default")
                    .transition(.opacity)
                }
            }
            .frame(width: Metrics.iconColumn)

            Text(state.spec.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)

            Slider(value: Binding(get: { state.normalized }, set: { onChange(state.value(fromNormalized: $0)) }), in: 0...1)
                .controlSize(.mini)

            Text(state.formatted)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(height: 30)
        .padding(.horizontal, Metrics.inset)
        .animation(.easeOut(duration: 0.15), value: canReset)
        .onHover { hover.value = $0 }
    }
}

/// A row showing the current choice, opening a menu to change it (like "Mic Mode").
struct ChoiceRow: View {
    let state: ControlState
    let onChange: (Int) -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        if case .choice(let labels) = state.spec.kind {
            Menu {
                ForEach(state.min...state.max, id: \.self) { value in
                    Toggle(labels[value], isOn: Binding(get: { state.value == value }, set: { _ in onChange(value) }))
                }
            } label: {
                HStack(spacing: 6) {
                    Text(state.spec.title).font(.system(size: 13))
                    Spacer()
                    Text(labels.indices.contains(state.value) ? labels[state.value] : "")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 26)
                .padding(.horizontal, Metrics.highlightOutset)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: Metrics.highlightRadius, style: .continuous)
                        .fill(Color.primary.opacity(hover.value ? 0.08 : 0))
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .padding(.horizontal, Metrics.inset - Metrics.highlightOutset)
            .onHover { hover.value = $0 }
        }
    }
}

/// A plain text item, like the bottom of a standard menu.
struct MenuItemRow: View {
    let title: String
    var checked = false
    let action: () -> Void

    var body: some View {
        HighlightRow(action: action) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                if checked {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                }
            }
            .frame(height: 26)
        }
    }
}

struct LaunchAtLoginRow: View {
    @StateObject private var enabled = Flag(SMAppService.mainApp.status == .enabled)

    var body: some View {
        MenuItemRow(title: "Open at Login", checked: enabled.value) {
            do {
                if enabled.value { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
            } catch {
                NSLog("Iris: launch at login failed: \(error)")
            }
            enabled.value = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Misc

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("No USB Camera Connected")
                .font(.system(size: 13, weight: .medium))
            Text("Iris controls UVC webcams. Built-in cameras don't expose these settings.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.inset)
        .padding(.vertical, 16)
    }
}

extension ControlState {
    /// Two-valued controls (e.g. backlight compensation on many webcams) read better as switches.
    var isSwitch: Bool { max - min == 1 }
}

/// Local view state. Stands in for `@State`, whose macro plugin ships with Xcode but not the Command Line Tools.
final class Flag: ObservableObject {
    @Published var value: Bool
    init(_ value: Bool = false) { self.value = value }
}
