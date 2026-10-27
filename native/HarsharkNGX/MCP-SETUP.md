# Native MCP integration

The native `harsharkngx-mcp` executable is a separate Swift process. Claude starts it over stdio. It does not connect to the GUI, launch a TCP listener, require Python, or need a LaunchAgent.

## Install

From this directory, run `./scripts/install-mcp.sh`. This builds the executable and installs it atomically at:

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

## Optional on/off control

MCP is enabled by default, and Claude can launch it without opening the app. The bottom-right **MCP On / MCP Off** button optionally disables or enables capture access. Your choice persists across app and server restarts; the indicator shows access permission, not whether a client is connected.

While off, tools and resource reads are blocked. Existing clients remain connected and can resume after you turn access on and reload a capture. Shared snapshots are kept. Install the updated executable and restart Claude once to enable this control for previously installed servers.

The setting is stored in `.mcp-access.json` in the shared sessions directory. Servers using a custom `--session-directory` have their own setting; the app controls the default directory.

## Files and shared GUI sessions

- `load_har` opens a local file directly, whether or not the GUI is running.
- In the GUI's MCP toolbar menu, **Share Capture with MCP** publishes a private snapshot. Sharing is explicit because captures can contain credentials and personal data.
- `list_sessions` discovers published snapshots; `open_session` loads one by UUID. It remains available after closing the window or quitting the app.
- **Remove Shared Snapshot** removes the published copy for an open capture. To remove snapshots from earlier app runs, delete the corresponding UUID `.har` files in the directory below. Closing a window does not delete published captures.
- The default shared directory for the sandboxed app is `~/Library/Containers/com.teezyyoxo.HarsharkNGX/Data/Library/Application Support/HarsharkNGX/Sessions`.
- A custom directory can be supplied with `--session-directory /absolute/path`. The server does not infer or silently change a GUI selection.

## Tools and resources

Existing tools: `load_har`, `summarize_har`, `list_entries`, `search_entries`, `get_entry`.

Additional tools: `get_body` (paged previews), `list_sessions`, `open_session`.

Resources: `harsharkngx://summary`, `harsharkngx://entries`.

Body previews/search are bounded to 8 MiB per body. Errors and missing captures are reported explicitly. `include_raw` is limited to 2 MiB per response. Larger bodies can be exported by the GUI. Metadata memory scales with entry count; imports retain file-backed body ranges instead of eagerly decoding all bodies.

## Diagnostics and lifecycle

The executable supports `--version` and `--help`. On stdio, stdout is reserved for JSON-RPC; diagnostics use stderr. An empty server is healthy: call `load_har` before inspecting entries. Invalid paths, malformed captures, out-of-range entries, and unsupported encodings return tool errors. EOF shuts the process down. No background service remains after the client closes its input.

The process runs as your user and can read files that user can access; it has no network listener. Do not configure untrusted clients to launch it. Protocol handling covers initialize, ping, tools, and resources; subscriptions and server-initiated requests are not advertised.

## Removal

Remove the `harsharkngx` entry from Claude's configuration and restart Claude. Delete the installed executable from the `bin` directory above. Delete shared snapshots if you no longer need them. No launchd registration or Python environment cleanup is required.

The repository README covers the native app; the previous Python guide is preserved in `README-PYSIDE6.md` at the repository root.

## This workstation

The installed executable is `/Users/mgray/Library/Application Support/HarsharkNGX/bin/harsharkngx-mcp`, with launch arguments `[]`. The inspected Claude configuration already names this path; it was not modified during this refinement. The corrected executable has been installed, with its predecessor retained as `harsharkngx-mcp.previous`. Restart Claude to replace any older running subprocess.

```json
{
  "mcpServers": {
    "harsharkngx": {
      "command": "/Users/mgray/Library/Application Support/HarsharkNGX/bin/harsharkngx-mcp",
      "args": []
    }
  }
}
```

Merge this entry into existing configuration rather than replacing the whole file. The regression command is:

```sh
python3 -B scripts/test_mcp.py "/Users/mgray/Library/Application Support/HarsharkNGX/bin/harsharkngx-mcp"
```

This exchanges individual requests and responses while stdin stays open, detecting the initialization stall that the earlier batch/EOF test missed. It validates a real stdio protocol connection, not the Claude application's own UI. No launchd service is needed. During removal, delete the optional `.previous` backup too.
