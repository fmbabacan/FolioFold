import Foundation
import PDFKit

public struct PDFDocumentInfo: Equatable, Sendable {
    public var pageCount: Int
    public var isEncrypted: Bool
    public var allowsCopying: Bool
    public var allowsPrinting: Bool

    public init(pageCount: Int, isEncrypted: Bool, allowsCopying: Bool, allowsPrinting: Bool) {
        self.pageCount = pageCount
        self.isEncrypted = isEncrypted
        self.allowsCopying = allowsCopying
        self.allowsPrinting = allowsPrinting
    }
}

public protocol PDFDocumentOpening: Sendable {
    func inspect(_ url: URL, password: String?) async throws -> PDFDocumentInfo
}

public struct PDFKitDocumentOpener: PDFDocumentOpening {
    public init() {}

    public func inspect(_ url: URL, password: String? = nil) async throws -> PDFDocumentInfo {
        try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: url) else {
                throw PDFOperationError.invalidInput
            }
            if document.isLocked {
                guard let password, document.unlock(withPassword: password) else {
                    throw PDFOperationError.passwordRequired
                }
            }
            guard document.pageCount > 0 else { throw PDFOperationError.invalidInput }
            return PDFDocumentInfo(
                pageCount: document.pageCount,
                isEncrypted: document.isEncrypted,
                allowsCopying: document.allowsCopying,
                allowsPrinting: document.allowsPrinting
            )
        }.value
    }
}

public struct PDFMergeInput: Sendable {
    public struct Item: Sendable {
        public var url: URL
        public var pageIndexes: [Int]?
        public var password: String?

        public init(url: URL, pageIndexes: [Int]? = nil, password: String? = nil) {
            self.url = url
            self.pageIndexes = pageIndexes
            self.password = password
        }
    }

    public var items: [Item]

    public init(items: [Item]) {
        self.items = items
    }
}

public struct PDFMergeOperation: PDFOperation {
    public init() {}

    public func run(_ input: PDFMergeInput, context: PDFOperationContext) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            guard !input.items.isEmpty else { throw PDFOperationError.invalidInput }
            try context.checkCancellation()
            let output = PDFDocument()
            var totalPages = 0
            var selections: [(PDFDocument, [Int])] = []

            for item in input.items {
                guard let document = PDFDocument(url: item.url) else {
                    throw PDFOperationError.invalidInput
                }
                if document.isLocked {
                    guard let password = item.password, document.unlock(withPassword: password) else {
                        throw PDFOperationError.passwordRequired
                    }
                }
                let indexes = item.pageIndexes ?? Array(0..<document.pageCount)
                guard !indexes.isEmpty, indexes.allSatisfy({ document.page(at: $0) != nil }) else {
                    throw PDFOperationError.invalidPageSelection
                }
                totalPages += indexes.count
                selections.append((document, indexes))
            }

            var completed = 0
            for (document, indexes) in selections {
                for index in indexes {
                    try context.checkCancellation()
                    guard let page = document.page(at: index),
                          let copiedPage = page.copy() as? PDFPage else {
                        throw PDFOperationError.invalidInput
                    }
                    output.insert(copiedPage, at: output.pageCount)
                    completed += 1
                    context.reportProgress(.init(completedUnitCount: completed, totalUnitCount: totalPages))
                }
            }
            guard output.pageCount == totalPages, totalPages > 0 else {
                throw PDFOperationError.outputVerificationFailed
            }
            try AtomicPDFWriter.write(output, to: context.outputURL)
            return context.outputURL
        }.value
    }
}

public struct PDFSplitInput: Sendable {
    public var url: URL
    public var selection: PDFSplitSelection
    public var password: String?

    public init(url: URL, selection: PDFSplitSelection, password: String? = nil) {
        self.url = url
        self.selection = selection
        self.password = password
    }
}

public struct PDFSplitOperation: PDFOperation {
    public init() {}

    public func run(_ input: PDFSplitInput, context: PDFOperationContext) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            guard let source = PDFDocument(url: input.url) else {
                throw PDFOperationError.invalidInput
            }
            if source.isLocked {
                guard let password = input.password, source.unlock(withPassword: password) else {
                    throw PDFOperationError.passwordRequired
                }
            }
            let groups = try input.selection.groups(pageCount: source.pageCount)
            let manager = FileManager.default
            let outputDirectory = context.outputURL
            let temporaryDirectory = outputDirectory.deletingLastPathComponent()
                .appendingPathComponent(".\(outputDirectory.lastPathComponent).\(UUID().uuidString).tmp", isDirectory: true)
            try manager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            defer { try? manager.removeItem(at: temporaryDirectory) }

            var completed = 0
            var temporaryURLs: [URL] = []
            let totalPages = groups.reduce(0) { $0 + $1.count }
            for (groupIndex, indexes) in groups.enumerated() {
                try context.checkCancellation()
                let part = PDFDocument()
                for index in indexes {
                    try context.checkCancellation()
                    guard let page = source.page(at: index),
                          let copiedPage = page.copy() as? PDFPage else {
                        throw PDFOperationError.invalidPageSelection
                    }
                    part.insert(copiedPage, at: part.pageCount)
                    completed += 1
                    context.reportProgress(.init(completedUnitCount: completed, totalUnitCount: totalPages))
                }
                let url = temporaryDirectory.appendingPathComponent(String(format: "part-%03d.pdf", groupIndex + 1))
                try AtomicPDFWriter.write(part, to: url)
                temporaryURLs.append(url)
            }

            try context.checkCancellation()
            if manager.fileExists(atPath: outputDirectory.path) {
                try manager.removeItem(at: outputDirectory)
            }
            try manager.moveItem(at: temporaryDirectory, to: outputDirectory)
            return temporaryURLs.map { outputDirectory.appendingPathComponent($0.lastPathComponent) }
        }.value
    }
}

private enum AtomicPDFWriter {
    static func write(_ document: PDFDocument, to destination: URL) throws {
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
