import Foundation
import Testing
@testable import FolioFoldCore

@Suite("PDF operation contracts")
struct PDFOperationTests {
    @Test("page edits preserve stable identity and source references")
    func pageEditing() throws {
        let documentID = UUID()
        let first = PDFPageDescriptor(source: .init(documentID: documentID, pageIndex: 0))
        let second = PDFPageDescriptor(source: .init(documentID: documentID, pageIndex: 1))
        var collection = PDFPageCollection(pages: [first, second])

        try collection.move(from: 1, to: 0)
        try collection.rotate(pageID: first.id, clockwiseBy: 90)
        let copyID = UUID()
        try collection.duplicate(pageID: first.id, newID: copyID)

        #expect(collection.pages.map(\.id) == [second.id, first.id, copyID])
        #expect(collection.pages[1].rotationDegrees == 90)
        #expect(collection.pages[2].source == first.source)
        #expect(collection.pages[2].id != first.id)
    }

    @Test("invalid page edits are transactional")
    func invalidPageEdit() {
        let page = PDFPageDescriptor(source: .init(documentID: UUID(), pageIndex: 0))
        var collection = PDFPageCollection(pages: [page])
        let original = collection

        #expect(throws: PDFOperationError.invalidPageSelection) {
            try collection.move(from: 4, to: 0)
        }
        #expect(collection == original)
    }

    @Test("split selections produce deterministic page groups")
    func splitGroups() throws {
        #expect(try PDFSplitSelection.selected([3, 1]).groups(pageCount: 5) == [[1, 3]])
        #expect(try PDFSplitSelection.ranges([0...1, 3...4]).groups(pageCount: 5) == [[0, 1], [3, 4]])
        #expect(try PDFSplitSelection.every(2).groups(pageCount: 5) == [[0, 1], [2, 3], [4]])
        #expect(try PDFSplitSelection.individualPages.groups(pageCount: 3) == [[0], [1], [2]])
    }

    @Test("split output previews expose deterministic counts and page groups")
    func splitOutputPreviewGroups() throws {
        #expect(try PDFSplitSelection.every(3).groups(pageCount: 7) == [[0, 1, 2], [3, 4, 5], [6]])
        #expect(try PDFSplitSelection.ranges([0...2, 4...4]).groups(pageCount: 6).count == 2)
        #expect(try PDFSplitSelection.selected([4, 0, 2]).groups(pageCount: 5) == [[0, 2, 4]])
        #expect(try PDFSplitSelection.individualPages.groups(pageCount: 4).count == 4)
    }

    @Test("invalid split selections fail before producing output")
    func invalidSplitGroups() {
        #expect(throws: PDFOperationError.invalidPageSelection) {
            try PDFSplitSelection.selected([4]).groups(pageCount: 4)
        }
        #expect(throws: PDFOperationError.invalidPageSelection) {
            try PDFSplitSelection.every(0).groups(pageCount: 4)
        }
        #expect(throws: PDFOperationError.invalidPageSelection) {
            try PDFSplitSelection.ranges([1...4]).groups(pageCount: 4)
        }
        #expect(throws: PDFOperationError.invalidPageSelection) {
            try PDFSplitSelection.selected([]).groups(pageCount: 4)
        }
    }

    @Test("operation context exposes bounded progress and cancellation")
    func progressAndCancellation() {
        #expect(PDFOperationProgress(completedUnitCount: 3, totalUnitCount: 4).fractionCompleted == 0.75)
        #expect(PDFOperationProgress(completedUnitCount: 8, totalUnitCount: 4).fractionCompleted == 1)
        let context = PDFOperationContext(outputURL: URL(fileURLWithPath: "/tmp/output.pdf"), isCancelled: { true })
        #expect(throws: PDFOperationError.cancelled) { try context.checkCancellation() }
    }
}
