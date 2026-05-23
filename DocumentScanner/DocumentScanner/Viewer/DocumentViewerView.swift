import SwiftUI
import PDFKit

struct DocumentViewerView: View {
    let summary: DocumentSummary
    let storage: DocumentStorage
    let scannerPresenter: DocumentScannerPresenting
    let pipeline: ScanPipeline
    let searchTerm: String?
    /// Closure dismissing the viewer; provided by LibraryView so the deletion
    /// path can pop the navigation stack.
    let onDeleted: () -> Void

    private struct PageEditorContext: Identifiable {
        let index: Int
        var id: Int { index }
    }

    @State private var session: DocumentSession?
    @State private var loadError: String?
    @State private var isRenaming = false
    @State private var showDeleteConfirm = false
    @State private var editMode = false
    @State private var showAddPages = false
    @State private var addPagesTask: Task<Void, Never>?
    @State private var editingPageIndex: Int?
    @State private var searchHighlight: SearchHighlight?

    var body: some View {
        Group {
            if let session {
                loadedBody(session: session)
            } else if let loadError {
                ContentUnavailableView("Couldn't open document",
                                       systemImage: "doc.text.fill",
                                       description: Text(loadError))
            } else {
                ProgressView()
            }
        }
        .task {
            do { session = try DocumentSession(summary: summary, storage: storage) }
            catch { loadError = String(describing: error) }
        }
    }

    @ViewBuilder
    private func loadedBody(session: DocumentSession) -> some View {
        VStack(spacing: 0) {
            PDFKitView(
                document: session.pdf,
                highlightedSelections: searchHighlight?.matches ?? [],
                currentSelection: searchHighlight?.current
            )
            .ignoresSafeArea(edges: editMode ? [] : .bottom)
            if editMode {
                EditModeView(
                    session: session,
                    onEditPage: { editingPageIndex = $0 },
                    onAddPages: { showAddPages = true }
                )
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: editMode)
        .task(id: ObjectIdentifier(session.pdf)) {
            rebuildHighlight(session: session)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if isRenaming {
                    TextField("Name", text: Binding(
                        get: { session.displayName },
                        set: { session.displayName = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { commitRename(session: session) }
                    .frame(minWidth: 200)
                } else {
                    Button(session.displayName) { isRenaming = true }
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button(editMode ? "Done" : "Edit") { editMode.toggle() }
                Spacer()
                if let h = searchHighlight, h.matchCount > 0 {
                    Button { h.previous() } label: { Image(systemName: "chevron.up") }
                    Text("\((h.currentIndex ?? 0) + 1) of \(h.matchCount)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button { h.next() } label: { Image(systemName: "chevron.down") }
                    Spacer()
                }
                ShareLink(item: session.url)
                Menu {
                    Button {
                        isRenaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete this document?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                try? storage.delete(at: session.url)
                onDeleted()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove \"\(session.displayName).pdf\" from iCloud.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestDeleteDocument)) { _ in
            showDeleteConfirm = true
        }
        .fullScreenCover(isPresented: $showAddPages) {
            CaptureSheet(
                presenter: scannerPresenter,
                onFinish: { images in
                    showAddPages = false
                    addPagesTask = Task { @MainActor in
                        guard let session = self.session else { return }
                        do {
                            let result = try await pipeline.process(images: images)
                            DocumentMutations.append(result.pdf, to: session.pdf)
                            _ = try session.save()
                        } catch {
                            // Surfaced later by Plan 4 error handling.
                        }
                    }
                },
                onCancel: { showAddPages = false }
            )
            .ignoresSafeArea()
        }
        .sheet(item: Binding(
            get: { editingPageIndex.map { PageEditorContext(index: $0) } },
            set: { editingPageIndex = $0?.index }
        )) { ctx in
            PageEditorView(
                session: session,
                pageIndex: ctx.index,
                onDismiss: { editingPageIndex = nil }
            )
        }
    }

    private func rebuildHighlight(session: DocumentSession) {
        guard let term = searchTerm, !term.isEmpty else {
            searchHighlight = nil
            return
        }
        let matches = session.pdf.findString(term, withOptions: .caseInsensitive)
        searchHighlight = SearchHighlight(matches: matches)
    }

    private func commitRename(session: DocumentSession) {
        isRenaming = false
        let trimmed = session.displayName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            session.displayName = summary.displayName // revert to original
            return
        }
        do { try session.save() }
        catch { session.displayName = summary.displayName } // revert on failure
    }
}

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let highlightedSelections: [PDFSelection]
    let currentSelection: PDFSelection?

    /// Tag we attach to highlight annotations so we can remove the ones we
    /// added on the next update without disturbing any annotations that
    /// happened to be in the PDF already.
    private static let annotationUserName = "DocumentScanner.searchHighlight"

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.usePageViewController(false)
        return v
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }

        // PDFView.highlightedSelections doesn't reliably render on iOS — use
        // real PDFAnnotation highlights, which are guaranteed to draw.
        removeOurAnnotations(from: document)

        for match in highlightedSelections {
            let color: UIColor = (match == currentSelection)
                ? UIColor.systemBlue.withAlphaComponent(0.45)
                : UIColor.systemYellow.withAlphaComponent(0.45)
            addHighlight(for: match, color: color)
        }

        if let currentSelection {
            view.go(to: currentSelection)
        }
    }

    private func removeOurAnnotations(from document: PDFDocument) {
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            for annotation in page.annotations where annotation.userName == Self.annotationUserName {
                page.removeAnnotation(annotation)
            }
        }
    }

    private func addHighlight(for selection: PDFSelection, color: UIColor) {
        // selectionsByLine() splits a multi-line match into one selection per
        // line, each with a single bounding rect we can wrap in an annotation.
        for lineSelection in selection.selectionsByLine() {
            for page in lineSelection.pages {
                let bounds = lineSelection.bounds(for: page)
                guard !bounds.isEmpty else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = color
                annotation.userName = Self.annotationUserName
                page.addAnnotation(annotation)
            }
        }
    }
}
