import Foundation
import Observation
import SwiftUI

/// Thin presenter for user-facing alerts. A single instance lives at the
/// app root and is bound by a `.alert` modifier. Any view or service that
/// needs to surface an error reaches it via `@Environment` or by passing
/// it explicitly.
@MainActor
@Observable
final class AlertCenter {
    private(set) var current: AppAlert?

    /// Allocation is pure and main-actor-free; `nonisolated init` lets the
    /// EnvironmentKey default value below initialize one without crossing
    /// actor isolation. All mutating operations still run on the main actor.
    nonisolated init() {}

    func present(_ alert: AppAlert) { current = alert }
    func dismiss() { current = nil }
}

private struct AlertCenterKey: EnvironmentKey {
    static let defaultValue = AlertCenter()
}

extension EnvironmentValues {
    var alertCenter: AlertCenter {
        get { self[AlertCenterKey.self] }
        set { self[AlertCenterKey.self] = newValue }
    }
}
