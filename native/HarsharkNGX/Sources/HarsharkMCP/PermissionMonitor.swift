import Foundation
import AppKit
import HarsharkCore

/// Launched by LaunchServices, independently of the GUI's sandbox and TCC identity.
/// One short-lived process polls; never spawn a fresh permission requester every second.
@MainActor func monitorPermissions(token: String, directory: URL) {
    guard UUID(uuidString: token) != nil else { return }
    let center = DistributedNotificationCenter.default()
    let stop = center.addObserver(forName: MCPPermissionProbe.stopNotificationName(token: token),
                                  object: nil, queue: .main) { _ in exit(0) }
    defer { center.removeObserver(stop) }
    let deadline = Date().addingTimeInterval(600)
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
        if Date() >= deadline { exit(0) }
        let status = MCPPermissionProbe.check(in: directory)
        // No paths, settings, capture data, or userInfo cross the notification boundary.
        center.postNotificationName(MCPPermissionProbe.notificationName(token: token),
                                    object: status.rawValue, userInfo: nil, deliverImmediately: true)
    }
    defer { timer.invalidate() }
    // Complete LaunchServices startup so openApplication's completion handler fires.
    application.run()
}
