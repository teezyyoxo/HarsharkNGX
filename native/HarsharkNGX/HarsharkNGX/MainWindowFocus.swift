import AppKit
import SwiftUI

/// Preserve SwiftUI's window delegate while routing Command–W to the selected capture.
/// The title-bar close button and Settings retain normal macOS window behavior.
struct MainWindowFocus: NSViewRepresentable {
    let workspace: Workspace

    func makeNSView(context: Context) -> Marker {
        let marker = Marker()
        marker.closeDelegate.workspace = workspace
        return marker
    }

    func updateNSView(_ view: Marker, context: Context) {}

    final class Marker: NSView {
        let closeDelegate = CaptureWindowDelegate()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window.delegate !== closeDelegate else { return }
            closeDelegate.original = window.delegate
            window.delegate = closeDelegate
        }
    }

    final class CaptureWindowDelegate: NSObject, NSWindowDelegate {
        weak var workspace: Workspace?
        weak var original: (any NSWindowDelegate)?

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if let event = NSApp.currentEvent,
               event.type == .keyDown,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "w",
               let workspace, let session = workspace.selectedSession {
                workspace.close(session)
                return false
            }
            return original?.windowShouldClose?(sender) ?? true
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            original
        }
    }
}
