# HarsharkNGX Native Changelog

This changelog tracks the native macOS application separately from the Python application's release history.

## 1.0.0 — In development

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
- Adopted the supplied blue/cyan shark icon set at all ten macOS asset sizes and in the README header. A larger banner and native screenshots remain planned.

### Current limitations
- This remains an in-development native migration, not a packaged release or a claim of complete Python feature parity.
- Metadata memory scales with entry count. Core release-build benchmarks are recorded in PERFORMANCE.md; full GUI profiling remains pending; full-body export materializes the selected body in memory.
- The in-memory reference parser retains its 32 MiB default limit. The app and MCP file-import path uses file-backed indexing instead.
- Inspector body previews/search use a configurable 2, 8, or 32 MiB source budget; MCP uses 8 MiB; oversized bodies have an explicit notice and can be exported from the GUI. Paging applies to decoded previews within that budget.
- Native body-state regressions pass; the Python application's intermittent blank-body issue has not been changed or independently reproduced here.
