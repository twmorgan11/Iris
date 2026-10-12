import AppKit
import SwiftUI

/// Owns the status item and the Liquid Glass panel it opens.
///
/// SwiftUI's `MenuBarExtra` window uses an older material and corner radius, so we host the
/// menu ourselves in an `NSGlassEffectView` to match the system's own menu bar panels.
@MainActor
final class MenuBarController: NSObject {
    /// Measured from Control Center's Video Effects panel.
    nonisolated static let cornerRadius: CGFloat = 18
    /// Gap between the menu bar and the top of the panel.
    private static let gap: CGFloat = 6

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let hosting: NSHostingController<AnyView>
    private let panel: MenuPanel
    private var monitors: [Any] = []
    private var sizeObservation: NSKeyValueObservation?

    init(store: CameraStore) {
        hosting = NSHostingController(rootView: AnyView(ContentView().environmentObject(store)))
        hosting.sizingOptions = .preferredContentSize
        panel = MenuPanel(content: hosting.view, cornerRadius: Self.cornerRadius)
        super.init()

        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
            button.target = self
            button.action = #selector(toggle)
        }

        sizeObservation = hosting.observe(\.preferredContentSize) { [weak self] _, _ in
            Task { @MainActor in self?.resizeKeepingTop() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(close),
                                               name: NSApplication.didResignActiveNotification, object: nil)
    }

    @objc func toggle() {
        panel.isVisible ? close() : show()
    }

    private func show() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = hosting.view.fittingSize
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero

        // Like the system's menus: left edge under the item, nudged in if it would run off screen.
        let x = min(anchor.minX, visible.maxX - size.width - Self.gap)
        // The status item's window spans the menu bar, so its bottom is the menu bar's.
        let top = buttonWindow.frame.minY - Self.gap
        panel.setGlassFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height))

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)

        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.close() }
            },
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }  // Escape
                self?.close()
                return nil
            },
            // Clicks on the shadow around the glass land in our window but are outside the menu.
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, event.window === panel, !panel.glassFrame.contains(NSEvent.mouseLocation) else { return event }
                close()
                return nil
            },
        ].compactMap { $0 }
    }

    @objc private func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    /// Grows or shrinks downward from the menu bar as content changes (e.g. toggling the preview).
    private func resizeKeepingTop() {
        guard panel.isVisible else { return }
        let size = hosting.view.fittingSize
        let frame = panel.glassFrame
        guard size != frame.size else { return }
        panel.setGlassFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height))
    }
}

/// A borderless panel showing its content on Liquid Glass.
///
/// Borderless windows get a rectangular system shadow and rim, which shows past rounded
/// corners. So the window's shadow is off, the glass is inset within a transparent window,
/// and a shadow matching the glass's shape is drawn in the margin around it.
final class MenuPanel: NSPanel {
    /// Room for the shadow. Kept small at the top so the window barely overlaps the menu bar.
    private static let margins = NSEdgeInsets(top: 8, left: 24, bottom: 32, right: 24)

    init(content: NSView, cornerRadius: CGFloat) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        contentView = ShadowedGlassView(content: content, cornerRadius: cornerRadius, margins: Self.margins)
    }

    override var canBecomeKey: Bool { true }

    /// The visible menu, in screen coordinates.
    var glassFrame: NSRect {
        let m = Self.margins
        return NSRect(x: frame.minX + m.left, y: frame.minY + m.bottom,
                      width: frame.width - m.left - m.right, height: frame.height - m.top - m.bottom)
    }

    func setGlassFrame(_ rect: NSRect) {
        let m = Self.margins
        setFrame(NSRect(x: rect.minX - m.left, y: rect.minY - m.bottom,
                        width: rect.width + m.left + m.right, height: rect.height + m.top + m.bottom), display: true)
    }
}

private final class ShadowedGlassView: NSView {
    private let glass: NSView
    private let shadowLayer = CALayer()
    private let shadowMask = CAShapeLayer()
    private let cornerRadius: CGFloat
    private let margins: NSEdgeInsets

    init(content: NSView, cornerRadius: CGFloat, margins: NSEdgeInsets) {
        self.cornerRadius = cornerRadius
        self.margins = margins
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            self.glass = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .menu
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = cornerRadius
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            effect.addSubview(content)
            self.glass = effect
        }
        super.init(frame: .zero)
        wantsLayer = true

        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.2
        shadowLayer.shadowRadius = 12
        shadowLayer.shadowOffset = CGSize(width: 0, height: -5)
        // Only draw outside the glass, so the glass doesn't pick up its own shadow.
        shadowMask.fillRule = .evenOdd
        shadowLayer.mask = shadowMask
        layer?.addSublayer(shadowLayer)
        addSubview(glass)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let rect = NSRect(x: margins.left, y: margins.bottom,
                          width: bounds.width - margins.left - margins.right,
                          height: bounds.height - margins.top - margins.bottom)
        glass.frame = rect
        if let content = (glass as? NSVisualEffectView)?.subviews.first { content.frame = glass.bounds }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        let mask = CGMutablePath()
        mask.addRect(bounds)
        mask.addPath(CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerWidth: cornerRadius - 1, cornerHeight: cornerRadius - 1, transform: nil))
        shadowMask.path = mask
        CATransaction.commit()
    }
}
