import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SignatureCaptureButton: View {
    @Binding var selectedData: Data?
    let report: (String) -> Void

    @State private var isPresented = false
    @State private var isImporting = false
    @State private var strokes: [[CGPoint]] = []
    @State private var savedSignatures: [StoredSignature] = []

    var body: some View {
        Button("Create Visual Signature…", systemImage: "signature") {
            savedSignatures = SignatureStore.load()
            strokes = []
            isPresented = true
        }
        .accessibilityIdentifier("pdf.signature.create")
        .sheet(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create Visual Signature")
                    .font(.title2.bold())

                Label(
                    "This creates an image annotation. It does not cryptographically sign or certify the PDF.",
                    systemImage: "info.circle"
                )
                    .font(.callout)
                    .accessibilityIdentifier("visual-signature.limitation")

                Text("Draw with a mouse or trackpad, import an image, or reuse a Visual Signature stored locally on this Mac.")
                    .foregroundStyle(.secondary)

                SignatureDrawingView(strokes: $strokes)
                    .frame(minWidth: 520, minHeight: 220)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.35))
                    }
                    .accessibilityLabel("Visual Signature drawing area")
                    .accessibilityHint("Draw a visual signature with a mouse or trackpad")

                HStack {
                    Button("Clear Drawing", systemImage: "eraser") {
                        strokes.removeAll()
                    }
                    .disabled(strokes.isEmpty)

                    Button("Import Signature Image…", systemImage: "photo") {
                        isImporting = true
                    }

                    Spacer()

                    Button("Use Drawing") {
                        useDrawing(saveLocally: false)
                    }
                    .disabled(strokes.isEmpty)

                    Button("Save and Use Drawing") {
                        useDrawing(saveLocally: true)
                    }
                    .disabled(strokes.isEmpty)
                }

                if !savedSignatures.isEmpty {
                    Divider()
                    Text("Saved Signatures")
                        .font(.headline)
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(savedSignatures) { signature in
                                VStack(spacing: 8) {
                                    if let image = NSImage(data: signature.data) {
                                        Image(nsImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 150, height: 60)
                                            .background(Color.white)
                                    }
                                    HStack {
                                        Button("Use") {
                                            selectedData = signature.data
                                            report("Saved signature selected.")
                                            isPresented = false
                                        }
                                        Button("Delete", role: .destructive) {
                                            SignatureStore.remove(id: signature.id)
                                            savedSignatures = SignatureStore.load()
                                        }
                                    }
                                }
                                .padding(10)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                Text("A visual signature is an image annotation, not a certified digital signature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        isPresented = false
                    }
                }
            }
            .padding(24)
            .frame(minWidth: 620, minHeight: 480)
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let data = try Data(contentsOf: url)
                    guard NSImage(data: data) != nil else {
                        throw SignatureCaptureError.invalidImage
                    }
                    selectedData = data
                    report("Imported Visual Signature image selected. This does not cryptographically sign the PDF.")
                    isPresented = false
                } catch {
                    report(error.localizedDescription)
                }
            }
        }
    }

    private func useDrawing(saveLocally: Bool) {
        do {
            let data = try SignatureRenderer.pngData(strokes: strokes, size: CGSize(width: 900, height: 300))
            if saveLocally {
                try SignatureStore.add(data)
                savedSignatures = SignatureStore.load()
                report("Signature saved locally and selected.")
            } else {
                report("Drawn signature selected.")
            }
            selectedData = data
            isPresented = false
        } catch {
            report(error.localizedDescription)
        }
    }
}

private struct SignatureDrawingView: NSViewRepresentable {
    @Binding var strokes: [[CGPoint]]

    func makeNSView(context: Context) -> SignatureCanvasView {
        let view = SignatureCanvasView()
        view.onChange = { strokes = $0 }
        return view
    }

    func updateNSView(_ view: SignatureCanvasView, context: Context) {
        if view.strokes != strokes {
            view.strokes = strokes
            view.needsDisplay = true
        }
    }
}

private final class SignatureCanvasView: NSView {
    var strokes: [[CGPoint]] = []
    var onChange: (([[CGPoint]]) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        strokes.append([convert(event.locationInWindow, from: nil)])
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !strokes.isEmpty else { return }
        strokes[strokes.count - 1].append(convert(event.locationInWindow, from: nil))
        onChange?(strokes)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !strokes.isEmpty else { return }
        strokes[strokes.count - 1].append(convert(event.locationInWindow, from: nil))
        onChange?(strokes)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
        NSColor.labelColor.setStroke()
        for points in strokes where !points.isEmpty {
            let path = NSBezierPath()
            path.lineWidth = 3
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.line(to: point)
            }
            path.stroke()
        }
    }
}

private struct StoredSignature: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let data: Data
}

private enum SignatureStore {
    private static let key = "foliofold.savedVisualSignatures"
    private static let maximumCount = 12

    static func load() -> [StoredSignature] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let values = try? JSONDecoder().decode([StoredSignature].self, from: data) else {
            return []
        }
        return values.sorted { $0.createdAt > $1.createdAt }
    }

    static func add(_ data: Data) throws {
        var values = load()
        values.insert(StoredSignature(id: UUID(), createdAt: Date(), data: data), at: 0)
        values = Array(values.prefix(maximumCount))
        try save(values)
    }

    static func remove(id: UUID) {
        try? save(load().filter { $0.id != id })
    }

    private static func save(_ values: [StoredSignature]) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(values), forKey: key)
    }
}

private enum SignatureRenderer {
    @MainActor
    static func pngData(strokes: [[CGPoint]], size: CGSize) throws -> Data {
        guard !strokes.isEmpty else { throw SignatureCaptureError.emptyDrawing }
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.black.setStroke()

        let allPoints = strokes.flatMap { $0 }
        guard let minX = allPoints.map({ $0.x }).min(),
              let maxX = allPoints.map({ $0.x }).max(),
              let minY = allPoints.map({ $0.y }).min(),
              let maxY = allPoints.map({ $0.y }).max() else {
            throw SignatureCaptureError.emptyDrawing
        }

        let sourceWidth = max(1, maxX - minX)
        let sourceHeight = max(1, maxY - minY)
        let scale = min((size.width - 60) / sourceWidth, (size.height - 60) / sourceHeight)
        let offsetX = (size.width - sourceWidth * scale) / 2
        let offsetY = (size.height - sourceHeight * scale) / 2

        for points in strokes where !points.isEmpty {
            let path = NSBezierPath()
            path.lineWidth = 7
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            let transformed = points.map { point in
                CGPoint(
                    x: offsetX + (point.x - minX) * scale,
                    y: offsetY + (maxY - point.y) * scale
                )
            }
            path.move(to: transformed[0])
            for point in transformed.dropFirst() {
                path.line(to: point)
            }
            path.stroke()
        }

        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let png = representation.representation(using: .png, properties: [:]) else {
            throw SignatureCaptureError.renderFailed
        }
        return png
    }
}

private enum SignatureCaptureError: LocalizedError {
    case emptyDrawing
    case invalidImage
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .emptyDrawing: "Draw a Visual Signature before using it."
        case .invalidImage: "The selected file is not a readable image."
        case .renderFailed: "The Visual Signature image could not be created."
        }
    }
}
