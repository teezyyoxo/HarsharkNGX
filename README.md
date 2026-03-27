# Harshark Next

A modernized, cross-platform HAR viewer inspired by the original `MacroPolo/harshark` project.

## What's new

- Updated for modern Python and Qt
- Uses `PySide6` instead of the old `PyQt5==5.11.3`
- Detects and follows macOS light/dark mode using `darkdetect`
- Cleaner table model and splitter-based UI
- Faster loading for common HAR files
- Safer parsing and better handling of missing fields

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
python -m harshark_next
```

## Notes

This is a best-effort modernization rather than a byte-for-byte fork. It keeps the spirit of the original app, but the codebase has been refreshed around a simpler Qt6 architecture.


## New in 3.1.0

- Better live theme switching while the app is already open
- Saved splitter position and window geometry
- Rearrange columns by dragging the header
- Show or hide columns from View > Columns or by right-clicking the header
- Column visibility and order are restored on the next launch
- Reset Columns to Default option
