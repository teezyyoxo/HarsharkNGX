import AppKit
import SwiftUI

@main
struct HarsharkNGXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var workspace = Workspace.shared

    init() { AppPreferences.registerDefaults() }

    var body: some Scene {
        WindowGroup("HarsharkNGX", id: "main") {
            ContentView(workspace: workspace)
                .frame(minWidth: 760, minHeight: 600)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .onOpenURL {
                    workspace.open([$0])
                    MainWindowFocusController.shared.requestFocus()
                }
                .background(MainWindowFocus(workspace: workspace).frame(width: 0, height: 0))
                .task {
                    workspace.startup()
                }
        }
        .defaultSize(width: 1440, height: 920)
        .commands {
            CaptureCommands(workspace: workspace)
            CommandGroup(after: .help) {
                Button("Open Sample Capture", action: workspace.openSample)
            }
        }
        Settings { SettingsView(workspace: workspace) }
    }
}

private struct CaptureCommands: Commands {
    let workspace: Workspace

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open HAR…") { Workspace.shared.chooseFiles() }.keyboardShortcut("o")
            Button("Reload Capture") { workspace.reload() }.keyboardShortcut("r")
                .disabled(workspace.selectedSession?.url == nil)
            Button("Close Capture") {
                if let session = workspace.selectedSession { workspace.close(session) }
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(workspace.selectedSession == nil)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainWindowFocusController.shared.didFinishLaunching()
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        Workspace.shared.open(filenames.map { URL(fileURLWithPath: $0) })
        application.reply(toOpenOrPrint: .success)
        MainWindowFocusController.shared.requestFocus()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Workspace.shared.open(urls)
        MainWindowFocusController.shared.requestFocus()
    }
}
