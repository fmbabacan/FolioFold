import FolioFoldCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct FolioFoldApp: App {
    @State private var openRequest = 0
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var isShowingWelcome = false

    var body: some Scene {
        WindowGroup {
            WorkspaceView(openRequest: openRequest)
                .frame(minWidth: 820, minHeight: 560)
                .onAppear {
                    let isAutomatedRun = ProcessInfo.processInfo.environment["FOLIOFOLD_READY_FILE"] != nil
                    if !hasSeenWelcome && !isAutomatedRun {
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
            SidebarCommands()
            CommandGroup(after: .newItem) {
                Button("Open…") { openRequest += 1 }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .help) {
                Button("FolioFold Help and Source") {
                    NSWorkspace.shared.open(FolioFoldRelease.repositoryURL)
                }
                Button("Check for Updates…") {
                    NSWorkspace.shared.open(FolioFoldRelease.releasesURL)
                }
                Divider()
                Button("Contact Support…") {
                    FolioFoldRelease.openSupportEmail()
                }
                Divider()
                Text("Version \(FolioFoldRelease.displayVersion)")
            }
        }
    }
}
