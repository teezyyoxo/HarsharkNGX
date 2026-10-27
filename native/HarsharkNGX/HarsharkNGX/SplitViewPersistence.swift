import AppKit
import SwiftUI

/// Give the native split views stable autosave names so pane sizes survive relaunches.
struct SplitViewPersistence: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> Marker {
        let view = Marker()
        view.name = name
        return view
    }

    func updateNSView(_ view: Marker, context: Context) { view.configure() }

    final class Marker: NSView {
        var name = ""
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            Task { @MainActor [weak self] in self?.configure() }
        }

        func configure() {
            var ancestor = superview
            while let view = ancestor {
                if let split = view as? NSSplitView {
                    if split.autosaveName == nil { split.autosaveName = name }
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
