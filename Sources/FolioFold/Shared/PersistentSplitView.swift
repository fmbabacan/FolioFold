import AppKit
import SwiftUI

enum SplitPanelAdjustment: String {
    case workspaceSidebar
    case pdfThumbnails
    case pdfInspector

    static let notification = Notification.Name("FolioFoldSplitPanelAdjustment")

    func post(delta: CGFloat) {
        NotificationCenter.default.post(
            name: Self.notification,
            object: nil,
            userInfo: ["panel": rawValue, "delta": delta]
        )
    }
}

struct PersistentSplitView: NSViewRepresentable {
    let autosaveName: String
    let panels: [SplitPanelAdjustment]

    func makeCoordinator() -> Coordinator {
        Coordinator(autosaveName: autosaveName, panels: panels)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
    }

    @MainActor
    final class Coordinator: NSObject {
        private let autosaveName: String
        private let panels: [SplitPanelAdjustment]
        private weak var splitView: NSSplitView?

        init(autosaveName: String, panels: [SplitPanelAdjustment]) {
            self.autosaveName = autosaveName
            self.panels = panels
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(receiveAdjustment(_:)),
                name: SplitPanelAdjustment.notification,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(to view: NSView) {
            Task { @MainActor [weak self, weak view] in
                guard let self, let view else { return }
                var ancestor = view.superview
                while let current = ancestor {
                    if let splitView = current as? NSSplitView {
                        self.splitView = splitView
                        splitView.autosaveName = self.autosaveName
                        return
                    }
                    ancestor = current.superview
                }
            }
        }

        @objc private func receiveAdjustment(_ notification: Notification) {
            guard let splitView,
                  let panelName = notification.userInfo?["panel"] as? String,
                  let panel = SplitPanelAdjustment(rawValue: panelName),
                  let panelIndex = panels.firstIndex(of: panel),
                  let delta = notification.userInfo?["delta"] as? CGFloat,
                  splitView.subviews.indices.contains(panelIndex) else { return }

            if panelIndex == 0, !splitView.subviews.isEmpty {
                let currentWidth = splitView.subviews[0].frame.width
                splitView.setPosition(currentWidth + delta, ofDividerAt: 0)
            } else if panelIndex == splitView.subviews.count - 1, panelIndex > 0 {
                let currentWidth = splitView.subviews[panelIndex].frame.width
                splitView.setPosition(
                    splitView.bounds.width - currentWidth - delta,
                    ofDividerAt: panelIndex - 1
                )
            }
            splitView.adjustSubviews()
        }
    }
}
