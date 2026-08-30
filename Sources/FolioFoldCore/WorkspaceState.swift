import Foundation

public struct WorkspaceSession: Codable, Equatable, Identifiable, Sendable {
    public enum SaveState: String, Codable, Sendable {
        case saved, changed, saving, recoveryAvailable
    }

    public enum RecoveryState: String, Codable, Sendable {
        case none
        case available
        case recovered
    }

    public enum Kind: String, Codable, Sendable {
        case folioDocument
        case pdfDocument
        case merge
        case split
        case convert
    }

    public let id: UUID
    public var kind: Kind
    public var title: String
    public var hasUnsavedChanges: Bool
    public var recoveryState: RecoveryState
    public var saveState: SaveState

    public init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        hasUnsavedChanges: Bool = false,
        recoveryState: RecoveryState = .none,
        saveState: SaveState = .saved
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.hasUnsavedChanges = hasUnsavedChanges
        self.recoveryState = recoveryState
        self.saveState = saveState
    }
}

public struct WorkspaceState: Codable, Equatable, Sendable {
    public enum CloseResult: Equatable, Sendable {
        case closed
        case needsConfirmation
        case notFound
    }

    public var sessions: [WorkspaceSession]
    public var selectedSessionID: UUID?

    public static func fresh() -> Self {
        let session = WorkspaceSession(kind: .folioDocument, title: "Untitled")
        return Self(sessions: [session], selectedSessionID: session.id)
    }

    public mutating func openTool(_ kind: WorkspaceSession.Kind) {
        if let existing = sessions.first(where: { $0.kind == kind }) {
            selectedSessionID = existing.id
            return
        }

        let session = WorkspaceSession(kind: kind, title: kind.title)
        sessions.append(session)
        selectedSessionID = session.id
    }

    public mutating func close(sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let wasSelected = selectedSessionID == sessionID
        sessions.remove(at: index)
        guard wasSelected else { return }
        selectedSessionID = sessions.isEmpty ? nil : sessions[min(index, sessions.count - 1)].id
    }

    public mutating func requestClose(sessionID: UUID) -> CloseResult {
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            return .notFound
        }
        guard !session.hasUnsavedChanges else { return .needsConfirmation }
        close(sessionID: sessionID)
        return .closed
    }

    public mutating func moveSession(from source: Int, to destination: Int) {
        guard sessions.indices.contains(source),
              destination >= 0,
              destination <= sessions.count else { return }
        let session = sessions.remove(at: source)
        sessions.insert(session, at: min(destination, sessions.count))
    }

    public mutating func updateDocumentState(sessionID: UUID, saveState: WorkspaceSession.SaveState) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].saveState = saveState
        sessions[index].hasUnsavedChanges = saveState != .saved
        if saveState == .recoveryAvailable { sessions[index].recoveryState = .available }
    }
}

private extension WorkspaceSession.Kind {
    var title: String {
        switch self {
        case .folioDocument: "Untitled"
        case .pdfDocument: "PDF"
        case .merge: "Merge"
        case .split: "Split"
        case .convert: "Convert"
        }
    }
}
