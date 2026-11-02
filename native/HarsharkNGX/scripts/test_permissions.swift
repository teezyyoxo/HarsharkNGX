// Run: swift scripts/test_permissions.swift /absolute/path/to/HarsharkMCP.app
// Exercises the real LaunchServices monitor and distributed-notification transport.
import AppKit
import Foundation

let bundle = URL(fileURLWithPath: CommandLine.arguments[1])
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let marker = directory.appendingPathComponent(".mcp-permission-probe")
let settings = directory.appendingPathComponent(".mcp-access.json")
let token = UUID().uuidString
let name = Notification.Name("com.teezyyoxo.HarsharkNGX.permission.\(token)")
let stop = Notification.Name("com.teezyyoxo.HarsharkNGX.permission.stop.\(token)")
let center = DistributedNotificationCenter.default()
var reports: [String] = []
var app: NSRunningApplication?
var launchError: Error?
let observer = center.addObserver(forName: name, object: nil, queue: .main) { notification in
    if let status = notification.object as? String { reports.append(status) }
}
defer {
    center.postNotificationName(stop, object: nil, userInfo: nil, deliverImmediately: true)
    center.removeObserver(observer)
}
let config = NSWorkspace.OpenConfiguration()
config.activates = false
config.allowsRunningApplicationSubstitution = false
config.createsNewApplicationInstance = true
config.arguments = ["--permission-monitor", token, "--session-directory", directory.path]
NSWorkspace.shared.openApplication(at: bundle, configuration: config) { running, error in
    app = running
    launchError = error
}
func waitFor(_ status: String) {
    let deadline = Date().addingTimeInterval(15)
    while reports.last != status && Date() < deadline && launchError == nil {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    precondition(launchError == nil, "LaunchServices failed: \(String(describing: launchError))")
    precondition(reports.last == status, "Expected \(status); got \(reports)")
}
waitFor("unavailable")
try Data("HarsharkNGX permission check v1\n".utf8).write(to: marker)
waitFor("granted")
try Data("invalid settings".utf8).write(to: settings)
waitFor("invalidSettings")
try Data("{\"enabled\":false}".utf8).write(to: settings)
waitFor("granted")
try FileManager.default.removeItem(at: marker)
waitFor("unavailable")
center.postNotificationName(stop, object: nil, userInfo: nil, deliverImmediately: true)
let deadline = Date().addingTimeInterval(5)
guard let processID = app?.processIdentifier else { fatalError("Missing monitor process") }
while kill(processID, 0) == 0 && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
precondition(kill(processID, 0) != 0 && errno == ESRCH, "Monitor did not stop when the assistant closed")
print("Permission monitor regression passed: independent launch, live grant, failure, recovery, revocation, shutdown.")
