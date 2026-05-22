import SwiftUI

struct LibraryView<Store: LibraryStoring & Observable>: View {
    @Bindable var store: Store
    @State private var searchText: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.summaries.isEmpty {
                    ContentUnavailableView(
                        "No documents yet",
                        systemImage: "doc.viewfinder",
                        description: Text("Tap + to scan a document.")
                    )
                } else {
                    List(filtered) { summary in
                        DocumentRow(summary: summary)
                    }
                    .searchable(text: $searchText, prompt: "Search documents")
                    .refreshable { store.refresh() }
                }
            }
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Wired in Task 13
                        print("[+] tap")
                    } label: {
                        Image(systemName: "plus")
                    }
                }
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
