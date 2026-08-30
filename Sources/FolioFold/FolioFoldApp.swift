import FolioFoldCore
import SwiftUI

@main
struct FolioFoldApp: App {
    var body: some Scene {
        WindowGroup {
            WorkspaceView()
                .frame(minWidth: 820, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .commands {
            SidebarCommands()
            CommandGroup(after: .newItem) {
                Button("Open…") {}
                    .keyboardShortcut("o")
            }
        }
    }
}

private struct WorkspaceView: View {
    @State private var workspace = WorkspaceState.fresh()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var pendingClose: WorkspaceSession?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                Button("Create", systemImage: "square.and.pencil") {
                    workspace = .fresh()
                }
                .keyboardShortcut("n")

                Button("Open", systemImage: "folder") {}
                    .keyboardShortcut("o")

                toolButton("Merge", systemImage: "rectangle.stack", kind: .merge)
                toolButton("Split", systemImage: "scissors", kind: .split)
                toolButton("Convert", systemImage: "arrow.triangle.2.circlepath", kind: .convert)

                Section("Recents") {
                    Text("No recent documents")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationSplitViewColumnWidth(
                min: DesignTokens.sidebarMinimumWidth,
                ideal: DesignTokens.sidebarIdealWidth,
                max: DesignTokens.sidebarMaximumWidth
            )
            .navigationTitle("FolioFold")
        } detail: {
            VStack(spacing: 0) {
                tabStrip
                Divider()
                content
            }
        }
        .tint(DesignTokens.inkBlue)
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
        ScrollView(.horizontal) {
            HStack(spacing: DesignTokens.tabSpacing) {
                ForEach(Array(workspace.sessions.enumerated()), id: \.element.id) { index, session in
                    tab(session, at: index)
                }
            }
            .padding(6)
            .accessibilityLabel("Workspace tabs")
        }
    }

    private func tab(_ session: WorkspaceSession, at index: Int) -> some View {
        HStack(spacing: 6) {
            Button {
                workspace.selectedSessionID = session.id
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon(for: session.kind))
                    Text(session.title)
                    if session.recoveryState != .none {
                        Image(systemName: "arrow.counterclockwise.circle")
                            .accessibilityLabel("Recovered")
                    }
                    if session.hasUnsavedChanges {
                        Circle()
                            .frame(width: 6, height: 6)
                            .accessibilityLabel("Unsaved changes")
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(session.title) tab")

            Button {
                close(session)
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(Text("Close \(session.title) tab"))
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            workspace.selectedSessionID == session.id
                ? Color.primary.opacity(0.08)
                : .clear,
            in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
        )
        .draggable(session.id.uuidString)
        .dropDestination(for: String.self) { sessionIDs, _ in
            guard let sessionID = sessionIDs.first,
                  let id = UUID(uuidString: sessionID),
                  let source = workspace.sessions.firstIndex(where: { $0.id == id }) else {
                return false
            }
            workspace.moveSession(from: source, to: index)
            return true
        }
    }

    @ViewBuilder
    private var content: some View {
        if let session = workspace.sessions.first(where: { $0.id == workspace.selectedSessionID }) {
            ContentUnavailableView(
                session.title,
                systemImage: icon(for: session.kind),
                description: Text(description(for: session.kind))
            )
        } else {
            ContentUnavailableView(
                "No Open Session",
                systemImage: "doc",
                description: Text("Create or open a document to begin.")
            )
        }
    }

    private func close(_ session: WorkspaceSession) {
        if workspace.requestClose(sessionID: session.id) == .needsConfirmation {
            pendingClose = session
        }
    }

    private func toolButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        kind: WorkspaceSession.Kind
    ) -> some View {
        Button(title, systemImage: systemImage) { workspace.openTool(kind) }
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
