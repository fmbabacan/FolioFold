import Foundation

public struct PDFPageReference: Codable, Equatable, Hashable, Sendable {
    public var documentID: UUID
    public var pageIndex: Int

    public init(documentID: UUID, pageIndex: Int) {
        self.documentID = documentID
        self.pageIndex = pageIndex
    }
}

public struct PDFPageDescriptor: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var source: PDFPageReference
    public var rotationDegrees: Int

    public init(id: UUID = UUID(), source: PDFPageReference, rotationDegrees: Int = 0) {
        self.id = id
        self.source = source
        self.rotationDegrees = Self.normalized(rotationDegrees)
    }

    private static func normalized(_ value: Int) -> Int {
        let remainder = value % 360
        return remainder < 0 ? remainder + 360 : remainder
    }
}

public struct PDFPageCollection: Codable, Equatable, Sendable {
    public var pages: [PDFPageDescriptor]

    public init(pages: [PDFPageDescriptor] = []) {
        self.pages = pages
    }

    public mutating func move(from source: Int, to destination: Int) throws {
        guard pages.indices.contains(source), destination >= 0, destination <= pages.count else {
            throw PDFOperationError.invalidPageSelection
        }
        let page = pages.remove(at: source)
        pages.insert(page, at: min(destination, pages.count))
    }

    public mutating func rotate(pageID: UUID, clockwiseBy degrees: Int) throws {
        guard degrees.isMultiple(of: 90), let index = pages.firstIndex(where: { $0.id == pageID }) else {
            throw PDFOperationError.invalidPageSelection
        }
        let remainder = (pages[index].rotationDegrees + degrees) % 360
        pages[index].rotationDegrees = remainder < 0 ? remainder + 360 : remainder
    }

    @discardableResult
    public mutating func duplicate(pageID: UUID, newID: UUID = UUID()) throws -> UUID {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else {
            throw PDFOperationError.invalidPageSelection
        }
        var copy = pages[index]
        copy = PDFPageDescriptor(id: newID, source: copy.source, rotationDegrees: copy.rotationDegrees)
        pages.insert(copy, at: index + 1)
        return newID
    }

    public mutating func remove(pageID: UUID) throws {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else {
            throw PDFOperationError.invalidPageSelection
        }
        pages.remove(at: index)
    }
}

public enum PDFOperationError: Error, Equatable, Sendable {
    case invalidInput
    case invalidPageSelection
    case passwordRequired
    case permissionDenied
    case unsupportedFormat
    case unsafeOutput
    case cancelled
    case outputVerificationFailed
}

public struct PDFOperationProgress: Equatable, Sendable {
    public var completedUnitCount: Int
    public var totalUnitCount: Int

    public init(completedUnitCount: Int, totalUnitCount: Int) {
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
    }

    public var fractionCompleted: Double {
        guard totalUnitCount > 0 else { return 0 }
        return min(1, max(0, Double(completedUnitCount) / Double(totalUnitCount)))
    }
}

public struct PDFOperationContext: Sendable {
    public var outputURL: URL
    public var isCancelled: @Sendable () -> Bool
    public var reportProgress: @Sendable (PDFOperationProgress) -> Void

    public init(
        outputURL: URL,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        reportProgress: @escaping @Sendable (PDFOperationProgress) -> Void = { _ in }
    ) {
        self.outputURL = outputURL
        self.isCancelled = isCancelled
        self.reportProgress = reportProgress
    }

    public func checkCancellation() throws {
        if isCancelled() { throw PDFOperationError.cancelled }
    }
}

public protocol PDFOperation: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    func run(_ input: Input, context: PDFOperationContext) async throws -> Output
}

public enum PDFSplitSelection: Equatable, Sendable {
    case selected(Set<Int>)
    case ranges([ClosedRange<Int>])
    case every(Int)
    case individualPages

    public func groups(pageCount: Int) throws -> [[Int]] {
        guard pageCount > 0 else { throw PDFOperationError.invalidInput }
        let valid = Set(0..<pageCount)
        switch self {
        case .selected(let selection):
            guard !selection.isEmpty, selection.isSubset(of: valid) else {
                throw PDFOperationError.invalidPageSelection
            }
            return [selection.sorted()]
        case .ranges(let ranges):
            guard !ranges.isEmpty else { throw PDFOperationError.invalidPageSelection }
            return try ranges.map { range in
                let pages = Array(range)
                guard !pages.isEmpty, pages.allSatisfy(valid.contains) else {
                    throw PDFOperationError.invalidPageSelection
                }
                return pages
            }
        case .every(let count):
            guard count > 0 else { throw PDFOperationError.invalidPageSelection }
            return stride(from: 0, to: pageCount, by: count).map { start in
                Array(start..<min(start + count, pageCount))
            }
        case .individualPages:
            return (0..<pageCount).map { [$0] }
        }
    }
}
