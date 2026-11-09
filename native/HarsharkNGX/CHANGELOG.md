# HarsharkNGX Native Changelog

This changelog tracks the native macOS application separately from the Python application's release history.

## 1.0.4 — 2026-11-09

### Changed
- The Started column shows the date and time (`yyyy-dd-MM HH:mm:ss`) in the system time zone by default. A UTC (Zulu) display, marked with a `Z` suffix, can be toggled from View > Show Started in UTC (Zulu), the request-row context menu, or Settings > Timestamps.
- Increased spacing between inspector tabs.
- Native app, redacted-export metadata, and MCP versions are now `1.0.4` (app build `4`).

## 1.0.3 — 2026-11-03

### Changed
- HAR files opened through any GUI entry point are automatically shared as persistent, unredacted MCP snapshots while MCP is on. Reloading replaces the previous snapshot after successful publication. Re-enabling MCP publishes open captures that are not shared yet; an existing MCP Off preference is preserved.
- MCP tool discovery declares all eight tools local, read-only, non-destructive, and idempotent. Initialization explains direct `load_har` usage and automatic session discovery to compatible agents. HarsharkNGX adds no per-capture or per-tool confirmation; client and macOS permissions remain under their respective apps' control.
- Updated setup, settings, and MCP documentation for automatic sharing and other local stdio MCP clients alongside Claude.
- Native app, redacted-export metadata, and MCP versions are now `1.0.3` (app build `3`).

### Validation
- Passed 29 core tests, 15 app tests, three targeted UI checks across the suite and final rerun, and the stdio MCP regression against the development and bundled release helpers. Built a universal arm64/x86_64 app and helper with ad hoc signing; client approval UI remains client-controlled.

## 1.0.2 — 2026-11-02

### Added
- A Setup Assistant that opens automatically only on a fresh install with no existing app preferences/configuration, reopenable from Help and Settings → MCP Integration, with guided helper installation, Full Disk Access instructions, Finder/path shortcuts, and Claude configuration verification.
- Live green checkmarks for installed helper, verified shared-data access, and matching Claude configuration. Permission status updates once per second after Check Access; configuration status updates as the selected file is saved.
- The MCP helper is bundled with the GUI and can be installed without Xcode or a source checkout. A background helper app lets LaunchServices run permission checks independently of the GUI’s sandbox, avoiding inherited-access false positives.
- A permission probe that reads only HarsharkNGX’s check marker and MCP settings; missing data, denied access, and invalid settings do not produce a success checkmark. The monitor exits when the assistant closes and has a ten-minute lifetime limit.

### Changed
- Opening or switching captures automatically resizes the main window based on measured column content, visible row count, and bounded payload previews, constrained to the current display’s usable area. Table columns retain readable widths with horizontal scrolling for content wider than the screen; inspector tabs wrap instead of disappearing offscreen.
- Native app, redacted-export metadata, and MCP versions are now `1.0.2` (app build `2`).
- The stable `bin/harsharkngx-mcp` command now links to `bin/HarsharkMCP.app/Contents/MacOS/harsharkngx-mcp`. Existing Claude command paths continue to work; upgrades may require re-adding or re-enabling the helper in Full Disk Access, followed by restarting Claude.
- Documented the permissions workflow and its limits: the check verifies effective shared-data access, not the Full Disk Access switch or a live Claude connection. Users change system permissions and Claude configuration themselves.

### Distribution
- The native release ZIP includes the GUI and MCP helper. Development builds remain ad hoc signed and are not Developer ID signed or notarized.

### Validation
- Passed 29 core tests, 12 app tests, and all 10 UI tests across the suite and targeted final reruns. Coverage includes fresh-install detection, helper installation/upgrades, automatic capture sizing/reopening, screen bounds, all inspector tabs, narrow layouts, keyboard selection, Settings, and LaunchServices file opening.
- Standalone MCP and independent LaunchServices permission-monitor regressions passed. The monitor checks live availability, access, invalid-settings recovery, and shutdown using fixtures; changing macOS’s Full Disk Access switch remains a manual system interaction.

## 1.0.1 — 2026-10-30

### Fixed
- Opening `.har` or `.json` captures by dropping them onto the Dock icon now brings the main window to the foreground, including when the app is launched by the drop. Focus waits for launch completion and the SwiftUI window to be ready; hidden or minimized capture windows are restored.
- Both SwiftUI and AppKit external file-open handlers request main-window focus. Added LaunchServices UI regressions for cold launches with both extensions; external multi-file opening now checks foreground state without calling the test application's activation helper.
- Preserved SwiftUI's window delegate during activation. Command–W still closes the selected capture through a window-scoped keyboard monitor, avoiding delegate callback crashes when bringing windows forward.

### Changed
- Bumped the native app and bundled MCP version to `1.0.1`.

### Validation
- Passed 27 core tests, 9 app tests, 4 targeted UI tests, and the standalone MCP regression. UI coverage includes LaunchServices cold launches for `.har` and `.json`, multi-file opening, Command–W, and Settings; physical Dock drag gestures remain a manual check.

## 1.0.0

### Added
- A local, UI-independent `HarsharkCore` Swift package with no external dependencies, shared by the macOS app and an independent MCP executable.
- HAR structure validation with path-specific errors, session-scoped entry identifiers, original source retention, and exporter-specific entry fields.
- Explicit missing, null, empty, malformed, encoded, unsupported, binary, and preview-limited body handling.
- On-demand strict base64 decoding, UTF-16 BOM handling, and common declared character encodings.
- Swift Testing regression coverage for ingestion, body states, decoding failures, identity, cancellation, and input/preview limits.
- Native capture sidebar, multi-file opening, drag-and-drop, reload, and a bundled sample capture.
- Sortable request table with status colors, timing bars, debounced filtering, and optional detail search.
- Independent request and response inspectors for bodies, headers, parameters, cookies, timings, and request SAML data; JSON formatting, syntax colors, word wrap, paged text, copying, and body export.
- Persisted split positions and appearance preferences, plus the original application icon at macOS asset sizes.
- Standalone `harsharkngx-mcp` stdio executable with eight tools, summary/entry resources, explicit shared capture snapshots, and an atomic per-user installer. See [MCP-SETUP.md](MCP-SETUP.md).
- UI regression coverage for sample loading, filtering, inspector tabs, keyboard selection, opening multiple files, and recovery after a malformed capture.
- MCP regression coverage for initialization, discovery, shared sessions, body paging, search, resources, failed-load recovery, and EOF shutdown.

### Changed
- Native application marketing version set to `1.0.0` (build `1`).
- Replaced the starter screen with the native HAR viewer.
- File imports now use private file-backed snapshots and deferred body decoding; a regression fixture verifies imports beyond the old 32 MiB limit.

### Native refinement — 2026-10-26
- Command–W closes the selected capture and selects its nearest remaining neighbor. Closing the final capture returns the same window to the reusable welcome screen; model and UI regression tests cover the transition.
- Added a native Settings window with General, Appearance, HAR Processing, Performance, Privacy & Sanitization, and MCP Integration sections. Working preferences include startup behavior, bookmark-based capture restoration, duplicate opening, timestamp style, table density/columns/colors, formatting, wrapping, highlighting, and preview limits.
- Local-time Started values retain the original timestamp in tooltips. Table columns resize with the window; methods and status retain textual values alongside optional colors.
- Wrapped sidebar filenames/privacy text, compacted filtering controls, and added vertically stacked inspectors for narrow windows while retaining split-view resizing.
- Added an explicit redacted-summary HAR export that omits bodies, headers, cookies, URL credentials/paths/queries, and unknown fields. Hostnames remain; original files are unchanged.
- Bounded raw-entry copying and made Copy Visible Text copy the current preview page. Table selection no longer compares all row values on each update.
- Fixed standalone MCP initialization stalling while stdin remained open. Pipe reads now process available bytes immediately; the regression harness requires a response to every request before sending the next.
- Added repeatable release-build benchmarks for import, filtering, sorting, preview latency, peak resident memory, and memory after releasing a capture.

### Stabilization — 2026-10-27
- Fixed external multi-file opening through LaunchServices by routing open events into the existing WindowGroup.
- Preserved normal Settings/window closure while intercepting Command–W for the selected capture.
- Added security-scoped bookmark entitlements and restoration/removal regression coverage.
- Added adaptive light/dark HTTP colors and accessible inspector controls.
- Installed the corrected standalone MCP binary at its stable per-user location; Claude configuration was left unchanged.
- Added an integration test that terminates the GUI before exercising the installed MCP executable.
- Validation: Xcode build passes; 27 core tests and all 12 app/UI tests have passing results (suite plus targeted rerun). Installed-MCP interactive regression also passes. See VALIDATION.md for exact scope and remaining manual checks.

### Documentation and branding — 2026-10-27
- Refreshed the repository README for native v1.0.0 with Xcode build/run steps and concise feature, MCP, and development links.
- Preserved the previous Python/PySide6 README as README-PYSIDE6.md, linked from the new README.
- Adopted the supplied blue/cyan shark icon set at all ten macOS asset sizes and in the README header. Added native overview and response-inspector screenshots to the README; a larger banner remains planned.

### Layout and MCP controls — 2026-10-27
- Fixed footer clipping and kept the request table full-width when selection is cleared, including clicks in empty table space.
- Method and status labels use the system selection text color on highlighted rows and restore their HTTP colors when the highlight loses emphasis.
- Added a persistent, default-on MCP access toggle; connected servers enforce changes and discard cached captures across off/on cycles.
- Refreshed README screenshots and documented MCP access control.
- Fixed clipped inspector options menus, showed the HTTP method in both inspector headers alongside the response status, and centered summary values over their labels.
- Removed the loading flash for small inspector previews by preparing them in one UI update; large previews retain cancellable background processing.

### Current limitations
- This remains a native migration in progress; packaged native releases do not claim complete Python feature parity.
- Metadata memory scales with entry count. Core release-build benchmarks are recorded in PERFORMANCE.md; full GUI profiling remains pending; full-body export materializes the selected body in memory.
- The in-memory reference parser retains its 32 MiB default limit. The app and MCP file-import path uses file-backed indexing instead.
- Inspector body previews/search use a configurable 2, 8, or 32 MiB source budget; MCP uses 8 MiB; oversized bodies have an explicit notice and can be exported from the GUI. Paging applies to decoded previews within that budget.
- Native body-state regressions pass; the Python application's intermittent blank-body issue has not been changed or independently reproduced here.
