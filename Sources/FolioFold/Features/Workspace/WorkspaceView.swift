import FolioFoldCore
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let folioFoldSelectNextTab = Notification.Name("FolioFold.selectNextTab")
    static let folioFoldSelectPreviousTab = Notification.Name("FolioFold.selectPreviousTab")
    static let folioFoldCloseCurrentTab = Notification.Name("FolioFold.closeCurrentTab")
}

struct WorkspaceView: View {
    let openRequest: Int
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var workspace = WorkspaceState.fresh()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var pendingClose: WorkspaceSession?
    @State private var isImporting = false
    @State private var presentedError: String?
    @State private var externalChangeSession: WorkspaceSession?
    @State private var documentReloadToken = 0
    @State private var isOpenDropTargeted = false
    @State private var externalChangeTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    @AppStorage("recentDocuments") private var storedRecents = Data()
    @AppStorage("workspaceRestorationState") private var storedWorkspace = Data()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                Button("Create", systemImage: "square.and.pencil") {
                    workspace = .fresh()
                }
                .keyboardShortcut("n")
                .accessibilityIdentifier("sidebar.create")

                Button("Open", systemImage: "folder") { isImporting = true }
                    .keyboardShortcut("o")
                    .accessibilityIdentifier("sidebar.open")

                toolButton("Merge", systemImage: "rectangle.stack", kind: .merge)
                toolButton("Split", systemImage: "scissors", kind: .split)
                toolButton("Convert", systemImage: "arrow.triangle.2.circlepath", kind: .convert)

                Section("Recents") {
                    if workspace.recents.isEmpty {
                        Text("No recent documents")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(workspace.recents) { recent in
                            HStack {
                                Button { openRecent(recent) } label: {
                                    Label(recent.displayName, systemImage: "clock.arrow.circlepath")
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Button {
                                    workspace.removeRecent(id: recent.id)
                                    persistRecents()
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove recent document")
                            }
                        }
                    }
                }

                Section("Sidebar Width") {
                    HStack {
                        Button("Narrower", systemImage: "arrow.left.to.line") {
                            SplitPanelAdjustment.workspaceSidebar.post(delta: -20)
                        }
                        .accessibilityIdentifier("sidebar.width.decrease")

                        Button("Wider", systemImage: "arrow.right.to.line") {
                            SplitPanelAdjustment.workspaceSidebar.post(delta: 20)
                        }
                        .accessibilityIdentifier("sidebar.width.increase")
                    }
                }
            }
            .navigationSplitViewColumnWidth(
                min: DesignTokens.sidebarMinimumWidth,
                ideal: DesignTokens.sidebarIdealWidth,
                max: DesignTokens.sidebarMaximumWidth
            )
            .navigationTitle("FolioFold")
            .accessibilityIdentifier("workspace.sidebar")
        } detail: {
            VStack(spacing: 0) {
                tabStrip
                Divider()
                content
            }
            .id(workspace.selectedSessionID)
        }
        .background {
            PersistentSplitView(
                autosaveName: "FolioFold.WorkspaceSplit",
                panels: [.workspaceSidebar]
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .tint(DesignTokens.inkBlue)
        .transaction { transaction in
            if reduceMotion {
                transaction.disablesAnimations = true
            }
        }
        .overlay {
            if isOpenDropTargeted {
                ZStack {
                    Color.black.opacity(0.18)
                    Label("Drop PDFs or FolioFold Documents to Open", systemImage: "folder.badge.plus")
                        .font(.title2.bold())
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityLabel("Drop PDFs or FolioFold documents to open")
                .accessibilityIdentifier("workspace.open-drop-target")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            acceptDroppedDocuments(urls)
        } isTargeted: { isOpenDropTargeted = $0 }
        .onAppear {
            restoreWorkspace()
            signalRuntimeReadinessIfRequested()
        }
        .onChange(of: workspace) { _, _ in persistWorkspace() }
        .onChange(of: openRequest) { _, _ in isImporting = true }
        .onReceive(externalChangeTimer) { _ in checkSelectedDocumentForExternalChanges() }
        .onReceive(NotificationCenter.default.publisher(for: .folioFoldSelectNextTab)) { _ in
            workspace.selectAdjacentSession(forward: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .folioFoldSelectPreviousTab)) { _ in
            workspace.selectAdjacentSession(forward: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .folioFoldCloseCurrentTab)) { _ in
            closeSelectedSession()
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.pdf, UTType(filenameExtension: "foliofold") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            do {
                for url in try result.get() {
                    openDocument(url)
                }
            } catch {
                presentedError = error.localizedDescription
            }
        }
        .alert("Unable to Open Document", isPresented: Binding(
            get: { presentedError != nil },
            set: { if !$0 { presentedError = nil } }
        )) {
            Button("OK") { presentedError = nil }
        } message: {
            Text(presentedError ?? "")
        }
        .confirmationDialog(
            "Document Changed Outside FolioFold",
            isPresented: Binding(
                get: { externalChangeSession != nil },
                set: { if !$0 { externalChangeSession = nil } }
            ),
            presenting: externalChangeSession
        ) { session in
            if session.externalChangeState == .changed {
                Button("Reload from Disk") { reload(session) }
                Button("Keep Current Work") { continueWithCurrentWork(session) }
            }
            Button("Save a Copy…") {
                workspace.selectedSessionID = session.id
                externalChangeSession = nil
            }
            Button("Cancel", role: .cancel) { externalChangeSession = nil }
        } message: { session in
            Text(session.externalChangeState == .missing
                ? "The source file is no longer available. Save a copy to preserve the current work."
                : "The source file changed on disk. Reload it, save a copy, or continue with the current work.")
        }
        .confirmationDialog(
            "Close Unsaved Session?",
            isPresented: Binding(
                get: { pendingClose != nil },
                set: { if !$0 { pendingClose = nil } }
            ),
            presenting: pendingClose
        ) { session in
            Button("Close Without Saving", role: .destructive) {
                workspace.close(sessionID: session.id)
                pendingClose = nil
            }
            Button("Cancel", role: .cancel) { pendingClose = nil }
        } message: { session in
            Text("Changes to \(session.title) will be lost.")
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: DesignTokens.tabSpacing) {
                    ForEach(Array(workspace.sessions.enumerated()), id: \.element.id) { index, session in
                        tab(session, at: index)
                    }
                }
                .padding(6)
            }

            if workspace.sessions.count > 1 {
                Menu {
                    ForEach(workspace.sessions) { session in
                        Button {
                            workspace.selectedSessionID = session.id
                            announce("Selected \(session.title) tab")
                        } label: {
                            Label(session.title, systemImage: icon(for: session.kind))
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.trailing, 8)
                .help("Show all open tabs")
                .accessibilityLabel("Open tabs menu")
                .accessibilityIdentifier("workspace.tabs.overflow")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace tabs")
    }

    private func tab(_ session: WorkspaceSession, at index: Int) -> some View {
        let isSelected = workspace.selectedSessionID == session.id

        return HStack(spacing: 6) {
            Button {
                workspace.selectedSessionID = session.id
                announce("Selected \(session.title) tab")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon(for: session.kind))
                    Text(session.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if session.recoveryState != .none {
                        Image(systemName: "arrow.counterclockwise.circle")
                            .accessibilityLabel("Recovered")
                    }
                    if session.hasUnsavedChanges {
                        Label("Unsaved", systemImage: "circle.fill")
                            .font(.caption2.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .accessibilityLabel("Unsaved changes")
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("workspace.tab.select.\(session.id.uuidString)")
            .accessibilityLabel("Select \(session.title) tab")
            .accessibilityValue(tabAccessibilityValue(for: session))
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button {
                close(session)
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityIdentifier("workspace.tab.close.\(session.id.uuidString)")
            .accessibilityLabel("Close \(session.title) tab")
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
        .background(
            isSelected
                ? DesignTokens.inkBlue.opacity(colorSchemeContrast == .increased ? 0.30 : 0.18)
                : .clear,
            in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                .stroke(
                    isSelected
                        ? (differentiateWithoutColor ? Color.primary : DesignTokens.inkBlue)
                        : Color.secondary.opacity(0.25),
                    lineWidth: isSelected
                        ? (colorSchemeContrast == .increased || differentiateWithoutColor ? 3 : 2)
                        : 1
                )
        }
        .help(tabHelp(for: session))
        .draggable(session.id.uuidString)
        .dropDestination(for: String.self) { sessionIDs, _ in
            guard let sessionID = sessionIDs.first,
                  let id = UUID(uuidString: sessionID),
                  let source = workspace.sessions.firstIndex(where: { $0.id == id }) else {
                return false
            }
            workspace.moveSession(from: source, to: index)
            announce("Moved \(session.title) tab to position \(index + 1)")
            return true
        }
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp.mainWindow as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
        )
    }

    @ViewBuilder
    private var content: some View {
        if let session = workspace.sessions.first(where: { $0.id == workspace.selectedSessionID }) {
            sessionContent(session)
        } else {
            ContentUnavailableView(
                "No Open Session",
                systemImage: "doc",
                description: Text("Create or open a document to begin.")
            )
        }
    }

    @ViewBuilder
    private func sessionContent(_ session: WorkspaceSession) -> some View {
        switch session.kind {
        case .pdfDocument:
            if let url = session.documentURL {
                PDFWorkspace(url: url)
                    .id("\(session.id.uuidString)-\(documentReloadToken)")
                    .accessibilityLabel(Text("PDF document \(session.title)"))
            } else {
                emptySession(session)
            }
        case .folioDocument:
            FolioDocumentWorkspace(
                title: session.title,
                url: session.documentURL,
                onSaveStateChange: { saveState in
                    workspace.updateDocumentState(sessionID: session.id, saveState: saveState)
                }
            )
                .id("\(session.id.uuidString)-\(documentReloadToken)")
        case .merge:
            MergeWorkspace()
        case .split:
            SplitWorkspace()
        case .convert:
            ConvertWorkspace()
        }
    }

    private func emptySession(_ session: WorkspaceSession) -> some View {
        ContentUnavailableView(
            session.title,
            systemImage: icon(for: session.kind),
            description: Text(description(for: session.kind))
        )
    }

    private func close(_ session: WorkspaceSession) {
        if workspace.requestClose(sessionID: session.id) == .needsConfirmation {
            pendingClose = session
        }
    }

    private func closeSelectedSession() {
        guard let selectedSessionID = workspace.selectedSessionID,
              let session = workspace.sessions.first(where: { $0.id == selectedSessionID }) else { return }
        close(session)
    }

    private func tabAccessibilityValue(for session: WorkspaceSession) -> String {
        var values = [workspace.selectedSessionID == session.id ? "Selected" : "Not selected"]
        if session.hasUnsavedChanges { values.append("Unsaved changes") }
        if session.recoveryState != .none { values.append("Recovery data available") }
        return values.joined(separator: ", ")
    }

    private func tabHelp(for session: WorkspaceSession) -> String {
        var value = session.title
        if session.hasUnsavedChanges { value += " - Unsaved changes" }
        if session.recoveryState != .none { value += " - Recovery data available" }
        return value
    }

    private func openDocument(_ url: URL) {
        _ = workspace.openDocument(at: url)
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: [.nameKey, .contentModificationDateKey],
                relativeTo: nil
            )
            workspace.recordRecent(.init(
                displayName: url.deletingPathExtension().lastPathComponent,
                bookmarkData: bookmark,
                thumbnailIdentifier: url.pathExtension.lowercased() == "pdf" ? url.lastPathComponent : nil
            ))
            persistRecents()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    private func openRecent(_ recent: RecentDocument) {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: recent.bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard url.startAccessingSecurityScopedResource() else {
                throw CocoaError(.fileReadNoPermission)
            }
            defer { url.stopAccessingSecurityScopedResource() }
            openDocument(url)
            if isStale { persistRecents() }
        } catch {
            workspace.removeRecent(id: recent.id)
            persistRecents()
            presentedError = error.localizedDescription
        }
    }

    private func restoreRecents() {
        guard !storedRecents.isEmpty,
              let recents = try? JSONDecoder().decode([RecentDocument].self, from: storedRecents) else { return }
        workspace.recents = recents.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    private func persistRecents() {
        storedRecents = (try? JSONEncoder().encode(workspace.recents)) ?? Data()
        persistWorkspace()
    }

    private func restoreWorkspace() {
        if let restored = WorkspaceState.restored(from: storedWorkspace) {
            workspace = restored
        }
        restoreRecents()
    }

    private func persistWorkspace() {
        storedWorkspace = (try? workspace.encodedForRestoration()) ?? Data()
    }

    private func acceptDroppedDocuments(_ urls: [URL]) -> Bool {
        let supported = urls.filter {
            let extensionName = $0.pathExtension.lowercased()
            return extensionName == "pdf" || extensionName == "foliofold"
        }
        for url in supported { openDocument(url) }
        let rejected = urls.count - supported.count
        if rejected > 0 {
            presentedError = "FolioFold can open PDF and .foliofold documents. Rejected \(rejected) unsupported file\(rejected == 1 ? "" : "s")."
        }
        return !supported.isEmpty
    }

    private func signalRuntimeReadinessIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["FOLIOFOLD_READY_FILE"],
              !path.isEmpty else { return }
        try? Data("ready".utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func checkSelectedDocumentForExternalChanges() {
        guard externalChangeSession == nil, let sessionID = workspace.selectedSessionID,
              let state = workspace.refreshExternalChangeState(sessionID: sessionID),
              state != .unchanged,
              let session = workspace.sessions.first(where: { $0.id == sessionID }) else { return }
        externalChangeSession = session
    }

    private func reload(_ session: WorkspaceSession) {
        workspace.acknowledgeExternalChange(sessionID: session.id)
        documentReloadToken += 1
        externalChangeSession = nil
    }

    private func continueWithCurrentWork(_ session: WorkspaceSession) {
        workspace.acknowledgeExternalChange(sessionID: session.id)
        workspace.updateDocumentState(sessionID: session.id, saveState: .changed)
        externalChangeSession = nil
    }

    private func toolButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        kind: WorkspaceSession.Kind
    ) -> some View {
        let isOpen = workspace.sessions.contains(where: { $0.kind == kind })
        let isSelected = workspace.sessions.first(where: { $0.id == workspace.selectedSessionID })?.kind == kind

        return Button {
            workspace.openTool(kind)
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if isOpen {
                    Text("Open")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isSelected ? DesignTokens.inkBlue : Color.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
            .accessibilityValue(
                isSelected
                    ? "Open and selected"
                    : (isOpen ? "Open in another tab" : "Not open")
            )
            .accessibilityHint(
                isOpen
                    ? "Focuses the existing workspace and preserves its current state."
                    : "Opens one reusable workspace for this tool."
            )
            .accessibilityIdentifier("sidebar.\(kind.rawValue)")
    }

    private func icon(for kind: WorkspaceSession.Kind) -> String {
        switch kind {
        case .folioDocument: "doc.text"
        case .pdfDocument: "doc.richtext"
        case .merge: "rectangle.stack"
        case .split: "scissors"
        case .convert: "arrow.triangle.2.circlepath"
        }
    }

    private func description(for kind: WorkspaceSession.Kind) -> LocalizedStringKey {
        switch kind {
        case .folioDocument: "Start writing with blocks. Pin an item when it needs a fixed page position."
        case .pdfDocument: "The source PDF will remain unchanged until you explicitly export or replace it."
        case .merge: "Add PDFs and arrange them in the order they should be combined."
        case .split: "Choose pages or ranges to export as separate PDFs."
        case .convert: "Convert supported local files without uploading them."
        }
    }
}
