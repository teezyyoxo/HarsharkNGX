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
    private var pendingCaptureSize: NSSize?
    private var pendingTableHeight: CGFloat?

    func didFinishLaunching() {
        launchFinished = true
        focusIfReady()
        fitIfReady()
    }

    func attach(_ window: NSWindow) {
        self.window = window
        focusIfReady()
        fitIfReady()
    }

    func fitCapture(_ session: HARSession?) {
        pendingCaptureSize = session.map { CaptureWindowLayout.preferredContentSize(for: $0) }
        pendingTableHeight = session.map { CaptureWindowLayout.preferredTableHeight(for: $0) }
        fitIfReady()
    }

    private func fitIfReady() {
        guard launchFinished, window != nil, pendingCaptureSize != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, let contentSize = self.pendingCaptureSize,
                  let screen = window.screen ?? NSScreen.main else { return }
            self.pendingCaptureSize = nil
            guard !window.styleMask.contains(.fullScreen) else { return }
            window.setFrame(CaptureWindowLayout.fittingFrame(contentSize: contentSize, window: window,
                                                             visibleFrame: screen.visibleFrame), display: true, animate: false)
            let tableHeight = self.pendingTableHeight
            DispatchQueue.main.async {
                window.contentView?.layoutSubtreeIfNeeded()
                guard let content = window.contentView, let tableHeight,
                      let split = Self.captureSplit(in: content) else { return }
                split.setPosition(min(tableHeight, max(150, split.bounds.height - 300)), ofDividerAt: 0)
            }
        }
    }

    private static func captureSplit(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView, split.autosaveName == "HarsharkMainSplitV1" { return split }
        for child in view.subviews {
            if let split = captureSplit(in: child) { return split }
        }
        return nil
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
