import Foundation
import Testing
@testable import FolioFoldCore

@Suite("Folio document")
struct FolioDocumentTests {
    @Test("the v1 model exposes every supported block kind")
    func v1BlockKindsAreComplete() {
        #expect(Set(Block.Kind.allCases) == Set([
            .paragraph, .heading, .list, .table, .image, .divider,
            .shape, .formField, .signatureField, .pageBreak
        ]))
    }

    @Test("a blank document carries page settings and package resources")
    func blankDocumentHasCompleteRootModel() {
        let document = FolioDocument.blank()

        #expect(document.pageSettings.size == .a4)
        #expect(document.pageSettings.margins.top == 72)
        #expect(document.templateFields.isEmpty)
        #expect(document.assets.isEmpty)
        #expect(document.sourcePDF == nil)
    }

    @Test("overlay geometry includes rotation z order and lock state")
    func overlayCarriesCompleteGeometry() throws {
        var document = FolioDocument.blank()
        let blockID = try #require(document.flow.first?.id)
        let pageID = document.pages[0].id

        try document.pin(
            blockID: blockID,
            to: pageID,
            frame: FolioRect(x: 10, y: 20, width: 30, height: 40),
            rotationDegrees: 15,
            zIndex: 7,
            isLocked: true
        )

        let overlay = try #require(document.overlays.first)
        #expect(overlay.rotationDegrees == 15)
        #expect(overlay.zIndex == 7)
        #expect(overlay.isLocked)
    }

    @Test("known documents preserve unknown fields when encoded again")
    func unknownFieldsSurviveRoundTrip() throws {
        let json = Data(#"{"formatVersion":{"major":1,"minor":4},"pages":[{"id":"00000000-0000-0000-0000-000000000001"}],"pageSettings":{"size":"a4","width":595,"height":842,"margins":{"top":72,"leading":72,"bottom":72,"trailing":72}},"flow":[],"overlays":[],"templateFields":[],"assets":[],"futureRoot":{"enabled":true}}"#.utf8)

        let opened = try FolioDocumentCodec.decode(json)
        let encoded = try FolioDocumentCodec.encode(opened.document)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect((object["futureRoot"] as? [String: Bool])?["enabled"] == true)
        #expect(!opened.isReadOnly)
    }

    @Test("a newer major version opens read only")
    func newerMajorVersionIsReadOnly() throws {
        let json = Data(#"{"formatVersion":{"major":2,"minor":0},"pages":[],"pageSettings":{"size":"a4","width":595,"height":842,"margins":{"top":72,"leading":72,"bottom":72,"trailing":72}},"flow":[],"overlays":[],"templateFields":[],"assets":[],"futureRoot":"kept"}"#.utf8)

        let opened = try FolioDocumentCodec.decode(json)

        #expect(opened.isReadOnly)
        #expect(opened.document.formatVersion.major == 2)
    }

    @Test("template fields assets and source PDF round trip")
    func documentResourcesRoundTrip() throws {
        var document = FolioDocument.blank()
        document.templateFields = [TemplateField(name: "Invoice number", kind: .sequence, format: "INV-%04d", defaultValue: nil)]
        document.assets = [FolioAsset(path: "assets/logo.png", mediaType: "image/png", checksum: "abc")]
        document.sourcePDF = SourcePDFInfo(path: "source/original.pdf", checksum: "def", pageCount: 2)

        let data = try FolioDocumentCodec.encode(document)
        let decoded = try FolioDocumentCodec.decode(data).document

        #expect(decoded.templateFields == document.templateFields)
        #expect(decoded.assets == document.assets)
        #expect(decoded.sourcePDF == document.sourcePDF)
    }

    @Test("a new document starts with one editable paragraph")
    func newDocumentStartsWithOneEditableParagraph() {
        let document = FolioDocument.blank()

        #expect(document.formatVersion == FormatVersion(major: 1))
        #expect(document.flow.count == 1)
        #expect(document.flow[0].kind == .paragraph)
        #expect(document.flow[0].text.isEmpty)
    }

    @Test("pinning a block removes it from flow and creates a page overlay")
    func pinningMovesBlockToOverlay() throws {
        var document = FolioDocument.blank()
        let blockID = try #require(document.flow.first?.id)
        let pageID = document.pages[0].id

        try document.pin(blockID: blockID, to: pageID, frame: FolioRect(x: 72, y: 72, width: 240, height: 80))

        #expect(document.flow.isEmpty)
        #expect(document.overlays.count == 1)
        #expect(document.overlays[0].sourceBlockID == blockID)
        #expect(document.overlays[0].pageID == pageID)
    }

    @Test("returning an overlay restores the original block position")
    func returningOverlayRestoresFlow() throws {
        var document = FolioDocument.blank()
        let blockID = try #require(document.flow.first?.id)
        let pageID = document.pages[0].id
        try document.pin(blockID: blockID, to: pageID, frame: FolioRect(x: 72, y: 72, width: 240, height: 80))
        let overlayID = try #require(document.overlays.first?.id)

        try document.returnToFlow(overlayID: overlayID)

        #expect(document.overlays.isEmpty)
        #expect(document.flow.map(\.id) == [blockID])
    }
}
