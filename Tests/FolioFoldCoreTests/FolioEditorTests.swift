import Foundation
import PDFKit
import Testing
@testable import FolioFoldCore

@Suite("Folio editor")
struct FolioEditorTests {
    @Test("pagination is deterministic and honors explicit page breaks")
    func deterministicPagination() throws {
        let first = Block(kind: .paragraph, text: "First")
        let pageBreak = Block(kind: .pageBreak)
        let second = Block(kind: .heading, text: "Second")
        let document = FolioDocument(
            pages: [FolioPage(), FolioPage()],
            flow: [first, pageBreak, second],
            overlays: []
        )
        let paginator = FolioPaginator()

        let firstLayout = try paginator.layout(document)
        let secondLayout = try paginator.layout(document)

        #expect(firstLayout == secondLayout)
        #expect(firstLayout.pageCount == 2)
        #expect(firstLayout.placements.map(\.pageIndex) == [0, 1])
        #expect(firstLayout.placements.map(\.blockID) == [first.id, second.id])
    }

    @Test("overflow moves a complete block to the next page")
    func blockOverflowCreatesPage() throws {
        let settings = PageSettings(
            size: .custom,
            width: 240,
            height: 160,
            margins: PageMargins(top: 20, leading: 20, bottom: 20, trailing: 20)
        )
        let document = FolioDocument(
            pages: [FolioPage()],
            pageSettings: settings,
            flow: [
                Block(kind: .image, text: "one"),
                Block(kind: .image, text: "two")
            ],
            overlays: []
        )

        let layout = try FolioPaginator().layout(document)

        #expect(layout.pageCount == 2)
        #expect(layout.placements.map(\.pageIndex) == [0, 1])
    }

    @Test("editing commands undo and redo without losing stable block identity")
    func editingUndoRedo() throws {
        var editor = FolioEditor(document: .blank())
        let originalID = try #require(editor.document.flow.first?.id)
        try editor.update(blockID: originalID) { $0.text = "Invoice" }
        let added = Block(kind: .heading, text: "Details")
        try editor.insert(added, at: 1)

        #expect(editor.document.flow.map(\.id) == [originalID, added.id])
        editor.undo()
        #expect(editor.document.flow.map(\.id) == [originalID])
        #expect(editor.document.flow[0].text == "Invoice")
        editor.undo()
        #expect(editor.document.flow[0].text.isEmpty)
        editor.redo()
        editor.redo()
        #expect(editor.document.flow.map(\.id) == [originalID, added.id])
        #expect(editor.document.flow[0].text == "Invoice")
    }

    @Test("pin and return operations participate in undo and redo")
    func overlayUndoRedo() throws {
        var editor = FolioEditor(document: .blank())
        let blockID = try #require(editor.document.flow.first?.id)
        let pageID = try #require(editor.document.pages.first?.id)
        try editor.pin(
            blockID: blockID,
            to: pageID,
            frame: FolioRect(x: 20, y: 30, width: 200, height: 60)
        )
        let overlayID = try #require(editor.document.overlays.first?.id)
        try editor.returnToFlow(overlayID: overlayID)

        #expect(editor.document.flow.map(\.id) == [blockID])
        editor.undo()
        #expect(editor.document.overlays.map(\.sourceBlockID) == [blockID])
        editor.undo()
        #expect(editor.document.flow.map(\.id) == [blockID])
        editor.redo()
        #expect(editor.document.overlays.map(\.sourceBlockID) == [blockID])
    }

    @Test("a failed command leaves the document and history unchanged")
    func failedCommandIsTransactional() {
        var editor = FolioEditor(document: .blank())
        let original = editor.document

        #expect(throws: FolioDocumentError.blockNotFound) {
            try editor.remove(blockID: UUID())
        }
        #expect(editor.document == original)
        #expect(!editor.canUndo)
        #expect(!editor.canRedo)
    }

    @Test("folio documents export to verified paginated PDFs")
    func exportsFolioPDF() throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolioFold-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: destination) }
        let document = FolioDocument(
            pages: [FolioPage(), FolioPage()],
            flow: [
                Block(kind: .heading, text: "Invoice"),
                Block(kind: .pageBreak),
                Block(kind: .paragraph, text: "Second page")
            ],
            overlays: []
        )

        try FolioPDFExporter.export(document, to: destination)

        let exported = try #require(PDFDocument(url: destination))
        #expect(exported.pageCount == 2)
        #expect((try Data(contentsOf: destination)).count > 1_000)
        for pageIndex in 0..<exported.pageCount {
            let page = try #require(exported.page(at: pageIndex))
            let thumbnail = page.thumbnail(of: CGSize(width: 120, height: 170), for: .mediaBox)
            #expect(thumbnail.size.width > 0)
            #expect(thumbnail.size.height > 0)
        }
    }

    @Test("one thousand page layouts remain bounded and deterministic")
    func thousandPageLayoutIsBounded() throws {
        var flow: [Block] = []
        flow.reserveCapacity(1_999)
        for index in 0..<1_000 {
            flow.append(Block(kind: .paragraph, text: "Page \(index + 1)"))
            if index < 999 {
                flow.append(Block(kind: .pageBreak))
            }
        }
        let document = FolioDocument(
            pages: (0..<1_000).map { _ in FolioPage() },
            flow: flow,
            overlays: []
        )

        let start = ContinuousClock.now
        let first = try FolioPaginator().layout(document)
        let second = try FolioPaginator().layout(document)
        let elapsed = start.duration(to: .now)

        #expect(first == second)
        #expect(first.pageCount == 1_000)
        #expect(first.placements.count == 1_000)
        #expect(elapsed < .seconds(1))
    }
}

@Suite("Template editing")
struct TemplateEditingTests {
    @Test("template fields bindings and generated values participate in undo and redo")
    func templateEditingIsUndoable() throws {
        var editor = FolioEditor(document: .blank())
        let blockID = try #require(editor.document.flow.first?.id)
        let field = TemplateField(name: "Client", kind: .text, defaultValue: "Default")

        try editor.setTemplateFields([field])
        try editor.bind(blockID: blockID, to: field.id)
        try editor.applyTemplateValues([field.id: .text("Acme")])
        #expect(editor.document.flow.first?.text == "Acme")
        #expect(editor.document.flow.first?.templateFieldID == field.id)

        editor.undo()
        #expect(editor.document.flow.first?.text == "")
        editor.redo()
        #expect(editor.document.flow.first?.text == "Acme")

        try editor.setTemplateFields([])
        #expect(editor.document.flow.first?.templateFieldID == nil)
    }
}
