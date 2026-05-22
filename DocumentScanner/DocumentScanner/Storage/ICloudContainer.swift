import Foundation

/// Resolves the URL to write documents into.
///
/// Primary: the app's iCloud Documents container (synced, visible in Files.app).
/// Fallback: the app's local Documents directory (when the user is signed out of iCloud
/// or the device is offline at first launch). A later plan adds migration of local files
/// to iCloud when it becomes available.
struct ICloudContainer {
    var iCloudURLProvider: () -> URL?
    var localDocumentsURL: URL

    init(
        iCloudURLProvider: @escaping () -> URL? = ICloudContainer.defaultICloudURLProvider,
        localDocumentsURL: URL = ICloudContainer.defaultLocalDocumentsURL
    ) {
        self.iCloudURLProvider = iCloudURLProvider
        self.localDocumentsURL = localDocumentsURL
    }

    func resolveDocumentsURL() -> URL {
        iCloudURLProvider() ?? localDocumentsURL
    }

    var isICloudAvailable: Bool { iCloudURLProvider() != nil }

    // MARK: - Defaults

    private static var defaultICloudURLProvider: () -> URL? {
        {
            FileManager.default
                .url(forUbiquityContainerIdentifier: nil)?
                .appendingPathComponent("Documents", isDirectory: true)
        }
    }

    private static var defaultLocalDocumentsURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
    }
}
