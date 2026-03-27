from __future__ import annotations

import json
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import parse_qsl, urlparse

from bs4 import BeautifulSoup
from lxml import etree
from PySide6.QtCore import QAbstractTableModel, QModelIndex, QObject, Qt, QThread, Signal
from PySide6.QtGui import QAction, QColor, QGuiApplication, QIcon, QKeySequence, QTextOption
from PySide6.QtWidgets import (
    QApplication,
    QFileDialog,
    QHeaderView,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QSplitter,
    QStatusBar,
    QTabWidget,
    QTableView,
    QToolBar,
    QVBoxLayout,
    QWidget,
)

try:
    import darkdetect
except Exception:  # pragma: no cover
    darkdetect = None

APP_NAME = "Harshark Next"
DEFAULT_COLUMNS = [
    "Started",
    "Method",
    "Status",
    "Protocol",
    "Host",
    "Path",
    "Mime Type",
    "Time (ms)",
]


@dataclass(slots=True)
class HarEntry:
    started: str
    method: str
    status: str
    protocol: str
    host: str
    path: str
    mime_type: str
    total_time_ms: str
    request_headers: str
    request_query: str
    request_cookies: str
    request_body: str
    request_saml: str
    response_headers: str
    response_cookies: str
    response_body: str
    full_url: str
    raw: dict[str, Any]

    def column_value(self, column: str) -> str:
        mapping = {
            "Started": self.started,
            "Method": self.method,
            "Status": self.status,
            "Protocol": self.protocol,
            "Host": self.host,
            "Path": self.path,
            "Mime Type": self.mime_type,
            "Time (ms)": self.total_time_ms,
        }
        return mapping.get(column, "")

    def haystack(self) -> str:
        parts = [
            self.started,
            self.method,
            self.status,
            self.protocol,
            self.host,
            self.path,
            self.mime_type,
            self.total_time_ms,
            self.request_headers,
            self.request_query,
            self.request_cookies,
            self.request_body,
            self.request_saml,
            self.response_headers,
            self.response_cookies,
            self.response_body,
            self.full_url,
        ]
        return "\n".join(part for part in parts if part)


class EntryTableModel(QAbstractTableModel):
    def __init__(self) -> None:
        super().__init__()
        self.columns = DEFAULT_COLUMNS[:]
        self.entries: list[HarEntry] = []
        self.filtered_entries: list[HarEntry] = []
        self.query = ""

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        if parent.isValid():
            return 0
        return len(self.filtered_entries)

    def columnCount(self, parent: QModelIndex = QModelIndex()) -> int:
        if parent.isValid():
            return 0
        return len(self.columns)

    def data(self, index: QModelIndex, role: int = Qt.DisplayRole) -> Any:
        if not index.isValid():
            return None
        entry = self.filtered_entries[index.row()]
        column = self.columns[index.column()]

        if role == Qt.DisplayRole:
            return entry.column_value(column)

        if role == Qt.ForegroundRole and column == "Status":
            try:
                status = int(entry.status)
            except Exception:
                return None
            if 200 <= status < 300:
                return QColor("#22863a")
            if 300 <= status < 400:
                return QColor("#8a63d2")
            if 400 <= status < 500:
                return QColor("#d97706")
            if status >= 500:
                return QColor("#c62828")

        return None

    def headerData(
        self,
        section: int,
        orientation: Qt.Orientation,
        role: int = Qt.DisplayRole,
    ) -> Any:
        if role != Qt.DisplayRole:
            return None
        if orientation == Qt.Horizontal:
            return self.columns[section]
        return str(section + 1)

    def set_entries(self, entries: list[HarEntry]) -> None:
        self.beginResetModel()
        self.entries = entries
        self.filtered_entries = entries[:]
        self.query = ""
        self.endResetModel()

    def apply_filter(self, query: str) -> None:
        self.beginResetModel()
        self.query = query.strip()
        if not self.query:
            self.filtered_entries = self.entries[:]
        else:
            needle = self.query.casefold()
            self.filtered_entries = [
                entry for entry in self.entries if needle in entry.haystack().casefold()
            ]
        self.endResetModel()

    def entry_at(self, row: int) -> HarEntry | None:
        if row < 0 or row >= len(self.filtered_entries):
            return None
        return self.filtered_entries[row]


class ThemeListener(QObject):
    theme_changed = Signal(str)

    def run(self) -> None:
        if darkdetect is None:
            return
        try:
            darkdetect.listener(lambda mode: self.theme_changed.emit((mode or "Light").lower()))
        except Exception:
            return


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle(f"{APP_NAME} 3.0.0")
        self.resize(1500, 900)

        self.model = EntryTableModel()
        self.current_path: Path | None = None
        self._theme_thread: QThread | None = None

        self._build_ui()
        self._apply_theme(self._detect_theme())
        self._start_theme_listener()

    def _build_ui(self) -> None:
        self._build_menu()
        self._build_toolbar()

        root = QWidget()
        layout = QVBoxLayout(root)
        layout.setContentsMargins(8, 8, 8, 8)
        layout.setSpacing(8)

        self.summary_label = QLabel("Open a HAR file to begin.")
        layout.addWidget(self.summary_label)

        splitter = QSplitter(Qt.Vertical)
        layout.addWidget(splitter, 1)

        self.table = QTableView()
        self.table.setModel(self.model)
        self.table.setSelectionBehavior(QTableView.SelectRows)
        self.table.setSelectionMode(QTableView.SingleSelection)
        self.table.setAlternatingRowColors(True)
        self.table.setSortingEnabled(True)
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeToContents)
        self.table.horizontalHeader().setStretchLastSection(True)
        self.table.verticalHeader().setVisible(False)
        self.table.clicked.connect(self._table_row_changed)
        splitter.addWidget(self.table)

        self.tabs = QTabWidget()
        splitter.addWidget(self.tabs)
        splitter.setSizes([480, 380])

        self.request_headers = self._make_text_tab("Request Headers")
        self.request_query = self._make_text_tab("Request Parameters")
        self.request_cookies = self._make_text_tab("Request Cookies")
        self.request_body = self._make_text_tab("Request Body")
        self.request_saml = self._make_text_tab("Request SAML")
        self.response_headers = self._make_text_tab("Response Headers")
        self.response_cookies = self._make_text_tab("Response Cookies")
        self.response_body = self._make_text_tab("Response Body")

        self.tabs.addTab(self.request_headers, "Req Headers")
        self.tabs.addTab(self.request_query, "Req Params")
        self.tabs.addTab(self.request_cookies, "Req Cookies")
        self.tabs.addTab(self.request_body, "Req Body")
        self.tabs.addTab(self.request_saml, "Req SAML")
        self.tabs.addTab(self.response_headers, "Resp Headers")
        self.tabs.addTab(self.response_cookies, "Resp Cookies")
        self.tabs.addTab(self.response_body, "Resp Body")

        self.setCentralWidget(root)
        self.setStatusBar(QStatusBar())

    def _build_menu(self) -> None:
        file_menu = self.menuBar().addMenu("&File")
        view_menu = self.menuBar().addMenu("&View")
        help_menu = self.menuBar().addMenu("&Help")

        open_action = QAction("&Open…", self)
        open_action.setShortcut(QKeySequence.Open)
        open_action.triggered.connect(self.open_file)
        file_menu.addAction(open_action)

        reload_action = QAction("&Reload", self)
        reload_action.setShortcut(QKeySequence.Refresh)
        reload_action.triggered.connect(self.reload_file)
        file_menu.addAction(reload_action)

        file_menu.addSeparator()

        exit_action = QAction("E&xit", self)
        exit_action.setShortcut(QKeySequence.Quit)
        exit_action.triggered.connect(self.close)
        file_menu.addAction(exit_action)

        wrap_action = QAction("Word &Wrap", self, checkable=True)
        wrap_action.setChecked(False)
        wrap_action.triggered.connect(self._toggle_wrap)
        view_menu.addAction(wrap_action)

        about_action = QAction("&About", self)
        about_action.triggered.connect(self._show_about)
        help_menu.addAction(about_action)

    def _build_toolbar(self) -> None:
        toolbar = QToolBar("Main")
        toolbar.setMovable(False)
        self.addToolBar(toolbar)

        open_btn = QAction("Open", self)
        open_btn.triggered.connect(self.open_file)
        toolbar.addAction(open_btn)

        toolbar.addSeparator()

        self.search_box = QLineEdit()
        self.search_box.setPlaceholderText("Filter entries…")
        self.search_box.textChanged.connect(self._search_changed)
        self.search_box.setClearButtonEnabled(True)
        self.search_box.setMinimumWidth(280)
        toolbar.addWidget(self.search_box)

        self.clear_btn = QPushButton("Clear")
        self.clear_btn.clicked.connect(self.search_box.clear)
        toolbar.addWidget(self.clear_btn)

    def _make_text_tab(self, _name: str) -> QPlainTextEdit:
        edit = QPlainTextEdit()
        edit.setReadOnly(True)
        edit.setWordWrapMode(QTextOption.NoWrap)
        return edit

    def _toggle_wrap(self, checked: bool) -> None:
        mode = QTextOption.WrapAtWordBoundaryOrAnywhere if checked else QTextOption.NoWrap
        for widget in [
            self.request_headers,
            self.request_query,
            self.request_cookies,
            self.request_body,
            self.request_saml,
            self.response_headers,
            self.response_cookies,
            self.response_body,
        ]:
            widget.setWordWrapMode(mode)

    def _show_about(self) -> None:
        QMessageBox.information(
            self,
            "About Harshark Next",
            (
                "Harshark Next 3.0.0\n\n"
                "A modernized offline HAR viewer inspired by the original Harshark project.\n"
                "Built with PySide6 and theme-aware behavior for macOS light/dark mode."
            ),
        )

    def _detect_theme(self) -> str:
        if darkdetect is not None:
            try:
                return "dark" if darkdetect.isDark() else "light"
            except Exception:
                pass
        palette = QGuiApplication.palette()
        return "dark" if palette.window().color().lightness() < 128 else "light"

    def _start_theme_listener(self) -> None:
        if darkdetect is None:
            return
        self._theme_thread = QThread(self)
        self._theme_listener = ThemeListener()
        self._theme_listener.moveToThread(self._theme_thread)
        self._theme_thread.started.connect(self._theme_listener.run)
        self._theme_listener.theme_changed.connect(self._apply_theme)
        self._theme_thread.start()

    def closeEvent(self, event) -> None:  # type: ignore[override]
        if self._theme_thread is not None:
            self._theme_thread.quit()
            self._theme_thread.wait(1000)
        super().closeEvent(event)

    def _apply_theme(self, theme: str) -> None:
        dark = theme == "dark"
        if dark:
            self.setStyleSheet(
                """
                QMainWindow, QWidget { background: #1e1f22; color: #e8e8e8; }
                QLineEdit, QPlainTextEdit, QTableView, QTabWidget::pane {
                    background: #25262b;
                    color: #e8e8e8;
                    border: 1px solid #3a3c43;
                    border-radius: 6px;
                }
                QHeaderView::section {
                    background: #2d2f36;
                    color: #f2f2f2;
                    padding: 6px;
                    border: 0;
                    border-right: 1px solid #3a3c43;
                    border-bottom: 1px solid #3a3c43;
                }
                QMenuBar, QMenu, QToolBar, QStatusBar { background: #1e1f22; color: #e8e8e8; }
                QPushButton {
                    background: #2d2f36;
                    color: #e8e8e8;
                    border: 1px solid #3a3c43;
                    border-radius: 6px;
                    padding: 4px 10px;
                }
                QTabBar::tab {
                    background: #2d2f36;
                    color: #dcdcdc;
                    padding: 8px 12px;
                    border: 1px solid #3a3c43;
                    border-bottom: none;
                    border-top-left-radius: 6px;
                    border-top-right-radius: 6px;
                }
                QTabBar::tab:selected { background: #25262b; }
                """
            )
        else:
            self.setStyleSheet(
                """
                QLineEdit, QPlainTextEdit, QTableView, QTabWidget::pane {
                    border: 1px solid #d0d7de;
                    border-radius: 6px;
                }
                QHeaderView::section {
                    background: #f6f8fa;
                    color: #1f2328;
                    padding: 6px;
                    border: 0;
                    border-right: 1px solid #d0d7de;
                    border-bottom: 1px solid #d0d7de;
                }
                QPushButton {
                    border: 1px solid #d0d7de;
                    border-radius: 6px;
                    padding: 4px 10px;
                    background: #f6f8fa;
                }
                QTabBar::tab {
                    background: #f6f8fa;
                    padding: 8px 12px;
                    border: 1px solid #d0d7de;
                    border-bottom: none;
                    border-top-left-radius: 6px;
                    border-top-right-radius: 6px;
                }
                QTabBar::tab:selected { background: white; }
                """
            )

    def open_file(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self,
            "Open HAR file",
            str(Path.home()),
            "HAR files (*.har *.json);;All files (*)",
        )
        if path:
            self.load_file(Path(path))

    def reload_file(self) -> None:
        if self.current_path is not None:
            self.load_file(self.current_path)

    def load_file(self, path: Path) -> None:
        try:
            text = path.read_text(encoding="utf-8")
            payload = json.loads(text)
            entries = parse_har(payload)
        except Exception as exc:
            QMessageBox.critical(self, "Failed to open HAR", f"{type(exc).__name__}: {exc}")
            return

        self.current_path = path
        self.model.set_entries(entries)
        self.summary_label.setText(
            f"{path.name} — {len(entries)} entries loaded"
        )
        self.statusBar().showMessage(f"Loaded {path}", 5000)
        if entries:
            self.table.selectRow(0)
            self._display_entry(entries[0])
        else:
            self._clear_details()

    def _search_changed(self, text: str) -> None:
        self.model.apply_filter(text)
        self.summary_label.setText(
            f"{self.current_path.name if self.current_path else 'No file'} — {len(self.model.filtered_entries)} visible entries"
        )
        if self.model.filtered_entries:
            self.table.selectRow(0)
            self._display_entry(self.model.filtered_entries[0])
        else:
            self._clear_details()

    def _table_row_changed(self) -> None:
        index = self.table.currentIndex()
        entry = self.model.entry_at(index.row())
        if entry is not None:
            self._display_entry(entry)

    def _display_entry(self, entry: HarEntry) -> None:
        self.request_headers.setPlainText(entry.request_headers)
        self.request_query.setPlainText(entry.request_query)
        self.request_cookies.setPlainText(entry.request_cookies)
        self.request_body.setPlainText(entry.request_body)
        self.request_saml.setPlainText(entry.request_saml)
        self.response_headers.setPlainText(entry.response_headers)
        self.response_cookies.setPlainText(entry.response_cookies)
        self.response_body.setPlainText(entry.response_body)

    def _clear_details(self) -> None:
        for widget in [
            self.request_headers,
            self.request_query,
            self.request_cookies,
            self.request_body,
            self.request_saml,
            self.response_headers,
            self.response_cookies,
            self.response_body,
        ]:
            widget.clear()


def _fmt_pairs(items: list[dict[str, Any]] | None, key_name: str = "name", value_name: str = "value") -> str:
    if not items:
        return ""
    lines = []
    for item in items:
        key = str(item.get(key_name, ""))
        value = item.get(value_name, "")
        lines.append(f"{key}: {value}")
    return "\n".join(lines)


def _fmt_query_from_url(url: str) -> str:
    parsed = urlparse(url)
    parts = parse_qsl(parsed.query, keep_blank_values=True)
    if not parts:
        return ""
    return "\n".join(f"{k}: {v}" for k, v in parts)


def _fmt_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, (dict, list)):
        return json.dumps(value, indent=2, ensure_ascii=False)
    return str(value)


def _extract_body_text(blob: dict[str, Any] | None) -> str:
    if not blob:
        return ""
    text = blob.get("text", "")
    if text is None:
        return ""
    return str(text)


def _extract_saml(text: str) -> str:
    if not text:
        return ""
    if "<saml" not in text.lower() and "samlresponse" not in text.lower() and "samlrequest" not in text.lower():
        return ""

    # First try XML pretty printing directly.
    try:
        parser = etree.XMLParser(remove_blank_text=True, recover=True)
        root = etree.fromstring(text.encode("utf-8"), parser=parser)
        return etree.tostring(root, pretty_print=True, encoding="unicode")
    except Exception:
        pass

    # Then try a more forgiving HTML/XML cleanup.
    try:
        soup = BeautifulSoup(text, "xml")
        pretty = soup.prettify()
        if pretty.strip():
            return pretty
    except Exception:
        pass

    return text


def _timestamp(value: str) -> str:
    if not value:
        return ""
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return dt.isoformat(sep=" ")
    except Exception:
        return value



def parse_har(payload: dict[str, Any]) -> list[HarEntry]:
    log = payload.get("log", {})
    raw_entries = log.get("entries", [])
    entries: list[HarEntry] = []

    for item in raw_entries:
        request = item.get("request", {})
        response = item.get("response", {})
        url = str(request.get("url", ""))
        parsed = urlparse(url)

        body_text = _extract_body_text(request.get("postData"))
        response_text = _extract_body_text(response.get("content"))
        protocol = parsed.scheme.upper() if parsed.scheme else ""

        entry = HarEntry(
            started=_timestamp(str(item.get("startedDateTime", ""))),
            method=str(request.get("method", "")),
            status=str(response.get("status", "")),
            protocol=protocol,
            host=parsed.hostname or "",
            path=parsed.path or "/",
            mime_type=str(response.get("content", {}).get("mimeType", "")),
            total_time_ms=str(item.get("time", "")),
            request_headers=_fmt_pairs(request.get("headers")),
            request_query=_fmt_pairs(request.get("queryString")) or _fmt_query_from_url(url),
            request_cookies=_fmt_pairs(request.get("cookies")),
            request_body=body_text,
            request_saml=_extract_saml(body_text),
            response_headers=_fmt_pairs(response.get("headers")),
            response_cookies=_fmt_pairs(response.get("cookies")),
            response_body=response_text,
            full_url=url,
            raw=item,
        )
        entries.append(entry)

    return entries



def main() -> None:
    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setOrganizationName("OpenAI")
    window = MainWindow()
    window.show()
    sys.exit(app.exec())
