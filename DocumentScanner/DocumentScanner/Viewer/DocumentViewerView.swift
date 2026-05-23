import SwiftUI
import PDFKit

struct DocumentViewerView: View {
    let summary: DocumentSummary
    let storage: DocumentStorage
    let scannerPresenter: DocumentScannerPresenting
    let pipeline: ScanPipeline
    /// Closure dismissing the viewer; provided by LibraryView so the deletion
    /// path can pop the navigation stack.
    let onDeleted: () -> Void

    @State private var session: DocumentSession?
    @State private var loadError: String?
    @State private var isRenaming = false
    @State private var showDeleteConfirm = false
    @State private var editMode = false
    @State private var showAddPages = false
    @State private var addPagesTask: Task<Void, Never>?

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
            PDFKitView(document: session.pdf)
                .ignoresSafeArea(edges: editMode ? [] : .bottom)
            if editMode {
                EditModeView(session: session, onAddPages: { showAddPages = true })
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: editMode)
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
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.usePageViewController(false)
        return v
    }
    func updateUIView(_ view: PDFView, context: Context) {
        view.document = document
    }
}
