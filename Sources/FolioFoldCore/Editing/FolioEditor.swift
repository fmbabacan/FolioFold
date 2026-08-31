import Foundation

public struct FolioPageLayout: Equatable, Sendable {
    public struct Placement: Equatable, Sendable {
        public var blockID: UUID
        public var pageIndex: Int
        public var frame: FolioRect

        public init(blockID: UUID, pageIndex: Int, frame: FolioRect) {
            self.blockID = blockID
            self.pageIndex = pageIndex
            self.frame = frame
        }
    }

    public var pageCount: Int
    public var placements: [Placement]

    public init(pageCount: Int, placements: [Placement]) {
        self.pageCount = pageCount
        self.placements = placements
    }
}

public protocol FolioBlockMeasuring: Sendable {
    func height(for block: Block, availableWidth: Double) -> Double
}

public struct DeterministicBlockMeasurer: FolioBlockMeasuring {
    public init() {}

    public func height(for block: Block, availableWidth: Double) -> Double {
        if block.kind == .pageBreak { return 0 }
        let lineHeight = block.kind == .heading ? 30.0 : 22.0
        let characterWidth = block.kind == .heading ? 11.0 : 8.0
        let charactersPerLine = max(1, Int(availableWidth / characterWidth))
        let lineCount = max(1, Int(ceil(Double(max(1, block.text.count)) / Double(charactersPerLine))))
        let verticalPadding: Double
        switch block.kind {
        case .table: verticalPadding = 32
        case .image, .shape, .formField, .signatureField: verticalPadding = 72
        case .divider: return 18
        default: verticalPadding = 12
        }
        return Double(lineCount) * lineHeight + verticalPadding
    }
}

public struct FolioPaginator: Sendable {
    public var blockSpacing: Double
    private let measurer: any FolioBlockMeasuring

    public init(
        blockSpacing: Double = 12,
        measurer: any FolioBlockMeasuring = DeterministicBlockMeasurer()
    ) {
        self.blockSpacing = blockSpacing
        self.measurer = measurer
    }

    public func layout(_ document: FolioDocument) throws -> FolioPageLayout {
        let settings = document.pageSettings
        let width = settings.width - settings.margins.leading - settings.margins.trailing
        let height = settings.height - settings.margins.top - settings.margins.bottom
        guard width > 0, height > 0 else { throw FolioDocumentError.invalidDocument }

        var pageIndex = 0
        var y = settings.margins.top
        var placements: [FolioPageLayout.Placement] = []
        for block in document.flow {
            if block.kind == .pageBreak {
                pageIndex += 1
                y = settings.margins.top
                continue
            }

            let measuredHeight = min(measurer.height(for: block, availableWidth: width), height)
            let requiredHeight = measuredHeight + (y == settings.margins.top ? 0 : blockSpacing)
            if y + requiredHeight > settings.height - settings.margins.bottom {
                pageIndex += 1
                y = settings.margins.top
            } else if y != settings.margins.top {
                y += blockSpacing
            }

            placements.append(.init(
                blockID: block.id,
                pageIndex: pageIndex,
                frame: FolioRect(x: settings.margins.leading, y: y, width: width, height: measuredHeight)
            ))
            y += measuredHeight
        }
        return FolioPageLayout(pageCount: max(1, pageIndex + 1), placements: placements)
    }
}

public struct FolioEditor: Sendable {
    public private(set) var document: FolioDocument
    private var undoStack: [FolioDocument] = []
    private var redoStack: [FolioDocument] = []

    public init(document: FolioDocument) {
        self.document = document
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public mutating func insert(_ block: Block, at index: Int) throws {
        guard index >= 0, index <= document.flow.count else {
            throw FolioDocumentError.invalidDocument
        }
        try mutate { $0.flow.insert(block, at: index) }
    }

    public mutating func update(blockID: UUID, transform: (inout Block) -> Void) throws {
        guard document.flow.contains(where: { $0.id == blockID }) else {
            throw FolioDocumentError.blockNotFound
        }
        try mutate { document in
            guard let index = document.flow.firstIndex(where: { $0.id == blockID }) else {
                throw FolioDocumentError.blockNotFound
            }
            transform(&document.flow[index])
        }
    }

    public mutating func remove(blockID: UUID) throws {
        guard document.flow.contains(where: { $0.id == blockID }) else {
            throw FolioDocumentError.blockNotFound
        }
        try mutate { document in
            guard let index = document.flow.firstIndex(where: { $0.id == blockID }) else {
                throw FolioDocumentError.blockNotFound
            }
            document.flow.remove(at: index)
        }
    }

    public mutating func pin(
        blockID: UUID,
        to pageID: UUID,
        frame: FolioRect,
        rotationDegrees: Double = 0,
        zIndex: Int = 0,
        isLocked: Bool = false
    ) throws {
        try mutate { document in
            try document.pin(
                blockID: blockID,
                to: pageID,
                frame: frame,
                rotationDegrees: rotationDegrees,
                zIndex: zIndex,
                isLocked: isLocked
            )
        }
    }

    public mutating func returnToFlow(overlayID: UUID) throws {
        try mutate { try $0.returnToFlow(overlayID: overlayID) }
    }

    public mutating func setTemplateFields(_ fields: [TemplateField]) throws {
        try mutate { document in
            let fieldIDs = Set(fields.map { $0.id })
            document.templateFields = fields
            for index in document.flow.indices where
                document.flow[index].templateFieldID.map({ !fieldIDs.contains($0) }) == true
            {
                document.flow[index].templateFieldID = nil
            }
        }
    }

    public mutating func bind(blockID: UUID, to templateFieldID: UUID?) throws {
        guard document.flow.contains(where: { $0.id == blockID }) else {
            throw FolioDocumentError.blockNotFound
        }
        if let templateFieldID,
           !document.templateFields.contains(where: { $0.id == templateFieldID }) {
            throw FolioDocumentError.invalidDocument
        }
        try mutate { document in
            guard let index = document.flow.firstIndex(where: { $0.id == blockID }) else {
                throw FolioDocumentError.blockNotFound
            }
            document.flow[index].templateFieldID = templateFieldID
        }
    }

    public mutating func applyTemplateValues(
        _ values: [UUID: TemplateValue],
        sequenceNumber: Int = 1,
        locale: Locale = .current
    ) throws {
        let rendered = try TemplateEngine(locale: locale).render(
            document: document,
            values: values,
            sequenceNumber: sequenceNumber
        )
        try mutate { document in
            document = rendered.document
        }
    }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
    }

    private mutating func mutate(_ operation: (inout FolioDocument) throws -> Void) throws {
        var candidate = document
        try operation(&candidate)
        undoStack.append(document)
        document = candidate
        redoStack.removeAll()
    }
}
