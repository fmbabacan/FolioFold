import AppKit
import Foundation
import PDFKit
import Testing
@testable import FolioFoldCore

@Suite("PDF redaction")
struct PDFRedactionTests {
    @Test("applied redactions rasterize pages and remove extractable content")
    func appliesVerifiedRedaction() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("redacted.pdf")
        try makePDF(at: source)
        let sourceDataBeforeRedaction = try Data(contentsOf: source)

        let result = try await PDFRedactionOperation().run(
            .init(url: source, marks: [
                .init(pageIndex: 0, bounds: CGRect(x: 10, y: 10, width: 180, height: 180))
            ], rasterScale: 1),
            context: .init(outputURL: output)
        )

        #expect(result.verification.pageCount == 1)
        #expect(result.verification.extractedTextIsEmpty)
        #expect(result.verification.annotationCount == 0)
        #expect(result.verification.sourceMetadataRemoved)
        #expect(result.verification.redactedRegionsAreOpaque)
        #expect(PDFDocument(url: output)?.string?.contains("Secret") != true)
        #expect(try Data(contentsOf: source) == sourceDataBeforeRedaction)
    }

    @Test("redaction removes source metadata and covers vector and embedded image content")
    func removesMetadataAndRenderedContent() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("mixed-content.pdf")
        let output = directory.appendingPathComponent("redacted.pdf")
        try makePDF(at: source, includeLink: true, includeMetadata: true)

        let result = try await PDFRedactionOperation().run(
            .init(url: source, marks: [
                .init(pageIndex: 0, bounds: CGRect(x: 10, y: 10, width: 180, height: 180))
            ], rasterScale: 2),
            context: .init(outputURL: output)
        )

        let redacted = try #require(PDFDocument(url: output))
        let metadataText = redacted.documentAttributes?.values.map(String.init(describing:)).joined(separator: " ") ?? ""
        #expect(result.verification.sourceMetadataRemoved)
        #expect(result.verification.redactedRegionsAreOpaque)
        #expect(!metadataText.contains("Sensitive FolioFold Title"))
        #expect(!metadataText.contains("Private Author"))
        #expect(redacted.page(at: 0)?.annotations.isEmpty == true)
        #expect(redacted.string?.contains("Secret account value") != true)
    }

    @Test("redaction removes links and annotations from final output")
    func removesAnnotations() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("redacted.pdf")
        try makePDF(at: source, includeLink: true)

        _ = try await PDFRedactionOperation().run(
            .init(url: source, marks: [
                .init(pageIndex: 0, bounds: CGRect(x: 10, y: 10, width: 80, height: 30))
            ], rasterScale: 1),
            context: .init(outputURL: output)
        )

        #expect(PDFDocument(url: output)?.page(at: 0)?.annotations.isEmpty == true)
    }

    @Test("source overwrite is rejected")
    func rejectsSourceOverwrite() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        try makePDF(at: source)

        await #expect(throws: PDFOperationError.invalidInput) {
            _ = try await PDFRedactionOperation().run(
                .init(url: source, marks: [
                    .init(pageIndex: 0, bounds: CGRect(x: 10, y: 10, width: 50, height: 20))
                ]),
                context: .init(outputURL: source)
            )
        }
    }

    @Test("cancelled redaction leaves no final output")
    func cancelledRedaction() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("redacted.pdf")
        try makePDF(at: source)

        await #expect(throws: PDFOperationError.cancelled) {
            _ = try await PDFRedactionOperation().run(
                .init(url: source, marks: [
                    .init(pageIndex: 0, bounds: CGRect(x: 10, y: 10, width: 50, height: 20))
                ]),
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

    private func makePDF(
        at url: URL,
        includeLink: Bool = false,
        includeMetadata: Bool = false
    ) throws {
        let image = NSImage(size: NSSize(width: 200, height: 200))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 200).fill()
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: 30, y: 30, width: 60, height: 60)).fill()
        let embedded = NSImage(size: NSSize(width: 40, height: 40))
        embedded.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 40).fill()
        embedded.unlockFocus()
        embedded.draw(in: NSRect(x: 120, y: 30, width: 40, height: 40))
        NSString(string: "Secret account value").draw(at: NSPoint(x: 20, y: 90))
        image.unlockFocus()
        let document = PDFDocument()
        guard let page = PDFPage(image: image) else { throw PDFOperationError.invalidInput }
        if includeLink {
            let link = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 80, height: 30), forType: .link, withProperties: nil)
            link.url = URL(string: "https://example.invalid")
            page.addAnnotation(link)
        }
        document.insert(page, at: 0)
        if includeMetadata {
            document.documentAttributes = [
                PDFDocumentAttribute.titleAttribute: "Sensitive FolioFold Title",
                PDFDocumentAttribute.authorAttribute: "Private Author",
                PDFDocumentAttribute.subjectAttribute: "Confidential Subject",
                PDFDocumentAttribute.keywordsAttribute: ["private", "secret"]
            ]
        }
        guard document.write(to: url) else { throw PDFOperationError.outputVerificationFailed }
    }
}
