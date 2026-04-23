# Changelog

All notable changes to this project will be documented in this file.

---

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
