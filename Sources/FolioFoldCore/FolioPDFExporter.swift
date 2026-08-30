import AppKit
import Foundation
import PDFKit

public enum FolioPDFExporter {
    public static func export(_ document: FolioDocument, to destination: URL) throws {
        let layout = try FolioPaginator().layout(document)
        let settings = document.pageSettings
        guard settings.width > 0, settings.height > 0 else {
            throw FolioDocumentError.invalidDocument
        }

        let output = PDFDocument()
        let pageCount = max(layout.pageCount, document.pages.count, 1)
        let blocks = Dictionary(uniqueKeysWithValues: document.flow.map { ($0.id, $0) })

        for pageIndex in 0..<pageCount {
            let size = NSSize(width: settings.width, height: settings.height)
            let image = NSImage(size: size)
            image.lockFocusFlipped(false)
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

            for placement in layout.placements where placement.pageIndex == pageIndex {
                guard let block = blocks[placement.blockID] else { continue }
                draw(block, in: placement.frame, pageHeight: settings.height)
            }

            if document.pages.indices.contains(pageIndex) {
                let pageID = document.pages[pageIndex].id
                for overlay in document.overlays
                    .filter({ $0.pageID == pageID })
                    .sorted(by: { $0.zIndex < $1.zIndex }) {
                    draw(overlay.contentBlock, in: overlay.frame, pageHeight: settings.height)
                }
            }

            image.unlockFocus()
            guard let page = PDFPage(image: image) else {
                throw PDFOperationError.outputVerificationFailed
            }
            output.insert(page, at: output.pageCount)
        }

        let manager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }
        guard output.write(to: temporary),
              let verified = PDFDocument(url: temporary),
              verified.pageCount == pageCount else {
            throw PDFOperationError.outputVerificationFailed
        }
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: destination)
        }
    }

    private static func draw(_ block: Block, in frame: FolioRect, pageHeight: Double) {
        let rect = NSRect(
            x: frame.x,
            y: pageHeight - frame.y - frame.height,
            width: frame.width,
            height: frame.height
        )
        if block.kind == .divider {
            NSColor.separatorColor.setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: rect.midY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
            path.stroke()
            return
        }

        if block.kind == .shape {
            NSColor.systemBlue.withAlphaComponent(0.12).setFill()
            NSColor.systemBlue.setStroke()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).stroke()
        }

        let text = block.text.isEmpty ? placeholder(for: block.kind) : block.text
        let font = block.kind == .heading
            ? NSFont.boldSystemFont(ofSize: 22)
            : NSFont.systemFont(ofSize: 12)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor
        ]
        NSString(string: text).draw(
            with: rect.insetBy(dx: 4, dy: 4),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }

    private static func placeholder(for kind: Block.Kind) -> String {
        switch kind {
        case .image: "Image"
        case .formField: "Form Field"
        case .signatureField: "Signature Field"
        case .table: "Table"
        case .list: "List"
        default: ""
        }
    }
}
