# Changelog

All notable changes to this project will be documented in this file.

---

## [1.1.0] - 2026-03-27

### ✨ Added
- Column management system:
  - Drag-and-drop column reordering via header
  - Toggle column visibility via `View > Columns`
  - Right-click context menu on table header for quick column toggling
- Persistent UI preferences:
  - Column order and visibility are saved across sessions
  - Window size and position are preserved
  - Splitter (table/detail pane) position is remembered
- `View > Reset Columns to Default` option

### 🎨 Improved
- macOS light/dark mode handling:
  - Theme changes now apply dynamically while the app is running
  - Full UI refresh on appearance change (no more partial theme mismatch)
  - Consistent styling across all widgets (tables, tabs, text areas, etc.)
- Theme handling moved to application-level palette instead of window-level stylesheet

### 🛠 Fixed
- Incomplete theme switching when toggling macOS appearance while app is open
  - Previously resulted in mixed light/dark UI elements
  - Now forces proper re-polish of all widgets

### ⚙️ Developer / Packaging
- Clarified `src/` layout usage
- Updated run instructions to include:
  ```bash
  pip install -e .

[3.0.0] - 2026-03-27

✨ Initial Release (Modernized Fork)

🚀 Added
	•	Complete rewrite using modern Qt stack (PySide6)
	•	Cross-platform desktop HAR viewer (macOS, Windows, Linux)
	•	HAR file parsing and entry table view
	•	Request/response inspection tabs:
	•	Headers
	•	Params
	•	Cookies
	•	Body
	•	SAML (best-effort formatting)
	•	Entry filtering/search
	•	MIME type display and timing metrics

🎨 UI / UX
	•	Native macOS light/dark mode support (initial implementation)
	•	Clean, modern Qt6 interface
	•	Improved readability over legacy PyQt5 UI

📦 Dependencies Updated
	•	PySide6 (Qt6-based UI framework)
	•	beautifulsoup4 (HTML/XML parsing)
	•	lxml (fast XML parsing)
	•	darkdetect (OS theme detection)

⚠️ Known Limitations (3.0.0)
	•	Theme switching only applied correctly on app launch (fixed in 3.1.0)
	•	Column layout not customizable or persistent (fixed in 3.1.0)

⸻

Notes
	•	This project is a modernized reimplementation inspired by the original Harshark project.
	•	Focus is on maintainability, cross-platform support, and improved UI/UX while preserving core functionality.