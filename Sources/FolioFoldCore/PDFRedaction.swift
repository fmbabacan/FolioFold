import AppKit
import CoreGraphics
import Foundation
import PDFKit

public struct PDFRedactionMark: Equatable, Sendable {
    public var pageIndex: Int
    public var bounds: CGRect

    public init(pageIndex: Int, bounds: CGRect) {
        self.pageIndex = pageIndex
        self.bounds = bounds
    }
}

public struct PDFRedactionInput: Sendable {
    public var url: URL
    public var marks: [PDFRedactionMark]
    public var password: String?
    public var rasterScale: CGFloat

    public init(
        url: URL,
        marks: [PDFRedactionMark],
        password: String? = nil,
        rasterScale: CGFloat = 2
    ) {
        self.url = url
        self.marks = marks
        self.password = password
        self.rasterScale = rasterScale
    }
}

public struct PDFRedactionVerification: Equatable, Sendable {
    public var pageCount: Int
    public var extractedTextIsEmpty: Bool
    public var annotationCount: Int
    public var sourceMetadataRemoved: Bool
    public var redactedRegionsAreOpaque: Bool

    public init(
        pageCount: Int,
        extractedTextIsEmpty: Bool,
        annotationCount: Int,
        sourceMetadataRemoved: Bool,
        redactedRegionsAreOpaque: Bool
    ) {
        self.pageCount = pageCount
        self.extractedTextIsEmpty = extractedTextIsEmpty
        self.annotationCount = annotationCount
        self.sourceMetadataRemoved = sourceMetadataRemoved
        self.redactedRegionsAreOpaque = redactedRegionsAreOpaque
    }
}

public struct PDFRedactionResult: Equatable, Sendable {
    public var url: URL
    public var verification: PDFRedactionVerification

    public init(url: URL, verification: PDFRedactionVerification) {
        self.url = url
        self.verification = verification
    }
}

public struct PDFRedactionOperation: PDFOperation {
    public init() {}

    public func run(_ input: PDFRedactionInput, context: PDFOperationContext) async throws -> PDFRedactionResult {
        try await Task.detached(priority: .userInitiated) {
            guard !input.marks.isEmpty, input.rasterScale > 0,
                  input.url.standardizedFileURL != context.outputURL.standardizedFileURL,
                  let source = PDFDocument(url: input.url) else {
                throw PDFOperationError.invalidInput
            }
            if source.isLocked {
                guard let password = input.password, source.unlock(withPassword: password) else {
                    throw PDFOperationError.passwordRequired
                }
            }
            guard source.pageCount > 0 else { throw PDFOperationError.invalidInput }

            let grouped = Dictionary(grouping: input.marks, by: \.pageIndex)
            guard grouped.keys.allSatisfy({ $0 >= 0 && $0 < source.pageCount }),
                  input.marks.allSatisfy({ $0.bounds.width > 0 && $0.bounds.height > 0 }) else {
                throw PDFOperationError.invalidPageSelection
            }

            let output = PDFDocument()
            for pageIndex in 0..<source.pageCount {
                try context.checkCancellation()
                guard let sourcePage = source.page(at: pageIndex) else {
                    throw PDFOperationError.invalidPageSelection
                }
                let mediaBox = sourcePage.bounds(for: .mediaBox)
                guard mediaBox.width > 0, mediaBox.height > 0 else {
                    throw PDFOperationError.unsafeOutput
                }
                let pixelWidth = Int(ceil(mediaBox.width * input.rasterScale))
                let pixelHeight = Int(ceil(mediaBox.height * input.rasterScale))
                guard pixelWidth > 0, pixelHeight > 0,
                      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                      let bitmap = CGContext(
                        data: nil,
                        width: pixelWidth,
                        height: pixelHeight,
                        bitsPerComponent: 8,
                        bytesPerRow: 0,
                        space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      ) else {
                    throw PDFOperationError.unsafeOutput
                }

                bitmap.setFillColor(NSColor.white.cgColor)
                bitmap.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
                bitmap.saveGState()
                bitmap.scaleBy(x: input.rasterScale, y: input.rasterScale)
                bitmap.translateBy(x: -mediaBox.minX, y: -mediaBox.minY)
                sourcePage.draw(with: .mediaBox, to: bitmap)
                bitmap.restoreGState()

                bitmap.setFillColor(NSColor.black.cgColor)
                for mark in grouped[pageIndex] ?? [] {
                    let clipped = mark.bounds.intersection(mediaBox)
                    guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else {
                        throw PDFOperationError.invalidPageSelection
                    }
                    bitmap.fill(CGRect(
                        x: (clipped.minX - mediaBox.minX) * input.rasterScale,
                        y: (clipped.minY - mediaBox.minY) * input.rasterScale,
                        width: clipped.width * input.rasterScale,
                        height: clipped.height * input.rasterScale
                    ))
                }

                guard let image = bitmap.makeImage(),
                      let page = PDFPage(image: NSImage(cgImage: image, size: mediaBox.size)) else {
                    throw PDFOperationError.unsafeOutput
                }
                output.insert(page, at: output.pageCount)
                context.reportProgress(.init(
                    completedUnitCount: pageIndex + 1,
                    totalUnitCount: source.pageCount
                ))
            }

            try context.checkCancellation()
            guard output.pageCount == source.pageCount else {
                throw PDFOperationError.outputVerificationFailed
            }
            let temporary = context.outputURL.deletingLastPathComponent()
                .appendingPathComponent(".\(context.outputURL.lastPathComponent).\(UUID().uuidString).tmp")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try FileManager.default.createDirectory(
                at: context.outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard output.write(to: temporary), let verificationDocument = PDFDocument(url: temporary),
                  verificationDocument.pageCount == source.pageCount else {
                throw PDFOperationError.outputVerificationFailed
            }

            let extracted = verificationDocument.string?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let annotationCount = (0..<verificationDocument.pageCount).reduce(0) { count, index in
                count + (verificationDocument.page(at: index)?.annotations.count ?? 0)
            }
            let sensitiveMetadataKeys: [PDFDocumentAttribute] = [
                .titleAttribute,
                .authorAttribute,
                .subjectAttribute,
                .keywordsAttribute
            ]
            let sourceAttributes = source.documentAttributes ?? [:]
            let outputAttributes = verificationDocument.documentAttributes ?? [:]
            let sourceMetadataValues = sensitiveMetadataKeys.compactMap { key -> String? in
                let value = sourceAttributes[key]
                if let string = value as? String { return string }
                if let strings = value as? [String] { return strings.joined(separator: " ") }
                return nil
            }.filter { !$0.isEmpty }
            let outputMetadataValues = sensitiveMetadataKeys.compactMap { key -> String? in
                let value = outputAttributes[key]
                if let string = value as? String { return string }
                if let strings = value as? [String] { return strings.joined(separator: " ") }
                return nil
            }
            let sourceMetadataRemoved = sourceMetadataValues.allSatisfy { sourceValue in
                !outputMetadataValues.contains(sourceValue)
            }
            let redactedRegionsAreOpaque = grouped.allSatisfy { pageIndex, marks in
                guard let page = verificationDocument.page(at: pageIndex) else { return false }
                let pageBounds = page.bounds(for: .mediaBox)
                let thumbnail = page.thumbnail(of: pageBounds.size, for: .mediaBox)
                guard let data = thumbnail.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: data) else { return false }
                return marks.allSatisfy { mark in
                    let clipped = mark.bounds.intersection(pageBounds)
                    guard !clipped.isNull else { return false }
                    let samplePoints = [
                        CGPoint(x: clipped.midX, y: clipped.midY),
                        CGPoint(x: clipped.minX + clipped.width * 0.25, y: clipped.minY + clipped.height * 0.25),
                        CGPoint(x: clipped.minX + clipped.width * 0.75, y: clipped.minY + clipped.height * 0.75)
                    ]
                    return samplePoints.allSatisfy { point in
                        let x = min(bitmap.pixelsWide - 1, max(0, Int((point.x - pageBounds.minX) / pageBounds.width * CGFloat(bitmap.pixelsWide))))
                        let mappedY = Int((point.y - pageBounds.minY) / pageBounds.height * CGFloat(bitmap.pixelsHigh))
                        let y = min(bitmap.pixelsHigh - 1, max(0, bitmap.pixelsHigh - 1 - mappedY))
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                        return color.alphaComponent >= 0.99
                            && color.redComponent <= 0.02
                            && color.greenComponent <= 0.02
                            && color.blueComponent <= 0.02
                    }
                }
            }
            guard extracted.isEmpty, annotationCount == 0, sourceMetadataRemoved, redactedRegionsAreOpaque else {
                throw PDFOperationError.unsafeOutput
            }

            let manager = FileManager.default
            if manager.fileExists(atPath: context.outputURL.path) {
                _ = try manager.replaceItemAt(context.outputURL, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: context.outputURL)
            }
            return PDFRedactionResult(
                url: context.outputURL,
                verification: .init(
                    pageCount: verificationDocument.pageCount,
                    extractedTextIsEmpty: true,
                    annotationCount: 0,
                    sourceMetadataRemoved: true,
                    redactedRegionsAreOpaque: true
                )
            )
        }.value
    }
}
