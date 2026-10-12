import AVFoundation
import SwiftUI

/// Live mirrored preview of the selected camera, so adjustments can be seen as they're made.
struct CameraPreview: NSViewRepresentable {
    let camera: CameraInfo

    func makeNSView(context: Context) -> PreviewView { PreviewView() }

    func updateNSView(_ view: PreviewView, context: Context) { view.show(camera) }

    static func dismantleNSView(_ view: PreviewView, coordinator: ()) { view.stop() }
}

final class PreviewView: NSView {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "iris.preview")
    private var currentID: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.backgroundColor = NSColor.black.cgColor
        layer = preview
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ camera: CameraInfo) {
        guard camera.captureDeviceID != currentID else { return }
        currentID = camera.captureDeviceID
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            self.sessionQueue.async { self.configure(for: camera) }
        }
    }

    func stop() {
        sessionQueue.async { self.session.stopRunning() }
    }

    private func configure(for camera: CameraInfo) {
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices
        let suffix = String(format: "%04x%04x", camera.vendorID, camera.productID)
        guard let device = devices.first(where: { $0.uniqueID.lowercased() == camera.captureDeviceID })
                ?? devices.first(where: { $0.uniqueID.lowercased().hasSuffix(suffix) }),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }

        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.sessionPreset = .medium
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()

        DispatchQueue.main.async {
            if let connection = (self.layer as? AVCaptureVideoPreviewLayer)?.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        if !session.isRunning { session.startRunning() }
    }
}
