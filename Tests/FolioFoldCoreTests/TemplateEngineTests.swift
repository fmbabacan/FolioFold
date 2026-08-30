import Foundation
import Testing
@testable import FolioFoldCore

@Suite("Template engine")
struct TemplateEngineTests {
    @Test("field values render into linked blocks")
    func rendersLinkedBlocks() throws {
        let name = TemplateField(name: "Customer", kind: .text, defaultValue: "Unknown")
        let sequence = TemplateField(name: "Invoice", kind: .sequence, format: "INV-%04d")
        var document = FolioDocument.blank()
        document.templateFields = [name, sequence]
        document.flow = [
            Block(kind: .paragraph, templateFieldID: name.id),
            Block(kind: .paragraph, templateFieldID: sequence.id)
        ]

        let result = try TemplateEngine(locale: Locale(identifier: "en_US_POSIX")).render(
            document: document,
            values: [name.id: .text("Acme")],
            sequenceNumber: 23
        )

        #expect(result.document.flow.map(\.text) == ["Acme", "INV-0023"])
    }

    @Test("missing values use field defaults")
    func usesDefaults() throws {
        let field = TemplateField(name: "Note", kind: .text, defaultValue: "Thank you")
        var document = FolioDocument.blank()
        document.templateFields = [field]
        document.flow = [Block(templateFieldID: field.id)]

        let result = try TemplateEngine().render(document: document)

        #expect(result.document.flow[0].text == "Thank you")
    }

    @Test("repeatable table rows are preserved as structured values")
    func repeatableRows() throws {
        let field = TemplateField(name: "Items", kind: .tableRow)
        var document = FolioDocument.blank()
        document.templateFields = [field]
        let rows: [[String: TemplateValue]] = [
            ["description": .text("Design"), "amount": .number(120)],
            ["description": .text("Delivery"), "amount": .number(30)]
        ]

        let result = try TemplateEngine().render(document: document, values: [field.id: .rows(rows)])

        #expect(result.tableRows[field.id] == rows)
    }

    @Test("v1 formulas calculate deterministic decimal results")
    func formulas() {
        let engine = TemplateEngine()
        let subtotal = engine.evaluate(.subtotal([100, 50]))
        let tax = engine.evaluate(.percentage(base: subtotal, rate: 20))

        #expect(subtotal == 150)
        #expect(tax == 30)
        #expect(engine.evaluate(.sum([1, 2, 3])) == 6)
        #expect(engine.evaluate(.grandTotal(subtotal: subtotal, additions: [tax, 5])) == 185)
    }

    @Test("unsafe sequence formats fail closed")
    func rejectsUnsafeSequenceFormat() {
        let field = TemplateField(name: "Sequence", kind: .sequence, format: "%@")
        var document = FolioDocument.blank()
        document.templateFields = [field]

        #expect(throws: TemplateEngineError.invalidSequenceFormat("%@")) {
            try TemplateEngine().render(document: document)
        }
    }

    @Test("duplicate names are rejected case insensitively")
    func rejectsDuplicateNames() {
        var document = FolioDocument.blank()
        document.templateFields = [
            TemplateField(name: "Total", kind: .number),
            TemplateField(name: "total", kind: .number)
        ]

        #expect(throws: TemplateEngineError.duplicateFieldName("total")) {
            try TemplateEngine(locale: Locale(identifier: "en_US_POSIX")).render(document: document)
        }
    }
}
