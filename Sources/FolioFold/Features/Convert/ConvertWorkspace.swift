import FolioFoldCore
import SwiftUI
import UniformTypeIdentifiers

struct ConvertWorkspace: View {
    @State private var sources: [URL] = []
    @State private var isImporting = false
    @State private var isRunning = false
    @State private var progress = 0.0
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Convert Files", systemImage: "arrow.triangle.2.circlepath").font(.title2.bold())
                    Spacer()
                    Button("Choose Files…") { isImporting = true }
                }
                Text("Convert local images, plain text, RTF, or local HTML to PDF without uploading files.")
                    .foregroundStyle(.secondary)
            }
            Section("Source files") {
                if sources.isEmpty {
                    Text("No files selected").foregroundStyle(.secondary)
                } else {
                    ForEach(sources, id: \.self) { url in
                        HStack {
                            Text(url.lastPathComponent)
                            Spacer()
                            Button(role: .destructive) { sources.removeAll { $0 == url } } label: { Image(systemName: "trash") }
                                .disabled(isRunning)
                        }
                    }
                }
            }
            Section {
                Button("Export PDF…") { convert() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sources.isEmpty || isRunning)
                OperationStatusView(isRunning: isRunning, progress: progress, message: message)
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image, .plainText, .rtf, .html],
            allowsMultipleSelection: true
        ) { result in
            do {
                for url in try result.get() where !sources.contains(url) { sources.append(url) }
                message = nil
            } catch { message = error.localizedDescription }
        }
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

    private func convert() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Converted.pdf"
        guard panel.runModal() == .OK, let output = panel.url else { return }
        isRunning = true
        progress = 0
        message = nil
        let selectedSources = sources
        Task {
            do {
                let inputs = try selectedSources.map(conversionSource)
                let result = try await PDFConvertOperation().run(
                    .init(sources: inputs),
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
