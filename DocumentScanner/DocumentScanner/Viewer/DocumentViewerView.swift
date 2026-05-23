import SwiftUI
import PDFKit

struct DocumentViewerView: View {
    let summary: DocumentSummary
    let storage: DocumentStorage
    /// Closure dismissing the viewer; provided by LibraryView so the deletion
    /// path can pop the navigation stack.
    let onDeleted: () -> Void

    @State private var session: DocumentSession?
    @State private var loadError: String?
    @State private var isRenaming = false
    @State private var showDeleteConfirm = false

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
        PDFKitView(document: session.pdf)
            .ignoresSafeArea(edges: .bottom)
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: session.url)
                    Button { showDeleteConfirm = true } label: {
                        Image(systemName: "trash")
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
