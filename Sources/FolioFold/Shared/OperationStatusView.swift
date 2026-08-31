import SwiftUI

struct OperationStatusView: View {
    let isRunning: Bool
    let progress: Double
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isRunning {
                ProgressView(value: progress)
                    .accessibilityLabel("Operation progress")
            }
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
