# Native v1.0.3 validation

## Current release — 2026-11-03

- Passed 29 Swift core tests and all 15 native app tests. New coverage verifies automatic publication of multiple captures, exact unredacted bytes, private snapshot permissions, reload replacement, failed-reload retention, persistent snapshots after closing, removal, sharing failure recovery, and automatic publication when MCP is re-enabled. Restoration tests use an isolated shared directory.
- Three targeted UI checks passed across the suite and final rerun: external multi-file opening, Setup Assistant opening/reopening, and sample opening/filtering with an automatically shared capture and no sheet. The sharing toolbar menu now exposes an explicit accessibility label; the first assertion exposed macOS's icon-only menu title and was corrected by adding that label.
- The stdio MCP harness passed against both the development executable and the universal release's bundled helper. It verifies tool annotations, initialization instructions, discovery of snapshots created after connection, direct loading of an agent-supplied local path with spaces, inspection/search/resources, access toggles, errors, and EOF shutdown.
- Built the app and bundled helper as universal arm64/x86_64 binaries, version `1.0.3`, build `3`, with ad hoc signing. The [published release](https://github.com/teezyyoxo/HarsharkNGX/releases/tag/native-v1.0.3) includes the ZIP and SHA-256 checksum. It is not Developer ID signed or notarized; Intel execution and Claude/other agents' own approval UI remain unverified.
- `git diff --check` passed. Native macOS privacy prompts and each MCP client's approval policy remain controlled by those applications.

## Previous release — 2026-11-02

- Passed 29 Swift core tests, 12 app tests, and all 10 UI tests across the suite and targeted final reruns. Final app tests cover fresh-install setup detection with absent, empty, and existing configuration directories; registered versus persisted preferences; helper upgrade/rollback behavior; content-dependent sizing; and display bounds.
- UI coverage includes Setup Assistant opening/reopening, capture-driven window growth, reopening the same capture after manually shrinking its window, every request/response inspector tab remaining hittable, narrow-window tabs, keyboard row selection, Settings, multi-file opening, cold-launch file focus, and closing captures.
- Standalone MCP stdio regression passed. The independent LaunchServices permission-monitor regression verifies live unavailable/granted/error/recovery transitions and process shutdown using temporary fixtures. These checks do not modify Full Disk Access or claim to validate Claude’s own UI.
- Setup and automatically sized payload screenshots were visually reviewed. The window grows to accommodate long metadata and bounded payload previews; row/payload panes are rebalanced on capture opening. Very large content remains scrollable within the current screen’s usable area. Measurement samples at most 256 rows and 1,024 characters per metadata value, and bounds payload inspection to 64 KiB.
- The distribution build is universal (arm64 and x86_64), ad hoc signed, and not Developer ID signed or notarized. Intel execution and a complete accessibility audit remain unverified.
- The release ZIP was extracted and its app/helper versions, universal architectures, code signatures, archive integrity, and standalone MCP behavior verified. A SHA-256 checksum accompanies the ZIP.

## Historical v1.0.0 validation

This is an in-development native application on `feature/native-swift-macos`, not a packaged release. Existing migration work was preserved. Python source and external Claude configuration were not changed, and no merge or force push was performed.

## Implementation status

The native app and standalone MCP executable share HarsharkCore. The original request-table/sidebar/dual-inspector design remains. The welcome view is now the reusable empty state. Capture removal selects a remaining neighbor; closing the final capture keeps the window open. Command–W closes the selected capture, while Settings and the title-bar close control retain normal window behavior.

Settings contains working persisted controls for startup/restoration, duplicate opening, timestamps, appearance, table density/columns/colorization, formatting, wrapping, highlighting, preview limits, privacy operations, and MCP diagnostics. Security-scoped bookmarks support restored files. Restoration can be forgotten explicitly. No speculative cache-size or daemon switches were added.

Bodies preserve distinct missing, null, empty, malformed, unsupported, binary, successfully decoded, and preview-limited states. File-backed snapshots defer body decoding. Formatting/search previews are bounded; full selected-body export can still materialize a large body. The conservative redacted-summary export removes payloads, headers, cookies, URL credentials/path/query, and unknown fields; it retains hostnames and is deliberately lossy. It does not modify the original capture.

The standalone MCP server processes requests while stdin remains open. It operates on explicitly loaded files or persistent snapshots automatically shared by the GUI while MCP is on. Installation and client configuration are in [MCP-SETUP.md](MCP-SETUP.md).

## Executed validation

- SwiftPM: 27 tests in four suites passed on 2026-10-27. Coverage includes validation, deferred JSON/Unicode scanning, import cancellation, imports exceeding 32 MiB, body states/decoding, preview limits, redaction, and backing-storage lifetime.
- Xcode BuildProject succeeded on 2026-10-27 with no errors.
- Xcode app/UI suite: 11 passed, 0 failed, 1 initially skipped. The installed-MCP test was corrected to resolve the real user home and launch Swift directly (the UI-test sandbox blocks the system Python launcher); its targeted rerun passed. All 12 tests therefore have passing results, across the suite and targeted rerun.
- Passing app/UI coverage: capture selection/removal/release, last-capture welcome transition, latest-filter selection, bookmark restoration/removal, parser-to-inspector flow, missing bodies, sample/keyboard workflows, malformed-file recovery, multi-file LaunchServices opening into one window without duplicate sessions, Settings sections/Command–Comma, narrow-window controls, and installed-MCP initialization with the GUI terminated.
- Release standalone MCP: after the UI test terminated the GUI, the interactive request/response regression passed against the installed executable, covering initialization, discovery, file loading, shared sessions, entry/body inspection, paging, search, resources, failed-load recovery, and EOF shutdown.
- `git diff --check` passed.
- Core performance: three fresh release processes per workload; see [PERFORMANCE.md](PERFORMANCE.md) and raw [PERFORMANCE.json](PERFORMANCE.json).
- HTTP color palette calculations against representative light backgrounds (`#FFFFFF`, `#ECECEC`) and dark backgrounds (`#1E1E1E`, `#2C2C2C`) gave minimum contrast ratios of 4.53:1 and 5.54:1 respectively. These are calculations, not an audit of every runtime background/theme.

## Remaining verification and limitations

- Accessibility verdict: **NEEDS VERIFICATION**. Controls have labels, keyboard workflows are tested, and status/method information remains textual. Full VoiceOver operation, Increase Contrast, selected-row colors, and all syntax themes need a manual audit.
- UI automation exercised a narrow window and its accessibility hierarchy. Screenshot capture returned another desktop window in this environment, so pixel-level layout/contrast review is not claimed.
- External multi-file opening is exercised through actual NSWorkspace/LaunchServices events. Direct Finder double-click and physical Dock/window drag gestures still need manual confirmation; existing drop handlers were retained.
- The MCP harness validates a real stdio connection. Claude's own connection UI still needs confirmation after restarting Claude to replace any old subprocess.
- Performance measurements cover the core process, not the full GUI or Instruments. The 50,000-entry workload retained approximately 90.45 MiB RSS after scope release; allocator retention and metadata costs merit further profiling. No memory improvement relative to Python is claimed.
- Full selected-body export and some large metadata operations can still allocate substantially. The app does not expose an unimplemented cache control.
- Full Python feature parity and distribution signing/notarization are not certified by these checks. The old Python GUI bridge is replaced by local file/shared-snapshot MCP access; it does not mirror live GUI selection.
- No annotation/editing model is implemented, so there are no unsaved capture edits to prompt for.
