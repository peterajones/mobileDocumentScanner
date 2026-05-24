import Foundation
import Observation

protocol LibraryStoring: AnyObject {
    var summaries: [DocumentSummary] { get }
    func refresh()
}

/// Testable in-memory store. Originally `nonisolated` to opt out of the project's
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` default; that setting was removed
/// in commit d2782f8, so this can be `@Observable` again — needed so XCUITest
/// mode can use it as the library store behind LibraryView<Store: Observable>.
@Observable
final class InMemoryLibraryStore: LibraryStoring {
    private(set) var summaries: [DocumentSummary] = []

    func append(_ summary: DocumentSummary) {
        summaries.append(summary)
        summaries.sort { $0.createdAt > $1.createdAt }
    }

    func refresh() { /* no-op for in-memory */ }
}
