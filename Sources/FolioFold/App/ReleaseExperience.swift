import AppKit
import SwiftUI

enum FolioFoldRelease {
    static let fallbackVersion = "0.3.1"
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

struct FolioFoldAboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            if let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 5) {
                Text("FolioFold")
                    .font(.largeTitle.bold())
                Text("Your documents, thoughtfully handled on your Mac.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Text("FolioFold is an independent, open-source workspace for creating structured documents and working with PDFs. Merge, split, convert, annotate, redact, and build reusable templates without sending your files away.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Label("Your documents stay on this Mac.", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.inkBlue)

            Text("Made with care for people who want useful document tools without giving up privacy. Thanks for being part of FolioFold’s journey.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Version \(FolioFoldRelease.displayVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Contact Support", systemImage: "envelope") {
                    FolioFoldRelease.openSupportEmail()
                }
                Button("View on GitHub", systemImage: "safari") {
                    NSWorkspace.shared.open(FolioFoldRelease.repositoryURL)
                }
            }
        }
        .padding(30)
        .frame(width: 500)
        .accessibilityIdentifier("about.window")
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
                    .accessibilityIdentifier("welcome.continue")
            }
        }
        .padding(30)
        .frame(width: 560)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welcome.sheet")
    }
}
