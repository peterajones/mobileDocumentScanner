import AVFoundation

/// Lightweight wrapper around AVFoundation's camera authorization API.
struct CameraPermission {

    enum Status { case authorized, denied, notDetermined }

    /// Synchronous current status. Use this when deciding which UI to show.
    static var current: Status {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    /// Trigger the system permission prompt when status is .notDetermined.
    /// Returns the resulting status. Has no effect if status is already
    /// .authorized or .denied.
    static func request() async -> Status {
        if current != .notDetermined { return current }
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return current
    }
}
