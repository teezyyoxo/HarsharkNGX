import Foundation
import Testing
import AppKit
@testable import HarsharkNGX

struct HarsharkNGXTests {
    @Test @MainActor func setupAppearsOnlyWithoutExistingPreferencesOrConfiguration() throws {
        let domain = "HarsharkSetupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory) }
        defaults.register(defaults: ["startup": "Welcome"])
        #expect(SetupLaunchPolicy.beginLaunch(defaults: defaults, domain: domain, configurationDirectory: directory))
        #expect(!SetupLaunchPolicy.beginLaunch(defaults: defaults, domain: domain, configurationDirectory: directory))
        defaults.removePersistentDomain(forName: domain)
        defaults.set("Dark", forKey: "appearance")
        #expect(!SetupLaunchPolicy.beginLaunch(defaults: defaults, domain: domain, configurationDirectory: directory))
        defaults.removePersistentDomain(forName: domain)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(SetupLaunchPolicy.beginLaunch(defaults: defaults, domain: domain, configurationDirectory: directory))
        defaults.removePersistentDomain(forName: domain)
        try Data("{\"enabled\":true}".utf8).write(to: directory.appendingPathComponent(".mcp-access.json"))
        #expect(!SetupLaunchPolicy.beginLaunch(defaults: defaults, domain: domain, configurationDirectory: directory))
    }

    @Test @MainActor func captureLayoutRespondsToMetadataAndFitsAvailableDisplay() throws {
        let small = try HARParser().parse(Data(#"{"log":{"entries":[{"request":{"url":"https://example.test/a"},"response":{}}]}}"#.utf8))
        let large = try HARParser().parse(Data((#"{"log":{"entries":[{"request":{"url":"https://long-hostname.example.test/"# + String(repeating: "long-path-", count: 12) + #""},"response":{}}]}}"#).utf8))
        let shortSession = HARSession(archive: small, url: nil, name: "Short", rows: small.entries.map(HARRow.init))
        let longSession = HARSession(archive: large, url: nil, name: "Long", rows: large.entries.map(HARRow.init))
        let short = CaptureWindowLayout.preferredContentSize(for: shortSession)
        let long = CaptureWindowLayout.preferredContentSize(for: longSession)
        #expect(long.width > short.width)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        let screen = NSRect(x: -1440, y: 30, width: 1440, height: 870)
        let frame = CaptureWindowLayout.fittingFrame(contentSize: long, window: window, visibleFrame: screen)
        #expect(screen.contains(frame))
        #expect(frame.width <= screen.width && frame.height <= screen.height)
    }

    @Test @MainActor func helperInstallationPreservesStableCommandAcrossUpgrades() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let source = root.appendingPathComponent("Source.app")
        let directory = root.appendingPathComponent("bin")
        let binary = source.appendingPathComponent("Contents/MacOS/harsharkngx-mcp")
        try manager.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("first".utf8).write(to: binary)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        try MCPHelperInstaller.install(source: source, directory: directory)
        let command = directory.appendingPathComponent("harsharkngx-mcp")
        #expect(try String(contentsOf: command, encoding: .utf8) == "first")
        try Data("second".utf8).write(to: binary)
        try MCPHelperInstaller.install(source: source, directory: directory)
        #expect(try String(contentsOf: command, encoding: .utf8) == "second")
        let backup = directory.appendingPathComponent("HarsharkMCP.previous.app/Contents/MacOS/harsharkngx-mcp")
        #expect(try String(contentsOf: backup, encoding: .utf8) == "first")
        // A bad upgrade leaves the working executable intact.
        try manager.removeItem(at: binary)
        #expect(throws: (any Error).self) { try MCPHelperInstaller.install(source: source, directory: directory) }
        #expect(try String(contentsOf: command, encoding: .utf8) == "second")
    }

    @Test @MainActor func requestCellColorsFollowSelectionAndReuse() {
        let cell = RequestTableCell()
        let field = NSTextField(labelWithString: "POST")
        cell.addSubview(field)
        cell.textField = field
        cell.normalTextColor = NativeColors.method("POST")
        #expect(field.textColor == cell.normalTextColor)

        cell.backgroundStyle = .emphasized
        #expect(field.textColor == NSColor.alternateSelectedControlTextColor)
        // Reloading or reusing a selected cell must preserve selection contrast.
        cell.normalTextColor = NativeColors.status(500)
        #expect(field.textColor == NSColor.alternateSelectedControlTextColor)

        cell.backgroundStyle = .normal
        #expect(field.textColor == cell.normalTextColor)
    }

    @Test @MainActor func mcpDefaultsOnAndTogglePersistsAcrossWorkspaces() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let access = MCPAccessControl(sessionDirectory: directory)
        let workspace = Workspace(mcpAccess: access)
        #expect(workspace.mcpEnabled)
        workspace.toggleMCP()
        #expect(!workspace.mcpEnabled)
        #expect(try !access.read().enabled)
        let reopened = Workspace(mcpAccess: access)
        #expect(!reopened.mcpEnabled)
        reopened.toggleMCP()
        #expect(reopened.mcpEnabled)
        #expect(try access.read().enabled)
    }

    @Test @MainActor func failedMCPToggleReportsErrorWithoutChangingDisplayedState() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let access = MCPAccessControl(sessionDirectory: file)
        let workspace = Workspace(mcpAccess: access)
        #expect(workspace.mcpEnabled)
        try Data().write(to: file)
        workspace.toggleMCP()
        #expect(workspace.mcpEnabled)
        #expect(workspace.errorMessage != nil)
    }

    @Test @MainActor func openedCapturesAreSharedAutomaticallyAndReloadReplacesSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let access = MCPAccessControl(sessionDirectory: directory.appendingPathComponent("Sessions"))
        let workspace = Workspace(mcpAccess: access)
        let urls = ["First.har", "Second.json"].map { directory.appendingPathComponent($0) }
        let original = Data(#"{"log":{"entries":[{"request":{"url":"https://original.test","headers":[{"name":"Authorization","value":"secret"}]},"response":{}}]}}"#.utf8)
        for url in urls { try original.write(to: url) }
        workspace.open(urls)
        for _ in 0..<200 {
            if workspace.sessions.count == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(workspace.sessions.count == 2)
        #expect(workspace.errorMessage == nil)
        for session in workspace.sessions {
            #expect(session.sharedWithMCP)
            let snapshot = workspace.sharedDirectory.appendingPathComponent(session.id.uuidString + ".har")
            #expect(try Data(contentsOf: snapshot) == original)
            let attributes = try FileManager.default.attributesOfItem(atPath: snapshot.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        let previous = try #require(workspace.selectedSession)
        let previousSnapshot = workspace.sharedDirectory.appendingPathComponent(previous.id.uuidString + ".har")
        let updated = Data(#"{"log":{"entries":[{"request":{"url":"https://updated.test"},"response":{}}]}}"#.utf8)
        try updated.write(to: urls[1])
        workspace.reload()
        for _ in 0..<200 {
            if workspace.selectedSessionID != previous.id { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let replacement = try #require(workspace.selectedSession)
        #expect(replacement.id != previous.id)
        #expect(replacement.sharedWithMCP)
        let snapshot = workspace.sharedDirectory.appendingPathComponent(replacement.id.uuidString + ".har")
        #expect(try Data(contentsOf: snapshot) == updated)
        #expect(!FileManager.default.fileExists(atPath: previousSnapshot.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: workspace.sharedDirectory.path).count == 2)

        try Data("invalid HAR".utf8).write(to: urls[1])
        workspace.reload()
        for _ in 0..<200 {
            if workspace.errorMessage != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(workspace.errorMessage != nil)
        #expect(workspace.selectedSessionID == replacement.id)
        #expect(try Data(contentsOf: snapshot) == updated)
        workspace.close(replacement)
        #expect(try Data(contentsOf: snapshot) == updated)
        workspace.removeSharedCopy(replacement)
        #expect(!FileManager.default.fileExists(atPath: snapshot.path))
    }

    @Test @MainActor func enablingMCPAutomaticallySharesCapturesOpenedWhileOff() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let access = MCPAccessControl(sessionDirectory: directory.appendingPathComponent("Sessions"))
        try access.setEnabled(false)
        let workspace = Workspace(mcpAccess: access)
        let url = directory.appendingPathComponent("Private.har")
        try Data(#"{"log":{"entries":[]}}"#.utf8).write(to: url)
        workspace.open([url])
        for _ in 0..<200 {
            if !workspace.sessions.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let session = try #require(workspace.sessions.first)
        let snapshot = workspace.sharedDirectory.appendingPathComponent(session.id.uuidString + ".har")
        #expect(!session.sharedWithMCP)
        #expect(!FileManager.default.fileExists(atPath: snapshot.path))
        workspace.toggleMCP()
        for _ in 0..<200 {
            if session.sharedWithMCP { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(session.sharedWithMCP)
        #expect(try Data(contentsOf: snapshot) == Data(contentsOf: url))
    }

    @Test @MainActor func sharingFailureKeepsCaptureOpenAndReportsError() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let access = MCPAccessControl(sessionDirectory: directory.appendingPathComponent("Sessions"))
        let workspace = Workspace(mcpAccess: access)
        try Data().write(to: access.sessionDirectory)
        let url = directory.appendingPathComponent("Capture.har")
        try Data(#"{"log":{"entries":[]}}"#.utf8).write(to: url)
        workspace.open([url])
        for _ in 0..<200 {
            if !workspace.sessions.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let session = try #require(workspace.sessions.first)
        #expect(!session.sharedWithMCP)
        #expect(workspace.errorMessage?.contains("Unable to share Capture.har with MCP") == true)
    }

    @Test @MainActor func captureLifecyclePreservesOtherSessionsAndReleasesClosedSession() throws {
        let workspace = Workspace()
        func session() throws -> HARSession {
            let archive = try HARParser().parse(Data(#"{"log":{"entries":[]}}"#.utf8))
            return HARSession(archive: archive, url: nil, name: "Fixture", rows: [])
        }
        var first: HARSession? = try session()
        let second = try session()
        weak var released = first
        workspace.sessions = [try #require(first), second]
        workspace.selectedSessionID = second.id
        workspace.close(try #require(first))
        first = nil
        #expect(released == nil)
        #expect(workspace.selectedSessionID == second.id)
        let third = try session()
        workspace.sessions.append(third)
        workspace.close(second)
        #expect(workspace.selectedSessionID == third.id)
        workspace.close(third)
        #expect(workspace.sessions.isEmpty)
        #expect(workspace.selectedSession == nil)
    }

    @Test @MainActor func latestFilterWinsAndKeepsSelectionValid() async throws {
        let archive = try HARParser().parse(Data(#"{"log":{"entries":[{"request":{"url":"https://first.test"},"response":{}},{"request":{"url":"https://second.test"},"response":{}}]}}"#.utf8))
        let session = HARSession(archive: archive, url: nil, name: "Fixture", rows: archive.entries.map(HARRow.init))
        session.query = "first"
        session.filter()
        session.query = "second"
        session.filter()
        for _ in 0..<100 {
            if !session.filtering { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(session.visibleRows.map(\.host) == ["second.test"])
        #expect(session.selectedEntry?.url == "https://second.test")
        session.query = "absent"
        session.filter()
        for _ in 0..<100 {
            if !session.filtering { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(session.visibleRows.isEmpty)
        #expect(session.selectedEntry == nil)
    }

    @Test @MainActor func bookmarksRestoreMultipleCapturesAndForgetClosedOnes() async throws {
        let suiteName = "HarsharkNGX.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set("Restore", forKey: "startup")
        defaults.set(true, forKey: "reuseCapture")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = ["One.har", "Two.har"].map { directory.appendingPathComponent($0) }
        for url in urls { try Data(#"{"log":{"entries":[]}}"#.utf8).write(to: url) }
        let access = MCPAccessControl(sessionDirectory: directory.appendingPathComponent("Sessions"))
        let first = Workspace(defaults: defaults, mcpAccess: access)
        first.open(urls)
        for _ in 0..<200 {
            if first.sessions.count == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(first.sessions.count == 2)
        #expect((defaults.array(forKey: "captureBookmarks") as? [Data])?.count == 2)
        let restored = Workspace(defaults: defaults, mcpAccess: access)
        restored.startup()
        for _ in 0..<200 {
            if restored.sessions.count == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(restored.sessions.map(\.name) == ["One.har", "Two.har"])
        for session in restored.sessions { restored.close(session) }
        #expect((defaults.array(forKey: "captureBookmarks") as? [Data])?.isEmpty == true)
        defaults.set("Welcome", forKey: "startup")
        restored.persistSessions()
        #expect(defaults.object(forKey: "captureBookmarks") == nil)
    }

    @Test func fixtureFlowsFromParserToInspector() throws {
        let json = #"{"log":{"entries":[{"request":{"method":"POST","url":"https://example.test/api","postData":{"text":"{\"enabled\":true}","mimeType":"application/json"}},"response":{"status":200,"httpVersion":"HTTP/2","content":{"text":"eyJvayI6dHJ1ZX0=","encoding":"base64","mimeType":"application/json"}},"time":42}]}}"#
        let archive = try HARParser().parse(Data(json.utf8))
        let entry = try #require(archive.entries.first)
        let row = HARRow(entry: entry)
        #expect(row.host == "example.test")
        #expect(row.httpVersion == "HTTP/2")
        #expect(row.matches("POST"))
        let detail = HARFormatter.detail(entry: entry, response: true, tab: .body, pretty: true)
        #expect(detail.syntax == "json")
        #expect(detail.text.contains("\"ok\""))
        #expect(detail.notice.isEmpty)
    }

    @Test @MainActor func smallInspectorPreviewsAreImmediateAndLargeOnesStayAsynchronous() throws {
        let small = try HARParser().parse(Data(#"{"log":{"entries":[{"request":{"postData":{"text":"hello"}},"response":{"content":{"text":"world"}}}]}}"#.utf8))
        let entry = try #require(small.entries.first)
        for response in [false, true] {
            let detail = InspectorPreparation.immediateDetail(entry: entry, response: response,
                tab: .body, pretty: true, maximumBodyBytes: 1024)
            #expect(detail?.text == (response ? "world" : "hello"))
        }
        let largeJSON = #"{"log":{"entries":[{"request":{},"response":{"content":{"text":""#
            + String(repeating: "x", count: 70_000) + #""}}}]}}"#
        let large = try HARParser().parse(Data(largeJSON.utf8))
        #expect(InspectorPreparation.immediateDetail(entry: try #require(large.entries.first),
            response: true, tab: .body, pretty: true, maximumBodyBytes: 1024) == nil)
    }

    @Test func missingBodyIsExplained() throws {
        let archive = try HARParser().parse(Data(#"{"log":{"entries":[{"request":{},"response":{}}]}}"#.utf8))
        let entry = try #require(archive.entries.first)
        let detail = HARFormatter.detail(entry: entry, response: true, tab: .body, pretty: true)
        #expect(!detail.notice.isEmpty)
        #expect(detail.text.isEmpty)
    }
}
