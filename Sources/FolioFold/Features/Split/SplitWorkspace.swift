import FolioFoldCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct SplitWorkspace: View {
    private enum SplitMode: String, CaseIterable, Identifiable {
        case every = "Every N Pages"
        case ranges = "Explicit Ranges"
        case selected = "Selected Pages"
        case individual = "One File per Page"

        var id: Self { self }
    }

    @State private var source: URL?
    @State private var isImporting = false
    @State private var splitMode: SplitMode = .every
    @State private var chunkSize = 1
    @State private var rangesText = "1-2, 3-4"
    @State private var selectedPagesText = "1, 3"
    @State private var isRunning = false
    @State private var progress = 0.0
    @State private var message: String?
    @State private var operationTask: Task<Void, Never>?
    @State private var isDropTargeted = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Split PDF", systemImage: "scissors")
                        .font(.headline)
                    Spacer()
                    Button("Choose PDF…") { isImporting = true }
                }
                if let source {
                    Text(source.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(source.path)
                        .accessibilityLabel(source.lastPathComponent)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose one PDF to configure its split outputs.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: DesignTokens.workspaceGuidanceMaximumWidth, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Choose a PDF…", systemImage: "doc.badge.plus") { isImporting = true }
                            .accessibilityIdentifier("split.empty.choose")
                        Text("You can also drag a PDF anywhere onto this workspace.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Split options") {
                Picker("Mode", selection: $splitMode) {
                    ForEach(SplitMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isRunning)
                .accessibilityIdentifier("split.mode")

                switch splitMode {
                case .every:
                    Stepper(
                        "Pages per output: \(chunkSize)",
                        value: $chunkSize,
                        in: 1...max(pageCount, 1)
                    )
                    .disabled(isRunning || pageCount == 0)
                    .accessibilityIdentifier("split.chunk-size")
                case .ranges:
                    TextField("Ranges, for example 1-3, 5, 8-10", text: $rangesText)
                        .disabled(isRunning)
                        .accessibilityIdentifier("split.ranges")
                case .selected:
                    TextField("Pages, for example 1, 3, 5", text: $selectedPagesText)
                        .disabled(isRunning)
                        .accessibilityIdentifier("split.selected-pages")
                case .individual:
                    Text("Each page becomes a separate PDF.")
                        .foregroundStyle(.secondary)
                }

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("split.validation")
                }
            }
            Section("Output preview") {
                if let groups = previewGroups {
                    Label("\(groups.count) PDF file\(groups.count == 1 ? "" : "s") will be created.", systemImage: "doc.on.doc")
                        .accessibilityIdentifier("split.output-count")
                    ForEach(Array(groups.prefix(5).enumerated()), id: \.offset) { index, pages in
                        Text("part-\(String(format: "%03d", index + 1)).pdf · \(pageDescription(pages))")
                            .font(.caption.monospacedDigit())
                    }
                    if groups.count > 5 {
                        Text("…and \(groups.count - 5) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(source == nil ? "Choose a PDF to preview outputs." : "Enter a valid split selection to preview outputs.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Split PDF…") { split() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("split.primary-action")
                    .disabled(source == nil || previewGroups == nil || isRunning)
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
                ZStack {
                    Color.black.opacity(0.18)
                    Label("Drop a PDF to Split", systemImage: "scissors")
                        .font(.title2.bold())
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityLabel("Drop a PDF to split")
                .accessibilityIdentifier("split.drop-target")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            acceptDroppedPDF(urls)
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            do { _ = acceptDroppedPDF(try result.get()) }
            catch { message = error.localizedDescription }
        }
    }

    private func acceptDroppedPDF(_ urls: [URL]) -> Bool {
        guard urls.count == 1,
              let url = urls.first,
              url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame else {
            message = urls.count > 1
                ? "Split accepts one PDF at a time."
                : "Only a PDF file can be split."
            return false
        }
        source = url
        if chunkSize > pageCount, pageCount > 0 { chunkSize = pageCount }
        message = nil
        return true
    }

    private var pageCount: Int {
        guard let source else { return 0 }
        return PDFDocument(url: source)?.pageCount ?? 0
    }

    private var splitSelection: PDFSplitSelection? {
        guard pageCount > 0 else { return nil }
        switch splitMode {
        case .every:
            guard chunkSize <= pageCount else { return nil }
            return .every(chunkSize)
        case .ranges:
            guard let ranges = parseRanges(rangesText) else { return nil }
            return .ranges(ranges)
        case .selected:
            guard let pages = parsePages(selectedPagesText) else { return nil }
            return .selected(Set(pages))
        case .individual:
            return .individualPages
        }
    }

    private var previewGroups: [[Int]]? {
        guard let splitSelection else { return nil }
        return try? splitSelection.groups(pageCount: pageCount)
    }

    private var validationMessage: String? {
        guard source != nil else { return nil }
        guard pageCount > 0 else { return "The selected PDF has no readable pages." }
        if splitMode == .every, chunkSize > pageCount {
            return "Pages per output cannot exceed the document's \(pageCount) pages."
        }
        guard previewGroups != nil else {
            return "Use page numbers from 1 through \(pageCount), separated by commas. Ranges use a hyphen."
        }
        return nil
    }

    private func parsePages(_ text: String) -> [Int]? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var pages: [Int] = []
        for part in parts {
            guard let value = Int(part.trimmingCharacters(in: .whitespacesAndNewlines)),
                  value >= 1, value <= pageCount else { return nil }
            pages.append(value - 1)
        }
        guard !pages.isEmpty else { return nil }
        return Array(Set(pages)).sorted()
    }

    private func parseRanges(_ text: String) -> [ClosedRange<Int>]? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var ranges: [ClosedRange<Int>] = []
        for part in parts {
            let bounds = part.split(separator: "-", omittingEmptySubsequences: false)
            if bounds.count == 1,
               let page = Int(bounds[0].trimmingCharacters(in: .whitespacesAndNewlines)),
               page >= 1, page <= pageCount {
                ranges.append((page - 1)...(page - 1))
            } else if bounds.count == 2,
                      let start = Int(bounds[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                      let end = Int(bounds[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                      start >= 1, start <= end, end <= pageCount {
                ranges.append((start - 1)...(end - 1))
            } else {
                return nil
            }
        }
        return ranges.isEmpty ? nil : ranges
    }

    private func pageDescription(_ pages: [Int]) -> String {
        guard let first = pages.first, let last = pages.last else { return "No pages" }
        return first == last ? "Page \(first + 1)" : "Pages \(first + 1)-\(last + 1)"
    }

    private func split() {
        guard let source, let selection = splitSelection else {
            message = validationMessage ?? "Choose a valid split selection."
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let output = parent.appendingPathComponent(source.deletingPathExtension().lastPathComponent + " Parts", isDirectory: true)
        isRunning = true
        progress = 0
        message = nil
        operationTask = Task {
            do {
                let results = try await PDFSplitOperation().run(
                    .init(url: source, selection: selection),
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
                    message = "Created \(results.count) PDF files"
                    NSWorkspace.shared.activateFileViewerSelecting(results)
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
        message = "Cancelling split…"
    }

    private func cancellationMessage(for error: Error) -> String {
        if error is CancellationError || (error as? PDFOperationError) == .cancelled {
            return "Split cancelled. No output folder was created."
        }
        return error.localizedDescription
    }
}
