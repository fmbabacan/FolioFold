import FolioFoldCore
import SwiftUI
import UniformTypeIdentifiers

struct SplitWorkspace: View {
    @State private var source: URL?
    @State private var isImporting = false
    @State private var chunkSize = 1
    @State private var isRunning = false
    @State private var progress = 0.0
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Split PDF", systemImage: "scissors").font(.title2.bold())
                    Spacer()
                    Button("Choose PDF…") { isImporting = true }
                }
                Text(source?.lastPathComponent ?? "No PDF selected")
                    .foregroundStyle(source == nil ? .secondary : .primary)
            }
            Section("Split options") {
                Stepper("Pages per output: \(chunkSize)", value: $chunkSize, in: 1...999)
                    .disabled(isRunning)
            }
            Section {
                Button("Choose Output Folder and Split…") { split() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(source == nil || isRunning)
                OperationStatusView(isRunning: isRunning, progress: progress, message: message)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            do { source = try result.get().first; message = nil }
            catch { message = error.localizedDescription }
        }
    }

    private func split() {
        guard let source else { return }
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
        Task {
            do {
                let results = try await PDFSplitOperation().run(
                    .init(url: source, selection: .every(chunkSize)),
                    context: .init(outputURL: output, reportProgress: { value in
                        Task { @MainActor in progress = value.fractionCompleted }
                    })
                )
                await MainActor.run {
                    isRunning = false
                    progress = 1
                    message = "Created \(results.count) PDF files"
                    NSWorkspace.shared.activateFileViewerSelecting(results)
                }
            } catch {
                await MainActor.run { isRunning = false; message = error.localizedDescription }
            }
        }
    }
}
