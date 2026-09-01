import AppKit
import PDFKit
import SwiftUI

@MainActor
enum VisualSnapshotHarness {
    private struct Scenario {
        let name: String
        let size: CGSize
        let view: AnyView
    }

    static func runIfRequested() -> Bool {
        guard let outputPath = ProcessInfo.processInfo.environment["FOLIOFOLD_SNAPSHOT_OUTPUT"] else {
            return false
        }

        do {
            let output = URL(fileURLWithPath: outputPath, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let pdfURL = try makeSamplePDF(in: output)

            for colorScheme in [ColorScheme.light, ColorScheme.dark] {
                let appearanceName = colorScheme == .dark ? "dark" : "light"
                for scenario in scenarios(pdfURL: pdfURL) {
                    let fileName = scenario.name + "-" + appearanceName + ".png"
                    let destination = output.appendingPathComponent(fileName)
                    let renderedView = scenario.view
                        .environment(\.colorScheme, colorScheme)
                        .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    try render(renderedView, size: scenario.size, to: destination)
                }
            }

            FileHandle.standardOutput.write(Data("visual_snapshot_render=passed\n".utf8))
            NSApplication.shared.terminate(nil)
        } catch {
            let message = "visual snapshot failure: " + String(describing: error) + "\n"
            FileHandle.standardError.write(Data(message.utf8))
            NSApplication.shared.terminate(nil)
        }
        return true
    }

    private static func scenarios(pdfURL: URL) -> [Scenario] {
        [
            Scenario(name: "welcome", size: CGSize(width: 620, height: 440), view: AnyView(FolioFoldWelcomeView())),
            Scenario(name: "about", size: CGSize(width: 540, height: 620), view: AnyView(FolioFoldAboutView())),
            Scenario(name: "create-narrow", size: CGSize(width: 820, height: 560), view: AnyView(FolioDocumentWorkspace(title: "Untitled", url: nil))),
            Scenario(name: "create-wide", size: CGSize(width: 1280, height: 760), view: AnyView(FolioDocumentWorkspace(title: "Untitled", url: nil))),
            Scenario(name: "merge-empty", size: CGSize(width: 900, height: 650), view: AnyView(MergeWorkspace())),
            Scenario(name: "split-empty", size: CGSize(width: 900, height: 650), view: AnyView(SplitWorkspace())),
            Scenario(name: "convert-empty", size: CGSize(width: 900, height: 650), view: AnyView(ConvertWorkspace())),
            Scenario(name: "pdf-workspace", size: CGSize(width: 1180, height: 760), view: AnyView(PDFWorkspace(url: pdfURL))),
            Scenario(
                name: "operation-progress",
                size: CGSize(width: 540, height: 120),
                view: AnyView(OperationStatusView(isRunning: true, progress: 0.42, message: "Exporting document…", onCancel: {}).padding(24))
            ),
            Scenario(
                name: "operation-error",
                size: CGSize(width: 540, height: 120),
                view: AnyView(OperationStatusView(isRunning: false, progress: 0, message: "Unable to export the selected document.").padding(24))
            )
        ]
    }

    private static func render<V: View>(_ view: V, size: CGSize, to destination: URL) throws {
        let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw SnapshotError.bitmapCreationFailed
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw SnapshotError.pngEncodingFailed
        }
        try data.write(to: destination, options: .atomic)
    }

    private static func makeSamplePDF(in directory: URL) throws -> URL {
        let image = NSImage(size: CGSize(width: 612, height: 792), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            "FolioFold Visual Snapshot".draw(
                at: CGPoint(x: 72, y: 680),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
                    .foregroundColor: NSColor.black
                ]
            )
            return true
        }
        guard let page = PDFPage(image: image) else { throw SnapshotError.samplePDFFailed }
        let document = PDFDocument()
        document.insert(page, at: 0)
        let url = directory.appendingPathComponent("sample.pdf")
        guard document.write(to: url) else { throw SnapshotError.samplePDFFailed }
        return url
    }

    private enum SnapshotError: Error {
        case bitmapCreationFailed
        case pngEncodingFailed
        case samplePDFFailed
    }
}
