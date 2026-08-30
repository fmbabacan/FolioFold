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
}
