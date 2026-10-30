import XCTest
import AppKit

final class HarsharkNGXUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private var testedAppURL: URL {
        // The runner and tested app are sibling build products. Another installed
        // build can have the same bundle ID, so never pick the first running app.
        Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("HarsharkNGX.app")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name) hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    @MainActor
    func testOpenSampleFilterAndInspect() throws {
        let app = XCUIApplication()
        app.launch()
        // SwiftUI's link button style is exposed as an accessibility link on macOS.
        let sample = app.links["openSample"]
        let sampleExists = sample.waitForExistence(timeout: 10)
        capture(app, name: "Native welcome")
        XCTAssertTrue(sampleExists)
        sample.click()
        let table = app.tables["requestTable"]
        let tableExists = table.waitForExistence(timeout: 10)
        capture(app, name: "Native HAR viewer")
        XCTAssertTrue(tableExists)
        XCTAssertTrue(app.staticTexts["6 of 6 requests"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Captured body is empty."].exists)
        XCTAssertTrue(app.buttons["responseHeaders"].exists)
        app.buttons["responseHeaders"].click()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
        app.buttons["responseBody"].click()

        let search = app.textFields["requestSearch"]
        search.click()
        search.typeText("403")
        XCTAssertTrue(app.staticTexts["1 of 6 requests"].waitForExistence(timeout: 5))
        XCTAssertTrue(table.staticTexts["403"].exists)
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["6 of 6 requests"].waitForExistence(timeout: 5))
        capture(app, name: "Native HAR viewer after filtering")
    }

    @MainActor
    private func openFile(_ url: URL, in app: XCUIApplication) {
        app.activate()
        app.typeKey("o", modifierFlags: .command)
        let openButton = app.sheets.buttons["OKButton"].firstMatch
        XCTAssertTrue(openButton.waitForExistence(timeout: 5))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let pathField = app.sheets.textFields.firstMatch
        XCTAssertTrue(pathField.waitForExistence(timeout: 5))
        pathField.typeText(url.path)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(openButton.waitForExistence(timeout: 5))
        openButton.click()
    }

    @MainActor
    func testOpenFilesAndMalformedCapture() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("First.har")
        let second = directory.appendingPathComponent("Second.har")
        let malformed = directory.appendingPathComponent("Malformed.har")
        let har = #"{"log":{"version":"1.2","creator":{"name":"UI Test","version":"1"},"entries":[{"startedDateTime":"2026-10-26T12:00:00Z","time":12,"request":{"method":"POST","url":"https://fixture.example.test/upload","httpVersion":"HTTP/2","headers":[],"queryString":[],"cookies":[],"headersSize":-1,"bodySize":12,"postData":{"mimeType":"text/plain","text":"request marker"}},"response":{"status":201,"statusText":"Created","httpVersion":"HTTP/2","headers":[],"cookies":[],"headersSize":-1,"bodySize":13,"content":{"size":13,"mimeType":"text/plain","text":"response marker"}},"cache":{},"timings":{"send":1,"wait":10,"receive":1}}]}}"#
        try Data(har.utf8).write(to: first)
        try Data(har.replacingOccurrences(of: "fixture.example.test", with: "second.example.test").utf8).write(to: second)
        try Data("{invalid JSON".utf8).write(to: malformed)
        let app = XCUIApplication()
        app.launch()
        openFile(first, in: app)
        XCTAssertTrue(app.tables["requestTable"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tables["requestTable"].staticTexts["fixture.example.test"].exists)
        XCTAssertTrue(app.staticTexts["1 of 1 requests"].exists)
        openFile(second, in: app)
        XCTAssertTrue(app.tables["requestTable"].staticTexts["second.example.test"].waitForExistence(timeout: 10))
        let sidebar = app.outlines.firstMatch
        XCTAssertTrue(sidebar.staticTexts["First.har"].exists)
        XCTAssertTrue(sidebar.staticTexts["Second.har"].exists)
        sidebar.staticTexts["First.har"].click()
        XCTAssertTrue(app.tables["requestTable"].staticTexts["fixture.example.test"].waitForExistence(timeout: 5))
        openFile(malformed, in: app)
        XCTAssertTrue(app.staticTexts["Unable to complete operation"].waitForExistence(timeout: 10))
        capture(app, name: "Malformed capture error")
        app.sheets.buttons["OK"].click()
        XCTAssertTrue(app.tables["requestTable"].staticTexts["fixture.example.test"].exists)
    }

    @MainActor
    func testExternalMultiFileOpenEvent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = ["ExternalOne.har", "ExternalTwo.har"].map { directory.appendingPathComponent($0) }
        for url in urls { try Data(#"{"log":{"entries":[]}}"#.utf8).write(to: url) }
        let app = XCUIApplication()
        app.launchArguments = ["-startup", "Welcome", "-reuseCapture", "YES"]
        app.launch()
        XCTAssertTrue(app.links["openSample"].waitForExistence(timeout: 10))
        let bundleURL = testedAppURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.path))
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.allowsRunningApplicationSubstitution = false
        _ = try await NSWorkspace.shared.open(urls, withApplicationAt: bundleURL, configuration: configuration)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        let opened = app.outlines.staticTexts["ExternalOne.har"].waitForExistence(timeout: 10)
        XCTAssertTrue(opened)
        XCTAssertTrue(app.outlines.staticTexts["ExternalTwo.har"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["0 of 0 requests"].exists)
        XCTAssertEqual(app.outlines.staticTexts.matching(identifier: "ExternalOne.har").count, 1)
        XCTAssertEqual(app.outlines.staticTexts.matching(identifier: "ExternalTwo.har").count, 1)
        XCTAssertEqual(app.windows.count, 1)
    }

    @MainActor
    func testExternalFileColdLaunchFocusesMainWindow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = XCUIApplication()
        app.launchArguments = ["-startup", "Welcome", "-reuseCapture", "YES"]
        app.launch()
        let bundleURL = testedAppURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.path))
        app.terminate()

        for filename in ["ColdLaunch.har", "ColdLaunch.json"] {
            let url = directory.appendingPathComponent(filename)
            try Data(#"{"log":{"entries":[]}}"#.utf8).write(to: url)
            XCTAssertEqual(app.state, .notRunning)
            // Launch through a file-open event, as Finder and the Dock do, without
            // calling XCTest's launch/activate methods on the resulting process.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.allowsRunningApplicationSubstitution = false
            configuration.createsNewApplicationInstance = true
            configuration.arguments = app.launchArguments
            let running = try await NSWorkspace.shared.open([url], withApplicationAt: bundleURL, configuration: configuration)
            XCTAssertEqual(running.bundleURL?.standardizedFileURL, bundleURL.standardizedFileURL)
            let launchedApp = XCUIApplication(bundleIdentifier: "com.teezyyoxo.HarsharkNGX")
            XCTAssertTrue(launchedApp.outlines.staticTexts[filename].waitForExistence(timeout: 10))
            XCTAssertTrue(launchedApp.wait(for: .runningForeground, timeout: 10), filename)
            XCTAssertEqual(launchedApp.windows.count, 1)
            launchedApp.terminate()
        }
    }

    @MainActor
    func testInstalledMCPWorksWithGUIStopped() async throws {
        let app = XCUIApplication()
        app.launch()
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
        guard let home = getpwuid(getuid())?.pointee.pw_dir else {
            throw XCTSkip("Unable to resolve the current user's installation directory.")
        }
        let executable = URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent("Library/Application Support/HarsharkNGX/bin/harsharkngx-mcp")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw XCTSkip("Install the native MCP executable with scripts/install-mcp.sh to run this integration test.")
        }
        let result = try await Task.detached {
            let process = Process()
            let input = Pipe()
            let output = Pipe()
            process.executableURL = executable
            process.standardInput = input
            process.standardOutput = output
            try process.run()
            try output.fileHandleForWriting.close()
            let request = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"ui-regression","version":"1"}}}"# + "\n"
            try input.fileHandleForWriting.write(contentsOf: Data(request.utf8))
            try input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, data)
        }.value
        XCTAssertEqual(result.0, 0)
        let response = try XCTUnwrap(JSONSerialization.jsonObject(with: result.1) as? [String: Any])
        XCTAssertEqual(response["id"] as? Int, 1)
        XCTAssertNotNil(response["result"])
        XCTAssertNil(response["error"])
        XCTAssertEqual(app.state, .notRunning)
    }

    @MainActor
    func testSettingsSectionsAndNarrowWindow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--sample"]
        app.launch()
        XCTAssertTrue(app.tables["requestTable"].waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        let end = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 800, dy: 650))
        start.press(forDuration: 0.1, thenDragTo: end)
        capture(app, name: "Narrow native viewer")
        XCTAssertTrue(app.tables["requestTable"].exists)
        XCTAssertTrue(app.buttons["responseHeaders"].exists)
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.popUpButtons["startupPreference"].waitForExistence(timeout: 5))
        capture(app, name: "General Settings")
        for section in ["Appearance", "HAR Processing", "Performance", "Privacy & Sanitization", "MCP Integration"] {
            let item = app.outlines.staticTexts[section].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5))
            item.click()
            capture(app, name: section + " Settings")
        }
        XCTAssertTrue(app.buttons["Copy Configuration"].exists)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.tables["requestTable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Copy Configuration"].exists)
    }

    @MainActor
    func testClosingFinalCaptureReturnsToWelcome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--sample"]
        app.launch()
        XCTAssertTrue(app.tables["requestTable"].waitForExistence(timeout: 10))
        app.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(app.menuItems["Close Capture"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("w", modifierFlags: .command)
        capture(app, name: "After closing final capture")
        XCTAssertTrue(app.links["openSample"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.exists)
        app.links["openSample"].click()
        XCTAssertTrue(app.tables["requestTable"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testSampleLaunchAndKeyboardSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--sample"]
        app.launch()
        let table = app.tables["requestTable"]
        let tableExists = table.waitForExistence(timeout: 10)
        capture(app, name: "Sample launch")
        XCTAssertTrue(tableExists)
        XCTAssertTrue(app.staticTexts["6 of 6 requests"].waitForExistence(timeout: 5))
        table.click()
        table.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(app.buttons["requestHeaders"].exists)
    }
}
