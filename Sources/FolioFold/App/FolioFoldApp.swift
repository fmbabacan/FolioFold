import FolioFoldCore
import PDFKit
import Sparkle
import SwiftUI
import UniformTypeIdentifiers

@main
struct FolioFoldApp: App {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    @Environment(\.openWindow) private var openWindow
    @State private var openRequest = 0
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var isShowingWelcome = false

    var body: some Scene {
        WindowGroup {
            WorkspaceView(openRequest: openRequest)
                .frame(minWidth: 820, minHeight: 560)
                .onAppear {
                    if VisualSnapshotHarness.runIfRequested() { return }
                    let isAutomatedRun = ProcessInfo.processInfo.environment["FOLIOFOLD_READY_FILE"] != nil
                    let shouldShowAutomatedWelcome = ProcessInfo.processInfo.environment["FOLIOFOLD_SHOW_WELCOME"] == "1"
                    if shouldShowAutomatedWelcome || (!hasSeenWelcome && !isAutomatedRun) {
                        isShowingWelcome = true
                        hasSeenWelcome = true
                    }
                }
                .sheet(isPresented: $isShowingWelcome) {
                    FolioFoldWelcomeView()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About FolioFold") {
                    openWindow(id: "about")
                }
            }
            SidebarCommands()
            CommandGroup(after: .newItem) {
                Button("Open…") { openRequest += 1 }
                    .keyboardShortcut("o")
            }
            CommandMenu("Tabs") {
                Button("Select Next Tab") {
                    NotificationCenter.default.post(name: .folioFoldSelectNextTab, object: nil)
                }
                .keyboardShortcut(.tab, modifiers: [.control])

                Button("Select Previous Tab") {
                    NotificationCenter.default.post(name: .folioFoldSelectPreviousTab, object: nil)
                }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])

                Divider()

                Button("Close Current Tab") {
                    NotificationCenter.default.post(name: .folioFoldCloseCurrentTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: [.command])
            }
            CommandGroup(replacing: .help) {
                Button("FolioFold Help and Source") {
                    NSWorkspace.shared.open(FolioFoldRelease.repositoryURL)
                }
                Button("Check for Updates…") {
                    updaterController.checkForUpdates(nil)
                }
                .disabled(!updaterController.updater.canCheckForUpdates)
                Divider()
                Button("Contact Support…") {
                    FolioFoldRelease.openSupportEmail()
                }
                Divider()
                Text("Version \(FolioFoldRelease.displayVersion)")
            }
        }

        Window("About FolioFold", id: "about") {
            FolioFoldAboutView()
        }
        .windowResizability(.contentSize)
    }
}
