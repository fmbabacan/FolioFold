import FolioFoldCore
import PDFKit
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class InteractivePDFView: PDFView {
    enum PlacementStyle {
        case annotation
        case form
        case redaction
    }

    var placementStyle: PlacementStyle? {
        didSet {
            placementLayer.isHidden = placementStyle == nil
            updatePlacementAppearance()
            needsLayout = true
        }
    }
    var placementPageIndex = 0
    var placementBounds = CGRect.zero {
        didSet { updatePlacementPreview() }
    }
    var onPlacementBoundsChanged: ((CGRect) -> Void)?

    private let placementLayer = CAShapeLayer()
    private var dragStart: CGPoint?
    private var dragPage: PDFPage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        placementLayer.lineWidth = 2
        placementLayer.lineDashPattern = [6, 4]
        layer?.addSublayer(placementLayer)
        updatePlacementAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        updatePlacementPreview()
    }

    override func mouseDown(with event: NSEvent) {
        guard placementStyle != nil,
              let page = page(for: convert(event.locationInWindow, from: nil), nearest: true),
              document?.index(for: page) == placementPageIndex else {
            super.mouseDown(with: event)
            return
        }
        window?.makeFirstResponder(self)
        let point = pagePoint(for: event, on: page)
        dragStart = point
        dragPage = page
        setPlacementBounds(CGRect(origin: point, size: .zero), on: page)
    }

    override func mouseDragged(with event: NSEvent) {
        guard placementStyle != nil,
              let start = dragStart,
              let page = dragPage else {
            super.mouseDragged(with: event)
            return
        }
        let point = pagePoint(for: event, on: page)
        setPlacementBounds(normalizedRect(from: start, to: point), on: page)
    }

    override func mouseUp(with event: NSEvent) {
        guard placementStyle != nil,
              let start = dragStart,
              let page = dragPage else {
            super.mouseUp(with: event)
            return
        }
        let point = pagePoint(for: event, on: page)
        var bounds = normalizedRect(from: start, to: point)
        if bounds.width < 4 || bounds.height < 4 {
            bounds = CGRect(x: point.x, y: point.y, width: 72, height: 24)
        }
        setPlacementBounds(bounds, on: page)
        dragStart = nil
        dragPage = nil
    }

    override func keyDown(with event: NSEvent) {
        guard placementStyle != nil,
              let page = document?.page(at: placementPageIndex) else {
            super.keyDown(with: event)
            return
        }
        let step: CGFloat = event.modifierFlags.contains(.option) ? 10 : 1
        var bounds = placementBounds
        let resize = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 123:
            if resize { bounds.size.width -= step } else { bounds.origin.x -= step }
        case 124:
            if resize { bounds.size.width += step } else { bounds.origin.x += step }
        case 125:
            if resize { bounds.size.height -= step } else { bounds.origin.y -= step }
        case 126:
            if resize { bounds.size.height += step } else { bounds.origin.y += step }
        default:
            super.keyDown(with: event)
            return
        }
        setPlacementBounds(bounds, on: page)
    }

    private func pagePoint(for event: NSEvent, on page: PDFPage) -> CGPoint {
        let viewPoint = convert(event.locationInWindow, from: nil)
        return convert(viewPoint, to: page)
    }

    private func normalizedRect(from first: CGPoint, to second: CGPoint) -> CGRect {
        CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }

    private func setPlacementBounds(_ proposed: CGRect, on page: PDFPage) {
        let pageBounds = page.bounds(for: .mediaBox)
        var constrained = proposed.standardized
        constrained.size.width = min(max(4, constrained.width), pageBounds.width)
        constrained.size.height = min(max(4, constrained.height), pageBounds.height)
        constrained.origin.x = min(max(pageBounds.minX, constrained.minX), pageBounds.maxX - constrained.width)
        constrained.origin.y = min(max(pageBounds.minY, constrained.minY), pageBounds.maxY - constrained.height)
        placementBounds = constrained
        onPlacementBoundsChanged?(constrained)
    }

    private func updatePlacementPreview() {
        guard placementStyle != nil,
              !placementBounds.isEmpty,
              let page = document?.page(at: placementPageIndex) else {
            placementLayer.isHidden = true
            return
        }
        placementLayer.isHidden = false
        let viewRect = convert(placementBounds, from: page)
        placementLayer.frame = bounds
        placementLayer.path = CGPath(rect: viewRect, transform: nil)
    }

    private func updatePlacementAppearance() {
        let color: NSColor
        switch placementStyle {
        case .annotation: color = .systemBlue
        case .form: color = .systemGreen
        case .redaction: color = .systemRed
        case nil: color = .clear
        }
        placementLayer.fillColor = color.withAlphaComponent(0.22).cgColor
        placementLayer.strokeColor = color.cgColor
    }
}

struct PDFDocumentView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var selectedPage: Int
    @Binding var scaleFactor: CGFloat
    fileprivate let command: PDFViewCommand?
    let searchText: String
    let placementStyle: InteractivePDFView.PlacementStyle?
    let placementPageIndex: Int
    @Binding var placementBounds: CGRect

    @MainActor
    final class Coordinator: NSObject {
        var selectedPage: Binding<Int>
        var scaleFactor: Binding<CGFloat>
        var lastCommandID: UUID?
        var lastSearchText = ""
        var isUpdating = false
        weak var view: InteractivePDFView?

        init(selectedPage: Binding<Int>, scaleFactor: Binding<CGFloat>) {
            self.selectedPage = selectedPage
            self.scaleFactor = scaleFactor
        }

        @objc func pageChanged() {
            guard !isUpdating,
                  let view,
                  let page = view.currentPage,
                  let index = view.document?.index(for: page) else { return }
            selectedPage.wrappedValue = index
        }

        @objc func scaleChanged() {
            guard !isUpdating, let view else { return }
            scaleFactor.wrappedValue = view.scaleFactor
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedPage: $selectedPage, scaleFactor: $scaleFactor)
    }

    func makeNSView(context: Context) -> InteractivePDFView {
        let view = InteractivePDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.document = document
        view.onPlacementBoundsChanged = { bounds in
            placementBounds = bounds
        }
        context.coordinator.view = view
        let center = NotificationCenter.default
        center.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged),
            name: .PDFViewPageChanged,
            object: view
        )
        center.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scaleChanged),
            name: .PDFViewScaleChanged,
            object: view
        )
        return view
    }

    func updateNSView(_ view: InteractivePDFView, context: Context) {
        context.coordinator.selectedPage = $selectedPage
        context.coordinator.scaleFactor = $scaleFactor
        if view.document !== document {
            view.document = document
        }
        view.placementStyle = placementStyle
        view.placementPageIndex = placementPageIndex
        view.placementBounds = placementBounds
        context.coordinator.isUpdating = true
        if document.pageCount > 0,
           selectedPage >= 0,
           selectedPage < document.pageCount,
           let page = document.page(at: selectedPage),
           view.currentPage !== page {
            view.go(to: page)
        }

        if let command, context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            switch command.kind {
            case .zoomIn:
                view.autoScales = false
                view.zoomIn(nil)
            case .zoomOut:
                view.autoScales = false
                view.zoomOut(nil)
            case .actualSize:
                view.autoScales = false
                view.scaleFactor = 1
            case .fitPage:
                view.displayMode = .singlePage
                view.autoScales = true
            case .fitWidth:
                view.displayMode = .singlePageContinuous
                view.autoScales = false
                view.scaleFactor = view.scaleFactorForSizeToFit
            }
            scaleFactor = view.scaleFactor
        }

        if searchText != context.coordinator.lastSearchText {
            context.coordinator.lastSearchText = searchText
            view.clearSelection()
            if !searchText.isEmpty,
               let selection = document.findString(searchText, withOptions: [.caseInsensitive]).first {
                view.setCurrentSelection(selection, animate: true)
                view.scrollSelectionToVisible(nil)
                if let page = selection.pages.first {
                    selectedPage = document.index(for: page)
                }
            }
        }
        context.coordinator.isUpdating = false
    }
}

fileprivate struct PDFViewCommand: Equatable {
    enum Kind { case zoomIn, zoomOut, actualSize, fitPage, fitWidth }
    let id = UUID()
    let kind: Kind
}

struct PDFWorkspace: View {
    @Environment(\.undoManager) private var undoManager

    private enum InspectorCategory: String, CaseIterable, Identifiable {
        case pages = "Pages"
        case annotation = "Annotate"
        case form = "Form"
        case redaction = "Redact"

        var id: String { rawValue }
    }

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
    @State private var formFieldName = ""
    @State private var formFieldValue = ""
    @State private var formTool: FormTool = .text
    @State private var formChoices = "Option 1, Option 2"
    @State private var annotationBounds = CGRect(x: 72, y: 72, width: 240, height: 48)
    @State private var formFieldBounds = CGRect(x: 72, y: 132, width: 240, height: 28)
    @State private var pdfPassword = ""
    @State private var isRequestingPDFPassword = false
    @State private var redactionX = 72.0
    @State private var redactionY = 72.0
    @State private var redactionWidth = 180.0
    @State private var redactionHeight = 36.0
    @State private var isRedactionAdvancedExpanded = false
    @State private var message: String?
    @State private var isRunning = false
    @State private var progress = 0.0
    @State private var draggedPageIndex: Int?
    @State private var undoTarget = PDFUndoTarget()
    @State private var operationTask: Task<Void, Never>?
    @State private var pdfViewCommand: PDFViewCommand?
    @State private var pdfScaleFactor: CGFloat = 1
    @State private var searchText = ""
    @State private var inspectorCategory: InspectorCategory = .pages
    @FocusState private var isSearchFocused: Bool

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
                    Label("PDF Editor", systemImage: "doc.richtext")
                        .font(.headline)
                        .lineLimit(1)
                        .accessibilityIdentifier("pdf.workspace-heading")

                    Menu("Panel Width", systemImage: "rectangle.split.3x1") {
                        Button("Narrower Thumbnails", systemImage: "arrow.left.to.line") {
                            SplitPanelAdjustment.pdfThumbnails.post(delta: -20)
                        }
                        .accessibilityIdentifier("pdf.thumbnails.width.decrease")

                        Button("Wider Thumbnails", systemImage: "arrow.right.to.line") {
                            SplitPanelAdjustment.pdfThumbnails.post(delta: 20)
                        }
                        .accessibilityIdentifier("pdf.thumbnails.width.increase")

                        Divider()

                        Button("Narrower Inspector", systemImage: "arrow.right.to.line") {
                            SplitPanelAdjustment.pdfInspector.post(delta: -20)
                        }
                        .accessibilityIdentifier("pdf.inspector.width.decrease")

                        Button("Wider Inspector", systemImage: "arrow.left.to.line") {
                            SplitPanelAdjustment.pdfInspector.post(delta: 20)
                        }
                        .accessibilityIdentifier("pdf.inspector.width.increase")
                    }
                    .help("Resize PDF panels")
                    .accessibilityLabel("Resize PDF panels")

                    ControlGroup {
                        Button { goToPage(selectedPage - 1) } label: {
                            Image(systemName: "chevron.left")
                        }
                        .help("Previous Page")
                        .accessibilityLabel("Previous Page")
                        .disabled(selectedPage == 0 || document.pageCount == 0)

                        TextField("Page", value: pageNumberBinding, format: .number)
                            .frame(width: 44)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Current page number")
                            .accessibilityValue("Page \(selectedPage + 1) of \(document.pageCount)")
                            .accessibilityIdentifier("pdf.page-number")

                        Text("of \(document.pageCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        Button { goToPage(selectedPage + 1) } label: {
                            Image(systemName: "chevron.right")
                        }
                        .help("Next Page")
                        .accessibilityLabel("Next Page")
                        .disabled(selectedPage >= document.pageCount - 1 || document.pageCount == 0)
                    }
                    .controlGroupStyle(.navigation)

                    ControlGroup {
                        Button { sendPDFViewCommand(.zoomOut) } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .help("Zoom Out")
                        .accessibilityLabel("Zoom Out")

                        Text("\(zoomPercentage)%")
                            .font(.caption.monospacedDigit())
                            .frame(minWidth: 46)
                            .accessibilityLabel("Current zoom")
                            .accessibilityValue("\(zoomPercentage) percent")
                            .accessibilityIdentifier("pdf.zoom-value")

                        Button { sendPDFViewCommand(.zoomIn) } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .help("Zoom In")
                        .accessibilityLabel("Zoom In")
                    }
                    .controlGroupStyle(.navigation)

                    Menu("View", systemImage: "rectangle.inset.filled") {
                        Button("Actual Size") { sendPDFViewCommand(.actualSize) }
                        Button("Fit Page") { sendPDFViewCommand(.fitPage) }
                        Button("Fit Width") { sendPDFViewCommand(.fitWidth) }
                    }
                    .help("PDF view size")

                    TextField("Find", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 100, idealWidth: 140, maxWidth: 180)
                        .focused($isSearchFocused)
                        .accessibilityLabel("Find in PDF")
                        .accessibilityIdentifier("pdf.find")

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
                        .help(document.pageCount <= 1
                            ? "A PDF must contain at least one page."
                            : "Delete Page \(selectedPage + 1)")
                    } label: {
                        Image(systemName: "doc.badge.ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Page Actions")
                    .accessibilityLabel("Page Actions")

                    Spacer()

                    Button("Export PDF…", systemImage: "square.and.arrow.up") {
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
                PDFDocumentView(
                    document: document,
                    selectedPage: $selectedPage,
                    scaleFactor: $pdfScaleFactor,
                    command: pdfViewCommand,
                    searchText: searchText,
                    placementStyle: placementStyle,
                    placementPageIndex: selectedPage,
                    placementBounds: placementBoundsBinding
                )
                .accessibilityLabel(
                    "PDF document, page \(selectedPage + 1) of \(document.pageCount), zoom \(Int((pdfScaleFactor * 100).rounded())) percent"
                )
                .accessibilityIdentifier("pdf.document-view")
            }
            .frame(minWidth: 500)

            Form {
                Picker("PDF inspector tool", selection: $inspectorCategory) {
                    ForEach(InspectorCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("PDF inspector tool")
                .accessibilityIdentifier("pdf.inspector-category")

                switch inspectorCategory {
                case .pages:
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
                    .accessibilityIdentifier("pdf.inspector.pages")

                case .annotation:
                    Section("Annotation") {
                    Label("Draw the annotation area directly on the selected page. Use arrow keys to move it and Shift-Arrows to resize it.", systemImage: "rectangle.dashed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("pdf.annotation-placement-help")
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
                            .accessibilityIdentifier("pdf.link-destination")
                        validationMessage(
                            linkValidationMessage,
                            isValid: validatedLinkDestination != nil,
                            identifier: "pdf.link-validation"
                        )
                    }
                    if annotationTool == .image || annotationTool == .signature {
                        if annotationTool == .signature {
                            Label(
                                "A Visual Signature is an image annotation. It does not cryptographically sign or certify the PDF.",
                                systemImage: "info.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("pdf.visual-signature-limitation")
                        }
                        Button(annotationTool == .signature ? "Choose Visual Signature Image…" : "Choose Image…") {
                            isImportingAnnotationImage = true
                        }
                        .accessibilityIdentifier(
                            annotationTool == .signature
                                ? "pdf.visual-signature.choose-image"
                                : "pdf.annotation.choose-image"
                        )
                        if annotationTool == .signature {
                            SignatureCaptureButton(selectedData: $importedAnnotationData) { message = $0 }
                        }
                        Text(
                            annotationTool == .signature
                                ? (importedAnnotationData == nil
                                    ? "No Visual Signature image selected"
                                    : "Visual Signature image ready")
                                : (importedAnnotationData == nil ? "No image selected" : "Image ready")
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(
                        annotationTool == .signature
                            ? "Add Visual Signature and Export…"
                            : "Add Annotation and Export…"
                    ) { addSelectedAnnotation() }
                        .disabled(!canAddSelectedAnnotation || document.pageCount == 0 || isRunning)
                    }
                    .accessibilityIdentifier("pdf.inspector.annotation")

                case .form:
                    Section("Form Field") {
                    Label("Draw the form field directly on the selected page. Use arrow keys to move it and Shift-Arrows to resize it.", systemImage: "rectangle.dashed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("pdf.form-placement-help")
                    Picker("Field type", selection: $formTool) {
                        ForEach(FormTool.allCases) { tool in
                            Text(tool.title).tag(tool)
                        }
                    }
                    TextField("Field name", text: $formFieldName)
                        .accessibilityIdentifier("pdf.form-field-name")
                    validationMessage(
                        formFieldValidationMessage,
                        isValid: validatedFormFieldName != nil,
                        identifier: "pdf.form-field-validation"
                    )
                    TextField("Default value", text: $formFieldValue)
                    if formTool == .choice {
                        TextField("Choices separated by commas", text: $formChoices)
                        validationMessage(
                            choiceValidationMessage,
                            isValid: validatedFormChoices != nil,
                            identifier: "pdf.form-choice-validation"
                        )
                    }
                    Button("Add Form Field and Export…") { addFormField() }
                        .disabled(!canAddFormField || document.pageCount == 0 || isRunning)
                    }
                    .accessibilityIdentifier("pdf.inspector.form")

                case .redaction:
                    Section("Redaction") {
                    Label("Draw the redaction area directly on the selected page.", systemImage: "rectangle.dashed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Drag to draw. Arrow keys move by 1 point, Option-Arrows move by 10, and Shift-Arrows resize.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(redactionValidationMessage, systemImage: redactionIsValid ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(redactionIsValid ? Color.secondary : Color.red)
                        .accessibilityLabel((redactionIsValid ? "Valid: " : "Error: ") + redactionValidationMessage)
                        .accessibilityIdentifier("pdf.redaction.validation")

                    DisclosureGroup("Advanced coordinates", isExpanded: $isRedactionAdvancedExpanded) {
                        LabeledContent("X") { TextField("X", value: $redactionX, format: .number) }
                        LabeledContent("Y") { TextField("Y", value: $redactionY, format: .number) }
                        LabeledContent("Width") { TextField("Width", value: $redactionWidth, format: .number) }
                        LabeledContent("Height") { TextField("Height", value: $redactionHeight, format: .number) }
                    }
                    .accessibilityIdentifier("pdf.redaction.advanced")

                    Button("Apply Redaction to New PDF…", role: .destructive) { applyRedaction() }
                        .disabled(!redactionIsValid || document.pageCount == 0 || isRunning)
                    }
                    .accessibilityIdentifier("pdf.inspector.redaction")
                }

                OperationStatusView(
                    isRunning: isRunning,
                    progress: progress,
                    message: message,
                    onCancel: cancelOperation
                )
            }
            .formStyle(.grouped)
            .frame(minWidth: 290, idealWidth: 330, maxWidth: 400)
        }
        .background {
            PersistentSplitView(
                autosaveName: "FolioFold.PDFWorkspaceSplit",
                panels: [.pdfThumbnails, .pdfInspector]
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
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
        .background {
            Group {
                Button("Zoom In") { sendPDFViewCommand(.zoomIn) }
                    .keyboardShortcut("+", modifiers: [.command])
                Button("Zoom Out") { sendPDFViewCommand(.zoomOut) }
                    .keyboardShortcut("-", modifiers: [.command])
                Button("Actual Size") { sendPDFViewCommand(.actualSize) }
                    .keyboardShortcut("0", modifiers: [.command])
                Button("Find in PDF") { isSearchFocused = true }
                    .keyboardShortcut("f", modifiers: [.command])
            }
            .hidden()
            .accessibilityHidden(true)
        }
    }

    private var zoomPercentage: Int {
        Int((pdfScaleFactor * 100).rounded())
    }

    private var pageNumberBinding: Binding<Int> {
        Binding(
            get: { document.pageCount == 0 ? 0 : selectedPage + 1 },
            set: { goToPage($0 - 1) }
        )
    }

    private func goToPage(_ index: Int) {
        guard document.pageCount > 0 else { return }
        selectedPage = min(max(0, index), document.pageCount - 1)
    }

    private var redactionBoundsBinding: Binding<CGRect> {
        Binding(
            get: {
                CGRect(x: redactionX, y: redactionY, width: redactionWidth, height: redactionHeight)
            },
            set: { bounds in
                redactionX = bounds.minX
                redactionY = bounds.minY
                redactionWidth = bounds.width
                redactionHeight = bounds.height
            }
        )
    }

    private var placementStyle: InteractivePDFView.PlacementStyle? {
        switch inspectorCategory {
        case .annotation: .annotation
        case .form: .form
        case .redaction: .redaction
        case .pages: nil
        }
    }

    private var placementBoundsBinding: Binding<CGRect> {
        switch inspectorCategory {
        case .annotation: $annotationBounds
        case .form: $formFieldBounds
        case .redaction: redactionBoundsBinding
        case .pages: .constant(.zero)
        }
    }

    private var redactionIsValid: Bool {
        guard document.pageCount > 0,
              let page = document.page(at: selectedPage),
              redactionWidth > 0,
              redactionHeight > 0 else { return false }
        let pageBounds = page.bounds(for: .mediaBox)
        let bounds = redactionBoundsBinding.wrappedValue
        return pageBounds.contains(bounds)
    }

    private var redactionValidationMessage: String {
        guard document.pageCount > 0,
              let page = document.page(at: selectedPage) else {
            return "Open a PDF page before creating a redaction."
        }
        guard redactionWidth > 0, redactionHeight > 0 else {
            return "The redaction must have a positive width and height."
        }
        let bounds = redactionBoundsBinding.wrappedValue
        guard page.bounds(for: .mediaBox).contains(bounds) else {
            return "The redaction must remain inside the selected page."
        }
        return "Redaction preview is inside Page (selectedPage + 1)."
    }

    private func sendPDFViewCommand(_ kind: PDFViewCommand.Kind) {
        pdfViewCommand = PDFViewCommand(kind: kind)
    }

    private var canAddSelectedAnnotation: Bool {
        switch annotationTool {
        case .note: !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .link: validatedLinkDestination != nil
        case .image, .signature: importedAnnotationData != nil
        case .highlight, .rectangle, .ink: true
        }
    }

    private var validatedLinkDestination: URL? {
        guard let components = URLComponents(string: linkDestination.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false else { return nil }
        return components.url
    }

    private var linkValidationMessage: String {
        validatedLinkDestination == nil
            ? "Enter a complete HTTP or HTTPS address, for example https://example.com."
            : "Valid web address."
    }

    private var validatedFormFieldName: String? {
        PDFFormOperation.normalizedFieldName(formFieldName)
    }

    private var parsedFormChoices: [String] {
        formChoices.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    }

    private var validatedFormChoices: [String]? {
        guard formTool == .choice else { return [] }
        return PDFFormOperation.normalizedChoiceOptions(parsedFormChoices)
    }

    private var formFieldValidationMessage: String {
        validatedFormFieldName == nil
            ? "Use a descriptive name of 2 to 64 characters starting with a letter. Letters, numbers, dots, hyphens, and underscores are allowed."
            : "Valid field name. Existing names are checked before export."
    }

    private var choiceValidationMessage: String {
        validatedFormChoices == nil
            ? "Enter one or more unique, non-empty choices separated by commas."
            : "Valid choice list."
    }

    private var canAddFormField: Bool {
        validatedFormFieldName != nil && (formTool != .choice || validatedFormChoices != nil)
    }

    @ViewBuilder
    private func validationMessage(_ text: String, isValid: Bool, identifier: String) -> some View {
        Label(text, systemImage: isValid ? "checkmark.circle" : "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(isValid ? Color.green : Color.orange)
            .accessibilityLabel((isValid ? "Valid: " : "Error: ") + text)
            .accessibilityIdentifier(identifier)
    }

    private func movePage(by offset: Int) {
        let destination = selectedPage + offset
        movePage(from: selectedPage, to: destination)
    }

    private func movePage(from source: Int, to destination: Int) {
        guard source >= 0, source < document.pageCount,
              destination >= 0, destination < document.pageCount,
              let page = document.page(at: source) else { return }
        registerUndoSnapshot(actionName: "Move Page")
        document.removePage(at: source)
        document.insert(page, at: destination)
        selectedPage = destination
        refreshDocument()
    }

    private func rotatePage() {
        guard let page = document.page(at: selectedPage) else { return }
        registerUndoSnapshot(actionName: "Rotate Page")
        page.rotation = (page.rotation + 90) % 360
        refreshDocument()
    }

    private func duplicatePage() {
        guard let page = document.page(at: selectedPage), let copy = page.copy() as? PDFPage else { return }
        registerUndoSnapshot(actionName: "Duplicate Page")
        document.insert(copy, at: selectedPage + 1)
        selectedPage += 1
        refreshDocument()
    }

    private func deletePage() {
        guard document.pageCount > 1 else { return }
        registerUndoSnapshot(actionName: "Delete Page \(selectedPage + 1)")
        document.removePage(at: selectedPage)
        selectedPage = min(selectedPage, document.pageCount - 1)
        refreshDocument()
    }

    private func refreshDocument() {
        guard let data = document.dataRepresentation(), let copy = PDFDocument(data: data) else { return }
        document = copy
    }

    private func registerUndoSnapshot(actionName: String) {
        guard let data = document.dataRepresentation() else { return }
        let page = selectedPage
        undoManager?.registerUndo(withTarget: undoTarget) { _ in
            restoreUndoSnapshot(data, selectedPage: page, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private func restoreUndoSnapshot(_ data: Data, selectedPage page: Int, actionName: String) {
        guard let restored = PDFDocument(data: data) else { return }
        if let redoData = document.dataRepresentation() {
            let redoPage = selectedPage
            undoManager?.registerUndo(withTarget: undoTarget) { _ in
                restoreUndoSnapshot(redoData, selectedPage: redoPage, actionName: actionName)
            }
        }
        document = restored
        selectedPage = min(page, max(0, restored.pageCount - 1))
        undoManager?.setActionName(actionName)
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
        let bounds = annotationBounds
        let kind: PDFAnnotationDescriptor.Kind
        switch annotationTool {
        case .note:
            kind = .freeText(note)
        case .highlight:
            kind = .highlight
        case .link:
            guard let destinationURL = validatedLinkDestination else {
                message = linkValidationMessage
                return
            }
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
        guard let name = validatedFormFieldName else {
            message = formFieldValidationMessage
            return
        }
        if formTool == .choice, validatedFormChoices == nil {
            message = choiceValidationMessage
            return
        }
        guard let destination = savePanel(defaultName: url.deletingPathExtension().lastPathComponent + " Form.pdf") else { return }
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
            guard let options = validatedFormChoices else { return }
            fieldKind = .choice(options: options)
        case .signature:
            fieldKind = .signature
        }
        runOperation { working in
            let result = try await PDFFormOperation().run(
                .init(url: working, fields: [
                    .init(
                        pageIndex: pageIndex,
                        bounds: formFieldBounds,
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
        .init(outputURL: output, isCancelled: {
            Task.isCancelled
        }, reportProgress: { value in
            Task { @MainActor in progress = value.fractionCompleted }
        })
    }

    private func runOperation(_ operation: @escaping (URL) async throws -> Void) {
        operationTask?.cancel()
        isRunning = true
        progress = 0
        message = nil
        operationTask = Task {
            var working: URL?
            do {
                let temporary = try temporaryWorkingPDF()
                working = temporary
                try Task.checkCancellation()
                try await operation(temporary)
            } catch {
                await MainActor.run {
                    operationTask = nil
                    isRunning = false
                    message = cancellationMessage(for: error)
                }
            }
            if let working { try? FileManager.default.removeItem(at: working) }
        }
    }

    private func cancelOperation() {
        operationTask?.cancel()
        message = "Cancelling PDF operation…"
    }

    private func cancellationMessage(for error: Error) -> String {
        if error is CancellationError || (error as? PDFOperationError) == .cancelled {
            return "PDF operation cancelled. No final output was created."
        }
        return error.localizedDescription
    }

    @MainActor
    private func finish(_ outputs: [URL], message newMessage: String) {
        operationTask = nil
        isRunning = false
        progress = 1
        message = newMessage
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
    }
}

private final class PDFUndoTarget: NSObject {}
