import Foundation
import Testing
@testable import FolioFoldCore

@Suite("Workspace sessions")
struct WorkspaceSessionTests {
    @Test("a new workspace starts with one untitled document")
    func newWorkspaceStartsWithDocument() {
        let workspace = WorkspaceState.fresh()

        #expect(workspace.sessions.count == 1)
        #expect(workspace.sessions[0].kind == .folioDocument)
        #expect(workspace.sessions[0].title == "Untitled")
        #expect(workspace.selectedSessionID == workspace.sessions[0].id)
    }

    @Test("opening a tool selects its reusable session")
    func openingToolSelectsReusableSession() {
        var workspace = WorkspaceState.fresh()

        workspace.openTool(.merge)
        let firstMergeID = workspace.selectedSessionID
        workspace.openTool(.merge)

        #expect(workspace.sessions.filter { $0.kind == .merge }.count == 1)
        #expect(workspace.selectedSessionID == firstMergeID)
    }

    @Test("closing the selected session chooses its nearest neighbor")
    func closingSelectedSessionChoosesNeighbor() throws {
        var workspace = WorkspaceState.fresh()
        workspace.openTool(.split)
        let splitID = try #require(workspace.selectedSessionID)
        workspace.openTool(.convert)

        workspace.close(sessionID: workspace.selectedSessionID!)

        #expect(workspace.selectedSessionID == splitID)
    }

    @Test("moving a session preserves selection and changes tab order")
    func movingSessionChangesOrder() throws {
        var workspace = WorkspaceState.fresh()
        workspace.openTool(.merge)
        workspace.openTool(.split)
        let selectedID = try #require(workspace.selectedSessionID)

        workspace.moveSession(from: 2, to: 0)

        #expect(workspace.sessions.map(\.kind) == [.split, .folioDocument, .merge])
        #expect(workspace.selectedSessionID == selectedID)
    }

    @Test("a dirty session requests confirmation instead of closing")
    func dirtySessionRequiresConfirmation() throws {
        var workspace = WorkspaceState.fresh()
        let sessionID = try #require(workspace.selectedSessionID)
        workspace.sessions[0].hasUnsavedChanges = true

        let result = workspace.requestClose(sessionID: sessionID)

        #expect(result == .needsConfirmation)
        #expect(workspace.sessions.map(\.id) == [sessionID])
    }

    @Test("a clean session closes immediately")
    func cleanSessionClosesImmediately() throws {
        var workspace = WorkspaceState.fresh()
        let sessionID = try #require(workspace.selectedSessionID)

        let result = workspace.requestClose(sessionID: sessionID)

        #expect(result == .closed)
        #expect(workspace.sessions.isEmpty)
    }

    @Test("recovery state is distinct from unsaved changes")
    func recoveryStateIsIndependent() {
        let session = WorkspaceSession(
            kind: .pdfDocument,
            title: "Recovered PDF",
            hasUnsavedChanges: false,
            recoveryState: .recovered
        )

        #expect(session.recoveryState == .recovered)
        #expect(!session.hasUnsavedChanges)
    }

    @Test("document save state drives dirty and recovery tab indicators")
    func documentSaveStateUpdatesSession() throws {
        var workspace = WorkspaceState.fresh()
        let sessionID = try #require(workspace.selectedSessionID)

        workspace.updateDocumentState(sessionID: sessionID, saveState: .saving)
        #expect(workspace.sessions[0].saveState == .saving)
        #expect(workspace.sessions[0].hasUnsavedChanges)

        workspace.updateDocumentState(sessionID: sessionID, saveState: .saved)
        #expect(workspace.sessions[0].saveState == .saved)
        #expect(!workspace.sessions[0].hasUnsavedChanges)

        workspace.updateDocumentState(sessionID: sessionID, saveState: .recoveryAvailable)
        #expect(workspace.sessions[0].recoveryState == .available)
    }

    @Test("recents deduplicate bookmark data and enforce their limit")
    func recentsAreBounded() {
        var workspace = WorkspaceState.fresh()
        workspace.recordRecent(.init(displayName: "First", bookmarkData: Data([1])), maximumCount: 2)
        workspace.recordRecent(.init(displayName: "Second", bookmarkData: Data([2])), maximumCount: 2)
        workspace.recordRecent(.init(displayName: "First Again", bookmarkData: Data([1])), maximumCount: 2)

        #expect(workspace.recents.map(\.displayName) == ["First Again", "Second"])
    }

    @Test("external file changes and deletion are detected")
    func detectsExternalChanges() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url)
        var workspace = WorkspaceState.fresh()
        let sessionID = workspace.openDocument(at: url)
        workspace.sessions[1].lastKnownModificationDate = Date(timeIntervalSince1970: 0)

        #expect(workspace.refreshExternalChangeState(sessionID: sessionID) == .changed)
        workspace.acknowledgeExternalChange(sessionID: sessionID)
        #expect(workspace.sessions[1].externalChangeState == .unchanged)

        try FileManager.default.removeItem(at: url)
        #expect(workspace.refreshExternalChangeState(sessionID: sessionID) == .missing)
    }

    @Test("workspace restoration preserves tab order and selection")
    func workspaceRestorationRoundTrips() throws {
        var workspace = WorkspaceState.fresh()
        workspace.openTool(.merge)
        workspace.openTool(.split)
        workspace.moveSession(from: 2, to: 0)
        let selectedID = try #require(workspace.selectedSessionID)

        let restored = try #require(WorkspaceState.restored(from: workspace.encodedForRestoration()))

        #expect(restored.sessions.map(\.kind) == [.split, .folioDocument, .merge])
        #expect(restored.selectedSessionID == selectedID)
    }

    @Test("workspace restoration repairs transient and invalid state")
    func workspaceRestorationNormalizesState() throws {
        let session = WorkspaceSession(
            kind: .folioDocument,
            title: "Interrupted",
            saveState: .saving,
            externalChangeState: .changed
        )
        let workspace = WorkspaceState(
            sessions: [session, session],
            selectedSessionID: UUID()
        )

        let restored = try #require(WorkspaceState.restored(from: workspace.encodedForRestoration()))

        #expect(restored.sessions.count == 1)
        #expect(restored.selectedSessionID == session.id)
        #expect(restored.sessions[0].saveState == .changed)
        #expect(restored.sessions[0].hasUnsavedChanges)
        #expect(restored.sessions[0].externalChangeState == .unchanged)
        #expect(WorkspaceState.restored(from: Data("invalid".utf8)) == nil)
    }
}
