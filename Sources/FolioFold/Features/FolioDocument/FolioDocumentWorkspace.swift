import FolioFoldCore
import SwiftUI
import UniformTypeIdentifiers

struct FolioDocumentWorkspace: View {
    let title: String
    let url: URL?
    let onSaveStateChange: (WorkspaceSession.SaveState) -> Void
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
    @State private var draggedBlockID: UUID?
    @FocusState private var focusedBlockID: UUID?

    init(
        title: String,
        url: URL?,
        onSaveStateChange: @escaping (WorkspaceSession.SaveState) -> Void = { _ in }
    ) {
        self.title = title
        self.url = url
        self.onSaveStateChange = onSaveStateChange
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(title, systemImage: "doc.richtext")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("document.workspace-heading")
                saveStateLabel
                Spacer()

                Picker("Block type", selection: $selectedBlockKind) {
                    ForEach(Block.Kind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                .accessibilityLabel("Block type")
                .accessibilityIdentifier("document.block-kind")

                Button("Add…", systemImage: "plus") { addBlock() }
                    .disabled(isReadOnly)
                    .help("Add the selected block type")
                    .accessibilityLabel("Add Selected Block")
                    .accessibilityIdentifier("document.block.add")

                TemplateWorkspace(editor: $editor, isReadOnly: isReadOnly) { message = $0 }

                Button("Undo", systemImage: "arrow.uturn.backward") { editor.undo() }
                    .disabled(isReadOnly || !editor.canUndo)
                    .keyboardShortcut("z", modifiers: [.command])
                    .accessibilityIdentifier("document.history.undo")

                Button("Redo", systemImage: "arrow.uturn.forward") { editor.redo() }
                    .disabled(isReadOnly || !editor.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .accessibilityIdentifier("document.history.redo")

                Button("Save…", systemImage: "square.and.arrow.down") { save() }
                    .disabled(isReadOnly)
                    .keyboardShortcut("s", modifiers: [.command])
                    .help("Save FolioFold document")
                    .accessibilityLabel("Save Document")
                    .accessibilityIdentifier("document.save")

                Button("Export…", systemImage: "doc.richtext") { exportPDF() }
                    .buttonStyle(.borderedProminent)
                    .layoutPriority(1)
                    .help("Export PDF")
                    .accessibilityLabel("Export PDF")
                    .accessibilityIdentifier("document.export")
            }
            .padding()
            Divider()
            if isReadOnly {
                Label("This document was created by a newer FolioFold version and is read-only.", systemImage: "lock")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 10)
            }
            OperationStatusView(isRunning: false, progress: 0, message: message)
                .padding(.horizontal)
                .padding(.top, message == nil ? 0 : 8)
                .accessibilityIdentifier("document.status")
            ScrollView {
                LazyVStack(spacing: 12) {
                    if showsFirstUseGuide {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Build your document with blocks", systemImage: "square.stack.3d.up")
                                .font(.headline)
                            Text("Blocks flow into pages automatically. Reorder blocks as your document grows, or pin a block when it needs a fixed page position.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(DesignTokens.inkBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("document.first-use-guide")
                    }

                    ForEach(editor.document.flow) { block in
                        blockEditor(block)
                    }
                    ForEach(editor.document.overlays) { overlay in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("Pinned block", systemImage: "pin")
                                Text(overlay.sourceBlockID.uuidString.prefix(8))
                                    .font(.caption.monospaced())
                                Spacer()
                                Button("Return to Flow") { returnToFlow(overlay.id) }
                                    .disabled(isReadOnly)
                                    .help("Return this block to position \(overlay.returnFlowPosition) in the document flow")
                                    .accessibilityIdentifier("document.overlay.return.\(overlay.id.uuidString)")
                            }
                            Text("Returns to flow position \(overlay.returnFlowPosition).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("document.overlay.return-position.\(overlay.id.uuidString)")
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
        .onChange(of: editor.document) { _, _ in
            guard !isLoadingDocument else { return }
            onSaveStateChange(.changed)
            scheduleAutosave()
        }
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

    private var saveStateLabel: some View {
        Label(
            editor.canUndo ? "Unsaved changes" : "Saved",
            systemImage: editor.canUndo ? "circle.fill" : "checkmark.circle"
        )
        .font(.caption)
        .foregroundStyle(editor.canUndo ? Color.secondary : Color.green)
        .accessibilityIdentifier("document.save-state")
    }

    @ViewBuilder
    private func blockEditor(_ block: Block) -> some View {
        let blockIndex = editor.document.flow.firstIndex(where: { $0.id == block.id }) ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .help("Drag to reorder this block")
                    .accessibilityLabel("Drag handle for \(block.kind.displayName) block")
                    .accessibilityIdentifier("document.block.drag-handle.\(block.id.uuidString)")
                Label(block.kind.displayName, systemImage: block.kind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let field = boundTemplateField(for: block) {
                    Label("Bound to \(field.name)", systemImage: "link")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DesignTokens.inkBlue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(DesignTokens.inkBlue.opacity(0.12), in: Capsule())
                        .help("Template field \(field.name) will generate content for this block")
                        .accessibilityIdentifier("document.block.binding.\(block.id.uuidString)")
                }
                Spacer()
                Button {
                    move(block.id, by: -1)
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
                .disabled(isReadOnly || blockIndex == 0)
                .help(blockIndex == 0 ? "Already first" : "Move \(block.kind.displayName) block up")
                .accessibilityLabel("Move \(block.kind.displayName) block up")
                .accessibilityIdentifier("document.block.move-up.\(block.id.uuidString)")

                Button {
                    move(block.id, by: 1)
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
                .disabled(isReadOnly || blockIndex == editor.document.flow.count - 1)
                .help(blockIndex == editor.document.flow.count - 1 ? "Already last" : "Move \(block.kind.displayName) block down")
                .accessibilityLabel("Move \(block.kind.displayName) block down")
                .accessibilityIdentifier("document.block.move-down.\(block.id.uuidString)")

                Button("Pin to Page", systemImage: "pin") { pin(block.id) }
                    .disabled(isReadOnly || editor.document.pages.isEmpty)
                    .help(pinHelp)
                    .accessibilityHint(pinHelp)
                    .accessibilityIdentifier("document.block.pin.\(block.id.uuidString)")
                Button(role: .destructive) { remove(block.id) } label: {
                    Label("Delete Block", systemImage: "trash")
                }
                .disabled(isReadOnly || editor.document.flow.count == 1)
                .accessibilityIdentifier("document.block.delete.\(block.id.uuidString)")
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
                    .accessibilityIdentifier("document.block.editor.\(block.id.uuidString)")
            }
        }
        .padding()
        .background(
            focusedBlockID == block.id
                ? DesignTokens.inkBlue.opacity(0.12)
                : Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    focusedBlockID == block.id ? DesignTokens.inkBlue : Color.clear,
                    lineWidth: 2
                )
        }
        .focusable()
        .focused($focusedBlockID, equals: block.id)
        .onMoveCommand { direction in
            guard focusedBlockID == block.id else { return }
            switch direction {
            case .up: move(block.id, by: -1)
            case .down: move(block.id, by: 1)
            default: break
            }
        }
        .draggable(block.id.uuidString) {
            draggedBlockID = block.id
            return Label(block.kind.displayName, systemImage: "line.3.horizontal")
                .padding(8)
        }
        .dropDestination(for: String.self) { values, _ in
            guard !isReadOnly,
                  let value = values.first,
                  let sourceID = UUID(uuidString: value),
                  sourceID != block.id,
                  let destination = editor.document.flow.firstIndex(where: { $0.id == block.id }) else {
                return false
            }
            move(sourceID, to: destination)
            draggedBlockID = nil
            return true
        } isTargeted: { targeted in
            if !targeted, draggedBlockID == block.id { draggedBlockID = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(block.kind.displayName) block, position \(blockIndex + 1) of \(editor.document.flow.count)")
        .accessibilityIdentifier("document.block.\(block.id.uuidString)")
    }

    private var showsFirstUseGuide: Bool {
        guard url == nil, editor.document.flow.count == 1, editor.document.overlays.isEmpty,
              let firstBlock = editor.document.flow.first else { return false }
        return firstBlock.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var pinHelp: String {
        if isReadOnly { return "This document is read-only." }
        if editor.document.pages.isEmpty {
            return "Add a page before pinning a block to a fixed page position."
        }
        return "Pin this block to a fixed position on the first page."
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

    private func boundTemplateField(for block: Block) -> TemplateField? {
        guard let fieldID = block.templateFieldID else { return nil }
        return editor.document.templateFields.first { $0.id == fieldID }
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
                onSaveStateChange(.recoveryAvailable)
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
            onSaveStateChange(.changed)
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
            onSaveStateChange(.changed)
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

    private func move(_ blockID: UUID, by offset: Int) {
        guard let source = editor.document.flow.firstIndex(where: { $0.id == blockID }) else { return }
        let destination = source + offset
        do {
            try editor.move(blockID: blockID, to: destination)
            focusedBlockID = blockID
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func move(_ blockID: UUID, to destination: Int) {
        do {
            try editor.move(blockID: blockID, to: destination)
            focusedBlockID = blockID
            message = nil
        } catch {
            message = error.localizedDescription
        }
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
        if let path = ProcessInfo.processInfo.environment["FOLIOFOLD_SAVE_TARGET"] {
            save(to: URL(fileURLWithPath: path), revealInFinder: false)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "foliofold") ?? .package]
        panel.nameFieldStringValue = (url?.deletingPathExtension().lastPathComponent ?? title) + ".foliofold"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        save(to: destination, revealInFinder: true)
    }

    private func save(to destination: URL, revealInFinder: Bool) {
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
            onSaveStateChange(.saved)
            if revealInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
        } catch { message = error.localizedDescription }
    }

    private func exportPDF() {
        if let path = ProcessInfo.processInfo.environment["FOLIOFOLD_EXPORT_TARGET"] {
            exportPDF(to: URL(fileURLWithPath: path), revealInFinder: false)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (url?.deletingPathExtension().lastPathComponent ?? title) + ".pdf"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        exportPDF(to: destination, revealInFinder: true)
    }

    private func exportPDF(to destination: URL, revealInFinder: Bool) {
        do {
            try FolioPDFExporter.export(editor.document, to: destination)
            message = "Created \(destination.lastPathComponent)"
            if revealInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

extension Block.Kind {
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
