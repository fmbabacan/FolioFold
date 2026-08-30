import Foundation

public struct FormatVersion: Codable, Equatable, Sendable {
    public var major: Int
    public var minor: Int

    public init(major: Int, minor: Int = 0) {
        self.major = major
        self.minor = minor
    }
}

public struct FolioRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct PageMargins: Codable, Equatable, Sendable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public init(top: Double = 72, leading: Double = 72, bottom: Double = 72, trailing: Double = 72) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}

public struct PageSettings: Codable, Equatable, Sendable {
    public enum Size: String, Codable, Sendable { case a4, letter, legal, custom }

    public var size: Size
    public var width: Double
    public var height: Double
    public var margins: PageMargins

    public init(size: Size = .a4, width: Double = 595, height: Double = 842, margins: PageMargins = PageMargins()) {
        self.size = size
        self.width = width
        self.height = height
        self.margins = margins
    }
}

public struct FolioPage: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public init(id: UUID = UUID()) { self.id = id }
}

public struct Block: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case paragraph, heading, list, table, image, divider, shape
        case formField, signatureField, pageBreak
    }

    public let id: UUID
    public var kind: Kind
    public var text: String
    public var style: [String: String]
    public var templateFieldID: UUID?
    public var keepWithNext: Bool

    public init(id: UUID = UUID(), kind: Kind = .paragraph, text: String = "", style: [String: String] = [:], templateFieldID: UUID? = nil, keepWithNext: Bool = false) {
        self.id = id
        self.kind = kind
        self.text = text
        self.style = style
        self.templateFieldID = templateFieldID
        self.keepWithNext = keepWithNext
    }
}

public struct OverlayElement: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sourceBlockID: UUID
    public let pageID: UUID
    public var frame: FolioRect
    public var rotationDegrees: Double
    public var zIndex: Int
    public var isLocked: Bool
    fileprivate let originalFlowIndex: Int
    fileprivate let block: Block

    fileprivate init(id: UUID = UUID(), block: Block, pageID: UUID, frame: FolioRect, rotationDegrees: Double, zIndex: Int, isLocked: Bool, originalFlowIndex: Int) {
        self.id = id
        self.sourceBlockID = block.id
        self.pageID = pageID
        self.frame = frame
        self.rotationDegrees = rotationDegrees
        self.zIndex = zIndex
        self.isLocked = isLocked
        self.originalFlowIndex = originalFlowIndex
        self.block = block
    }
}

public struct TemplateField: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case text, date, number, currency, sequence, tableRow }

    public let id: UUID
    public var name: String
    public var kind: Kind
    public var format: String?
    public var defaultValue: String?

    public init(id: UUID = UUID(), name: String, kind: Kind, format: String? = nil, defaultValue: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.format = format
        self.defaultValue = defaultValue
    }
}

public struct FolioAsset: Codable, Equatable, Sendable {
    public var path: String
    public var mediaType: String
    public var checksum: String

    public init(path: String, mediaType: String, checksum: String) {
        self.path = path
        self.mediaType = mediaType
        self.checksum = checksum
    }
}

public struct SourcePDFInfo: Codable, Equatable, Sendable {
    public var path: String
    public var checksum: String
    public var pageCount: Int

    public init(path: String, checksum: String, pageCount: Int) {
        self.path = path
        self.checksum = checksum
        self.pageCount = pageCount
    }
}

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

public enum FolioDocumentError: Error, Equatable {
    case blockNotFound
    case pageNotFound
    case overlayNotFound
    case invalidDocument
}

public struct FolioDocument: Codable, Equatable, Sendable {
    public var formatVersion: FormatVersion
    public var pages: [FolioPage]
    public var pageSettings: PageSettings
    public var flow: [Block]
    public var overlays: [OverlayElement]
    public var templateFields: [TemplateField]
    public var assets: [FolioAsset]
    public var sourcePDF: SourcePDFInfo?
    fileprivate var unknownFields: [String: JSONValue] = [:]

    fileprivate enum CodingKeys: String, CodingKey, CaseIterable {
        case formatVersion, pages, pageSettings, flow, overlays, templateFields, assets, sourcePDF
    }

    public init(formatVersion: FormatVersion = FormatVersion(major: 1), pages: [FolioPage], pageSettings: PageSettings = PageSettings(), flow: [Block], overlays: [OverlayElement], templateFields: [TemplateField] = [], assets: [FolioAsset] = [], sourcePDF: SourcePDFInfo? = nil) {
        self.formatVersion = formatVersion
        self.pages = pages
        self.pageSettings = pageSettings
        self.flow = flow
        self.overlays = overlays
        self.templateFields = templateFields
        self.assets = assets
        self.sourcePDF = sourcePDF
    }

    public static func blank() -> Self {
        Self(pages: [FolioPage()], flow: [Block()], overlays: [])
    }

    public mutating func pin(blockID: UUID, to pageID: UUID, frame: FolioRect, rotationDegrees: Double = 0, zIndex: Int = 0, isLocked: Bool = false) throws {
        guard pages.contains(where: { $0.id == pageID }) else { throw FolioDocumentError.pageNotFound }
        guard let index = flow.firstIndex(where: { $0.id == blockID }) else { throw FolioDocumentError.blockNotFound }
        let block = flow.remove(at: index)
        overlays.append(OverlayElement(block: block, pageID: pageID, frame: frame, rotationDegrees: rotationDegrees, zIndex: zIndex, isLocked: isLocked, originalFlowIndex: index))
    }

    public mutating func returnToFlow(overlayID: UUID) throws {
        guard let index = overlays.firstIndex(where: { $0.id == overlayID }) else { throw FolioDocumentError.overlayNotFound }
        let overlay = overlays.remove(at: index)
        flow.insert(overlay.block, at: min(overlay.originalFlowIndex, flow.endIndex))
    }
}

public struct OpenedFolioDocument: Sendable {
    public var document: FolioDocument
    public var isReadOnly: Bool
}

public enum FolioDocumentCodec {
    public static func decode(_ data: Data) throws -> OpenedFolioDocument {
        let object = try JSONDecoder().decode([String: JSONValue].self, from: data)
        var document = try JSONDecoder().decode(FolioDocument.self, from: data)
        let known = Set(FolioDocument.CodingKeys.allCases.map(\.rawValue))
        document.unknownFields = object.filter { !known.contains($0.key) }
        return OpenedFolioDocument(document: document, isReadOnly: document.formatVersion.major > 1)
    }

    public static func encode(_ document: FolioDocument) throws -> Data {
        var root = try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(document))
        for (key, value) in document.unknownFields where root[key] == nil { root[key] = value }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(root)
    }
}
