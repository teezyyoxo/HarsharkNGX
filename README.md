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
- Detailed request/response inspection:
  - headers, parameters, cookies, bodies
  - SAML/XML payload formatting
- Faster HAR loading and more robust parsing with improved handling of missing fields
- Local-first workflow with no network dependency required

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
python -m harsharkngx
```

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
