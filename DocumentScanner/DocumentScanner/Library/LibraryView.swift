import SwiftUI

struct LibraryView<Store: LibraryStoring & Observable>: View {
    @Bindable var store: Store

    let scannerPresenter: DocumentScannerPresenting
    let storage: DocumentStorage
    let pipeline: ScanPipeline
    let lockSettings: AppLockSettings

    @State private var searchText = ""
    @State private var showingCapture = false
    @State private var showingCameraDenied = false
    @State private var nameSheet: NameSheetContext?
    @State private var path = NavigationPath()
    @State private var folders: [URL] = []
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var folderActionError: String?
    @State private var folderBeingRenamed: URL?
    @State private var renameFolderName = ""
    @State private var folderBeingDeleted: URL?
    @AppStorage("showFolders") private var showFolders = true

    private struct NameSheetContext: Identifiable {
        let id = UUID()
        let task: Task<ScanResult, Error>
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if visibleDocs.isEmpty && (!showFolders || folders.isEmpty) {
                    ContentUnavailableView(
                        "No documents yet",
                        systemImage: "doc.viewfinder",
                        description: Text(showFolders
                            ? "Tap + to scan a document or create a folder."
                            : "Tap + to scan a document.")
                    )
                } else {
                    List {
                        if showFolders && !folders.isEmpty {
                            Section {
                                ForEach(folders, id: \.self) { folderURL in
                                    NavigationLink(value: folderURL) {
                                        folderRow(folderURL)
                                    }
                                    .accessibilityIdentifier("Library.Folder.\(folderURL.lastPathComponent)")
                                    .contextMenu {
                                        Button {
                                            renameFolderName = folderURL.lastPathComponent
                                            folderBeingRenamed = folderURL
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            folderBeingDeleted = folderURL
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        if !filteredDocs.isEmpty {
                            Section {
                                ForEach(filteredDocs) { summary in
                                    docRow(summary)
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search documents")
                    .refreshable {
                        store.refresh()
                        refreshFolders()
                    }
                }
            }
            .navigationTitle("Scanned Documents")
            .navigationDestination(for: DocumentSummary.self) { summary in
                DocumentViewerView(
                    summary: summary,
                    storage: storage,
                    scannerPresenter: scannerPresenter,
                    pipeline: pipeline,
                    searchTerm: searchText.isEmpty ? nil : searchText,
                    onDeleted: {
                        store.refresh()
                        path.removeLast()
                    }
                )
            }
            .navigationDestination(for: URL.self) { folderURL in
                FolderContentsView(folderURL: folderURL, store: store, storage: storage)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView(lockSettings: lockSettings)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("Library.SettingsButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if showFolders {
                        Menu {
                            Button {
                                triggerScan()
                            } label: {
                                Label("Scan Document", systemImage: "doc.viewfinder")
                            }
                            Button {
                                newFolderName = ""
                                showingNewFolderAlert = true
                            } label: {
                                Label("New Folder", systemImage: "folder.badge.plus")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityIdentifier("Library.AddButton")
                    } else {
                        Button {
                            triggerScan()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityIdentifier("Library.AddButton")
                    }
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
            .fullScreenCover(isPresented: $showingCameraDenied) {
                CameraDeniedView(onDismiss: { showingCameraDenied = false })
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
            .alert("New Folder", isPresented: $showingNewFolderAlert) {
                TextField("Folder name", text: $newFolderName)
                    .autocorrectionDisabled()
                Button("Create") { createFolder() }
                    .accessibilityIdentifier("Library.NewFolder.Create")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter a name for the new folder.")
            }
            .alert("Rename Folder",
                   isPresented: Binding(
                    get: { folderBeingRenamed != nil },
                    set: { if !$0 { folderBeingRenamed = nil } }
                   )) {
                TextField("Folder name", text: $renameFolderName)
                    .autocorrectionDisabled()
                Button("Rename") { renameFolder() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose a new name for this folder.")
            }
            .alert("Delete Folder?",
                   isPresented: Binding(
                    get: { folderBeingDeleted != nil },
                    set: { if !$0 { folderBeingDeleted = nil } }
                   )) {
                Button("Delete", role: .destructive) { deleteFolder() }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let folder = folderBeingDeleted, !isFolderEmpty(folder) {
                    Text("This folder and all documents inside it will be deleted.")
                } else {
                    Text("This folder will be deleted.")
                }
            }
            .alert("Couldn't update folder",
                   isPresented: Binding(
                    get: { folderActionError != nil },
                    set: { _ in folderActionError = nil }
                   )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(folderActionError ?? "")
            }
            .task { refreshFolders() }
        }
    }

    private func folderRow(_ url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
                .font(.title3)
            Text(url.lastPathComponent)
                .font(.body)
            Spacer()
        }
    }

    @ViewBuilder
    private func docRow(_ summary: DocumentSummary) -> some View {
        if summary.isCorrupt {
            DocumentRow(summary: summary)
                .contextMenu {
                    Button(role: .destructive) {
                        try? storage.delete(at: summary.url)
                        store.refresh()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        } else {
            NavigationLink(value: summary) {
                DocumentRow(summary: summary)
            }
            .contextMenu {
                if showFolders && !folders.isEmpty {
                    Menu("Move to Folder") {
                        ForEach(folders, id: \.self) { folder in
                            Button(folder.lastPathComponent) {
                                moveDocument(summary, to: folder)
                            }
                        }
                    }
                }
            }
        }
    }

    private var docsAtRoot: [DocumentSummary] {
        let rootPath = storage.documentsURL.standardizedFileURL.path
        return store.summaries.filter {
            $0.url.deletingLastPathComponent().standardizedFileURL.path == rootPath
        }
    }

    /// Docs shown in the main list, before search filter. When the user has
    /// disabled "Show Folders" in Settings, we ignore the root-only filter
    /// and show every PDF in storage as a single flat list.
    private var visibleDocs: [DocumentSummary] {
        showFolders ? docsAtRoot : store.summaries
    }

    private var filteredDocs: [DocumentSummary] {
        guard !searchText.isEmpty else { return visibleDocs }
        let needle = searchText.lowercased()
        return visibleDocs.filter {
            $0.displayName.lowercased().contains(needle)
            || $0.ocrSnippet.lowercased().contains(needle)
        }
    }

    private func triggerScan() {
        Task {
            switch await CameraPermission.request() {
            case .authorized: showingCapture = true
            case .denied: showingCameraDenied = true
            case .notDetermined: break  // unreachable after request()
            }
        }
    }

    private func refreshFolders() {
        folders = (try? storage.listFolders())?.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) ?? []
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try storage.createFolder(named: trimmed)
            refreshFolders()
        } catch {
            folderActionError = error.localizedDescription
        }
    }

    private func moveDocument(_ summary: DocumentSummary, to folderURL: URL) {
        do {
            _ = try storage.moveDocument(at: summary.url, toFolder: folderURL)
            store.refresh()
        } catch {
            folderActionError = error.localizedDescription
        }
    }

    private func renameFolder() {
        guard let folder = folderBeingRenamed else { return }
        let trimmed = renameFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try storage.renameFolder(at: folder, to: trimmed)
            refreshFolders()
            store.refresh()
        } catch {
            folderActionError = error.localizedDescription
        }
        folderBeingRenamed = nil
    }

    private func deleteFolder() {
        guard let folder = folderBeingDeleted else { return }
        do {
            try storage.deleteFolder(at: folder)
            refreshFolders()
            store.refresh()
        } catch {
            folderActionError = error.localizedDescription
        }
        folderBeingDeleted = nil
    }

    private func isFolderEmpty(_ folderURL: URL) -> Bool {
        let path = folderURL.standardizedFileURL.path
        return !store.summaries.contains {
            $0.url.deletingLastPathComponent().standardizedFileURL.path == path
        }
    }
}
