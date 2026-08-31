import AppKit
import Foundation
import PDFKit

public struct PDFAnnotationDescriptor: Sendable {
    public enum Kind: Sendable {
        case freeText(String)
        case highlight
        case link(URL)
        case rectangle
        case ink([[CGPoint]])
        case image(Data)
        case visualSignature(Data)
    }

    public var pageIndex: Int
    public var bounds: CGRect
    public var kind: Kind

    public init(pageIndex: Int, bounds: CGRect, kind: Kind) {
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.kind = kind
    }
}

public struct PDFAnnotationInput: Sendable {
    public var url: URL
    public var annotations: [PDFAnnotationDescriptor]
    public var password: String?

    public init(url: URL, annotations: [PDFAnnotationDescriptor], password: String? = nil) {
        self.url = url
        self.annotations = annotations
        self.password = password
    }
}

public struct PDFAnnotationOperation: PDFOperation {
    public init() {}

    public func run(_ input: PDFAnnotationInput, context: PDFOperationContext) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            guard !input.annotations.isEmpty, let document = PDFDocument(url: input.url) else {
                throw PDFOperationError.invalidInput
            }
            if document.isLocked {
                guard let password = input.password, document.unlock(withPassword: password) else {
                    throw PDFOperationError.passwordRequired
                }
            }

            for (offset, descriptor) in input.annotations.enumerated() {
                try context.checkCancellation()
                guard let page = document.page(at: descriptor.pageIndex),
                      descriptor.bounds.width > 0, descriptor.bounds.height > 0 else {
                    throw PDFOperationError.invalidPageSelection
                }
                let annotation = try Self.makeAnnotation(descriptor)
                page.addAnnotation(annotation)
                context.reportProgress(.init(
                    completedUnitCount: offset + 1,
                    totalUnitCount: input.annotations.count
                ))
            }

            try context.checkCancellation()
            try PDFEditingWriter.write(document, to: context.outputURL)
            return context.outputURL
        }.value
    }

    private static func makeAnnotation(_ descriptor: PDFAnnotationDescriptor) throws -> PDFAnnotation {
        switch descriptor.kind {
        case .freeText(let text):
            let annotation = PDFAnnotation(bounds: descriptor.bounds, forType: .freeText, withProperties: nil)
            annotation.contents = text
            annotation.font = NSFont.systemFont(ofSize: 12)
            annotation.fontColor = .textColor
            return annotation
        case .highlight:
            let annotation = PDFAnnotation(bounds: descriptor.bounds, forType: .highlight, withProperties: nil)
            annotation.color = NSColor.systemYellow.withAlphaComponent(0.45)
            return annotation
        case .link(let url):
            let annotation = PDFAnnotation(bounds: descriptor.bounds, forType: .link, withProperties: nil)
            annotation.url = url
            return annotation
        case .rectangle:
            let annotation = PDFAnnotation(bounds: descriptor.bounds, forType: .square, withProperties: nil)
            annotation.color = .systemBlue
            let border = PDFBorder()
            border.lineWidth = 1
            annotation.border = border
            return annotation
        case .ink(let paths):
            guard !paths.isEmpty else { throw PDFOperationError.invalidInput }
            let annotation = PDFAnnotation(bounds: descriptor.bounds, forType: .ink, withProperties: nil)
            annotation.color = .labelColor
            for points in paths where !points.isEmpty {
                let path = NSBezierPath()
                path.move(to: points[0])
                for point in points.dropFirst() { path.line(to: point) }
                annotation.add(path)
            }
            return annotation
        case .image(let data), .visualSignature(let data):
            guard let image = NSImage(data: data) else { throw PDFOperationError.invalidInput }
            let annotation = PDFImageStampAnnotation(bounds: descriptor.bounds, image: image)
            return annotation
        }
    }
}

public enum PDFFormFieldKind: Sendable {
    case text
    case checkBox
    case radioButton
    case choice(options: [String])
    case signature
}

public struct PDFFormFieldDescriptor: Sendable {
    public var pageIndex: Int
    public var bounds: CGRect
    public var name: String
    public var kind: PDFFormFieldKind
    public var value: String?

    public init(pageIndex: Int, bounds: CGRect, name: String, kind: PDFFormFieldKind, value: String? = nil) {
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.name = name
        self.kind = kind
        self.value = value
    }
}

public struct PDFFormInput: Sendable {
    public var url: URL
    public var fields: [PDFFormFieldDescriptor]
    public var valuesByName: [String: String]
    public var password: String?

    public init(
        url: URL,
        fields: [PDFFormFieldDescriptor] = [],
        valuesByName: [String: String] = [:],
        password: String? = nil
    ) {
        self.url = url
        self.fields = fields
        self.valuesByName = valuesByName
        self.password = password
    }
}

public struct PDFFormOperation: PDFOperation {
    public init() {}

    public func run(_ input: PDFFormInput, context: PDFOperationContext) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            guard !input.fields.isEmpty || !input.valuesByName.isEmpty,
                  let document = PDFDocument(url: input.url) else {
                throw PDFOperationError.invalidInput
            }
            if document.isLocked {
                guard let password = input.password, document.unlock(withPassword: password) else {
                    throw PDFOperationError.passwordRequired
                }
            }

            var completed = 0
            let existing = (0..<document.pageCount).flatMap { document.page(at: $0)?.annotations ?? [] }
            for (name, value) in input.valuesByName {
                try context.checkCancellation()
                guard let field = existing.first(where: { annotation in
                    annotation.fieldName == name && (
                        annotation.type == PDFAnnotationSubtype.widget.rawValue ||
                        annotation.type == "Widget"
                    )
                }) else {
                    throw PDFOperationError.invalidInput
                }
                field.widgetStringValue = value
                completed += 1
                context.reportProgress(.init(
                    completedUnitCount: completed,
                    totalUnitCount: input.valuesByName.count + input.fields.count
                ))
            }

            for descriptor in input.fields {
                try context.checkCancellation()
                guard !descriptor.name.isEmpty,
                      descriptor.bounds.width > 0, descriptor.bounds.height > 0,
                      let page = document.page(at: descriptor.pageIndex) else {
                    throw PDFOperationError.invalidPageSelection
                }
                guard !existing.contains(where: { $0.fieldName == descriptor.name }) else {
                    throw PDFOperationError.invalidInput
                }
                page.addAnnotation(Self.makeField(descriptor))
                completed += 1
                context.reportProgress(.init(
                    completedUnitCount: completed,
                    totalUnitCount: input.valuesByName.count + input.fields.count
                ))
            }

            try context.checkCancellation()
            try PDFEditingWriter.write(document, to: context.outputURL)
            return context.outputURL
        }.value
    }

    private static func makeField(_ descriptor: PDFFormFieldDescriptor) -> PDFAnnotation {
        let annotation: PDFAnnotation
        switch descriptor.kind {
        case .text:
            annotation = PDFAnnotation(bounds: descriptor.bounds, forType: .widget, withProperties: nil)
            annotation.widgetFieldType = .text
        case .checkBox:
            annotation = PDFAnnotation(bounds: descriptor.bounds, forType: .widget, withProperties: nil)
            annotation.widgetFieldType = .button
            annotation.widgetControlType = .checkBoxControl
        case .radioButton:
            annotation = PDFAnnotation(bounds: descriptor.bounds, forType: .widget, withProperties: nil)
            annotation.widgetFieldType = .button
            annotation.widgetControlType = .radioButtonControl
        case .choice(let options):
            annotation = PDFAnnotation(bounds: descriptor.bounds, forType: .widget, withProperties: nil)
            annotation.widgetFieldType = .choice
            annotation.choices = options
            if descriptor.value == nil {
                annotation.widgetStringValue = options.first
            }
        case .signature:
            annotation = PDFAnnotation(bounds: descriptor.bounds, forType: .widget, withProperties: nil)
            annotation.widgetFieldType = .signature
        }
        annotation.fieldName = descriptor.name
        if let value = descriptor.value {
            annotation.widgetStringValue = value
        }
        annotation.color = .separatorColor
        return annotation
    }
}

private final class PDFImageStampAnnotation: PDFAnnotation {
    private let stampImage: NSImage

    init(bounds: CGRect, image: NSImage) {
        self.stampImage = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cgImage = stampImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        context.saveGState()
        context.draw(cgImage, in: bounds)
        context.restoreGState()
    }
}

private enum PDFEditingWriter {
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
