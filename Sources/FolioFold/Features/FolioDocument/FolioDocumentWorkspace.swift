import FolioFoldCore
import SwiftUI
import UniformTypeIdentifiers

struct FolioDocumentWorkspace: View {
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
