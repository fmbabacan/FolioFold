import Foundation

public struct WorkspaceSession: Codable, Equatable, Identifiable, Sendable {
    public enum ExternalChangeState: String, Codable, Sendable {
        case unchanged
        case changed
        case missing
    }

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
    public var documentURL: URL?
    public var lastKnownModificationDate: Date?
    public var externalChangeState: ExternalChangeState

    public init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        hasUnsavedChanges: Bool = false,
        recoveryState: RecoveryState = .none,
        saveState: SaveState = .saved,
        documentURL: URL? = nil,
        lastKnownModificationDate: Date? = nil,
        externalChangeState: ExternalChangeState = .unchanged
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.hasUnsavedChanges = hasUnsavedChanges
        self.recoveryState = recoveryState
        self.saveState = saveState
        self.documentURL = documentURL
        self.lastKnownModificationDate = lastKnownModificationDate
        self.externalChangeState = externalChangeState
    }
}

public struct RecentDocument: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var displayName: String
    public var bookmarkData: Data
    public var thumbnailIdentifier: String?
    public var lastOpenedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        bookmarkData: Data,
        thumbnailIdentifier: String? = nil,
        lastOpenedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.bookmarkData = bookmarkData
        self.thumbnailIdentifier = thumbnailIdentifier
        self.lastOpenedAt = lastOpenedAt
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
    public var recents: [RecentDocument]

    public init(
        sessions: [WorkspaceSession],
        selectedSessionID: UUID?,
        recents: [RecentDocument] = []
    ) {
        self.sessions = sessions
        self.selectedSessionID = selectedSessionID
        self.recents = recents
    }

    public static func fresh() -> Self {
        let session = WorkspaceSession(kind: .folioDocument, title: "Untitled")
        return Self(sessions: [session], selectedSessionID: session.id)
    }

    public func encodedForRestoration() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func restored(from data: Data) -> Self? {
        guard !data.isEmpty, var state = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        state.normalizeAfterRestoration()
        return state
    }

    public mutating func normalizeAfterRestoration() {
        let uniqueSessions = Dictionary(grouping: sessions, by: \.id)
            .compactMap { _, matches in matches.first }
        var order: [UUID: Int] = [:]
        for (index, session) in sessions.enumerated() where order[session.id] == nil {
            order[session.id] = index
        }
        sessions = uniqueSessions.sorted {
            (order[$0.id] ?? .max) < (order[$1.id] ?? .max)
        }
        for index in sessions.indices {
            sessions[index].externalChangeState = .unchanged
            if sessions[index].saveState == .saving {
                sessions[index].saveState = .changed
                sessions[index].hasUnsavedChanges = true
            }
        }
        if let selectedSessionID, sessions.contains(where: { $0.id == selectedSessionID }) {
            return
        }
        selectedSessionID = sessions.first?.id
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

    @discardableResult
    public mutating func openDocument(at url: URL) -> UUID {
        let standardizedURL = url.standardizedFileURL
        if let existing = sessions.first(where: { $0.documentURL?.standardizedFileURL == standardizedURL }) {
            selectedSessionID = existing.id
            return existing.id
        }
        let kind: WorkspaceSession.Kind = url.pathExtension.lowercased() == "pdf"
            ? .pdfDocument
            : .folioDocument
        let session = WorkspaceSession(
            kind: kind,
            title: url.deletingPathExtension().lastPathComponent,
            documentURL: standardizedURL,
            lastKnownModificationDate: Self.modificationDate(for: standardizedURL)
        )
        sessions.append(session)
        selectedSessionID = session.id
        return session.id
    }

    public mutating func recordRecent(_ recent: RecentDocument, maximumCount: Int = 12) {
        guard maximumCount > 0 else {
            recents.removeAll()
            return
        }
        recents.removeAll { $0.bookmarkData == recent.bookmarkData }
        recents.insert(recent, at: 0)
        if recents.count > maximumCount {
            recents.removeLast(recents.count - maximumCount)
        }
    }

    public mutating func removeRecent(id: UUID) {
        recents.removeAll { $0.id == id }
    }

    @discardableResult
    public mutating func refreshExternalChangeState(sessionID: UUID) -> WorkspaceSession.ExternalChangeState? {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              let url = sessions[index].documentURL else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else {
            sessions[index].externalChangeState = .missing
            return .missing
        }
        let current = Self.modificationDate(for: url)
        if let known = sessions[index].lastKnownModificationDate,
           let current, current > known {
            sessions[index].externalChangeState = .changed
        } else {
            sessions[index].externalChangeState = .unchanged
        }
        return sessions[index].externalChangeState
    }

    public mutating func acknowledgeExternalChange(sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              let url = sessions[index].documentURL else { return }
        sessions[index].lastKnownModificationDate = Self.modificationDate(for: url)
        sessions[index].externalChangeState = .unchanged
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

    private static func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
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
