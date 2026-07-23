# Changelog

All notable changes to this project will be documented in this file.

---

## [1.7.0]

### Added
- Native rich JSON previews in request and response detail panes, with pretty indentation and syntax colors for keys, strings, numbers, and JSON literals
- Native HTTP header highlighting in both request and response header tabs, with distinct colors for header names, URLs, MIME types, status codes, and common cache/security directives
- Persistent text color-theme selector under `Settings > Text Color Theme`, with Default (the original palette), Nord, Solarized, and Monokai options for parsed request/response text

### Improved
- HAR reading, JSON formatting, base64 decoding, and entry construction now run off the UI thread, keeping the window interactive while large HAR files load
- Large request and response payloads render progressively in the detail pane instead of blocking the interface in a single text-layout pass
- Very large payloads automatically use no-wrap rendering and skip syntax highlighting past a safe threshold; the complete payload is still retained and viewable
- Entry filtering is debounced and runs in a background worker, avoiding UI pauses while searching body-heavy HAR files
- Waterfall scaling is cached rather than recalculated for every painted table cell

### Stability
- Disabled undo history in read-only detail previews to avoid an unnecessary second in-memory copy of large event bodies
- Preserved active-tab-only detail rendering so inactive panes do not duplicate large text documents

### Developer / Packaging
- Standalone macOS builds now use optimized Python bytecode and strip symbols where safe to reduce at-rest bundle size
- Version metadata aligned for the performance, UX, and stability overhaul (`1.7.0`)

---

## [1.6.5]

### Changed
- Updated the standalone app icon source to `packaging/assets/AppIcon_Transparent.png`
- Standalone app builds now generate the macOS `.icns` from the transparent RGBA icon

### Developer / Packaging
- Version metadata aligned for the transparent app icon release (`1.6.5`)

## [1.6.4]

### Changed
- App icon source is now tracked at `packaging/assets/AppIcon.png` so fresh clones can build the same branded app bundle
- Standalone app builds generate the macOS `.icns` from the tracked icon asset

### Developer / Packaging
- Generated `.icns` and iconset files remain ignored while the source PNG is committed
- Version metadata aligned for the tracked app icon asset release (`1.6.4`)

## [1.6.3]

### Added
- Clickable MCP status-bar control that toggles the in-app MCP server on and off
- macOS app icon generation from a local `AppIcon.png` source during standalone app builds

### Developer / Packaging
- Ignored the local icon source and generated `.icns`/iconset artifacts
- Version metadata aligned for the MCP toggle and app icon release (`1.6.3`)

## [1.6.2]

### Added
- Persistent bottom status-bar indicator showing whether the in-app MCP server is active or inactive

### Fixed
- Standalone app bundle startup now uses an absolute package import so the PyInstaller app launches correctly

## [1.6.1]

### Added
- PyInstaller app-bundle build support for compiling HarsharkNGX as a standalone desktop app
- `scripts/build_app.py` wrapper for building from the tracked PyInstaller spec
- Optional `packaging` dependency extra for installing PyInstaller only when app bundle builds are needed
- README instructions for building and launching the local standalone bundle

### Developer / Packaging
- Ignored local app packaging artifacts such as `.app`, `.dmg`, `.pkg`, and PyInstaller backup spec files
- Version metadata aligned for the standalone-app packaging release (`1.6.1`)

## [1.6.0]

### Added
- App-managed local MCP service that starts with HarsharkNGX and stops when the app closes
- `harsharkngx-mcp` console script with a stdio bridge mode for Claude Desktop
- MCP tools for loading HAR files, summarizing loaded data, listing entries, searching entries, and fetching request/response details
- MCP resources for the loaded HAR summary and entry list
- README setup instructions and Claude Desktop `mcpServers` configuration example

### Changed
- Version metadata aligned for the MCP server release (`1.6.0`)

## [1.5.0]

### Added
- Right-click copy menu for HAR table entries, with the clicked field shown first
- Copy actions for common entry fields including full URL, host, path, method, status, protocol, MIME type, timing, request/response headers, parameters, cookies, bodies, SAML, and raw entry JSON
- Right-click copy menu for request/response detail panes, including selected text when highlighted
- README roadmap item for a potential MCP server mode to expose HAR data to other programs

### Developer / Packaging
- Expanded `.gitignore` for Python bytecode, `__pycache__`, build artifacts, egg-info, local caches, virtual environments, and `.DS_Store`
- Removed previously tracked Python bytecode cache files from git tracking
- Version metadata aligned for this minor release (`1.5.0`)

## [1.4.1]

### Improved
- Detail text extraction now uses normalized MIME hints consistently across decoding and formatting paths
- Active-tab-only detail rendering was finalized to reduce memory churn with very large request/response bodies while keeping full data available

### Fixed
- Follow-up stability refinements for large/binary-heavy HAR events without reintroducing body truncation
- Version metadata alignment updated for this patch release (`1.4.1`)

## [1.4.0]

### Added
- Dual request/response detail layout in the lower pane:
  - left side: request tabs (Body, Parameters, Cookies, Headers, SAML)
  - right side: response tabs (Body, Parameters, Cookies, Headers)
- Response parameter tab content from HAR `response.content.params`
- Native JSON pretty-formatting for request/response bodies when valid JSON is detected
- Request parameter view now combines query parameters and request body parameters

### Improved
- Word wrap is now enabled by default for detail panes and can still be toggled from `View > Word Wrap`
- Multipart request body rendering now redacts `application/octet-stream` file payload sections to keep text view readable

### Fixed
- Keyboard navigation bug: moving rows with arrow keys now updates the selected event details immediately
- Stability issue with very large bodies by removing eager truncation and replacing binary-unsafe rendering paths
- Version metadata is now aligned across app/package fields (`1.4.0`)

## [1.3.0]
- Renamed project to HarsharkNGX. (iykyk ✈)

## [1.2.0]

### Added
- Waterfall timing column for quick visual comparison of request durations
- HTTP status color coding for easier scanning of response classes
  - 1xx: informational
  - 2xx: success
  - 3xx: redirect
  - 4xx: client error
  - 5xx: server error
- Column width presets:
  - Compact
  - Balanced
  - Comfortable
- Header right-click menu for:
  - toggling column visibility
  - changing width presets
  - resetting columns to defaults

### Improved
- Column layout persistence across launches:
  - column order
  - column visibility
  - column widths
- Saved UI state now handles layout changes more safely
- Default column layout now includes:
  - Started
  - Method
  - Status
  - Protocol
  - Host
  - Path
  - Mime Type
  - Waterfall
  - Time (ms)
- README updated with:
  - revised install/run steps
  - venv recovery steps
  - table customization guidance
  - feature overview for the new column tools

### Fixed
- Fixed an issue where previously saved Qt header/layout state could conflict with the new column schema
- Fixed a case where the `Time (ms)` column could appear blank after upgrading to the new layout
- Added saved layout versioning to prevent stale column state from breaking future releases
- Reset-to-default behavior now restores a clean compatible column arrangement when needed

---

## [1.1.0]

### Added
- Column management system:
  - Drag-and-drop column reordering via header
  - Toggle column visibility via `View > Columns`
  - Right-click context menu on table header for quick column toggling
- Persistent UI preferences:
  - Column order and visibility are saved across sessions
  - Window size and position are preserved
  - Splitter (table/detail pane) position is remembered
- `View > Reset Columns to Default` option

### Improved
- macOS light/dark mode handling:
  - Theme changes now apply dynamically while the app is running
  - Full UI refresh on appearance change (no more partial theme mismatch)
  - Consistent styling across all widgets (tables, tabs, text areas, etc.)
- Theme handling moved to application-level palette instead of window-level stylesheet

### Fixed
- Incomplete theme switching when toggling macOS appearance while app is open
  - Previously resulted in mixed light/dark UI elements
  - Now forces proper re-polish of all widgets

### Developer / Packaging
- Clarified `src/` layout usage
- Updated run instructions to include:
  ```bash
  pip install -e .
  ```

---

## [1.0.0]

### Initial Release

### Added
- Complete rewrite using modern Qt stack (PySide6)
- Cross-platform desktop HAR viewer (macOS, Windows, Linux)
- HAR file parsing and entry table view
- Request/response inspection tabs:
  - Headers
  - Params
  - Cookies
  - Body
  - SAML (best-effort formatting)
- Entry filtering/search
- MIME type display and timing metrics

### UI / UX
- Native macOS light/dark mode support (initial implementation)
- Clean, modern Qt6 interface
- Improved readability over legacy PyQt5 UI

### Dependencies Updated
- PySide6 (Qt6-based UI framework)
- beautifulsoup4 (HTML/XML parsing)
- lxml (fast XML parsing)
- darkdetect (OS theme detection)

### Known Limitations
- Theme switching only applied correctly on app launch (fixed in 1.1.0)
- Column layout not customizable or persistent (fixed in 1.1.0)

---

## Notes
- This project is a modernized reimplementation inspired by the original Harshark project
- Focus is on maintainability, cross-platform support, and improved UI/UX while preserving core functionality
