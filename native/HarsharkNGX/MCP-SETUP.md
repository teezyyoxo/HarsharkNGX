# Native MCP integration

The native `harsharkngx-mcp` executable is a separate Swift process. Claude or any other client supporting local stdio MCP servers starts it on demand. It reads the same capture snapshots published by HarsharkNGX, without a TCP listener, Python, or a LaunchAgent.

## Install

In v1.0.4, open **Help → Setup Assistant** (or **Settings → MCP Integration → Open Setup Assistant**). The assistant opens automatically only when no existing app preferences or configuration are found; upgrades and configured installations keep their existing startup behavior. Choose **Install / Upgrade Helper**, then select the installation folder; the default is `~/Library/Application Support/HarsharkNGX/bin`. The bundled helper requires no Xcode or source checkout.

For installation from source, run `./scripts/install-mcp.sh` from this directory. Both methods install `HarsharkMCP.app` and a stable command symlink at:

`~/Library/Application Support/HarsharkNGX/bin/harsharkngx-mcp`

Run the installer again after an upgrade. The source tree and virtual environment may move without breaking this installed path. Restart Claude after upgrading so its next subprocess uses the new binary.

Replace only the existing `harsharkngx` entry in Claude Desktop's `mcpServers` configuration with the following, substituting your actual home directory. Preserve all unrelated settings and servers.

```json
{
  "harsharkngx": {
    "command": "/Users/YOUR_USER/Library/Application Support/HarsharkNGX/bin/harsharkngx-mcp",
    "args": []
  }
}
```

Remove the old Python `--bridge` configuration. The native app never starts the old TCP service, so there is no competing listener. Each client owns its own stdio subprocess and loaded capture.

For another MCP-compatible agent, register that same absolute executable path as a local stdio server with no arguments. Clients have their own configuration formats; the JSON above is the server entry for clients using `mcpServers`. This is a local server, so a remote-only client needs a local MCP connection capable of launching the helper.

## Privacy and permissions

Claude starts the helper each time it opens. The helper reads the MCP toggle from the app’s protected container, which can cause macOS to display “harsharkngx-mcp would like to access data from other apps.” To prevent repeated prompts:

1. Install the current helper in the Setup Assistant.
2. Click **Open Full Disk Access**, or open **System Settings → Privacy & Security → Full Disk Access**.
3. Click **+**, press **⇧⌘G**, and paste the helper app path shown in the assistant, normally `~/Library/Application Support/HarsharkNGX/bin/HarsharkMCP.app`. Add it and enable its switch. Authenticate if macOS asks.
4. Click **Check Access**. The assistant launches the installed helper independently of the GUI’s sandbox and checks only a HarsharkNGX marker file and MCP settings. It updates every second and displays a green checkmark when shared-data access works. A failed or unavailable check never counts as granted. If macOS stops the process after a permission change, click **Check Access** again.
5. Merge the copied MCP entry into Claude’s configuration. **Select Claude Configuration** grants read access to that file and lets the assistant verify the command and empty arguments as you save changes. Other server entries are preserved because the assistant does not write the file.
6. Fully quit and reopen Claude. The check does not confirm a live Claude connection.

Full Disk Access is a broad filesystem permission. It is optional for ordinary HAR viewing; grant it only if you want MCP integration. The app does not change system privacy permissions, inspect the TCC database, or claim to read the Full Disk Access switch. A checkmark reports effective access, which macOS may also allow through a narrower consent grant. Merely opening the assistant does not request protected-data access. The monitor stops when the assistant closes, with a ten-minute fallback lifetime; it is not a persistent service.

An upgraded or re-signed helper may need to be re-added or re-enabled in Full Disk Access. The v1.0.2 helper lives in an app bundle; an older permission for the standalone executable may need to be replaced with the new helper app entry. Existing Claude command paths continue to work through the symlink. Source/development builds remain ad hoc signed; stable Developer ID signing and notarization are not yet provided.

## Optional on/off control

MCP is enabled by default, and clients can launch it without opening the app. The bottom-right **MCP On / MCP Off** button optionally disables or enables capture access and automatic sharing. Your choice persists across app and server restarts; the indicator shows access permission, not whether a client is connected. Turning access on automatically shares any open captures that have no shared snapshot.

While off, tools and resource reads are blocked. Existing clients remain connected and can resume after you turn access on and reload a capture. Shared snapshots are kept. Install the updated executable and restart Claude once to enable this control for previously installed servers.

The setting is stored in `.mcp-access.json` in the shared sessions directory. Servers using a custom `--session-directory` have their own setting; the app controls the default directory.

## Files and shared GUI sessions

- `load_har` opens a local file directly, whether or not the GUI is running. Give the agent a path readable by the local helper; an attachment kept only in a remote agent's storage must first be saved locally.
- Opening a capture automatically publishes a private, unredacted snapshot while MCP is on. This applies to file dialogs, Finder/Dock opens, drag-and-drop, samples, and restored captures. Reloading publishes the replacement and removes that capture's previous shared snapshot after the new snapshot succeeds.
- `list_sessions` discovers published snapshots, including captures opened after the client connected; `open_session` loads one by UUID. A snapshot remains available after closing the window or quitting the app. After a reload, call `list_sessions` again to open the replacement snapshot.
- The GUI's MCP toolbar menu shows **Shared with MCP** and retains **Update Shared Snapshot** and **Remove Shared Snapshot** controls. Removing a snapshot keeps it removed until it is shared again, reloaded, reopened, or MCP is re-enabled. To remove snapshots from earlier app runs, delete the corresponding UUID `.har` files in the directory below. Closing a window does not delete published captures.
- The default shared directory for the sandboxed app is `~/Library/Containers/com.teezyyoxo.HarsharkNGX/Data/Library/Application Support/HarsharkNGX/Sessions`.
- A custom directory can be supplied with `--session-directory /absolute/path`. The server does not infer or silently change a GUI selection.

For example, ask your connected agent: “Use HarsharkNGX to load `/absolute/path/capture.har` and find failed requests,” or “Use HarsharkNGX to list shared captures, open the relevant session, and inspect the slowest requests.” The agent can call the MCP tools directly; no shell commands or GUI automation are needed for analysis.

HarsharkNGX has no additional per-file or per-tool approval dialogs. All eight tools advertise `readOnlyHint: true`, `destructiveHint: false`, `idempotentHint: true`, and `openWorldHint: false`: they inspect local data, preserve original files, and make no network requests. These annotations describe behavior to the client; each agent app controls its own tool approval policy, and macOS controls system permission prompts. The server cannot suppress those prompts.

## Tools and resources

Existing tools: `load_har`, `summarize_har`, `list_entries`, `search_entries`, `get_entry`.

Additional tools: `get_body` (paged previews), `list_sessions`, `open_session`.

Resources: `harsharkngx://summary`, `harsharkngx://entries`.

Body previews/search are bounded to 8 MiB per body. Errors and missing captures are reported explicitly. `include_raw` is limited to 2 MiB per response. Larger bodies can be exported by the GUI. Metadata memory scales with entry count; imports retain file-backed body ranges instead of eagerly decoding all bodies.

## Diagnostics and lifecycle

The executable supports `--version` and `--help`. On stdio, stdout is reserved for JSON-RPC; diagnostics use stderr. An empty server is healthy: call `load_har` before inspecting entries. Invalid paths, malformed captures, out-of-range entries, and unsupported encodings return tool errors. EOF shuts the process down. No background service remains after the client closes its input.

The process runs as your user and can read files that user can access; it has no network listener. Do not configure untrusted clients to launch it. Protocol handling covers initialize, ping, tools, and resources; subscriptions and server-initiated requests are not advertised.

## Removal

Remove the `harsharkngx` entry from Claude's configuration and restart Claude. Delete the installed `harsharkngx-mcp` symlink, `HarsharkMCP.app`, and optional `HarsharkMCP.previous.app` backup from the installation directory. Remove its Full Disk Access entry in System Settings if no longer needed. Delete shared snapshots if you no longer need them. No launchd registration or Python environment cleanup is required.

The repository README covers the native app; the previous Python guide is preserved in `README-PYSIDE6.md` at the repository root.

## Regression checks

```sh
python3 -B scripts/test_mcp.py "/absolute/path/to/harsharkngx-mcp"
swift scripts/test_permissions.swift "/absolute/path/to/HarsharkMCP.app"
```

The MCP harness exchanges individual requests and responses while stdin stays open. The permission harness launches the actual background helper through LaunchServices, verifies live status changes and shutdown, and uses temporary fixtures without altering macOS privacy settings. Neither harness verifies Claude’s UI or automatically changes Full Disk Access.
