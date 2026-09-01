import FolioFoldCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct MergeWorkspace: View {
    @State private var sources: [URL] = []
    @State private var isImporting = false
    @State private var isRunning = false
    @State private var progress = 0.0
    @State private var message: String?
    @State private var operationTask: Task<Void, Never>?
    @State private var isDropTargeted = false
    @State private var draggedSource: URL?

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Merge PDFs", systemImage: "rectangle.stack")
                        .font(.headline)
                    Spacer()
                    Button("Choose Files…") { isImporting = true }
                }
                Text("Choose two or more PDF files, arrange their order, then export a combined PDF.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: DesignTokens.workspaceGuidanceMaximumWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("PDF files") {
                if sources.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Add at least two PDFs to define the merge order.", systemImage: "doc.on.doc")
                            .foregroundStyle(.secondary)
                        Button("Choose PDF Files…", systemImage: "plus") { isImporting = true }
                            .accessibilityIdentifier("merge.empty.choose")
                        Text("You can also drag PDF files anywhere onto this workspace.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Array(sources.enumerated()), id: \.element) { index, url in
                        HStack(spacing: 12) {
                            Image(nsImage: thumbnail(for: url))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 56, height: 72)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 4) {
                                Label(url.lastPathComponent, systemImage: "line.3.horizontal")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(url.path)
                                Text(metadataDescription(for: url))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Spacer()
                            Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(index == 0 || isRunning)
                                .help(index == 0 ? "Already first in the merge order" : "Move \(url.lastPathComponent) up")
                                .accessibilityLabel("Move \(url.lastPathComponent) up")
                            Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(index == sources.count - 1 || isRunning)
                                .help(index == sources.count - 1 ? "Already last in the merge order" : "Move \(url.lastPathComponent) down")
                                .accessibilityLabel("Move \(url.lastPathComponent) down")
                            Button(role: .destructive) { sources.remove(at: index) } label: { Image(systemName: "trash") }
                                .disabled(isRunning)
                                .help("Remove \(url.lastPathComponent)")
                                .accessibilityLabel("Remove \(url.lastPathComponent)")
                        }
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("\(url.lastPathComponent), \(metadataDescription(for: url)), position \(index + 1) of \(sources.count)")
                        .accessibilityIdentifier("merge.source.\(index)")
                        .draggable(url.absoluteString) {
                            draggedSource = url
                            return Label(url.lastPathComponent, systemImage: "doc.richtext")
                                .padding(8)
                        }
                        .dropDestination(for: String.self) { values, _ in
                            guard !isRunning,
                                  let value = values.first,
                                  let sourceURL = URL(string: value),
                                  let sourceIndex = sources.firstIndex(of: sourceURL),
                                  sourceIndex != index else { return false }
                            moveSource(from: sourceIndex, to: index)
                            draggedSource = nil
                            return true
                        } isTargeted: { targeted in
                            if !targeted, draggedSource == url { draggedSource = nil }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(draggedSource == url ? Color.accentColor : Color.clear, lineWidth: 2)
                        }
                    }
                }
            }
            Section {
                Button("Merge PDFs…") { export() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("merge.primary-action")
                    .disabled(sources.count < 2 || isRunning)
                OperationStatusView(
                    isRunning: isRunning,
                    progress: progress,
                    message: message,
                    onCancel: cancelOperation
                )
            }
        }
        .formStyle(.grouped)
        .overlay {
            if isDropTargeted {
                dropOverlay("Drop PDFs to Merge", systemImage: "rectangle.stack.badge.plus")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            acceptDroppedPDFs(urls)
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            do {
                _ = acceptDroppedPDFs(try result.get())
            } catch { message = error.localizedDescription }
        }
    }

    private func acceptDroppedPDFs(_ urls: [URL]) -> Bool {
        let pdfs = urls.filter { $0.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame }
        let rejected = urls.count - pdfs.count
        let additions = pdfs.filter { !sources.contains($0) }
        sources.append(contentsOf: additions)
        if rejected > 0 {
            message = "Only PDF files can be merged. Rejected \(rejected) unsupported file\(rejected == 1 ? "" : "s")."
        } else if additions.count < pdfs.count {
            message = "Duplicate PDFs were already in the merge list and were not added again."
        } else {
            message = nil
        }
        return !additions.isEmpty
    }

    private func dropOverlay(_ title: String, systemImage: String) -> some View {
        ZStack {
            Color.black.opacity(0.18)
            Label(title, systemImage: systemImage)
                .font(.title2.bold())
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier("merge.drop-target")
    }

    private func move(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard sources.indices.contains(destination) else { return }
        sources.swapAt(index, destination)
    }

    private func moveSource(from source: Int, to destination: Int) {
        guard sources.indices.contains(source), sources.indices.contains(destination) else { return }
        let url = sources.remove(at: source)
        sources.insert(url, at: destination)
    }

    private func metadataDescription(for url: URL) -> String {
        let pageCount = PDFDocument(url: url)?.pageCount ?? 0
        let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        return "\(pageCount) page\(pageCount == 1 ? "" : "s") · \(size)"
    }

    private func thumbnail(for url: URL) -> NSImage {
        guard let page = PDFDocument(url: url)?.page(at: 0) else {
            return NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: nil) ?? NSImage()
        }
        return page.thumbnail(of: NSSize(width: 112, height: 144), for: .mediaBox)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Merged.pdf"
        guard panel.runModal() == .OK, let output = panel.url else { return }
        isRunning = true
        progress = 0
        message = nil
        let selectedSources = sources
        operationTask = Task {
            do {
                let result = try await PDFMergeOperation().run(
                    .init(items: selectedSources.map { .init(url: $0) }),
                    context: .init(outputURL: output, isCancelled: {
                        Task.isCancelled
                    }, reportProgress: { value in
                        Task { @MainActor in progress = value.fractionCompleted }
                    })
                )
                await MainActor.run {
                    operationTask = nil
                    isRunning = false
                    progress = 1
                    message = "Created \(result.lastPathComponent)"
                    NSWorkspace.shared.activateFileViewerSelecting([result])
                }
            } catch {
                await MainActor.run {
                    operationTask = nil
                    isRunning = false
                    message = cancellationMessage(for: error)
                }
            }
        }
    }

    private func cancelOperation() {
        operationTask?.cancel()
        message = "Cancelling merge…"
    }

    private func cancellationMessage(for error: Error) -> String {
        if error is CancellationError || (error as? PDFOperationError) == .cancelled {
            return "Merge cancelled. No output PDF was created."
        }
        return error.localizedDescription
    }
}
