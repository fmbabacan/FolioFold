import FolioFoldCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct PDFDocumentView: NSViewRepresentable {
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

struct PDFWorkspace: View {
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
                HStack(spacing: 8) {
                    ControlGroup {
                        Button { movePage(by: -1) } label: {
                            Image(systemName: "arrow.up")
                        }
                        .help("Move Page Up")
                        .accessibilityLabel("Move Page Up")
                        .disabled(selectedPage == 0 || isRunning)

                        Button { movePage(by: 1) } label: {
                            Image(systemName: "arrow.down")
                        }
                        .help("Move Page Down")
                        .accessibilityLabel("Move Page Down")
                        .disabled(selectedPage >= document.pageCount - 1 || isRunning)
                    }
                    .controlGroupStyle(.navigation)

                    Button { rotatePage() } label: {
                        Image(systemName: "rotate.right")
                    }
                    .buttonStyle(.bordered)
                    .help("Rotate Page")
                    .accessibilityLabel("Rotate Page")
                    .disabled(document.pageCount == 0 || isRunning)

                    Menu {
                        Button("Duplicate Page", systemImage: "plus.square.on.square") {
                            duplicatePage()
                        }
                        .disabled(document.pageCount == 0 || isRunning)

                        Divider()

                        Button("Delete Page", systemImage: "trash", role: .destructive) {
                            deletePage()
                        }
                        .disabled(document.pageCount <= 1 || isRunning)
                    } label: {
                        Image(systemName: "doc.badge.ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Page Actions")
                    .accessibilityLabel("Page Actions")

                    Spacer()

                    Button("Export…", systemImage: "square.and.arrow.up") {
                        exportWorkingPDF()
                    }
                    .buttonStyle(.borderedProminent)
                        .disabled(document.pageCount == 0 || isRunning)

                    Menu {
                        Button("Replace Source PDF…", systemImage: "arrow.triangle.2.circlepath", role: .destructive) {
                            isConfirmingSourceReplacement = true
                        }
                        .disabled(document.pageCount == 0 || isRunning)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("More PDF Actions")
                    .accessibilityLabel("More PDF Actions")
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
