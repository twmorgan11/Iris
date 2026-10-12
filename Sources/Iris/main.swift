import AppKit
import SwiftUI

// A plain AppKit entry point: SwiftUI's App lifecycle requires a scene, and its placeholder
// Settings window would open whenever the app was relaunched or reopened.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(store: CameraStore())
        // `--open` shows the menu at launch, for checking placement.
        if CommandLine.arguments.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.menuBar?.toggle() }
        }
    }
}

/// `Iris --probe [--set id=value ...]` prints each camera's controls, optionally after setting some.
func probe() {
    let assignments = zip(CommandLine.arguments, CommandLine.arguments.dropFirst())
        .filter { $0.0 == "--set" }
        .compactMap { pair -> (String, Int)? in
            let parts = pair.1.split(separator: "=")
            guard parts.count == 2, let value = Int(parts[1]) else { return nil }
            return (String(parts[0]), value)
        }
    for camera in CameraInfo.attached() {
        print("\(camera.name)  \(camera.captureDeviceID)")
        guard let device = UVCDevice(locationID: camera.locationID) else { print("  could not open"); continue }
        for (id, value) in assignments {
            guard let spec = ControlSpec.all.first(where: { $0.id == id }) else { continue }
            print("  set \(id) = \(value): \(device.set(spec, value) ? "ok" : "failed")")
        }
        for spec in ControlSpec.all {
            let values = [UVCRequest.getCur, .getMin, .getMax, .getDef, .getRes].map { device.get($0, spec).map(String.init) ?? "-" }
            print("  \(spec.id.padding(toLength: 18, withPad: " ", startingAt: 0)) cur \(values[0])  min \(values[1])  max \(values[2])  def \(values[3])  res \(values[4])")
        }
    }
}

/// `Iris --snapshot <path> [--light]` renders the menu offscreen to a PNG, for checking the design.
@MainActor
func snapshot(to path: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let store = CameraStore()
    let host = NSHostingView(rootView: ContentView().environmentObject(store))
    let window = NSWindow(contentRect: NSRect(x: -4000, y: 0, width: 320, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.appearance = NSAppearance(named: CommandLine.arguments.contains("--light") ? .aqua : .darkAqua)
    window.backgroundColor = CommandLine.arguments.contains("--light")
        ? NSColor(red: 0.74, green: 0.87, blue: 0.98, alpha: 1)
        : NSColor(white: 0.16, alpha: 1)
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    window.setContentSize(host.fittingSize)
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

let arguments = CommandLine.arguments
MainActor.assumeIsolated {
    if arguments.contains("--probe") {
        probe()
    } else if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
        snapshot(to: arguments[index + 1])
    } else {
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.run()
    }
}
