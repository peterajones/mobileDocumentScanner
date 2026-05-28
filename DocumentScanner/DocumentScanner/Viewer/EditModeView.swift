import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct EditModeView: View {
    @Bindable var session: DocumentSession
    let onEditPage: (Int) -> Void
    let onAddPages: () -> Void

    @State private var isMultiSelectMode = false
    @State private var selectedIndices: Set<Int> = []

    var body: some View {
        // Read session.revision so SwiftUI subscribes to it; the body
        // re-evaluates whenever DocumentSession.save() bumps revision after
        // page-list mutations (add/delete/reorder/replace). Without this,
        // `currentPages` would be stale because session.pdf's reference
        // doesn't change when DocumentMutations mutates pages in place.
        let _ = session.revision
        VStack(spacing: 0) {
            if isMultiSelectMode {
                multiSelectHeader
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(currentPages.indices, id: \.self) { index in
                        thumbnail(at: index)
                    }
                    if !isMultiSelectMode {
                        addButton
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 140)
        }
        .background(.thinMaterial)
        .animation(.easeInOut(duration: 0.2), value: isMultiSelectMode)
    }

    private var multiSelectHeader: some View {
        HStack {
            Button("Cancel") { exitMultiSelect() }
                .accessibilityIdentifier("EditMode.MultiSelect.Cancel")
            Spacer()
            Text("\(selectedIndices.count) selected")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
            Spacer()
            Button(role: .destructive) {
                deleteSelected()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(selectedIndices.isEmpty)
            .accessibilityIdentifier("EditMode.MultiSelect.Delete")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 40)
    }

    private var addButton: some View {
        Button {
            onAddPages()
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.tint)
                    .overlay(Image(systemName: "plus").font(.title2).foregroundStyle(.tint))
                    .frame(width: 80, height: 104)
                Text("Add").font(.caption).foregroundStyle(.tint)
            }
        }
        .accessibilityIdentifier("EditMode.AddPages")
    }

    private var currentPages: [PDFPage] {
        (0..<session.pdf.pageCount).compactMap(session.pdf.page(at:))
    }

    @ViewBuilder
    private func thumbnail(at index: Int) -> some View {
        if let page = session.pdf.page(at: index) {
            VStack(spacing: 4) {
                thumbnailImage(for: page, index: index)
                Text("\(index + 1)").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("EditMode.Thumbnail.\(index)")
        }
    }

    @ViewBuilder
    private func thumbnailImage(for page: PDFPage, index: Int) -> some View {
        let isSelected = selectedIndices.contains(index)
        let base = ZStack(alignment: .topTrailing) {
            PageThumbnail(page: page, size: CGSize(width: 80, height: 104))
                .opacity(isMultiSelectMode && !isSelected ? 0.5 : 1.0)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                )
            if isMultiSelectMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .background(Circle().fill(Color(.systemBackground)).padding(2))
                    .padding(4)
            }
        }

        if isMultiSelectMode {
            base.onTapGesture { toggleSelection(at: index) }
        } else {
            base
                .draggable(IndexPayload(index: index)) {
                    PageThumbnail(page: page, size: CGSize(width: 60, height: 78))
                }
                .dropDestination(for: IndexPayload.self) { items, _ in
                    guard let first = items.first else { return false }
                    DocumentMutations.reorder(in: session.pdf, from: first.index, to: index)
                    _ = try? session.save()
                    return true
                }
                .contextMenu {
                    Button {
                        selectedIndices = [index]
                        isMultiSelectMode = true
                    } label: {
                        Label("Select Multiple", systemImage: "checkmark.circle")
                    }
                    Button(role: .destructive) {
                        deletePage(at: index)
                    } label: {
                        Label("Delete page", systemImage: "trash")
                    }
                }
                .onTapGesture {
                    onEditPage(index)
                }
        }
    }

    private func toggleSelection(at index: Int) {
        if selectedIndices.contains(index) {
            selectedIndices.remove(index)
        } else {
            selectedIndices.insert(index)
        }
    }

    private func exitMultiSelect() {
        isMultiSelectMode = false
        selectedIndices = []
    }

    private func deleteSelected() {
        // If the user has selected every page, fall back to the
        // delete-whole-document flow that the single-page path uses.
        if selectedIndices.count >= session.pdf.pageCount {
            NotificationCenter.default.post(name: .requestDeleteDocument, object: nil)
            return
        }
        DocumentMutations.deletePages(in: session.pdf, at: selectedIndices)
        _ = try? session.save()
        exitMultiSelect()
    }

    private func deletePage(at index: Int) {
        guard session.pdf.pageCount > 1 else {
            // Last page — surface delete-whole-document via notification so
            // EditModeView doesn't need direct access to storage/onDeleted.
            NotificationCenter.default.post(name: .requestDeleteDocument, object: nil)
            return
        }
        DocumentMutations.deletePage(in: session.pdf, at: index)
        _ = try? session.save()
    }

    private struct IndexPayload: Codable, Transferable {
        let index: Int
        static var transferRepresentation: some TransferRepresentation {
            CodableRepresentation(contentType: .data)
        }
    }
}

extension Notification.Name {
    static let requestDeleteDocument = Notification.Name("requestDeleteDocument")
}
