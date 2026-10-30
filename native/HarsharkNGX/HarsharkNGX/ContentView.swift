import SwiftUI

struct ContentView: View {
    @Bindable var workspace: Workspace
    @State private var dropTargeted = false
    @AppStorage("appearance") private var appearance = "System"

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                CaptureSidebar(workspace: workspace)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
            } detail: {
                if let session = workspace.selectedSession {
                    CaptureView(session: session, workspace: workspace).id(session.id)
                } else {
                    WelcomeView(open: workspace.chooseFiles, sample: workspace.openSample)
                }
            }
            Divider()
            WorkspaceStatus(workspace: workspace)
        }
        .preferredColorScheme(appearance == "System" ? nil : (appearance == "Dark" ? .dark : .light))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: workspace.chooseFiles) { Label("Open HAR", systemImage: "folder.badge.plus") }
                    .help("Open HAR files (⌘O)")
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .background(.tint.opacity(0.08))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            workspace.open(files)
            return !files.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .alert("Unable to complete operation", isPresented: Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } }
        )) {
            Button("OK") { workspace.errorMessage = nil }
        } message: {
            Text(workspace.errorMessage ?? "")
        }
    }
}

struct CaptureSidebar: View {
    @Bindable var workspace: Workspace

    var body: some View {
        List(selection: $workspace.selectedSessionID) {
            Section("Captures") {
                ForEach(workspace.sessions) { session in
                    VStack(alignment: .leading, spacing: 5) {
                        Label(session.name, systemImage: "doc.text.magnifyingglass")
                            .lineLimit(2)
                            .help(session.name)
                        Text("\(session.rows.count.formatted()) requests")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                    .tag(session.id)
                    .contextMenu {
                        Button("Close Capture") { workspace.close(session) }
                    }
                }
            }
        }
        .overlay {
            if workspace.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.title2)
                    Text("No captures open").font(.callout)
                }
                .foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Local", systemImage: "lock.shield")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.caption.weight(.medium))
                Text("Your captures stay on this Mac.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

        }
        .navigationTitle("HarsharkNGX")
    }
}

struct WelcomeView: View {
    let open: () -> Void
    let sample: () -> Void

    var body: some View {
        ScrollView {
        VStack(spacing: 20) {
            Image(systemName: "network").accessibilityHidden(true)
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.tint)
                .padding(24)
                .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 28))
            VStack(spacing: 8) {
                Text("See the whole request.").font(.largeTitle.weight(.semibold))
                Text("Inspect HTTP traffic, trace slow requests, and explore every response.")
                    .foregroundStyle(.secondary)
            }
            Button(action: open) { Label("Open HAR Files…", systemImage: "folder") }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("openHAR")
            Text("or drop .har files anywhere in this window")
                .font(.callout).foregroundStyle(.secondary)
            Button("Explore a Sample Capture", action: sample)
                .buttonStyle(.link).accessibilityIdentifier("openSample")
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
        .background(.background)
    }
}

struct WorkspaceStatus: View {
    let workspace: Workspace

    var body: some View {
        HStack(spacing: 8) {
            if let name = workspace.loadingNames.first {
                ProgressView().controlSize(.small)
                Text("Opening \(name)…").lineLimit(1).truncationMode(.middle).help(name)
                Button("Cancel", action: workspace.cancelLoading).buttonStyle(.link)
            } else if let session = workspace.selectedSession {
                Image(systemName: "doc.text")
                Text("\(session.visibleRows.count.formatted()) of \(session.rows.count.formatted()) requests")
                if session.filtering { ProgressView().controlSize(.mini) }
            } else {
                Text("Ready to inspect")
            }
            Spacer()
            MCPStatusButton(workspace: workspace)
            Text("1.0.1").foregroundStyle(.tertiary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.bar)
    }
}

private struct MCPStatusButton: View {
    let workspace: Workspace

    var body: some View {
        Button(action: workspace.toggleMCP) {
            Label(workspace.mcpEnabled ? "MCP On" : "MCP Off",
                  systemImage: workspace.mcpEnabled ? "power.circle.fill" : "power.circle")
                .foregroundStyle(workspace.mcpEnabled ? Color.green : Color.secondary)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityIdentifier("mcpToggle")
        .accessibilityLabel("MCP server access")
        .accessibilityValue(workspace.mcpEnabled ? "On" : "Off")
        .help(workspace.mcpEnabled
              ? "Disable MCP requests. Clients launch the server; this does not indicate a connected client."
              : "Enable MCP requests. Clients launch the server when they connect.")
    }
}

struct CaptureView: View {
    @Bindable var session: HARSession
    let workspace: Workspace
    @State private var requestTab = HARDetailTab.body
    @State private var responseTab = HARDetailTab.body
    @AppStorage("previewMiB") private var previewMiB = 8

    var body: some View {
        VStack(spacing: 0) {
            CaptureSummary(session: session)
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter URL, host, method, status…", text: $session.query)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("requestSearch")
                if !session.query.isEmpty {
                    Button { session.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).help("Clear filter").accessibilityLabel("Clear filter")
                }
                Menu {
                    Toggle("Search details", isOn: $session.searchBodies)
                    Toggle("Errors only", isOn: $session.errorsOnly)
                } label: {
                    Label(session.errorsOnly ? "Errors only" : "Filters", systemImage: "line.3.horizontal.decrease")
                }
                .fixedSize()
                .help("Search headers, parameters, cookies, and bodies within the preview limit")
            }
            .font(.callout)
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            VSplitView {
                RequestTable(session: session)
                    .background(SplitViewPersistence(name: "HarsharkMainSplitV1").frame(width: 0, height: 0))
                    .frame(maxWidth: .infinity, minHeight: 150, idealHeight: 340)
                    .overlay {
                        if session.visibleRows.isEmpty {
                            ContentUnavailableView(
                                session.rows.isEmpty ? "Empty capture" : "No matching requests",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text(session.rows.isEmpty ? "This HAR contains no entries." : "Try another filter or turn off Errors only.")
                            )
                        }
                    }
                if let entry = session.selectedEntry {
                    GeometryReader { geometry in
                        if geometry.size.width >= 620 {
                            HSplitView {
                                InspectorPane(entry: entry, response: false, tab: $requestTab, workspace: workspace)
                                    .background(SplitViewPersistence(name: "HarsharkInspectorSplitV1").frame(width: 0, height: 0))
                                    .frame(minWidth: 260)
                                InspectorPane(entry: entry, response: true, tab: $responseTab, workspace: workspace)
                                    .frame(minWidth: 260)
                            }
                        } else {
                            VSplitView {
                                InspectorPane(entry: entry, response: false, tab: $requestTab, workspace: workspace)
                                    .frame(minHeight: 120)
                                InspectorPane(entry: entry, response: true, tab: $responseTab, workspace: workspace)
                                    .frame(minHeight: 120)
                            }
                        }
                    }
                    .frame(minHeight: 260, idealHeight: 410)
                } else {
                    ContentUnavailableView("Select a request", systemImage: "cursorarrow.click",
                                           description: Text("Inspect its headers, payload, cookies, and timings."))
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(session.name)
        .toolbar {
            ToolbarItem {
                Menu {
                    Button(session.sharedWithMCP ? "Update Shared Snapshot" : "Share Capture with MCP") {
                        workspace.shareWithMCP(session)
                    }
                    if session.sharedWithMCP {
                        Button("Remove Shared Snapshot", role: .destructive) { workspace.removeSharedCopy(session) }
                    }
                    Text("Shared snapshots remain available after this window closes.")
                } label: {
                    Label(session.sharedWithMCP ? "Shared with MCP" : "MCP", systemImage: session.sharedWithMCP ? "checkmark.circle" : "point.3.connected.trianglepath.dotted")
                }
                .help("Share a persistent copy with the independent MCP server")
            }
            ToolbarItem {
                Button(action: workspace.reload) { Label("Reload", systemImage: "arrow.clockwise") }
                    .help("Reload capture (⌘R)")
            }
        }
        .onChange(of: session.query) { _, _ in session.filter() }
        .onChange(of: session.searchBodies) { _, _ in session.filter() }
        .onChange(of: session.errorsOnly) { _, _ in session.filter() }
        .onChange(of: previewMiB) { _, _ in if session.searchBodies { session.filter() } }
    }
}

struct CaptureSummary: View {
    let session: HARSession

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NETWORK ACTIVITY").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(session.name).font(.title3.weight(.semibold)).lineLimit(2).help(session.name)
            }
            Spacer(minLength: 12)
            SummaryMetric(title: "Requests", value: session.rows.count.formatted(), color: .primary)
            SummaryMetric(title: "Errors", value: session.errorCount.formatted(), color: session.errorCount == 0 ? .secondary : .orange)
            SummaryMetric(title: "Slowest", value: String(format: "%.0f ms", session.maximumDuration), color: .secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

struct SummaryMetric: View {
    let title: String
    let value: String
    let color: Color
    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            Text(value).font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
