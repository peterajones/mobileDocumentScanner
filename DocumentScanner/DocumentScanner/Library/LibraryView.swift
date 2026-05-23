import SwiftUI

struct LibraryView<Store: LibraryStoring & Observable>: View {
    @Bindable var store: Store

    let scannerPresenter: DocumentScannerPresenting
    let storage: DocumentStorage
    let pipeline: ScanPipeline

    @State private var searchText = ""
    @State private var showingCapture = false
    @State private var nameSheet: NameSheetContext?
    @State private var path: [DocumentSummary] = []

    private struct NameSheetContext: Identifiable {
        let id = UUID()
        let task: Task<ScanResult, Error>
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.summaries.isEmpty {
                    ContentUnavailableView(
                        "No documents yet",
                        systemImage: "doc.viewfinder",
                        description: Text("Tap + to scan a document.")
                    )
                } else {
                    List(filtered) { summary in
                        NavigationLink(value: summary) {
                            DocumentRow(summary: summary)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search documents")
                    .refreshable { store.refresh() }
                    .navigationDestination(for: DocumentSummary.self) { summary in
                        DocumentViewerView(
                            summary: summary,
                            storage: storage,
                            onDeleted: {
                                store.refresh()
                                path.removeLast()
                            }
                        )
                    }
                }
            }
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCapture = true } label: { Image(systemName: "plus") }
                }
            }
            .fullScreenCover(isPresented: $showingCapture) {
                CaptureSheet(
                    presenter: scannerPresenter,
                    onFinish: { images in
                        showingCapture = false
                        let task = Task { try await pipeline.process(images: images) }
                        nameSheet = NameSheetContext(task: task)
                    },
                    onCancel: { showingCapture = false }
                )
                .ignoresSafeArea()
            }
            .sheet(item: $nameSheet) { ctx in
                NameDocumentSheet(
                    pipelineTask: ctx.task,
                    storage: storage,
                    onSaved: {
                        nameSheet = nil
                        store.refresh()
                    },
                    onCancel: { nameSheet = nil }
                )
            }
        }
    }

    private var filtered: [DocumentSummary] {
        guard !searchText.isEmpty else { return store.summaries }
        let needle = searchText.lowercased()
        return store.summaries.filter {
            $0.displayName.lowercased().contains(needle)
            || $0.ocrSnippet.lowercased().contains(needle)
        }
    }
}
