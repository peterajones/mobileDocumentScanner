import Foundation
import Observation

@MainActor
@Observable
final class MetadataQueryLibraryStore: NSObject, LibraryStoring {
    private(set) var summaries: [DocumentSummary] = []

    private let query: NSMetadataQuery = {
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K LIKE '*.pdf'", NSMetadataItemFSNameKey)
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey, ascending: false)]
        return q
    }()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidFinishGathering, object: query
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate, object: query
        )
        query.start()
    }

    deinit {
        query.stop()
        NotificationCenter.default.removeObserver(self)
    }

    func refresh() {
        query.disableUpdates()
        query.enableUpdates()
    }

    @objc private func queryDidUpdate(_ note: Notification) {
        query.disableUpdates()
        defer { query.enableUpdates() }

        let items = (query.results as? [NSMetadataItem]) ?? []
        let urls = items.compactMap { $0.value(forAttribute: NSMetadataItemURLKey) as? URL }
        let built = urls.map { DocumentSummary.fromFile(at: $0) }
            .sorted(by: { $0.createdAt > $1.createdAt })
        // Hop to main since `@Observable` notifies SwiftUI on whatever queue mutates the value.
        DispatchQueue.main.async {
            self.summaries = built
        }
    }
}
