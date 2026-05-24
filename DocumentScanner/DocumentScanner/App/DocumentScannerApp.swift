import SwiftUI

@main
struct DocumentScannerApp: App {
    @State private var metadataStore = MetadataQueryLibraryStore()
    @State private var inMemoryStore = InMemoryLibraryStore()
    @State private var lockSettings = AppLockSettings()
    @State private var alertCenter = AlertCenter()
    @AppStorage("iCloudOnboardingDismissed") private var iCloudOnboardingDismissed = false

    private let container = ICloudContainer()
    private let pipeline = ScanPipeline()
    private let scannerPresenter: DocumentScannerPresenting =
        isUITesting ? StubDocumentScanner() : SystemDocumentScanner()
    private let testStorage: DocumentStorage = {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("uitests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return DocumentStorage(documentsURL: tmp)
    }()

    private static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestMode")
    }

    var body: some Scene {
        WindowGroup {
            if Self.isUITesting {
                // Hermetic wiring: no iCloud, no real scanner, no lock gate.
                LibraryView(
                    store: inMemoryStore,
                    scannerPresenter: scannerPresenter,
                    storage: testStorage,
                    pipeline: pipeline,
                    lockSettings: lockSettings
                )
                .environment(\.alertCenter, alertCenter)
            } else if !iCloudOnboardingDismissed && !container.isICloudAvailable {
                ICloudOnboardingView(onTryAnyway: { iCloudOnboardingDismissed = true })
                    .environment(\.alertCenter, alertCenter)
            } else {
                LockGate(lockSettings: lockSettings) {
                    PrivacyBlurOverlay {
                        LibraryView(
                            store: metadataStore,
                            scannerPresenter: scannerPresenter,
                            storage: DocumentStorage(documentsURL: container.resolveDocumentsURL()),
                            pipeline: pipeline,
                            lockSettings: lockSettings
                        )
                    }
                }
                .environment(\.alertCenter, alertCenter)
                .alert(item: Binding(
                    get: { alertCenter.current },
                    set: { _ in alertCenter.dismiss() }
                )) { alert in
                    appAlert(alert)
                }
            }
        }
    }

    @MainActor
    private func appAlert(_ alert: AppAlert) -> Alert {
        let primaryButton = button(from: alert.primary)
        if let secondary = alert.secondary {
            return Alert(title: Text(alert.title),
                         message: Text(alert.message),
                         primaryButton: primaryButton,
                         secondaryButton: button(from: secondary))
        }
        return Alert(title: Text(alert.title),
                     message: Text(alert.message),
                     dismissButton: primaryButton)
    }

    private func button(from action: AppAlert.Action) -> Alert.Button {
        switch action.role {
        case .cancel:
            return .cancel(Text(action.title)) { action.handler?() }
        case .destructive:
            return .destructive(Text(action.title)) { action.handler?() }
        case .default:
            return .default(Text(action.title)) { action.handler?() }
        }
    }
}
