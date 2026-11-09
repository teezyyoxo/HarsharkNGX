import AppKit
import SwiftUI

@MainActor @Observable
final class MCPInstallation {
    static let shared = MCPInstallation()
    private(set) var directory: URL
    private var scopedDirectory: URL?

    private init() {
        directory = AppPreferences.userHome.appendingPathComponent("Library/Application Support/HarsharkNGX/bin")
        if let data = UserDefaults.standard.data(forKey: "mcpInstallDirectory") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                  bookmarkDataIsStale: &stale), url.startAccessingSecurityScopedResource() {
                directory = url
                scopedDirectory = url
            }
        }
    }

    func use(_ url: URL) throws {
        let granted = url.startAccessingSecurityScopedResource()
        let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        scopedDirectory?.stopAccessingSecurityScopedResource()
        scopedDirectory = granted ? url : nil
        directory = url
        UserDefaults.standard.set(bookmark, forKey: "mcpInstallDirectory")
    }

    var bundle: URL { directory.appendingPathComponent("HarsharkMCP.app") }
    var executable: URL { directory.appendingPathComponent("harsharkngx-mcp") }
    var ready: Bool {
        guard let bundle = Bundle(url: bundle),
              bundle.infoDictionary?["CFBundleShortVersionString"] as? String == "1.0.4",
              let bundledExecutable = bundle.executableURL else { return false }
        return FileManager.default.isExecutableFile(atPath: executable.path)
            && executable.resolvingSymlinksInPath() == bundledExecutable.resolvingSymlinksInPath()
    }
}

/// Installs the bundled helper without a shell, preserving Claude's stable command path.
enum MCPHelperInstaller {
    static func install(source: URL, directory: URL) throws {
        let manager = FileManager.default
        let staging = directory.appendingPathComponent(".HarsharkMCP-\(UUID().uuidString).app")
        let target = directory.appendingPathComponent("HarsharkMCP.app")
        let previous = directory.appendingPathComponent("HarsharkMCP.previous.app")
        let link = directory.appendingPathComponent(".harsharkngx-mcp-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: staging); try? manager.removeItem(at: link) }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try manager.copyItem(at: source, to: staging)
        guard manager.isExecutableFile(atPath: staging.appendingPathComponent("Contents/MacOS/harsharkngx-mcp").path) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try manager.createSymbolicLink(atPath: link.path,
                                       withDestinationPath: "HarsharkMCP.app/Contents/MacOS/harsharkngx-mcp")
        if manager.fileExists(atPath: previous.path) { try manager.removeItem(at: previous) }
        let hadPrevious = manager.fileExists(atPath: target.path)
        if hadPrevious { try manager.moveItem(at: target, to: previous) }
        do {
            try manager.moveItem(at: staging, to: target)
            guard rename(link.path, directory.appendingPathComponent("harsharkngx-mcp").path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? manager.removeItem(at: target)
            if hadPrevious { try? manager.moveItem(at: previous, to: target) }
            throw error
        }
    }
}

@MainActor @Observable
final class SetupAssistantModel {
    let installation = MCPInstallation.shared
    var permission: MCPPermissionProbe.Status?
    var monitoring = false
    var configurationMatches = false
    var configurationSelected = false
    var message: String?
    private var token: String?
    private var observer: NSObjectProtocol?
    private var configurationURL: URL?
    private var lastReport: Date?
    private var monitorStarted: Date?
    private var monitorApplication: NSRunningApplication?
    private var active = false

    var configuration: String {
        let value: [String: Any] = ["mcpServers": ["harsharkngx": ["command": installation.executable.path, "args": []] as [String: Any]]]
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    func install() {
        let source = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/HarsharkMCP.app")
        guard FileManager.default.fileExists(atPath: source.path) else {
            message = "This build is missing its MCP helper. Rebuild with the native Xcode project."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Install MCP Helper"
        panel.message = "Choose the bin folder shown below, or create it. This grants access to install the helper there."
        panel.prompt = "Install Here"
        panel.directoryURL = installation.directory
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let directory = panel.url else { return }
            self.stopMonitor()
            do {
                try self.installation.use(directory)
                try MCPHelperInstaller.install(source: source, directory: directory)
                self.message = "Helper installed. Recheck its Full Disk Access entry after upgrading, then restart Claude."
                self.startMonitor()
            } catch { self.message = "Installation failed: \(error.localizedDescription)" }
        }
    }

    func startMonitor() {
        stopMonitor()
        guard installation.ready else { return }
        do { try MCPPermissionProbe.prepare(in: Workspace.shared.sharedDirectory) }
        catch { message = "Cannot prepare the permission check: \(error.localizedDescription)"; return }
        let token = UUID().uuidString
        self.token = token
        permission = nil
        monitoring = true
        monitorStarted = Date()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: MCPPermissionProbe.notificationName(token: token), object: nil, queue: .main
        ) { [weak self] notification in
            guard let raw = notification.object as? String,
                  let status = MCPPermissionProbe.Status(rawValue: raw) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.token == token else { return }
                self.permission = status
                self.lastReport = Date()
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.allowsRunningApplicationSubstitution = false
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--permission-monitor", token, "--session-directory", Workspace.shared.sharedDirectory.path]
        // A Process child inherits the GUI's sandbox/access and could report a false positive.
        NSWorkspace.shared.openApplication(at: installation.bundle, configuration: configuration) { [weak self] app, error in
            Task { @MainActor [weak self] in
                guard let self, self.token == token else { return }
                if let error {
                    self.stopMonitor()
                    self.message = "Could not start the helper check: \(error.localizedDescription)"
                } else { self.monitorApplication = app }
            }
        }
    }

    func stopMonitor() {
        if let token {
            DistributedNotificationCenter.default().postNotificationName(
                MCPPermissionProbe.stopNotificationName(token: token), object: nil, userInfo: nil, deliverImmediately: true)
        }
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        token = nil
        lastReport = nil
        monitorStarted = nil
        monitorApplication = nil
        monitoring = false
        permission = nil
    }

    func watch() async {
        active = true
        defer { active = false; stopMonitor(); configurationURL?.stopAccessingSecurityScopedResource() }
        // Starting a check is explicit: merely opening the assistant never triggers a privacy alert.
        while !Task.isCancelled {
            refreshConfiguration()
            if monitoring, let started = monitorStarted {
                if monitorApplication?.isTerminated == true {
                    stopMonitor()
                    message = "The helper stopped. Click Check Access to verify again."
                } else if Date().timeIntervalSince(lastReport ?? started) > 15 {
                    stopMonitor()
                    message = "The helper stopped reporting. Respond to any macOS permission dialog, then click Check Access again."
                }
            }
            do { try await Task.sleep(for: .seconds(1)) } catch { break }
        }
    }

    func chooseConfiguration() {
        let panel = NSOpenPanel()
        panel.title = "Verify Claude Configuration"
        panel.message = "Select claude_desktop_config.json. The assistant checks it without changing it."
        panel.directoryURL = AppPreferences.userHome.appendingPathComponent("Library/Application Support/Claude")
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url, self.active else { return }
            self.configurationURL?.stopAccessingSecurityScopedResource()
            _ = url.startAccessingSecurityScopedResource()
            self.configurationURL = url
            self.configurationSelected = true
            self.refreshConfiguration()
        }
    }

    private func refreshConfiguration() {
        guard let url = configurationURL else { return }
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any],
              let server = servers["harsharkngx"] as? [String: Any],
              let command = server["command"] as? String, command.hasPrefix("/"),
              server["args"] == nil || server["args"] is [String] else { configurationMatches = false; return }
        let args = server["args"] as? [String] ?? []
        configurationMatches = URL(fileURLWithPath: command).standardizedFileURL == installation.executable.standardizedFileURL
            && args.isEmpty
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    var permissionDescription: String {
        switch permission {
        case .granted: "Shared capture access verified"
        case .denied: "Permission needed — enable the MCP helper in Full Disk Access"
        case .unavailable: "Permission check file unavailable — click Check Access to prepare it again"
        case .invalidSettings: "Shared MCP settings could not be read — check the settings file"
        case nil: monitoring ? "Waiting for permission status…" : "Ready to check access"
        }
    }
}

struct SetupAssistantView: View {
    @State private var model = SetupAssistantModel()
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield").font(.system(size: 32)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up Claude & MCP").font(.title2.bold())
                    Text("HarsharkNGX 1.0.4 · Privacy & permissions").foregroundStyle(.secondary)
                }
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    step(1, title: "Install the MCP helper", complete: model.installation.ready) {
                        Text("The helper lets Claude and other MCP clients read local HAR files and captures automatically shared when opened in HarsharkNGX. It runs only when a client or this access check starts it.")
                        Text(model.installation.executable.path).font(.caption.monospaced()).textSelection(.enabled)
                        Button(model.installation.ready ? "Reinstall Helper…" : "Install / Upgrade Helper…", action: model.install)
                            .accessibilityIdentifier("installMCPHelper")
                    }
                    step(2, title: "Allow shared capture access", complete: model.permission == .granted) {
                        Text("To prevent the recurring macOS prompt, open Full Disk Access, click +, press ⇧⌘G, and paste the helper app path below. Add it and turn its switch on.")
                        Text(model.installation.bundle.path).font(.caption.monospaced()).textSelection(.enabled)
                        HStack {
                            Button("Open Full Disk Access", action: model.openPrivacySettings)
                            Button("Copy Helper Path") { copy(model.installation.bundle.path) }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.installation.bundle]) }
                                .disabled(!model.installation.ready)
                        }
                        Text("Full Disk Access is a broad macOS permission. Grant it only if you want this integration. Ordinary HAR viewing uses the files you choose and needs no Full Disk Access.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(model.monitoring ? "Recheck Access" : "Check Access", action: model.startMonitor)
                                .disabled(!model.installation.ready).accessibilityIdentifier("checkMCPAccess")
                            if model.monitoring && model.permission == nil { ProgressView().controlSize(.small) }
                            Text(model.permissionDescription)
                                .foregroundStyle(model.permission == .granted ? Color.green : Color.secondary)
                                .accessibilityIdentifier("mcpPermissionStatus")
                        }
                        Text("After Check Access, this status updates every second while you change permissions. The check verifies access to HarsharkNGX’s shared data; it cannot read the Full Disk Access switch itself. If macOS stops the helper after a change, click Check Access again.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    step(3, title: "Connect and restart Claude", complete: model.configurationMatches) {
                        Text("Merge this entry into Claude Desktop’s configuration, preserving other servers. Select the configuration file below to watch for changes as you save it.")
                        Text(model.configuration).font(.caption.monospaced()).textSelection(.enabled)
                        HStack {
                            Button("Copy Configuration") { copy(model.configuration) }
                            Button("Select Claude Configuration…", action: model.chooseConfiguration)
                                .accessibilityIdentifier("verifyClaudeConfiguration")
                        }
                        if model.configurationSelected {
                            Text(model.configurationMatches ? "Claude configuration verified" : "The selected file does not yet match this helper’s command and empty arguments.")
                                .foregroundStyle(model.configurationMatches ? Color.green : Color.secondary)
                        }
                        Text("Fully quit and reopen Claude after installing the helper or changing permissions. Configuration verification does not confirm a live Claude connection. MCP On / Off controls capture access separately.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let message = model.message { Text(message).font(.callout).textSelection(.enabled) }
                }.padding(24)
            }
            Divider()
            HStack {
                Text("Reopen anytime from Help → Setup Assistant.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { model.stopMonitor(); dismissWindow(id: "setup") }
                    .keyboardShortcut(.defaultAction).accessibilityIdentifier("finishSetup")
            }.padding(16)
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 580, idealHeight: 760)
        .task { await model.watch() }
    }

    private func step<Content: View>(_ number: Int, title: String, complete: Bool,
                                     @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2).foregroundStyle(complete ? Color.green : Color.secondary)
                .accessibilityLabel(complete ? "\(title): complete" : "\(title): pending")
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                content()
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
