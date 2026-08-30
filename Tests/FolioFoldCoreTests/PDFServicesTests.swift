import Foundation
import PDFKit
import Testing
@testable import FolioFoldCore

@Suite("PDF services")
struct PDFServicesTests {
    @Test("opener reports document properties")
    func inspectDocument() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        try makePDF(pageCount: 2, at: source)

        let info = try await PDFKitDocumentOpener().inspect(source, password: nil)
        #expect(info.pageCount == 2)
        #expect(!info.isEncrypted)
    }

    @Test("merge preserves requested document and page order")
    func mergeDocuments() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.pdf")
        let second = directory.appendingPathComponent("second.pdf")
        let output = directory.appendingPathComponent("merged.pdf")
        try makePDF(pageCount: 2, at: first)
        try makePDF(pageCount: 1, at: second)

        _ = try await PDFMergeOperation().run(
            .init(items: [.init(url: first, pageIndexes: [1]), .init(url: second)]),
            context: .init(outputURL: output)
        )

        #expect(PDFDocument(url: output)?.pageCount == 2)
    }

    @Test("split writes verified groups into one final directory")
    func splitDocument() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("parts", isDirectory: true)
        try makePDF(pageCount: 5, at: source)

        let urls = try await PDFSplitOperation().run(
            .init(url: source, selection: .every(2)),
            context: .init(outputURL: output)
        )

        #expect(urls.count == 3)
        #expect(urls.compactMap { PDFDocument(url: $0)?.pageCount } == [2, 2, 1])
    }

    @Test("cancelled merge leaves no final output")
    func cancelledMerge() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("output.pdf")
        try makePDF(pageCount: 1, at: source)

        await #expect(throws: PDFOperationError.cancelled) {
            _ = try await PDFMergeOperation().run(
                .init(items: [.init(url: source)]),
                context: .init(outputURL: output, isCancelled: { true })
            )
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makePDF(pageCount: Int, at url: URL) throws {
        let document = PDFDocument()
        for index in 0..<pageCount {
            let image = NSImage(size: NSSize(width: 200, height: 200))
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 200, height: 200).fill()
            NSString(string: "Page \(index + 1)").draw(at: NSPoint(x: 20, y: 90))
            image.unlockFocus()
            guard let page = PDFPage(image: image) else { throw PDFOperationError.invalidInput }
            document.insert(page, at: document.pageCount)
        }
        guard document.write(to: url) else { throw PDFOperationError.outputVerificationFailed }
    }
}
