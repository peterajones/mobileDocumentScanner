import Foundation
import Observation

protocol LibraryStoring: AnyObject {
    var summaries: [DocumentSummary] { get }
    func refresh()
}

/// Testable in-memory store. Explicitly `nonisolated` to opt out of the project's
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` default — XCTest tears the test
/// instance down off-main and a main-actor-isolated deinit crashes there.
/// SwiftUI views use `MetadataQueryLibraryStore`, which stays main-actor by default.
nonisolated final class InMemoryLibraryStore: LibraryStoring {
    private(set) var summaries: [DocumentSummary] = []

    func append(_ summary: DocumentSummary) {
        summaries.append(summary)
        summaries.sort { $0.createdAt > $1.createdAt }
    }

    func refresh() { /* no-op for in-memory */ }
}
