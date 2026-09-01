import AppKit
import Foundation
import PDFKit
import Testing
@testable import FolioFoldCore

@Suite("PDF editing")
struct PDFEditingTests {
    @Test("annotations export to a new PDF without changing the source")
    func addsAnnotations() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("annotated.pdf")
        try makePDF(at: source)

        _ = try await PDFAnnotationOperation().run(
            .init(url: source, annotations: [
                .init(pageIndex: 0, bounds: CGRect(x: 20, y: 20, width: 120, height: 30), kind: .freeText("Local note")),
                .init(pageIndex: 0, bounds: CGRect(x: 20, y: 60, width: 100, height: 20), kind: .highlight)
            ]),
            context: .init(outputURL: output)
        )

        #expect(PDFDocument(url: source)?.page(at: 0)?.annotations.isEmpty == true)
        #expect(PDFDocument(url: output)?.page(at: 0)?.annotations.count == 2)
    }

    @Test("basic AcroForm fields can be created and filled")
    func createsAndFillsFormFields() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let form = directory.appendingPathComponent("form.pdf")
        let filled = directory.appendingPathComponent("filled.pdf")
        try makePDF(at: source)

        _ = try await PDFFormOperation().run(
            .init(url: source, fields: [
                .init(pageIndex: 0, bounds: CGRect(x: 20, y: 20, width: 160, height: 24), name: "customer", kind: .text),
                .init(pageIndex: 0, bounds: CGRect(x: 20, y: 60, width: 18, height: 18), name: "approved", kind: .checkBox)
            ]),
            context: .init(outputURL: form)
        )
        _ = try await PDFFormOperation().run(
            .init(url: form, valuesByName: ["customer": "Acme", "approved": "Yes"]),
            context: .init(outputURL: filled)
        )

        let annotations = try #require(PDFDocument(url: filled)?.page(at: 0)?.annotations)
        #expect(annotations.first(where: { $0.fieldName == "customer" })?.widgetStringValue == "Acme")
        #expect(annotations.first(where: { $0.fieldName == "approved" })?.widgetStringValue == "Yes")
    }

    @Test("form field names and choices normalize predictably")
    func validatesFormFieldInputs() {
        #expect(PDFFormOperation.normalizedFieldName(" customer_name ") == "customer_name")
        #expect(PDFFormOperation.normalizedFieldName("field") == nil)
        #expect(PDFFormOperation.normalizedFieldName("1customer") == nil)
        #expect(PDFFormOperation.normalizedFieldName("customer name") == nil)
        #expect(PDFFormOperation.normalizedChoiceOptions([" One ", "Two"]) == ["One", "Two"])
        #expect(PDFFormOperation.normalizedChoiceOptions(["One", "one"]) == nil)
        #expect(PDFFormOperation.normalizedChoiceOptions(["One", " "]) == nil)
    }

    @Test("duplicate pending AcroForm names are rejected case insensitively")
    func rejectsDuplicatePendingFormNames() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("duplicate.pdf")
        try makePDF(at: source)

        await #expect(throws: PDFOperationError.invalidInput) {
            _ = try await PDFFormOperation().run(
                .init(url: source, fields: [
                    .init(pageIndex: 0, bounds: CGRect(x: 20, y: 20, width: 100, height: 20), name: "Customer", kind: .text),
                    .init(pageIndex: 0, bounds: CGRect(x: 20, y: 50, width: 100, height: 20), name: "customer", kind: .text)
                ]),
                context: .init(outputURL: output)
            )
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test("all v1 AcroForm field kinds survive PDF serialization")
    func createsEveryV1FormFieldKind() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("all-fields.pdf")
        try makePDF(at: source)

        _ = try await PDFFormOperation().run(
            .init(url: source, fields: [
                .init(pageIndex: 0, bounds: CGRect(x: 10, y: 10, width: 100, height: 20), name: "text", kind: .text, value: "Value"),
                .init(pageIndex: 0, bounds: CGRect(x: 10, y: 40, width: 20, height: 20), name: "check", kind: .checkBox, value: "Yes"),
                .init(pageIndex: 0, bounds: CGRect(x: 40, y: 40, width: 20, height: 20), name: "radio", kind: .radioButton, value: "ChoiceA"),
                .init(pageIndex: 0, bounds: CGRect(x: 10, y: 70, width: 100, height: 20), name: "choice", kind: .choice(options: ["One", "Two"]), value: "Two"),
                .init(pageIndex: 0, bounds: CGRect(x: 10, y: 100, width: 120, height: 30), name: "signature", kind: .signature)
            ]),
            context: .init(outputURL: output)
        )

        let annotations = try #require(PDFDocument(url: output)?.page(at: 0)?.annotations)
        #expect(Set(annotations.compactMap(\.fieldName)) == ["text", "check", "radio", "choice", "signature"])
        #expect(annotations.first(where: { $0.fieldName == "text" })?.widgetFieldType == .text)
        #expect(annotations.first(where: { $0.fieldName == "check" })?.widgetFieldType == .button)
        #expect(annotations.first(where: { $0.fieldName == "check" })?.widgetControlType == .checkBoxControl)
        #expect(annotations.first(where: { $0.fieldName == "radio" })?.widgetFieldType == .button)
        #expect(annotations.first(where: { $0.fieldName == "radio" })?.widgetControlType == .radioButtonControl)
        #expect(annotations.first(where: { $0.fieldName == "choice" })?.widgetFieldType == .choice)
        #expect(annotations.first(where: { $0.fieldName == "choice" })?.choices == ["One", "Two"])
        #expect(annotations.first(where: { $0.fieldName == "signature" })?.widgetFieldType == .signature)
        #expect(annotations.first(where: { $0.fieldName == "choice" })?.widgetStringValue == "Two")
    }

    @Test("visual signatures are explicitly image annotations")
    func addsVisualSignature() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("signed.pdf")
        try makePDF(at: source)
        let image = NSImage(size: NSSize(width: 80, height: 30))
        image.lockFocus()
        NSColor.black.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 5, y: 5))
        path.line(to: NSPoint(x: 70, y: 25))
        path.stroke()
        image.unlockFocus()
        let data = try #require(image.tiffRepresentation)

        _ = try await PDFAnnotationOperation().run(
            .init(url: source, annotations: [
                .init(pageIndex: 0, bounds: CGRect(x: 20, y: 20, width: 80, height: 30), kind: .visualSignature(data))
            ]),
            context: .init(outputURL: output)
        )

        let type = PDFDocument(url: output)?.page(at: 0)?.annotations.first?.type
        #expect(type == "Stamp" || type == PDFAnnotationSubtype.stamp.rawValue)
    }

    @Test("cancelled editing leaves no final output")
    func cancelledEditing() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.pdf")
        let output = directory.appendingPathComponent("output.pdf")
        try makePDF(at: source)

        await #expect(throws: PDFOperationError.cancelled) {
            _ = try await PDFAnnotationOperation().run(
                .init(url: source, annotations: [
                    .init(pageIndex: 0, bounds: CGRect(x: 10, y: 10, width: 20, height: 20), kind: .rectangle)
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

    private func makePDF(at url: URL) throws {
        let document = PDFDocument()
        let image = NSImage(size: NSSize(width: 200, height: 200))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 200).fill()
        image.unlockFocus()
        guard let page = PDFPage(image: image) else { throw PDFOperationError.invalidInput }
        document.insert(page, at: 0)
        guard document.write(to: url) else { throw PDFOperationError.outputVerificationFailed }
    }
}
