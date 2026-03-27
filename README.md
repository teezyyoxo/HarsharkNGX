# Harshark Next

A modernized, cross-platform HAR viewer inspired by the original `MacroPolo/harshark` project.

## What's new

- Updated for modern Python and Qt
- Uses `PySide6` instead of the old `PyQt5==5.11.3`
- Detects and follows macOS light/dark mode using `darkdetect`
- Cleaner table model and splitter-based UI
- Faster loading for common HAR files
- Safer parsing and better handling of missing fields

## Highlights

- Native desktop UI built with PySide6
- macOS light and dark mode support, including live theme switching while the app is open
- Reorderable columns with saved layout state
- Show or hide columns from the View menu or by right-clicking the table header
- Column width presets: Compact, Balanced, and Comfortable
- Status color coding for quick HTTP response scanning
- Waterfall timing column for visual request-duration comparison
- Request and response detail panes for headers, parameters, cookies, bodies, and SAML-like XML payloads
- Local-first workflow with no network dependency required to inspect HAR files

## Requirements

- Python 3.10+
- macOS, Windows, or Linux

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
python -m harshark_next
```

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
python -m harshark_next
```


## New in 3.1.0

- Better live theme switching while the app is already open
- Saved splitter position and window geometry
- Rearrange columns by dragging the header
- Show or hide columns from View > Columns or by right-clicking the header
- Column visibility and order are restored on the next launch
- Reset Columns to Default option