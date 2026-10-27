import AppKit
import SwiftUI
import Darwin

enum AppPreferences {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            "startup": "Welcome", "reuseCapture": true, "timestampStyle": "Local",
            "tableDensity": "Comfortable", "colorizeStatus": true,
            "previewMiB": 8, "syntaxHighlighting": true, "prettyPrint": true,
            "wordWrap": true, "appearance": "System", "syntaxTheme": "Default",
            "columnHidden.protocol": true, "columnHidden.size": true
        ])
    }

    static var previewBytes: Int {
        min(32, max(1, UserDefaults.standard.integer(forKey: "previewMiB"))) * 1_048_576
    }

    static var userHome: URL {
        if let entry = getpwuid(getuid()), let path = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: path))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var mcpExecutable: URL {
        userHome.appendingPathComponent("Library/Application Support/HarsharkNGX/bin/harsharkngx-mcp")
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General", appearance = "Appearance", processing = "HAR Processing"
    case performance = "Performance", privacy = "Privacy & Sanitization", mcp = "MCP Integration"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .processing: "doc.text.magnifyingglass"
        case .performance: "speedometer"
        case .privacy: "lock.shield"
        case .mcp: "point.3.connected.trianglepath.dotted"
        }
    }
}

struct SettingsView: View {
    let workspace: Workspace
    @State private var selection: SettingsSection? = .general
    @AppStorage("appearance") private var appearance = "System"

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 185, ideal: 210)
        } detail: {
            Form {
                switch selection ?? .general {
                case .general: GeneralPreferences(workspace: workspace)
                case .appearance: AppearancePreferences()
                case .processing: ProcessingPreferences()
                case .performance: PerformancePreferences()
                case .privacy: PrivacyPreferences(workspace: workspace)
                case .mcp: MCPPreferences()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((selection ?? .general).rawValue)
        }
        .frame(minWidth: 680, idealWidth: 780, minHeight: 480, idealHeight: 600)
        .preferredColorScheme(appearance == "System" ? nil : appearance == "Dark" ? .dark : .light)
    }
}

private struct GeneralPreferences: View {
    let workspace: Workspace
    @AppStorage("startup") private var startup = "Welcome"
    @AppStorage("reuseCapture") private var reuseCapture = true
    @AppStorage("timestampStyle") private var timestampStyle = "Local"
    @AppStorage("defaultSearchDetails") private var searchDetails = false

    var body: some View {
        Section("Startup and captures") {
            Picker("On launch", selection: $startup) {
                Text("Show welcome screen").tag("Welcome")
                Text("Open sample capture").tag("Sample")
                Text("Restore previous captures").tag("Restore")
            }
            .accessibilityIdentifier("startupPreference")
            Toggle("Select existing capture when reopening a file", isOn: $reuseCapture)
            Toggle("Search details by default in new captures", isOn: $searchDetails)
            Text("Restoration stores file-access bookmarks only when enabled. Captures remain read-only; closing one never modifies its source file.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Timestamps") {
            Picker("Started column", selection: $timestampStyle) {
                Text("Local time").tag("Local")
                Text("Original ISO timestamp").tag("ISO")
            }
            Text("Hover over Started to see the full original timestamp and time zone.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: startup) { _, _ in workspace.persistSessions() }
    }
}

private struct AppearancePreferences: View {
    @AppStorage("appearance") private var appearance = "System"
    @AppStorage("syntaxTheme") private var syntaxTheme = "Default"
    @AppStorage("tableDensity") private var density = "Comfortable"
    @AppStorage("colorizeStatus") private var colorize = true

    var body: some View {
        Section("Appearance") {
            Picker("Appearance", selection: $appearance) {
                Text("Follow System").tag("System")
                Text("Light").tag("Light")
                Text("Dark").tag("Dark")
            }
            Picker("Text colors", selection: $syntaxTheme) {
                Text("Default").tag("Default")
                Text("Nord").tag("Nord")
                Text("Solarized").tag("Solarized")
                Text("Monokai").tag("Monokai")
            }
            Picker("Table density", selection: $density) {
                Text("Compact").tag("Compact")
                Text("Comfortable").tag("Comfortable")
            }
            Toggle("Colorize methods, status codes, and timing bars", isOn: $colorize)
        }
        Section("Visible columns") {
            ForEach(RequestTable.Coordinator.columns, id: \.0) { column in
                ColumnPreference(key: column.0, title: column.1)
            }
            Text("Path stays visible. Drag column dividers to resize; right-click a header for width presets. Timing values remain available when Waterfall is hidden.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ColumnPreference: View {
    let key: String
    let title: String
    @AppStorage private var hidden: Bool

    init(key: String, title: String) {
        self.key = key
        self.title = title
        _hidden = AppStorage(wrappedValue: ["protocol", "size"].contains(key), "columnHidden.\(key)")
    }

    var body: some View {
        Toggle(title, isOn: Binding(get: { !hidden }, set: { hidden = !$0 }))
            .disabled(key == "path")
            .onChange(of: hidden) { _, _ in
                UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "columnPreferencesRevision") + 1, forKey: "columnPreferencesRevision")
            }
    }
}

private struct ProcessingPreferences: View {
    @AppStorage("prettyPrint") private var pretty = true
    @AppStorage("wordWrap") private var wrap = true
    var body: some View {
        Section("Body display") {
            Toggle("Pretty-print JSON", isOn: $pretty)
            Toggle("Wrap inspector text", isOn: $wrap)
            Text("JSON below 1 MiB is formatted. Larger previews retain their original text. Missing, empty, null, malformed, binary, and unsupported bodies have distinct explanations.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Decoding and validation") {
            Text("HAR text is preserved as Unicode. Base64 decoding is strict; UTF-8, UTF-16, Latin-1, Windows-1252, and ASCII are supported. Unsupported encodings are reported without guessing.")
            Text("Imports validate JSON and required HAR structure. Failed imports report a reason and preserve already open captures.")
        }
    }
}

private struct PerformancePreferences: View {
    @AppStorage("previewMiB") private var previewMiB = 8
    @AppStorage("syntaxHighlighting") private var highlight = true
    var body: some View {
        Section("Expensive preview operations") {
            Picker("Maximum body preview", selection: $previewMiB) {
                Text("2 MiB").tag(2)
                Text("8 MiB").tag(8)
                Text("32 MiB").tag(32)
            }
            Toggle("Syntax highlighting", isOn: $highlight)
            Text("The limit also applies to body searches in the app. Export Body saves the full payload. The independent MCP process uses its own fixed 8 MiB limit.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Memory and storage") {
            Text("Bodies are decoded on demand from private file snapshots. Only the selected inspector previews are retained; there is no persistent decoded-body cache to clear.")
            Text("Closing a capture releases its data after any canceled operation finishes. Metadata memory grows with request count. Raising the preview limit increases peak memory.")
        }
    }
}

private struct PrivacyPreferences: View {
    let workspace: Workspace
    @AppStorage("startup") private var startup = "Welcome"
    @State private var message = ""
    var body: some View {
        Section("Local data") {
            Text("Original captures and full-body exports can contain credentials. MCP sharing publishes an explicit, unredacted copy that survives quitting the app.")
            Button("Show Shared Snapshots") {
                do {
                    try FileManager.default.createDirectory(at: workspace.sharedDirectory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(workspace.sharedDirectory)
                } catch { message = error.localizedDescription }
            }
            Button("Forget Restored Captures") {
                startup = "Welcome"
                workspace.persistSessions()
                message = "Saved restoration bookmarks removed. Open captures are unchanged."
            }
        }
        Section("Sanitized export") {
            Button("Export Redacted Summary HAR…") { workspace.exportSanitizedCapture() }
                .disabled(workspace.selectedSession == nil)
            Text("Exports only methods, status, timings, sizes, MIME types, and URL origins. Omits bodies, headers, cookies, URL paths, query strings, credentials, and exporter-specific fields. Hostnames remain visible. Originals are never modified.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if !message.isEmpty { Text(message).textSelection(.enabled) }
    }
}

private struct MCPPreferences: View {
    @State private var diagnostic = "Choose the installed executable to grant access and check its version."
    @State private var checking = false

    private var configuration: String {
        let value = ["mcpServers": ["harsharkngx": ["command": AppPreferences.mcpExecutable.path, "args": []] as [String: Any]]]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    var body: some View {
        Section("Standalone stdio server") {
            LabeledContent("Transport", value: "stdio · launched on demand by Claude")
            Text(AppPreferences.mcpExecutable.path).font(.caption.monospaced()).textSelection(.enabled)
            Text("No GUI, listener port, LaunchAgent, or always-running service is required. Each client owns one process and loads files explicitly or opens published snapshots.")
            Button(checking ? "Checking…" : "Check Installed Executable…") { checkExecutable() }
                .disabled(checking)
            Text(diagnostic).font(.caption).textSelection(.enabled)
        }
        Section("Claude configuration") {
            Text(configuration).font(.caption.monospaced()).textSelection(.enabled)
            Button("Copy Configuration") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(configuration, forType: .string)
            }
            Text("Run scripts/install-mcp.sh from the native project to install or upgrade. Merge this server entry into Claude Desktop’s configuration, preserving other servers, then restart Claude. Remove the old Python --bridge command. No external configuration is changed by this app.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func checkExecutable() {
        let panel = NSOpenPanel()
        panel.directoryURL = AppPreferences.mcpExecutable.deletingLastPathComponent()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select the installed harsharkngx-mcp executable."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            checking = true
            Task {
                diagnostic = await Task.detached {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let process = Process()
                    let output = Pipe()
                    process.executableURL = url
                    process.arguments = ["--version"]
                    process.standardOutput = output
                    process.standardError = output
                    do {
                        try process.run()
                        try output.fileHandleForWriting.close()
                        // Bound diagnostics even if the selected program is unresponsive.
                        for _ in 0..<30 {
                            if !process.isRunning { break }
                            try await Task.sleep(for: .milliseconds(100))
                        }
                        if process.isRunning {
                            process.terminate()
                            return "Executable did not finish within 3 seconds."
                        }
                        let data = output.fileHandleForReading.availableData
                        return "Exit \(process.terminationStatus): " + String(decoding: data.prefix(4096), as: UTF8.self)
                    } catch { return error.localizedDescription }
                }.value
                checking = false
            }
        }
    }
}
