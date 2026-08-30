import AppKit
import SwiftUI

enum FolioFoldRelease {
    static let fallbackVersion = "0.1.0"
    static let supportAddress = "fatihmehmet@babacan.co"
    static let repositoryURL = URL(string: "https://github.com/fmbabacan/FolioFold")!
    static let releasesURL = repositoryURL.appending(path: "releases/latest")

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? fallbackVersion
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? version
    }

    static var displayVersion: String {
        version == build ? version : "\(version) (\(build))"
    }

    static func openSupportEmail() {
        guard let url = URL(string: "mailto:\(supportAddress)?subject=FolioFold%20Support") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct FolioFoldWelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 46))
                .foregroundStyle(DesignTokens.inkBlue)
            Text("Welcome to FolioFold")
                .font(.largeTitle.bold())
            Text("Thank you for using FolioFold. Your support helps this independent macOS app continue to improve.")
                .font(.title3)
            Text("If you find a problem or have an idea, please contact \(FolioFoldRelease.supportAddress).")
                .foregroundStyle(.secondary)
            LabeledContent("Version", value: FolioFoldRelease.displayVersion)
            HStack {
                Button("Contact Support", systemImage: "envelope") {
                    FolioFoldRelease.openSupportEmail()
                }
                Button("View on GitHub", systemImage: "safari") {
                    NSWorkspace.shared.open(FolioFoldRelease.repositoryURL)
                }
                Spacer()
                Button("Continue") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 560)
        .accessibilityIdentifier("welcome.sheet")
    }
}
