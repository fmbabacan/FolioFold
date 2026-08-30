import FolioFoldCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct FolioFoldApp: App {
    @State private var openRequest = 0
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var isShowingWelcome = false

    var body: some Scene {
        WindowGroup {
            WorkspaceView(openRequest: openRequest)
                .frame(minWidth: 820, minHeight: 560)
                .onAppear {
                    let isAutomatedRun = ProcessInfo.processInfo.environment["FOLIOFOLD_READY_FILE"] != nil
                    if !hasSeenWelcome && !isAutomatedRun {
                        isShowingWelcome = true
                        hasSeenWelcome = true
                    }
                }
                .sheet(isPresented: $isShowingWelcome) {
                    FolioFoldWelcomeView()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            SidebarCommands()
            CommandGroup(after: .newItem) {
                Button("Open…") { openRequest += 1 }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .help) {
                Button("FolioFold Help and Source") {
                    NSWorkspace.shared.open(FolioFoldRelease.repositoryURL)
                }
                Button("Check for Updates…") {
                    NSWorkspace.shared.open(FolioFoldRelease.releasesURL)
                }
                Divider()
                Button("Contact Support…") {
                    FolioFoldRelease.openSupportEmail()
                }
                Divider()
                Text("Version \(FolioFoldRelease.displayVersion)")
            }
        }
    }
}

private struct WorkspaceView: View {
    let openRequest: Int
    @State private var workspace = WorkspaceState.fresh()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var pendingClose: WorkspaceSession?
    @State private var isImporting = false
    @State private var presentedError: String?
    @State private var externalChangeSession: WorkspaceSession?
    @State private var documentReloadToken = 0
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
        }
        .tint(DesignTokens.inkBlue)
        .onAppear {
            restoreWorkspace()
            signalRuntimeReadinessIfRequested()
        }
        .onChange(of: workspace) { _, _ in persistWorkspace() }
        .onChange(of: openRequest) { _, _ in isImporting = true }
        .onReceive(externalChangeTimer) { _ in checkSelectedDocumentForExternalChanges() }
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
        ScrollView(.horizontal) {
            HStack(spacing: DesignTokens.tabSpacing) {
                ForEach(Array(workspace.sessions.enumerated()), id: \.element.id) { index, session in
                    tab(session, at: index)
                }
            }
            .padding(6)
            .accessibilityLabel("Workspace tabs")
            .accessibilityIdentifier("workspace.tabs")
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
            .accessibilityIdentifier("workspace.tab.\(session.kind.rawValue)")

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
            FolioDocumentWorkspace(title: session.title, url: session.documentURL)
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
        Button(title, systemImage: systemImage) { workspace.openTool(kind) }
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

private struct PDFDocumentView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.document = document
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
    }
}

private struct PDFWorkspace: View {
    private enum FormTool: String, CaseIterable, Identifiable {
        case text, checkBox, radioButton, choice, signature
        var id: String { rawValue }
        var title: String {
            switch self {
            case .text: "Text Field"
            case .checkBox: "Check Box"
            case .radioButton: "Radio Button"
            case .choice: "Choice List"
            case .signature: "Signature Field"
            }
        }
    }

    private enum AnnotationTool: String, CaseIterable, Identifiable {
        case note, highlight, link, rectangle, ink, image, signature
        var id: String { rawValue }
        var title: String {
            switch self {
            case .note: "Text Note"
            case .highlight: "Highlight"
            case .link: "Link"
            case .rectangle: "Shape"
            case .ink: "Drawing"
            case .image: "Image"
            case .signature: "Visual Signature"
            }
        }
    }

    let url: URL
    @State private var document: PDFDocument
    @State private var selectedPage = 0
    @State private var note = ""
    @State private var annotationTool: AnnotationTool = .note
    @State private var linkDestination = "https://"
    @State private var importedAnnotationData: Data?
    @State private var isImportingAnnotationImage = false
    @State private var isConfirmingSourceReplacement = false
    @State private var formFieldName = "field"
    @State private var formFieldValue = ""
    @State private var formTool: FormTool = .text
    @State private var formChoices = "Option 1, Option 2"
    @State private var pdfPassword = ""
    @State private var isRequestingPDFPassword = false
    @State private var redactionX = 72.0
    @State private var redactionY = 72.0
    @State private var redactionWidth = 180.0
    @State private var redactionHeight = 36.0
    @State private var message: String?
    @State private var isRunning = false
    @State private var progress = 0.0
    @State private var draggedPageIndex: Int?

    init(url: URL) {
        self.url = url
        let opened = PDFDocument(url: url) ?? PDFDocument()
        _document = State(initialValue: opened)
        _isRequestingPDFPassword = State(initialValue: opened.isLocked)
    }

    var body: some View {
        HSplitView {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(0..<document.pageCount, id: \.self) { index in
                        Button {
                            selectedPage = index
                        } label: {
                            VStack(spacing: 6) {
                                if let page = document.page(at: index) {
                                    Image(nsImage: page.thumbnail(
                                        of: CGSize(width: 112, height: 150),
                                        for: .mediaBox
                                    ))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 112, height: 150)
                                    .background(Color.white)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(
                                                selectedPage == index ? DesignTokens.inkBlue : Color.secondary.opacity(0.25),
                                                lineWidth: selectedPage == index ? 2 : 1
                                            )
                                    }
                                }
                                Text("Page \(index + 1)")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Page \(index + 1) thumbnail")
                        .draggable(String(index)) {
                            draggedPageIndex = index
                            return Text("Page \(index + 1)")
                        }
                        .dropDestination(for: String.self) { values, _ in
                            guard let sourceText = values.first,
                                  let source = Int(sourceText),
                                  source != index else { return false }
                            movePage(from: source, to: index)
                            draggedPageIndex = nil
                            return true
                        } isTargeted: { _ in }
                    }
                }
                .padding(12)
            }
            .frame(minWidth: 145, idealWidth: 160, maxWidth: 190)
            .accessibilityLabel("Page thumbnails")

            VStack(spacing: 0) {
                HStack {
                    Button("Move Up", systemImage: "arrow.up") { movePage(by: -1) }
                        .disabled(selectedPage == 0 || isRunning)
                    Button("Move Down", systemImage: "arrow.down") { movePage(by: 1) }
                        .disabled(selectedPage >= document.pageCount - 1 || isRunning)
                    Button("Rotate", systemImage: "rotate.right") { rotatePage() }
                        .disabled(document.pageCount == 0 || isRunning)
                    Button("Duplicate", systemImage: "plus.square.on.square") { duplicatePage() }
                        .disabled(document.pageCount == 0 || isRunning)
                    Button("Delete", systemImage: "trash", role: .destructive) { deletePage() }
                        .disabled(document.pageCount <= 1 || isRunning)
                    Spacer()
                    Button("Export PDF…") { exportWorkingPDF() }
                        .disabled(document.pageCount == 0 || isRunning)
                    Button("Replace Source…", role: .destructive) {
                        isConfirmingSourceReplacement = true
                    }
                    .disabled(document.pageCount == 0 || isRunning)
                }
                .padding(10)
                Divider()
                PDFDocumentView(document: document)
            }
            .frame(minWidth: 500)

            Form {
                Section("Pages") {
                    Picker("Selected page", selection: $selectedPage) {
                        ForEach(0..<max(1, document.pageCount), id: \.self) { index in
                            Text("Page \(index + 1)").tag(index)
                        }
                    }
                    .disabled(document.pageCount == 0)
                    Button("Export Page Images…") { exportImages() }
                        .disabled(document.pageCount == 0 || isRunning)
                }
                Section("Annotation") {
                    Picker("Annotation type", selection: $annotationTool) {
                        ForEach(AnnotationTool.allCases) { tool in
                            Text(tool.title).tag(tool)
                        }
                    }
                    if annotationTool == .note {
                        TextField("Note text", text: $note)
                    }
                    if annotationTool == .link {
                        TextField("Link destination", text: $linkDestination)
                    }
                    if annotationTool == .image || annotationTool == .signature {
                        Button(annotationTool == .signature ? "Choose Signature Image…" : "Choose Image…") {
                            isImportingAnnotationImage = true
                        }
                        if annotationTool == .signature {
                            SignatureCaptureButton(selectedData: $importedAnnotationData) { message = $0 }
                        }
                        Text(importedAnnotationData == nil ? "No image selected" : "Image ready")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if annotationTool == .signature {
                        Text("A visual signature is an image annotation, not a certified digital signature.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Add Annotation and Export…") { addSelectedAnnotation() }
                        .disabled(!canAddSelectedAnnotation || document.pageCount == 0 || isRunning)
                }
                Section("Form Field") {
                    Picker("Field type", selection: $formTool) {
                        ForEach(FormTool.allCases) { tool in
                            Text(tool.title).tag(tool)
                        }
                    }
                    TextField("Field name", text: $formFieldName)
                    TextField("Default value", text: $formFieldValue)
                    if formTool == .choice {
                        TextField("Choices separated by commas", text: $formChoices)
                    }
                    Button("Add Form Field and Export…") { addFormField() }
                        .disabled(formFieldName.isEmpty || document.pageCount == 0 || isRunning)
                }
                Section("Redaction") {
                    Text("Coordinates use PDF page points. Applying redactions creates a new rasterized PDF and never overwrites the source.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("X") { TextField("X", value: $redactionX, format: .number) }
                    LabeledContent("Y") { TextField("Y", value: $redactionY, format: .number) }
                    LabeledContent("Width") { TextField("Width", value: $redactionWidth, format: .number) }
                    LabeledContent("Height") { TextField("Height", value: $redactionHeight, format: .number) }
                    Button("Apply Redaction to New PDF…", role: .destructive) { applyRedaction() }
                        .disabled(redactionWidth <= 0 || redactionHeight <= 0 || document.pageCount == 0 || isRunning)
                }
                OperationStatusView(isRunning: isRunning, progress: progress, message: message)
            }
            .formStyle(.grouped)
            .frame(minWidth: 290, idealWidth: 330, maxWidth: 400)
        }
        .fileImporter(
            isPresented: $isImportingAnnotationImage,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let selectedURL = try result.get().first else { return }
                importedAnnotationData = try Data(contentsOf: selectedURL)
                message = nil
            } catch {
                message = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Replace Source PDF?",
            isPresented: $isConfirmingSourceReplacement
        ) {
            Button("Replace Source PDF", role: .destructive) { replaceSourcePDF() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This explicitly replaces the original PDF after writing and verifying a temporary copy. This action cannot be undone.")
        }
        .alert("PDF Password Required", isPresented: $isRequestingPDFPassword) {
            SecureField("Password", text: $pdfPassword)
            Button("Unlock PDF") { unlockPDF() }
                .disabled(pdfPassword.isEmpty)
            Button("Cancel", role: .cancel) { pdfPassword = "" }
        } message: {
            Text("Enter the PDF password. The password is used only for this open document and is not saved.")
        }
    }

    private var canAddSelectedAnnotation: Bool {
        switch annotationTool {
        case .note: !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .link: URL(string: linkDestination)?.scheme != nil
        case .image, .signature: importedAnnotationData != nil
        case .highlight, .rectangle, .ink: true
        }
    }

    private func movePage(by offset: Int) {
        let destination = selectedPage + offset
        movePage(from: selectedPage, to: destination)
    }

    private func movePage(from source: Int, to destination: Int) {
        guard source >= 0, source < document.pageCount,
              destination >= 0, destination < document.pageCount,
              let page = document.page(at: source) else { return }
        document.removePage(at: source)
        document.insert(page, at: destination)
        selectedPage = destination
        refreshDocument()
    }

    private func rotatePage() {
        guard let page = document.page(at: selectedPage) else { return }
        page.rotation = (page.rotation + 90) % 360
        refreshDocument()
    }

    private func duplicatePage() {
        guard let page = document.page(at: selectedPage), let copy = page.copy() as? PDFPage else { return }
        document.insert(copy, at: selectedPage + 1)
        selectedPage += 1
        refreshDocument()
    }

    private func deletePage() {
        guard document.pageCount > 1 else { return }
        document.removePage(at: selectedPage)
        selectedPage = min(selectedPage, document.pageCount - 1)
        refreshDocument()
    }

    private func refreshDocument() {
        guard let data = document.dataRepresentation(), let copy = PDFDocument(data: data) else { return }
        document = copy
    }

    private func temporaryWorkingPDF() throws -> URL {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolioFold-\(UUID().uuidString).pdf")
        guard document.write(to: temporary) else { throw PDFOperationError.outputVerificationFailed }
        return temporary
    }

    private func savePanel(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = defaultName
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func exportWorkingPDF() {
        guard let destination = savePanel(defaultName: url.deletingPathExtension().lastPathComponent + " Edited.pdf") else { return }
        guard document.write(to: destination), PDFDocument(url: destination)?.pageCount == document.pageCount else {
            message = PDFOperationError.outputVerificationFailed.localizedDescription
            return
        }
        message = "Created \(destination.lastPathComponent)"
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    private func exportImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let output = parent.appendingPathComponent(url.deletingPathExtension().lastPathComponent + " Images", isDirectory: true)
        runOperation { working in
            let results = try await PDFImageExportOperation().run(
                .init(url: working, format: .png),
                context: operationContext(output: output)
            )
            finish(results, message: "Created \(results.count) images")
        }
    }

    private func addSelectedAnnotation() {
        guard let destination = savePanel(defaultName: url.deletingPathExtension().lastPathComponent + " Annotated.pdf") else { return }
        let pageIndex = selectedPage
        let bounds = CGRect(x: 72, y: 72, width: 240, height: 48)
        let kind: PDFAnnotationDescriptor.Kind
        switch annotationTool {
        case .note:
            kind = .freeText(note)
        case .highlight:
            kind = .highlight
        case .link:
            guard let destinationURL = URL(string: linkDestination) else { return }
            kind = .link(destinationURL)
        case .rectangle:
            kind = .rectangle
        case .ink:
            kind = .ink([[
                CGPoint(x: bounds.minX, y: bounds.midY),
                CGPoint(x: bounds.midX, y: bounds.maxY),
                CGPoint(x: bounds.maxX, y: bounds.minY)
            ]])
        case .image:
            guard let importedAnnotationData else { return }
            kind = .image(importedAnnotationData)
        case .signature:
            guard let importedAnnotationData else { return }
            kind = .visualSignature(importedAnnotationData)
        }
        runOperation { working in
            let result = try await PDFAnnotationOperation().run(
                .init(url: working, annotations: [
                    .init(pageIndex: pageIndex, bounds: bounds, kind: kind)
                ]),
                context: operationContext(output: destination)
            )
            finish([result], message: "Created \(result.lastPathComponent)")
        }
    }

    private func replaceSourcePDF() {
        do {
            let manager = FileManager.default
            let parent = url.deletingLastPathComponent()
            let temporary = parent.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
            defer { try? manager.removeItem(at: temporary) }
            guard document.write(to: temporary),
                  let verification = PDFDocument(url: temporary),
                  verification.pageCount == document.pageCount else {
                throw PDFOperationError.outputVerificationFailed
            }
            _ = try manager.replaceItemAt(url, withItemAt: temporary)
            message = "Source PDF replaced and verified."
        } catch {
            message = error.localizedDescription
        }
    }

    private func addFormField() {
        guard let destination = savePanel(defaultName: url.deletingPathExtension().lastPathComponent + " Form.pdf") else { return }
        let name = formFieldName
        let value = formFieldValue
        let pageIndex = selectedPage
        let fieldKind: PDFFormFieldKind
        switch formTool {
        case .text:
            fieldKind = .text
        case .checkBox:
            fieldKind = .checkBox
        case .radioButton:
            fieldKind = .radioButton
        case .choice:
            let options = formChoices
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !options.isEmpty else {
                message = "Add at least one choice."
                return
            }
            fieldKind = .choice(options: options)
        case .signature:
            fieldKind = .signature
        }
        runOperation { working in
            let result = try await PDFFormOperation().run(
                .init(url: working, fields: [
                    .init(
                        pageIndex: pageIndex,
                        bounds: CGRect(x: 72, y: 132, width: 240, height: 28),
                        name: name,
                        kind: fieldKind,
                        value: value.isEmpty ? nil : value
                    )
                ]),
                context: operationContext(output: destination)
            )
            finish([result], message: "Created \(result.lastPathComponent)")
        }
    }

    private func unlockPDF() {
        let submittedPassword = pdfPassword
        pdfPassword = ""
        guard document.unlock(withPassword: submittedPassword) else {
            message = "The PDF password is incorrect. Try again."
            isRequestingPDFPassword = true
            return
        }
        message = document.allowsPrinting && document.allowsCopying
            ? "PDF unlocked."
            : "PDF unlocked with document permission restrictions."
        refreshDocument()
    }

    private func applyRedaction() {
        guard let destination = savePanel(defaultName: url.deletingPathExtension().lastPathComponent + " Redacted.pdf") else { return }
        let mark = PDFRedactionMark(
            pageIndex: selectedPage,
            bounds: CGRect(x: redactionX, y: redactionY, width: redactionWidth, height: redactionHeight)
        )
        runOperation { working in
            let result = try await PDFRedactionOperation().run(
                .init(url: working, marks: [mark]),
                context: operationContext(output: destination)
            )
            finish([result.url], message: "Created and verified \(result.url.lastPathComponent)")
        }
    }

    private func operationContext(output: URL) -> PDFOperationContext {
        .init(outputURL: output, reportProgress: { value in
            Task { @MainActor in progress = value.fractionCompleted }
        })
    }

    private func runOperation(_ operation: @escaping (URL) async throws -> Void) {
        isRunning = true
        progress = 0
        message = nil
        Task {
            var working: URL?
            do {
                let temporary = try temporaryWorkingPDF()
                working = temporary
                try await operation(temporary)
            } catch {
                await MainActor.run { isRunning = false; message = error.localizedDescription }
            }
            if let working { try? FileManager.default.removeItem(at: working) }
        }
    }

    @MainActor
    private func finish(_ outputs: [URL], message newMessage: String) {
        isRunning = false
        progress = 1
        message = newMessage
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
    }
}

private struct FolioDocumentWorkspace: View {
    let title: String
    let url: URL?
    @State private var editor = FolioEditor(document: .blank())
    @State private var isReadOnly = false
    @State private var hasLoaded = false
    @State private var selectedBlockKind: Block.Kind = .paragraph
    @State private var message: String?
    @State private var password = ""
    @State private var isRequestingPassword = false
    @State private var passwordError: String?
    @State private var openedPassword: String?
    @State private var isRecoveryAvailable = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var isLoadingDocument = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Picker("Block type", selection: $selectedBlockKind) {
                    ForEach(Block.Kind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                Button("Add Block", systemImage: "plus") { addBlock() }
                    .disabled(isReadOnly)
                    .accessibilityHint("Adds another content block")
                TemplateWorkspace(editor: $editor, isReadOnly: isReadOnly) { message = $0 }
                Button("Undo", systemImage: "arrow.uturn.backward") { editor.undo() }
                    .disabled(isReadOnly || !editor.canUndo)
                Button("Redo", systemImage: "arrow.uturn.forward") { editor.redo() }
                    .disabled(isReadOnly || !editor.canRedo)
                Button("Save…", systemImage: "square.and.arrow.down") { save() }
                    .disabled(isReadOnly)
                Button("Export PDF…", systemImage: "doc.richtext") { exportPDF() }
            }
            .padding()
            Divider()
            if isReadOnly {
                Label("This document was created by a newer FolioFold version and is read-only.", systemImage: "lock")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 10)
            }
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(editor.document.flow) { block in
                        blockEditor(block)
                    }
                    ForEach(editor.document.overlays) { overlay in
                        HStack {
                            Label("Pinned block", systemImage: "pin")
                            Text(overlay.sourceBlockID.uuidString.prefix(8))
                                .font(.caption.monospaced())
                            Spacer()
                            Button("Return to Flow") { returnToFlow(overlay.id) }
                                .disabled(isReadOnly)
                        }
                        .padding()
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(24)
            }
            .accessibilityLabel("Document content")
        }
        .task(id: url) { load() }
        .onChange(of: editor.document) { _, _ in scheduleAutosave() }
        .onDisappear { autosaveTask?.cancel() }
        .alert("Password Required", isPresented: $isRequestingPassword) {
            SecureField("Password", text: $password)
            Button("Open Document") { openWithPassword() }
                .disabled(password.isEmpty)
            Button("Cancel", role: .cancel) {
                password = ""
                passwordError = nil
            }
        } message: {
            Text(passwordError ?? "Enter the password for this encrypted FolioFold document.")
        }
        .confirmationDialog(
            "Recovery Data Available",
            isPresented: $isRecoveryAvailable
        ) {
            Button("Restore Recovery Data") { restoreRecovery() }
            Button("Discard Recovery Data", role: .destructive) { discardRecovery() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("FolioFold found a verified recovery snapshot. Restore it or keep the last saved document.")
        }
    }

    @ViewBuilder
    private func blockEditor(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(block.kind.displayName, systemImage: block.kind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Pin to Page", systemImage: "pin") { pin(block.id) }
                    .disabled(isReadOnly || editor.document.pages.isEmpty)
                Button(role: .destructive) { remove(block.id) } label: {
                    Label("Delete Block", systemImage: "trash")
                }
                .disabled(isReadOnly || editor.document.flow.count == 1)
            }
            if block.kind == .divider {
                Divider()
            } else if block.kind == .pageBreak {
                Label("Page Break", systemImage: "doc.append")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical)
            } else {
                TextEditor(text: textBinding(for: block.id))
                    .font(block.kind == .heading ? .title2.bold() : .body)
                    .frame(minHeight: block.kind == .heading ? 48 : 80)
                    .disabled(isReadOnly)
                    .accessibilityLabel("Block content")
            }
        }
        .padding()
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func textBinding(for blockID: UUID) -> Binding<String> {
        Binding(
            get: { editor.document.flow.first(where: { $0.id == blockID })?.text ?? "" },
            set: { newValue in
                guard !isReadOnly else { return }
                do {
                    try editor.update(blockID: blockID) { $0.text = newValue }
                    message = nil
                } catch { message = error.localizedDescription }
            }
        )
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let url else {
            isLoadingDocument = false
            return
        }
        do {
            let opened = try FolioPackageStore.open(url)
            isLoadingDocument = true
            editor = FolioEditor(document: opened.document)
            isReadOnly = opened.isReadOnly
            openedPassword = nil
            isRecoveryAvailable = opened.recoveryState == .available
            isLoadingDocument = false
        } catch FolioPackageError.passwordRequired {
            password = ""
            passwordError = nil
            isRequestingPassword = true
            isLoadingDocument = false
        } catch {
            message = error.localizedDescription
            isReadOnly = true
            isLoadingDocument = false
        }
    }

    private func openWithPassword() {
        guard let url, !password.isEmpty else { return }
        let submittedPassword = password
        password = ""
        do {
            let opened = try FolioPackageStore.open(url, password: submittedPassword)
            isLoadingDocument = true
            editor = FolioEditor(document: opened.document)
            isReadOnly = opened.isReadOnly
            openedPassword = submittedPassword
            passwordError = nil
            isRecoveryAvailable = opened.recoveryState == .available
            message = nil
            isLoadingDocument = false
        } catch FolioPackageError.authenticationFailed {
            passwordError = "The password is incorrect. Try again."
            isRequestingPassword = true
        } catch FolioPackageError.manifestAuthenticationFailed {
            passwordError = "The encrypted package could not be authenticated."
            isRequestingPassword = true
        } catch {
            passwordError = error.localizedDescription
            isRequestingPassword = true
        }
    }

    private func scheduleAutosave() {
        guard !isLoadingDocument, !isReadOnly, let url else { return }
        autosaveTask?.cancel()
        let snapshot = editor.document
        let snapshotPassword = openedPassword
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            do {
                try await Task.detached(priority: .utility) {
                    try FolioPackageStore.saveRecovery(
                        snapshot,
                        for: url,
                        password: snapshotPassword
                    )
                }.value
                guard !Task.isCancelled else { return }
                message = "Recovery snapshot saved."
            } catch {
                guard !Task.isCancelled else { return }
                message = "Unable to save recovery snapshot: \(error.localizedDescription)"
            }
        }
    }

    private func restoreRecovery() {
        guard let url else { return }
        do {
            let recovered = try FolioPackageStore.openRecovery(
                for: url,
                password: openedPassword
            )
            isLoadingDocument = true
            editor = FolioEditor(document: recovered.document)
            isLoadingDocument = false
            message = "Recovery data restored."
            scheduleAutosave()
        } catch {
            isLoadingDocument = false
            message = error.localizedDescription
        }
    }

    private func discardRecovery() {
        guard let url else { return }
        do {
            try FolioPackageStore.discardRecovery(for: url)
            message = "Recovery data discarded."
        } catch {
            message = error.localizedDescription
        }
    }

    private func addBlock() {
        do {
            try editor.insert(Block(kind: selectedBlockKind), at: editor.document.flow.count)
            message = nil
        } catch { message = error.localizedDescription }
    }

    private func remove(_ blockID: UUID) {
        do { try editor.remove(blockID: blockID); message = nil }
        catch { message = error.localizedDescription }
    }

    private func pin(_ blockID: UUID) {
        guard let pageID = editor.document.pages.first?.id else { return }
        do {
            try editor.pin(
                blockID: blockID,
                to: pageID,
                frame: FolioRect(x: 72, y: 72, width: 240, height: 96)
            )
            message = nil
        } catch { message = error.localizedDescription }
    }

    private func returnToFlow(_ overlayID: UUID) {
        do { try editor.returnToFlow(overlayID: overlayID); message = nil }
        catch { message = error.localizedDescription }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "foliofold") ?? .package]
        panel.nameFieldStringValue = (url?.deletingPathExtension().lastPathComponent ?? title) + ".foliofold"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            autosaveTask?.cancel()
            try FolioPackageStore.save(
                editor.document,
                to: destination,
                password: destination.standardizedFileURL == url?.standardizedFileURL
                    ? openedPassword
                    : nil
            )
            try? FolioPackageStore.discardRecovery(for: destination)
            message = "Saved \(destination.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch { message = error.localizedDescription }
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (url?.deletingPathExtension().lastPathComponent ?? title) + ".pdf"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try FolioPDFExporter.export(editor.document, to: destination)
            message = "Created \(destination.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            message = error.localizedDescription
        }
    }
}

private extension Block.Kind {
    var displayName: String {
        switch self {
        case .paragraph: "Text"
        case .heading: "Heading"
        case .list: "List"
        case .table: "Table"
        case .image: "Image"
        case .divider: "Divider"
        case .shape: "Shape"
        case .formField: "Form Field"
        case .signatureField: "Signature Field"
        case .pageBreak: "Page Break"
        }
    }

    var systemImage: String {
        switch self {
        case .paragraph: "text.alignleft"
        case .heading: "textformat.size.larger"
        case .list: "list.bullet"
        case .table: "tablecells"
        case .image: "photo"
        case .divider: "minus"
        case .shape: "square.on.circle"
        case .formField: "rectangle.and.pencil.and.ellipsis"
        case .signatureField: "signature"
        case .pageBreak: "doc.append"
        }
    }
}

private struct OperationStatusView: View {
    let isRunning: Bool
    let progress: Double
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isRunning {
                ProgressView(value: progress)
                    .accessibilityLabel("Operation progress")
            }
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct MergeWorkspace: View {
    @State private var sources: [URL] = []
    @State private var isImporting = false
    @State private var isRunning = false
    @State private var progress = 0.0
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Merge PDFs", systemImage: "rectangle.stack")
                        .font(.title2.bold())
                    Spacer()
                    Button("Choose Files…") { isImporting = true }
                }
                Text("Choose two or more PDF files, arrange their order, then export a combined PDF.")
                    .foregroundStyle(.secondary)
            }
            Section("PDF files") {
                if sources.isEmpty {
                    Text("No PDF files selected").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(sources.enumerated()), id: \.element) { index, url in
                        HStack {
                            Text(url.lastPathComponent)
                            Spacer()
                            Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(index == 0 || isRunning)
                            Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(index == sources.count - 1 || isRunning)
                            Button(role: .destructive) { sources.remove(at: index) } label: { Image(systemName: "trash") }
                                .disabled(isRunning)
                        }
                    }
                }
            }
            Section {
                Button("Export Merged PDF…") { export() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sources.count < 2 || isRunning)
                OperationStatusView(isRunning: isRunning, progress: progress, message: message)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            do {
                for url in try result.get() where !sources.contains(url) { sources.append(url) }
                message = nil
            } catch { message = error.localizedDescription }
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard sources.indices.contains(destination) else { return }
        sources.swapAt(index, destination)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Merged.pdf"
        guard panel.runModal() == .OK, let output = panel.url else { return }
        isRunning = true
        progress = 0
        message = nil
        let selectedSources = sources
        Task {
            do {
                let result = try await PDFMergeOperation().run(
                    .init(items: selectedSources.map { .init(url: $0) }),
                    context: .init(outputURL: output, reportProgress: { value in
                        Task { @MainActor in progress = value.fractionCompleted }
                    })
                )
                await MainActor.run {
                    isRunning = false
                    progress = 1
                    message = "Created \(result.lastPathComponent)"
                    NSWorkspace.shared.activateFileViewerSelecting([result])
                }
            } catch {
                await MainActor.run { isRunning = false; message = error.localizedDescription }
            }
        }
    }
}

private struct SplitWorkspace: View {
    @State private var source: URL?
    @State private var isImporting = false
    @State private var chunkSize = 1
    @State private var isRunning = false
    @State private var progress = 0.0
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Split PDF", systemImage: "scissors").font(.title2.bold())
                    Spacer()
                    Button("Choose PDF…") { isImporting = true }
                }
                Text(source?.lastPathComponent ?? "No PDF selected")
                    .foregroundStyle(source == nil ? .secondary : .primary)
            }
            Section("Split options") {
                Stepper("Pages per output: \(chunkSize)", value: $chunkSize, in: 1...999)
                    .disabled(isRunning)
            }
            Section {
                Button("Choose Output Folder and Split…") { split() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(source == nil || isRunning)
                OperationStatusView(isRunning: isRunning, progress: progress, message: message)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            do { source = try result.get().first; message = nil }
            catch { message = error.localizedDescription }
        }
    }

    private func split() {
        guard let source else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let output = parent.appendingPathComponent(source.deletingPathExtension().lastPathComponent + " Parts", isDirectory: true)
        isRunning = true
        progress = 0
        message = nil
        Task {
            do {
                let results = try await PDFSplitOperation().run(
                    .init(url: source, selection: .every(chunkSize)),
                    context: .init(outputURL: output, reportProgress: { value in
                        Task { @MainActor in progress = value.fractionCompleted }
                    })
                )
                await MainActor.run {
                    isRunning = false
                    progress = 1
                    message = "Created \(results.count) PDF files"
                    NSWorkspace.shared.activateFileViewerSelecting(results)
                }
            } catch {
                await MainActor.run { isRunning = false; message = error.localizedDescription }
            }
        }
    }
}

private struct ConvertWorkspace: View {
    @State private var sources: [URL] = []
    @State private var isImporting = false
    @State private var isRunning = false
    @State private var progress = 0.0
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Convert Files", systemImage: "arrow.triangle.2.circlepath").font(.title2.bold())
                    Spacer()
                    Button("Choose Files…") { isImporting = true }
                }
                Text("Convert local images, plain text, RTF, or local HTML to PDF without uploading files.")
                    .foregroundStyle(.secondary)
            }
            Section("Source files") {
                if sources.isEmpty {
                    Text("No files selected").foregroundStyle(.secondary)
                } else {
                    ForEach(sources, id: \.self) { url in
                        HStack {
                            Text(url.lastPathComponent)
                            Spacer()
                            Button(role: .destructive) { sources.removeAll { $0 == url } } label: { Image(systemName: "trash") }
                                .disabled(isRunning)
                        }
                    }
                }
            }
            Section {
                Button("Export PDF…") { convert() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sources.isEmpty || isRunning)
                OperationStatusView(isRunning: isRunning, progress: progress, message: message)
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image, .plainText, .rtf, .html],
            allowsMultipleSelection: true
        ) { result in
            do {
                for url in try result.get() where !sources.contains(url) { sources.append(url) }
                message = nil
            } catch { message = error.localizedDescription }
        }
    }

    private func conversionSource(for url: URL) throws -> PDFConversionSource {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "tif", "tiff", "heic": return .image(url)
        case "txt": return .plainText(url)
        case "rtf": return .richText(url)
        case "html", "htm": return .html(url)
        default: throw PDFOperationError.unsupportedFormat
        }
    }

    private func convert() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Converted.pdf"
        guard panel.runModal() == .OK, let output = panel.url else { return }
        isRunning = true
        progress = 0
        message = nil
        let selectedSources = sources
        Task {
            do {
                let inputs = try selectedSources.map(conversionSource)
                let result = try await PDFConvertOperation().run(
                    .init(sources: inputs),
                    context: .init(outputURL: output, reportProgress: { value in
                        Task { @MainActor in progress = value.fractionCompleted }
                    })
                )
                await MainActor.run {
                    isRunning = false
                    progress = 1
                    message = "Created \(result.lastPathComponent)"
                    NSWorkspace.shared.activateFileViewerSelecting([result])
                }
            } catch {
                await MainActor.run { isRunning = false; message = error.localizedDescription }
            }
        }
    }
}
