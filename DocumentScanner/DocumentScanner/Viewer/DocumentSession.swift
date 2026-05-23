import Foundation
import Observation
import PDFKit

/// Per-screen view-model owning the document the viewer is showing. Wraps
/// the file URL, the parsed PDFDocument, and the document's display name
/// (filename without extension). Saves back to disk via DocumentStorage
/// at explicit save points.
@MainActor
@Observable
final class DocumentSession {
    private(set) var url: URL
    private(set) var pdf: PDFDocument
    var displayName: String
    private(set) var conflicts: [NSFileVersion]

    private let storage: DocumentStorage

    /// Annotation `userName` that marks PDFAnnotations added by the search-highlight
    /// view layer. `save()` strips these before writing so they don't persist.
    static let searchHighlightAnnotationName = "DocumentScanner.searchHighlight"

    enum InitError: Error { case unreadablePDF }

    init(summary: DocumentSummary, storage: DocumentStorage) throws {
        guard let pdf = PDFDocument(url: summary.url) else { throw InitError.unreadablePDF }
        self.url = summary.url
        self.pdf = pdf
        self.displayName = summary.displayName
        self.storage = storage
        self.conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: summary.url) ?? []
    }

    func resolveConflict(keeping chosen: NSFileVersion?) throws {
        // chosen == nil means "keep this device's current version" (i.e., do nothing
        // with the conflict version, just mark resolved).
        // chosen != nil means "replace with that version".
        if let chosen {
            try chosen.replaceItem(at: url, options: [])
        }
        for version in conflicts {
            version.isResolved = true
        }
        conflicts = []
        if let reloaded = PDFDocument(url: url) {
            pdf = reloaded
        }
    }

    /// Persist the current `pdf` over the current `url`. Used after edit-mode
    /// mutations or rename. Returns the (possibly new) URL.
    @discardableResult
    func save() throws -> URL {
        stripSearchHighlightAnnotations()
        let newURL = try storage.write(pdf, replacing: url, withName: displayName)
        self.url = newURL
        return newURL
    }

    private func stripSearchHighlightAnnotations() {
        // We rely on annotation type rather than the userName tag because
        // PDFKit doesn't reliably preserve userName on .highlight subtypes
        // through the page's annotation lifecycle. Since the app doesn't add
        // any non-search highlight annotations of its own, removing every
        // .highlight is safe — if that ever changes, fall back to userName
        // tagging or track our annotations explicitly.
        //
        // Note: PDFAnnotation.type returns the subtype string without the
        // leading slash ("Highlight"), while PDFAnnotationSubtype.highlight
        // .rawValue includes it ("/Highlight"). Compare against the bare
        // form.
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let toRemove = page.annotations.filter { $0.type == "Highlight" }
            for annotation in toRemove {
                page.removeAnnotation(annotation)
            }
        }
    }
}
