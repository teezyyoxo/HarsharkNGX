# HarsharkNGX

A modernized, cross-platform HAR viewer inspired by the original [MacroPolo/harshark](https://github.com/MacroPolo/harshark) project.
<img width="2670" height="1456" alt="image" src="https://github.com/user-attachments/assets/b6bb5c0d-ebe5-465c-8556-39d796d4c7ae" />

## Features

- Modernized for current Python and Qt using `PySide6` (replacing legacy PyQt5)
- Native desktop UI (with macOS light/dark mode support + including live theme switching)
- Waterfall timing column for visual request-duration comparison
- HTTP status color coding for quick response analysis
- Reorderable columns with persistent layout (order, visibility, widths)
- Column visibility toggling via View menu or header right-click menu
- Column width presets: Compact, Balanced, Comfortable
- Splitter-based UI with resizable table and detail panes
- Lower detail pane now mirrors original Harshark flow:
  - left side request tabs (Body, Parameters, Cookies, Headers, SAML)
  - right side response tabs (Body, Parameters, Cookies, Headers)
- Keyboard navigation now updates selected event details immediately
- Detailed request/response inspection:
  - headers, parameters, cookies, bodies
  - SAML/XML payload formatting
- JSON request/response bodies are formatted natively when valid JSON is detected
- Multipart file payloads (`application/octet-stream`) are redacted from text view for readability and stability
- Word wrap is enabled by default in detail panes (toggle via `View > Word Wrap`)
- Local MCP server for querying HAR files from Claude Desktop or other MCP clients
- Faster HAR loading and more robust parsing with improved handling of missing fields
- Local-first workflow with no network dependency required

## Requirements

- Python 3.10+
- macOS, Linux, and *technically* Windows, but I have not tested this on a Windows machine yet. Stay tuned!

## Install

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install -e .
```

## Run

```bash
source .venv/bin/activate
python -m harsharkngx
```

## Build a Standalone App Bundle

HarsharkNGX can be compiled into a local desktop app with PyInstaller. On macOS this produces `dist/HarsharkNGX.app`; on other platforms PyInstaller produces the native runnable output under `dist/`.

The source app icon is tracked at `packaging/assets/AppIcon_Transparent.png`. On macOS, the build script converts that PNG into the generated `.icns` file used by the bundle. Generated icon files are ignored by git.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -e ".[packaging]"
python scripts/build_app.py
```

On macOS, launch the compiled app with:

```bash
open dist/HarsharkNGX.app
```

The generated bundle is intentionally not tracked by git. Build output such as `build/`, `dist/`, `.app`, `.dmg`, and `.pkg` artifacts is ignored locally.

### macOS Gatekeeper Note

Locally built app bundles are not code-signed or notarized. If macOS blocks the first launch, right-click `HarsharkNGX.app`, choose `Open`, and confirm the prompt. For redistribution outside your own machine, sign and notarize the bundle with your Apple Developer credentials.

## MCP Server

HarsharkNGX starts a local MCP service automatically when the desktop app opens, and stops it when the app closes. Claude Desktop connects through a stdio bridge process, so Claude can inspect the HAR file currently loaded in HarsharkNGX.

The bottom-right status bar control shows `MCP Server: active` when the in-app MCP service starts successfully, or `MCP Server: inactive` if it cannot start. The server is on by default; click the status control to stop or restart it.

Run the app as usual:

```bash
source .venv/bin/activate
python -m harsharkngx
```

The app listens locally on `127.0.0.1:8765`. For development, you can also run a standalone TCP MCP service:

```bash
source .venv/bin/activate
python -m harsharkngx.mcp_server --tcp /absolute/path/to/file.har
```

The service exposes tools to summarize the loaded HAR, list entries, search entries, and fetch full request/response details. It also exposes MCP resources for the loaded HAR summary and entry list.

### Claude Desktop Configuration

Add this to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "harsharkngx": {
      "type": "stdio",
      "command": "/Users/mgray/GitHub/harsharkngx/.venv/bin/python",
      "args": [
        "-m",
        "harsharkngx.mcp_server",
        "--bridge"
      ],
      "env": {}
    }
  }
}
```

Open HarsharkNGX before using the MCP tools in Claude. If HarsharkNGX is closed, the bridge has nothing to connect to.

The standalone app bundle still starts the same local MCP service. The `harsharkngx-mcp` stdio bridge is currently provided by the Python package install, so keep a source/venv install available if you use Claude Desktop integration.

## Pro Tip: Create a One-Command Launcher

If you use HarsharkNGX frequently, you can create a simple shell alias so you can launch it from anywhere with a single command.

### macOS / Linux (zsh or bash)

Add this to your `~/.zshrc` or `~/.bashrc`:

```bash
alias harshark='~/GitHub/harsharkngx/.venv/bin/python -m harsharkngx'
```

Then reload your shell (as applicable – I use zsh):
```bash
source ~/.zshrc
```

Now you can launch the app from anywhere by running `harshark`.

## Notes

This is a best-effort modernization rather than a byte-for-byte fork. It keeps the spirit of the original app, but the codebase has been refreshed around a simpler Qt6 architecture.
If for some reason your venv gets into a bad state, do the following to reset it:
```bash
deactivate
rm -rf .venv
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -e .
python -m harsharkngx
```

## Acknowledgements

This project is inspired by the original Harshark project:
https://github.com/MacroPolo/harshark

The original concept and foundation are credited to its author.
