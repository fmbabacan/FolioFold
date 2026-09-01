import FolioFoldCore
import SwiftUI
import UniformTypeIdentifiers

struct ConvertWorkspace: View {
    private enum OutputMode: String, CaseIterable, Identifiable {
        case combined = "One Combined PDF"
        case separate = "One PDF per Source"

        var id: Self { self }
    }

    @State private var sources: [URL] = []
    @State private var outputMode: OutputMode = .combined
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
                    Label("Convert Files", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                    Spacer()
                    Button("Choose Files…") { isImporting = true }
                }
                Text("Convert local images, plain text, RTF, or local HTML without uploading files. Combined mode creates one PDF in the listed source order.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: DesignTokens.workspaceGuidanceMaximumWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Output") {
                Picker("Output mode", selection: $outputMode) {
                    ForEach(OutputMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isRunning)
                .accessibilityIdentifier("convert.output-mode")

                Label(outputSummary, systemImage: outputMode == .combined ? "doc" : "folder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("convert.output-summary")
            }
            Section("Source files") {
                if sources.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Add images, text, RTF, or local HTML to create a PDF.", systemImage: "doc.badge.plus")
                            .foregroundStyle(.secondary)
                        Button("Choose Source Files…", systemImage: "plus") { isImporting = true }
                            .accessibilityIdentifier("convert.empty.choose")
                        Text("You can also drag supported files anywhere onto this workspace.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Array(sources.enumerated()), id: \.element) { index, url in
                        HStack {
                            Label(url.lastPathComponent, systemImage: "line.3.horizontal")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(url.path)
                            Text(pageEstimateDescription(for: url))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Spacer()
                            Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(index == 0 || isRunning)
                                .help(index == 0 ? "Already first" : "Move \(url.lastPathComponent) up")
                                .accessibilityLabel("Move \(url.lastPathComponent) up")
                            Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(index == sources.count - 1 || isRunning)
                                .help(index == sources.count - 1 ? "Already last" : "Move \(url.lastPathComponent) down")
                                .accessibilityLabel("Move \(url.lastPathComponent) down")
                            Button(role: .destructive) { sources.removeAll { $0 == url } } label: { Image(systemName: "trash") }
                                .disabled(isRunning)
                                .help("Remove \(url.lastPathComponent)")
                                .accessibilityLabel("Remove \(url.lastPathComponent)")
                        }
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("\(url.lastPathComponent), \(pageEstimateDescription(for: url)), position \(index + 1) of \(sources.count)")
                        .accessibilityIdentifier("convert.source.\(index)")
                        .draggable(url.absoluteString) {
                            draggedSource = url
                            return Label(url.lastPathComponent, systemImage: "doc")
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
                    }
                }
            }
            Section {
                Button(outputMode == .combined ? "Export Combined PDF…" : "Convert to PDFs…") { convert() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("convert.primary-action")
                    .disabled(sources.isEmpty || isRunning)
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
                    Label("Drop Files to Convert", systemImage: "arrow.triangle.2.circlepath")
                        .font(.title2.bold())
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityLabel("Drop supported files to convert")
                .accessibilityIdentifier("convert.drop-target")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            acceptDroppedSources(urls)
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image, .plainText, .rtf, .html],
            allowsMultipleSelection: true
        ) { result in
            do {
                _ = acceptDroppedSources(try result.get())
            } catch { message = error.localizedDescription }
        }
    }

    private func acceptDroppedSources(_ urls: [URL]) -> Bool {
        let supported = urls.filter { (try? conversionSource(for: $0)) != nil }
        let rejected = urls.count - supported.count
        let additions = supported.filter { !sources.contains($0) }
        sources.append(contentsOf: additions)
        if rejected > 0 {
            message = "Supported formats are images, TXT, RTF, HTML, and HTM. Rejected \(rejected) unsupported file\(rejected == 1 ? "" : "s")."
        } else if additions.count < supported.count {
            message = "Duplicate source files were already selected and were not added again."
        } else {
            message = nil
        }
        return !additions.isEmpty
    }

    private func conversionSource(for url: URL) throws -> PDFConversionSource {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "tif", "tiff", "heic": return .image(url)
        case "txt": return .plainText(url)
        case "rtf": return .richText(url)
        case "html", "htm": return .html(url)
        default: throw PDFOperationError.unsupportedFormat
        }
    }

    private var outputSummary: String {
        guard !sources.isEmpty else {
            return outputMode == .combined
                ? "Selected sources will become one PDF in listed order."
                : "Each selected source will become a separate PDF."
        }
        let pageCount = estimatedTotalPageCount
        if outputMode == .combined {
            return "One PDF with approximately \(pageCount) page\(pageCount == 1 ? "" : "s") will be created in listed order."
        }
        return "\(sources.count) PDF file\(sources.count == 1 ? "" : "s") with approximately \(pageCount) total page\(pageCount == 1 ? "" : "s") will be created."
    }

    private var estimatedTotalPageCount: Int {
        sources.reduce(0) { $0 + estimatedPageCount(for: $1) }
    }

    private func estimatedPageCount(for url: URL) -> Int {
        guard let source = try? conversionSource(for: url) else { return 0 }
        return (try? PDFConvertOperation.estimatedPageCount(for: source)) ?? 0
    }

    private func pageEstimateDescription(for url: URL) -> String {
        let count = estimatedPageCount(for: url)
        return count > 0 ? "About \(count) page\(count == 1 ? "" : "s")" : "Page count unavailable"
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

    private func convert() {
        if outputMode == .separate {
            convertSeparately()
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Converted.pdf"
        guard panel.runModal() == .OK, let output = panel.url else { return }
        isRunning = true
        progress = 0
        message = nil
        let selectedSources = sources
        operationTask = Task {
            do {
                let inputs = try selectedSources.map(conversionSource)
                let result = try await PDFConvertOperation().run(
                    .init(sources: inputs),
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

    private func convertSeparately() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let outputDirectory = parent.appendingPathComponent("Converted PDFs", isDirectory: true)
        isRunning = true
        progress = 0
        message = nil
        let selectedSources = sources
        operationTask = Task {
            do {
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                var results: [URL] = []
                for (index, url) in selectedSources.enumerated() {
                    try Task.checkCancellation()
                    let input = try conversionSource(for: url)
                    let destination = uniqueOutputURL(for: url, in: outputDirectory, existing: results)
                    let result = try await PDFConvertOperation().run(
                        .init(sources: [input]),
                        context: .init(outputURL: destination, isCancelled: {
                            Task.isCancelled
                        })
                    )
                    results.append(result)
                    await MainActor.run {
                        progress = Double(index + 1) / Double(selectedSources.count)
                    }
                }
                await MainActor.run {
                    operationTask = nil
                    isRunning = false
                    progress = 1
                    message = "Created \(results.count) PDF file\(results.count == 1 ? "" : "s")"
                    NSWorkspace.shared.activateFileViewerSelecting(results)
                }
            } catch {
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: outputDirectory)
                }
                await MainActor.run {
                    operationTask = nil
                    isRunning = false
                    message = cancellationMessage(for: error)
                }
            }
        }
    }

    private func uniqueOutputURL(for source: URL, in directory: URL, existing: [URL]) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(base + ".pdf")
        var suffix = 2
        while existing.contains(candidate) || FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(suffix).pdf")
            suffix += 1
        }
        return candidate
    }

    private func cancelOperation() {
        operationTask?.cancel()
        message = "Cancelling conversion…"
    }

    private func cancellationMessage(for error: Error) -> String {
        if error is CancellationError || (error as? PDFOperationError) == .cancelled {
            return "Conversion cancelled. No output PDF was created."
        }
        return error.localizedDescription
    }
}
