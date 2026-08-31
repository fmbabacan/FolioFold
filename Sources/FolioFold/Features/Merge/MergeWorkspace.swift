import FolioFoldCore
import SwiftUI
import UniformTypeIdentifiers

struct MergeWorkspace: View {
    @State private var sources: [URL] = []
    @State private var isImporting = false
    @State private var isRunning = false
    @State private var progress = 0.0
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Merge PDFs", systemImage: "rectangle.stack")
                        .font(.title2.bold())
                    Spacer()
                    Button("Choose Files…") { isImporting = true }
                }
                Text("Choose two or more PDF files, arrange their order, then export a combined PDF.")
                    .foregroundStyle(.secondary)
            }
            Section("PDF files") {
                if sources.isEmpty {
                    Text("No PDF files selected").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(sources.enumerated()), id: \.element) { index, url in
                        HStack {
                            Text(url.lastPathComponent)
                            Spacer()
                            Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(index == 0 || isRunning)
                            Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(index == sources.count - 1 || isRunning)
                            Button(role: .destructive) { sources.remove(at: index) } label: { Image(systemName: "trash") }
                                .disabled(isRunning)
                        }
                    }
                }
            }
            Section {
                Button("Export Merged PDF…") { export() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sources.count < 2 || isRunning)
                OperationStatusView(isRunning: isRunning, progress: progress, message: message)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            do {
                for url in try result.get() where !sources.contains(url) { sources.append(url) }
                message = nil
            } catch { message = error.localizedDescription }
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard sources.indices.contains(destination) else { return }
        sources.swapAt(index, destination)
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
        Task {
            do {
                let result = try await PDFMergeOperation().run(
                    .init(items: selectedSources.map { .init(url: $0) }),
                    context: .init(outputURL: output, reportProgress: { value in
                        Task { @MainActor in progress = value.fractionCompleted }
                    })
                )
                await MainActor.run {
                    isRunning = false
                    progress = 1
                    message = "Created \(result.lastPathComponent)"
                    NSWorkspace.shared.activateFileViewerSelecting([result])
                }
            } catch {
                await MainActor.run { isRunning = false; message = error.localizedDescription }
            }
        }
    }
}
