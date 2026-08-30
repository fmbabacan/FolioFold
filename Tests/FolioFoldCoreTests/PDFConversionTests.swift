import AppKit
import Foundation
import PDFKit
import Testing
@testable import FolioFoldCore

@Suite("PDF conversion")
struct PDFConversionTests {
    @Test("plain text converts to a verified PDF")
    func convertsPlainText() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("note.txt")
        let output = directory.appendingPathComponent("note.pdf")
        try "FolioFold local conversion".write(to: input, atomically: true, encoding: .utf8)

        _ = try await PDFConvertOperation().run(
            .init(sources: [.plainText(input)]),
            context: .init(outputURL: output)
        )

        #expect(PDFDocument(url: output)?.pageCount == 1)
    }

    @Test("supported image converts to PDF")
    func convertsImage() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("image.png")
        let output = directory.appendingPathComponent("image.pdf")
        try makePNG(at: input)

        _ = try await PDFConvertOperation().run(
            .init(sources: [.image(input)]),
            context: .init(outputURL: output)
        )

        #expect(PDFDocument(url: output)?.pageCount == 1)
    }

    @Test("JPEG and TIFF images convert to verified PDFs")
    func convertsJPEGAndTIFFImages() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let jpeg = directory.appendingPathComponent("image.jpg")
        let tiff = directory.appendingPathComponent("image.tiff")
        try makeImage(at: jpeg, using: .jpeg)
        try makeImage(at: tiff, using: .tiff)

        for (index, input) in [jpeg, tiff].enumerated() {
            let output = directory.appendingPathComponent("image-\(index).pdf")
            _ = try await PDFConvertOperation().run(
                .init(sources: [.image(input)]),
                context: .init(outputURL: output)
            )
            #expect(PDFDocument(url: output)?.pageCount == 1)
        }
    }

    @Test("RTF and controlled local HTML convert to verified PDFs")
    func convertsRichTextAndLocalHTML() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rtf = directory.appendingPathComponent("note.rtf")
        let html = directory.appendingPathComponent("note.html")
        let richText = NSAttributedString(
            string: "Formatted FolioFold text",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]
        )
        let rtfData = try #require(
            richText.rtf(from: NSRange(location: 0, length: richText.length))
        )
        try rtfData.write(to: rtf)
        try Data("<html><body><h1>Local document</h1><p>Offline conversion</p></body></html>".utf8)
            .write(to: html)

        for (index, source) in [PDFConversionSource.richText(rtf), .html(html)].enumerated() {
            let output = directory.appendingPathComponent("text-\(index).pdf")
            _ = try await PDFConvertOperation().run(
                .init(sources: [source]),
                context: .init(outputURL: output)
            )
            #expect(PDFDocument(url: output)?.pageCount == 1)
        }
    }

    @Test("PDF pages export to PNG files")
    func exportsPagesToPNG() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("images", isDirectory: true)
        try makePDF(pageCount: 2, at: input)

        let urls = try await PDFImageExportOperation().run(
            .init(url: input, format: .png, scale: 1),
            context: .init(outputURL: output)
        )

        #expect(urls.count == 2)
        #expect(urls.allSatisfy { NSImage(contentsOf: $0) != nil })
    }

    @Test("PDF pages export to JPEG files")
    func exportsPagesToJPEG() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("images", isDirectory: true)
        try makePDF(pageCount: 2, at: input)

        let urls = try await PDFImageExportOperation().run(
            .init(url: input, format: .jpeg(quality: 0.8), scale: 1),
            context: .init(outputURL: output)
        )

        #expect(urls.count == 2)
        #expect(urls.allSatisfy { $0.pathExtension == "jpg" })
        #expect(urls.allSatisfy { NSImage(contentsOf: $0) != nil })
    }

    @Test("cancelled conversion leaves no final output")
    func cancelledConversion() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("note.txt")
        let output = directory.appendingPathComponent("note.pdf")
        try "Text".write(to: input, atomically: true, encoding: .utf8)

        await #expect(throws: PDFOperationError.cancelled) {
            _ = try await PDFConvertOperation().run(
                .init(sources: [.plainText(input)]),
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

    private func makePNG(at url: URL) throws {
        try makeImage(at: url, using: .png)
    }

    private func makeImage(at url: URL, using type: NSBitmapImageRep.FileType) throws {
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 100).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: type, properties: [:]) else {
            throw PDFOperationError.outputVerificationFailed
        }
        try data.write(to: url)
    }

    private func makePDF(pageCount: Int, at url: URL) throws {
        let document = PDFDocument()
        for _ in 0..<pageCount {
            let image = NSImage(size: NSSize(width: 100, height: 100))
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 100, height: 100).fill()
            image.unlockFocus()
            guard let page = PDFPage(image: image) else { throw PDFOperationError.invalidInput }
            document.insert(page, at: document.pageCount)
        }
        guard document.write(to: url) else { throw PDFOperationError.outputVerificationFailed }
    }
}
