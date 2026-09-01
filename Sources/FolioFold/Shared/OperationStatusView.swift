import SwiftUI

struct OperationStatusView: View {
    enum SemanticStatus: String {
        case success = "Success"
        case warning = "Warning"
        case error = "Error"
        case information = "Information"

        var systemImage: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            case .information: "info.circle.fill"
            }
        }
    }

    let isRunning: Bool
    let progress: Double
    let message: String?
    let onCancel: (() -> Void)?

    init(
        isRunning: Bool,
        progress: Double,
        message: String?,
        onCancel: (() -> Void)? = nil
    ) {
        self.isRunning = isRunning
        self.progress = progress
        self.message = message
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isRunning {
                HStack(spacing: 12) {
                    ProgressView(value: progress)
                        .accessibilityLabel("Operation progress")
                        .accessibilityValue(Text("\(Int((progress * 100).rounded())) percent"))
                    if let onCancel {
                        Button("Cancel", role: .cancel, action: onCancel)
                            .accessibilityLabel("Cancel current operation")
                            .accessibilityIdentifier("operation.cancel")
                    }
                }
            }
            if let message {
                let status = semanticStatus(for: message)
                Label(message, systemImage: status.systemImage)
                    .font(.callout)
                    .foregroundStyle(status == .error ? .red : .secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(status.rawValue): \(message)")
                    .accessibilityIdentifier("operation.status.\(status.rawValue.lowercased())")
            }
        }
        .frame(minHeight: isRunning || message != nil ? 28 : 0, alignment: .leading)
        .accessibilityElement(children: .contain)
        .onChange(of: message) { _, newMessage in
            guard let newMessage, !newMessage.isEmpty else { return }
            let status = semanticStatus(for: newMessage)
            NSAccessibility.post(
                element: NSApp.mainWindow as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: "\(status.rawValue): \(newMessage)",
                    .priority: NSAccessibilityPriorityLevel.medium.rawValue
                ]
            )
        }
    }

    private func semanticStatus(for message: String) -> SemanticStatus {
        let normalized = message.lowercased()
        if normalized.contains("error")
            || normalized.contains("failed")
            || normalized.contains("unable")
            || normalized.contains("incorrect")
            || normalized.contains("could not") {
            return .error
        }
        if normalized.contains("warning")
            || normalized.contains("recovery")
            || normalized.contains("read-only") {
            return .warning
        }
        if normalized.contains("saved")
            || normalized.contains("created")
            || normalized.contains("exported")
            || normalized.contains("completed")
            || normalized.contains("restored")
            || normalized.contains("discarded") {
            return .success
        }
        return .information
    }
}
