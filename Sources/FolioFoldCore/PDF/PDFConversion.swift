import AppKit
import Foundation
import PDFKit

public enum PDFConversionSource: Sendable {
    case image(URL)
    case plainText(URL)
    case richText(URL)
    case html(URL)
}

public struct PDFConvertInput: Sendable {
    public var sources: [PDFConversionSource]

    public init(sources: [PDFConversionSource]) {
        self.sources = sources
    }
}

public struct PDFConvertOperation: PDFOperation {
    public init() {}

    public static func estimatedPageCount(for source: PDFConversionSource) throws -> Int {
        try pages(for: source).count
    }

    public static func estimatedPageCount(for sources: [PDFConversionSource]) throws -> Int {
        guard !sources.isEmpty else { throw PDFOperationError.invalidInput }
        return try sources.reduce(0) { count, source in
            count + (try estimatedPageCount(for: source))
        }
    }

    public func run(_ input: PDFConvertInput, context: PDFOperationContext) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            guard !input.sources.isEmpty else { throw PDFOperationError.invalidInput }
            let output = PDFDocument()

            for (index, source) in input.sources.enumerated() {
                try context.checkCancellation()
                let pages = try Self.pages(for: source)
                guard !pages.isEmpty else { throw PDFOperationError.invalidInput }
                for page in pages { output.insert(page, at: output.pageCount) }
                context.reportProgress(.init(
                    completedUnitCount: index + 1,
                    totalUnitCount: input.sources.count
                ))
            }

            guard output.pageCount > 0 else { throw PDFOperationError.outputVerificationFailed }
            try Self.writePDF(output, to: context.outputURL)
            return context.outputURL
        }.value
    }

    private static func pages(for source: PDFConversionSource) throws -> [PDFPage] {
        switch source {
        case .image(let url):
            guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else {
                throw PDFOperationError.unsupportedFormat
            }
            return [page]
        case .plainText(let url):
            let text = try String(contentsOf: url, encoding: .utf8)
            return try textPages(NSAttributedString(string: text, attributes: textAttributes))
        case .richText(let url):
            let data = try Data(contentsOf: url)
            guard let text = NSAttributedString(rtf: data, documentAttributes: nil) else {
                throw PDFOperationError.unsupportedFormat
            }
            return try textPages(text)
        case .html(let url):
            guard url.isFileURL else { throw PDFOperationError.permissionDenied }
            let data = try Data(contentsOf: url)
            guard let text = NSAttributedString(
                html: data,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
            ) else {
                throw PDFOperationError.unsupportedFormat
            }
            return try textPages(text)
        }
    }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.textColor]
    }

    private static func textPages(_ text: NSAttributedString) throws -> [PDFPage] {
        let pageSize = NSSize(width: 595, height: 842)
        let printableRect = NSRect(x: 54, y: 54, width: 487, height: 734)
        let storage = NSTextStorage(attributedString: text)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        var pages: [PDFPage] = []
        var glyphIndex = 0

        repeat {
            let container = NSTextContainer(size: printableRect.size)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            layoutManager.ensureLayout(for: container)
            let glyphRange = layoutManager.glyphRange(for: container)
            guard glyphRange.length > 0 || storage.length == 0 else {
                throw PDFOperationError.outputVerificationFailed
            }

            let image = NSImage(size: pageSize)
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: pageSize).fill()
            if glyphRange.length > 0 {
                layoutManager.drawBackground(forGlyphRange: glyphRange, at: printableRect.origin)
                layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: printableRect.origin)
            }
            image.unlockFocus()
            guard let page = PDFPage(image: image) else {
                throw PDFOperationError.outputVerificationFailed
            }
            pages.append(page)
            glyphIndex = NSMaxRange(glyphRange)
        } while glyphIndex < layoutManager.numberOfGlyphs

        return pages
    }

    private static func writePDF(_ document: PDFDocument, to destination: URL) throws {
        let manager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }
        guard document.write(to: temporary),
              let verification = PDFDocument(url: temporary),
              verification.pageCount == document.pageCount else {
            throw PDFOperationError.outputVerificationFailed
        }
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: destination)
        }
    }
}

public enum PDFImageExportFormat: Sendable {
    case png
    case jpeg(quality: Double)
}

public struct PDFImageExportInput: Sendable {
    public var url: URL
    public var pageIndexes: [Int]?
    public var format: PDFImageExportFormat
    public var scale: Double
    public var password: String?

    public init(
        url: URL,
        pageIndexes: [Int]? = nil,
        format: PDFImageExportFormat,
        scale: Double = 2,
        password: String? = nil
    ) {
        self.url = url
        self.pageIndexes = pageIndexes
        self.format = format
        self.scale = scale
        self.password = password
    }
}

public struct PDFImageExportOperation: PDFOperation {
    public init() {}

    public func run(_ input: PDFImageExportInput, context: PDFOperationContext) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            guard input.scale > 0, let document = PDFDocument(url: input.url) else {
                throw PDFOperationError.invalidInput
            }
            if document.isLocked {
                guard let password = input.password, document.unlock(withPassword: password) else {
                    throw PDFOperationError.passwordRequired
                }
            }
            let indexes = input.pageIndexes ?? Array(0..<document.pageCount)
            guard !indexes.isEmpty, indexes.allSatisfy({ document.page(at: $0) != nil }) else {
                throw PDFOperationError.invalidPageSelection
            }

            let manager = FileManager.default
            let destination = context.outputURL
            let temporary = destination.deletingLastPathComponent()
                .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp", isDirectory: true)
            try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer { try? manager.removeItem(at: temporary) }

            var names: [String] = []
            for (offset, pageIndex) in indexes.enumerated() {
                try context.checkCancellation()
                guard let page = document.page(at: pageIndex) else {
                    throw PDFOperationError.invalidPageSelection
                }
                let bounds = page.bounds(for: .mediaBox)
                let size = NSSize(width: bounds.width * input.scale, height: bounds.height * input.scale)
                let image = page.thumbnail(of: size, for: .mediaBox)
                guard let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff) else {
                    throw PDFOperationError.outputVerificationFailed
                }
                let extensionName: String
                let data: Data?
                switch input.format {
                case .png:
                    extensionName = "png"
                    data = bitmap.representation(using: .png, properties: [:])
                case .jpeg(let quality):
                    extensionName = "jpg"
                    data = bitmap.representation(
                        using: .jpeg,
                        properties: [.compressionFactor: min(1, max(0, quality))]
                    )
                }
                guard let data else { throw PDFOperationError.outputVerificationFailed }
                let name = String(format: "page-%03d.%@", pageIndex + 1, extensionName)
                try data.write(to: temporary.appendingPathComponent(name), options: .atomic)
                names.append(name)
                context.reportProgress(.init(completedUnitCount: offset + 1, totalUnitCount: indexes.count))
            }

            try context.checkCancellation()
            if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
            try manager.moveItem(at: temporary, to: destination)
            return names.map { destination.appendingPathComponent($0) }
        }.value
    }
}
