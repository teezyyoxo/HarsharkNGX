import AppKit
import SwiftUI

/// File-open events can arrive before launch completes or SwiftUI attaches its
/// window. Keep the request until both are ready, then focus on the next run loop.
@MainActor
final class MainWindowFocusController {
    static let shared = MainWindowFocusController()
    private weak var window: NSWindow?
    private var launchFinished = false
    private var focusRequested = false

    func didFinishLaunching() {
        launchFinished = true
        focusIfReady()
    }

    func attach(_ window: NSWindow) {
        self.window = window
        focusIfReady()
    }

    func requestFocus() {
        focusRequested = true
        focusIfReady()
    }

    private func focusIfReady() {
        guard launchFinished, focusRequested, window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.focusRequested, let window = self.window else { return }
            self.focusRequested = false
            NSApp.unhide(nil)
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }
}

/// Preserve SwiftUI's window delegate while routing Command–W to the selected capture.
/// The title-bar close button and Settings retain normal macOS window behavior.
struct MainWindowFocus: NSViewRepresentable {
    let workspace: Workspace

    func makeNSView(context: Context) -> Marker {
        let marker = Marker()
        marker.workspace = workspace
        return marker
    }

    func updateNSView(_ view: Marker, context: Context) {}

    final class Marker: NSView {
        weak var workspace: Workspace?
        private var keyMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            guard let window else { return }
            MainWindowFocusController.shared.attach(window)
            // Leave SwiftUI's delegate intact: AppKit sends it lifecycle callbacks
            // when an external file-open event brings this window to the front.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window,
                      NSApp.keyWindow === window,
                      window.attachedSheet == nil,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      event.charactersIgnoringModifiers == "w",
                      let workspace = self.workspace, let session = workspace.selectedSession else { return event }
                workspace.close(session)
                return nil
            }
        }

        deinit {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        }
    }
}
