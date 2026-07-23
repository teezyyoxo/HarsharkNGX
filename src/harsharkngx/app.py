from __future__ import annotations

import base64
import binascii
import json
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import parse_qsl, urlparse

from bs4 import BeautifulSoup
from lxml import etree
from PySide6.QtCore import (
    QByteArray,
    QAbstractTableModel,
    QModelIndex,
    QObject,
    QRectF,
    QRegularExpression,
    QSettings,
    Qt,
    QThread,
    QTimer,
    Signal,
    Slot,
)
from PySide6.QtGui import (
    QAction,
    QColor,
    QFont,
    QGuiApplication,
    QKeySequence,
    QPainter,
    QPalette,
    QSyntaxHighlighter,
    QTextCharFormat,
    QTextCursor,
    QTextOption,
)
from PySide6.QtWidgets import (
    QApplication,
    QFileDialog,
    QHeaderView,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMenu,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QSplitter,
    QStatusBar,
    QStyle,
    QStyledItemDelegate,
    QStyleFactory,
    QStyleOptionViewItem,
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

SETTINGS_LAYOUT_VERSION = 2
MAX_SAML_PARSE_CHARS = 1_000_000
DETAIL_INCREMENTAL_RENDER_CHARS = 256_000
DETAIL_RENDER_CHUNK_CHARS = 48_000
DETAIL_HIGHLIGHT_MAX_CHARS = 2_000_000
DETAIL_NOWRAP_CHARS = 1_000_000
SEARCH_DEBOUNCE_MS = 220
SEARCH_CHUNK_CHARS = 512_000

APP_NAME = "HarsharkNGX"
APP_VERSION = "1.7.0"
SETTINGS_GROUP = "MainWindow"
DEFAULT_COLUMNS = [
    "Started",
    "Method",
    "Status",
    "Protocol",
    "Host",
    "Path",
    "Mime Type",
    "Waterfall",
    "Time (ms)",
]
DEFAULT_WIDTH_PRESET = "Balanced"
DEFAULT_SYNTAX_COLOR_THEME = "Default"
SYNTAX_COLOR_THEMES: dict[str, dict[str, dict[str, dict[str, str]]]] = {
    "Default": {
        "light": {
            "json": {"key": "#0550ae", "string": "#0a7f3f", "number": "#953800", "literal": "#8250df"},
            "headers": {"name": "#0550ae", "url": "#0a7f3f", "mime": "#953800", "status": "#cf222e", "directive": "#8250df"},
        },
        "dark": {
            "json": {"key": "#79c0ff", "string": "#a5d6a7", "number": "#ffcc80", "literal": "#f48fb1"},
            "headers": {"name": "#79c0ff", "url": "#a5d6a7", "mime": "#ffcc80", "status": "#f48fb1", "directive": "#c4b5fd"},
        },
    },
    "Nord": {
        "light": {
            "json": {"key": "#2e5d74", "string": "#3d7a5e", "number": "#a35d2d", "literal": "#7c4d8e"},
            "headers": {"name": "#2e5d74", "url": "#3d7a5e", "mime": "#a35d2d", "status": "#b14c57", "directive": "#7c4d8e"},
        },
        "dark": {
            "json": {"key": "#88c0d0", "string": "#a3be8c", "number": "#ebcb8b", "literal": "#b48ead"},
            "headers": {"name": "#88c0d0", "url": "#a3be8c", "mime": "#ebcb8b", "status": "#bf616a", "directive": "#b48ead"},
        },
    },
    "Solarized": {
        "light": {
            "json": {"key": "#268bd2", "string": "#2aa198", "number": "#b58900", "literal": "#d33682"},
            "headers": {"name": "#268bd2", "url": "#2aa198", "mime": "#b58900", "status": "#dc322f", "directive": "#d33682"},
        },
        "dark": {
            "json": {"key": "#268bd2", "string": "#2aa198", "number": "#b58900", "literal": "#d33682"},
            "headers": {"name": "#268bd2", "url": "#2aa198", "mime": "#b58900", "status": "#dc322f", "directive": "#d33682"},
        },
    },
    "Monokai": {
        "light": {
            "json": {"key": "#0077aa", "string": "#5f7800", "number": "#8b4dcc", "literal": "#c92762"},
            "headers": {"name": "#0077aa", "url": "#5f7800", "mime": "#8b4dcc", "status": "#c92762", "directive": "#8b4dcc"},
        },
        "dark": {
            "json": {"key": "#66d9ef", "string": "#e6db74", "number": "#ae81ff", "literal": "#f92672"},
            "headers": {"name": "#66d9ef", "url": "#e6db74", "mime": "#ae81ff", "status": "#f92672", "directive": "#ae81ff"},
        },
    },
}
COLUMN_WIDTH_PRESETS: dict[str, dict[str, int]] = {
    "Compact": {
        "Started": 170,
        "Method": 78,
        "Status": 78,
        "Protocol": 88,
        "Host": 170,
        "Path": 360,
        "Mime Type": 180,
        "Waterfall": 150,
        "Time (ms)": 95,
    },
    "Balanced": {
        "Started": 210,
        "Method": 90,
        "Status": 90,
        "Protocol": 95,
        "Host": 220,
        "Path": 520,
        "Mime Type": 220,
        "Waterfall": 200,
        "Time (ms)": 110,
    },
    "Comfortable": {
        "Started": 240,
        "Method": 100,
        "Status": 100,
        "Protocol": 110,
        "Host": 260,
        "Path": 660,
        "Mime Type": 260,
        "Waterfall": 240,
        "Time (ms)": 120,
    },
}
STATUS_COLOR_MAP = {
    "1xx": QColor("#5c6bc0"),
    "2xx": QColor("#2e7d32"),
    "3xx": QColor("#6a1b9a"),
    "4xx": QColor("#ef6c00"),
    "5xx": QColor("#c62828"),
    "other": QColor("#546e7a"),
}
COPY_FIELD_SPECS = [
    ("Full Path", "full_url"),
    ("Host", "host"),
    ("Path", "path"),
    ("Method", "method"),
    ("Status", "status"),
    ("Protocol", "protocol"),
    ("Started", "started"),
    ("Mime Type", "mime_type"),
    ("Time (ms)", "total_time_ms"),
    ("Request Headers", "request_headers"),
    ("Request Parameters", "request_query"),
    ("Request Cookies", "request_cookies"),
    ("Request Body", "request_body"),
    ("Request SAML", "request_saml"),
    ("Response Headers", "response_headers"),
    ("Response Parameters", "response_params"),
    ("Response Cookies", "response_cookies"),
    ("Response Body", "response_body"),
]
COLUMN_COPY_FIELD_MAP = {
    "Started": ("Started", "started"),
    "Method": ("Method", "method"),
    "Status": ("Status", "status"),
    "Protocol": ("Protocol", "protocol"),
    "Host": ("Host", "host"),
    "Path": ("Path", "path"),
    "Mime Type": ("Mime Type", "mime_type"),
    "Waterfall": ("Time (ms)", "total_time_ms"),
    "Time (ms)": ("Time (ms)", "total_time_ms"),
}


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
    total_time_value: float
    request_headers: str
    request_query: str
    request_cookies: str
    request_body: str
    request_saml: str
    response_headers: str
    response_params: str
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
            "Waterfall": "",
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
            self.response_params,
            self.response_cookies,
            self.response_body,
            self.full_url,
        ]
        return "\n".join(part for part in parts if part)

    def matches_query(self, needle: str) -> bool:
        """Search fields individually so a query does not build another giant payload string."""
        for value in (
            self.started,
            self.method,
            self.status,
            self.protocol,
            self.host,
            self.path,
            self.mime_type,
            self.total_time_ms,
            self.full_url,
            self.request_headers,
            self.request_query,
            self.request_cookies,
            self.request_body,
            self.request_saml,
            self.response_headers,
            self.response_params,
            self.response_cookies,
            self.response_body,
        ):
            if _contains_casefold(value, needle):
                return True
        return False


def _contains_casefold(text: str, needle: str) -> bool:
    """Search oversized text in slices so a single casefold does not monopolize the interpreter."""
    if len(text) <= SEARCH_CHUNK_CHARS:
        return needle in text.casefold()

    overlap = max(len(needle) - 1, 0)
    for start in range(0, len(text), SEARCH_CHUNK_CHARS):
        end = min(start + SEARCH_CHUNK_CHARS + overlap, len(text))
        if needle in text[start:end].casefold():
            return True
    return False


def status_bucket(status_text: str) -> str:
    try:
        status = int(status_text)
    except Exception:
        return "other"
    if 100 <= status < 200:
        return "1xx"
    if 200 <= status < 300:
        return "2xx"
    if 300 <= status < 400:
        return "3xx"
    if 400 <= status < 500:
        return "4xx"
    if status >= 500:
        return "5xx"
    return "other"


def status_color(status_text: str) -> QColor:
    return STATUS_COLOR_MAP.get(status_bucket(status_text), STATUS_COLOR_MAP["other"])


def muted(color: QColor, alpha: int) -> QColor:
    toned = QColor(color)
    toned.setAlpha(alpha)
    return toned


class WaterfallDelegate(QStyledItemDelegate):
    def paint(self, painter: QPainter, option: QStyleOptionViewItem, index: QModelIndex) -> None:  # type: ignore[override]
        model = index.model()
        if not isinstance(model, EntryTableModel):
            super().paint(painter, option, index)
            return

        entry = model.entry_at(index.row())
        if entry is None:
            super().paint(painter, option, index)
            return

        opt = QStyleOptionViewItem(option)
        self.initStyleOption(opt, index)
        opt.text = ""
        style = opt.widget.style() if opt.widget is not None else QApplication.style()
        style.drawControl(QStyle.CE_ItemViewItem, opt, painter, opt.widget)

        inner = option.rect.adjusted(8, 8, -8, -8)
        if inner.width() <= 0 or inner.height() <= 0:
            return

        dark = option.palette.base().color().lightness() < 128
        track_color = QColor("#3a3c43") if dark else QColor("#dde3ea")
        painter.save()
        painter.setRenderHint(QPainter.Antialiasing, True)
        painter.setPen(Qt.NoPen)
        painter.setBrush(track_color)
        painter.drawRoundedRect(QRectF(inner), 4, 4)

        max_time = max(model.max_time_ms(), 1.0)
        ratio = max(0.0, min(entry.total_time_value / max_time, 1.0))
        if ratio > 0:
            fill_rect = QRectF(inner)
            fill_rect.setWidth(max(6.0, fill_rect.width() * ratio))
            fill_color = status_color(entry.status)
            fill_color.setAlpha(220)
            painter.setBrush(fill_color)
            painter.drawRoundedRect(fill_rect, 4, 4)

        if option.state & QStyle.State_Selected:
            painter.setBrush(muted(option.palette.highlight().color(), 70))
            painter.drawRoundedRect(QRectF(inner), 4, 4)

        painter.restore()


class EntryTableModel(QAbstractTableModel):
    def __init__(self) -> None:
        super().__init__()
        self.columns = DEFAULT_COLUMNS[:]
        self.entries: list[HarEntry] = []
        self.filtered_entries: list[HarEntry] = []
        self.query = ""
        self._max_time_value = 1.0

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

        if role == Qt.TextAlignmentRole and column in {"Method", "Status", "Protocol", "Time (ms)"}:
            return int(Qt.AlignCenter)

        if role == Qt.ForegroundRole and column == "Status":
            return status_color(entry.status)

        if role == Qt.BackgroundRole and column == "Status":
            dark = QGuiApplication.palette().base().color().lightness() < 128
            alpha = 72 if dark else 32
            return muted(status_color(entry.status), alpha)

        if role == Qt.ToolTipRole:
            if column == "Waterfall":
                return f"{entry.total_time_ms} ms"
            return entry.column_value(column)

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
        self._max_time_value = max((entry.total_time_value for entry in entries), default=1.0) or 1.0
        self.endResetModel()

    def set_filtered_entries(self, entries: list[HarEntry], query: str) -> None:
        self.beginResetModel()
        self.query = query
        self.filtered_entries = entries
        self._max_time_value = max((entry.total_time_value for entry in entries), default=1.0) or 1.0
        self.endResetModel()

    def entry_at(self, row: int) -> HarEntry | None:
        if row < 0 or row >= len(self.filtered_entries):
            return None
        return self.filtered_entries[row]

    def max_time_ms(self) -> float:
        return self._max_time_value


def _syntax_colors(theme_name: str, dark: bool, syntax_kind: str) -> dict[str, str]:
    theme = SYNTAX_COLOR_THEMES.get(theme_name, SYNTAX_COLOR_THEMES[DEFAULT_SYNTAX_COLOR_THEME])
    return theme["dark" if dark else "light"][syntax_kind]


def _syntax_format(color: str, bold: bool = False) -> QTextCharFormat:
    text_format = QTextCharFormat()
    text_format.setForeground(QColor(color))
    if bold:
        text_format.setFontWeight(QFont.Bold)
    return text_format


class JsonSyntaxHighlighter(QSyntaxHighlighter):
    """Small native JSON highlighter with no web view or editor extension dependency."""

    def __init__(self, document) -> None:
        super().__init__(document)
        self._key_pattern = QRegularExpression(r'"(?:\\.|[^"\\])*"(?=\s*:)')
        self._string_pattern = QRegularExpression(r'"(?:\\.|[^"\\])*"')
        self._number_pattern = QRegularExpression(r'(?<![\w."])-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?')
        self._literal_pattern = QRegularExpression(r'\b(?:true|false|null)\b')
        self.set_theme(False)

    def set_theme(self, dark: bool, color_theme: str = DEFAULT_SYNTAX_COLOR_THEME) -> None:
        colors = _syntax_colors(color_theme, dark, "json")
        self._key_format = _syntax_format(colors["key"], True)
        self._string_format = _syntax_format(colors["string"])
        self._number_format = _syntax_format(colors["number"])
        self._literal_format = _syntax_format(colors["literal"], True)
        self.rehighlight()

    def highlightBlock(self, text: str) -> None:  # type: ignore[override]
        for pattern, text_format in (
            (self._string_pattern, self._string_format),
            (self._number_pattern, self._number_format),
            (self._literal_pattern, self._literal_format),
            (self._key_pattern, self._key_format),
        ):
            match_iterator = pattern.globalMatch(text)
            while match_iterator.hasNext():
                match = match_iterator.next()
                self.setFormat(match.capturedStart(), match.capturedLength(), text_format)


class HeaderSyntaxHighlighter(QSyntaxHighlighter):
    """Native highlighting for HTTP-style ``Name: value`` detail panes."""

    def __init__(self, document) -> None:
        super().__init__(document)
        self._name_pattern = QRegularExpression(r"^[^:\r\n]+(?=:)")
        self._url_pattern = QRegularExpression(r"\bhttps?://[^\s;,]+")
        self._mime_pattern = QRegularExpression(r"\b(?:application|audio|font|image|multipart|text|video)/[^\s;,]+")
        self._status_pattern = QRegularExpression(r"\b[1-5]\d\d\b")
        self._directive_pattern = QRegularExpression(
            r"\b(?:no-cache|no-store|max-age|private|public|same-origin|strict|upgrade-insecure-requests)\b"
        )
        self.set_theme(False)

    def set_theme(self, dark: bool, color_theme: str = DEFAULT_SYNTAX_COLOR_THEME) -> None:
        colors = _syntax_colors(color_theme, dark, "headers")
        self._name_format = _syntax_format(colors["name"], True)
        self._url_format = _syntax_format(colors["url"])
        self._mime_format = _syntax_format(colors["mime"])
        self._status_format = _syntax_format(colors["status"], True)
        self._directive_format = _syntax_format(colors["directive"])
        self.rehighlight()

    def highlightBlock(self, text: str) -> None:  # type: ignore[override]
        for pattern, text_format in (
            (self._url_pattern, self._url_format),
            (self._mime_pattern, self._mime_format),
            (self._status_pattern, self._status_format),
            (self._directive_pattern, self._directive_format),
            (self._name_pattern, self._name_format),
        ):
            match_iterator = pattern.globalMatch(text)
            while match_iterator.hasNext():
                match = match_iterator.next()
                self.setFormat(match.capturedStart(), match.capturedLength(), text_format)


class DetailTextEdit(QPlainTextEdit):
    """A read-only detail pane that keeps very large payloads responsive."""

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setReadOnly(True)
        self.setUndoRedoEnabled(False)
        self.setWordWrapMode(QTextOption.WrapAtWordBoundaryOrAnywhere)
        self._wrap_requested = True
        self._render_text = ""
        self._render_offset = 0
        self._render_token = 0
        self._syntax_kind = "plain"
        self._render_timer = QTimer(self)
        self._render_timer.setInterval(1)
        self._render_timer.timeout.connect(self._append_render_chunk)
        self._json_highlighter = JsonSyntaxHighlighter(self.document())
        self._header_highlighter = HeaderSyntaxHighlighter(self.document())
        self._json_highlighter.setDocument(None)
        self._header_highlighter.setDocument(None)

    def set_wrap_enabled(self, enabled: bool) -> None:
        self._wrap_requested = enabled
        self._apply_wrap_policy()

    def set_syntax_theme(
        self,
        dark: bool,
        color_theme: str = DEFAULT_SYNTAX_COLOR_THEME,
    ) -> None:
        self._json_highlighter.set_theme(dark, color_theme)
        self._header_highlighter.set_theme(dark, color_theme)

    def render_text(self, text: str, syntax_kind: str = "plain") -> None:
        self._render_token += 1
        self._render_timer.stop()
        self._render_text = text
        self._render_offset = 0
        self._syntax_kind = syntax_kind if len(text) <= DETAIL_HIGHLIGHT_MAX_CHARS else "plain"
        self._json_highlighter.setDocument(
            self.document() if self._syntax_kind == "json" else None
        )
        self._header_highlighter.setDocument(
            self.document() if self._syntax_kind == "headers" else None
        )
        self._apply_wrap_policy()
        self.clear()

        if not text:
            return
        if len(text) < DETAIL_INCREMENTAL_RENDER_CHARS:
            self.setPlainText(text)
            return

        self.setToolTip(
            f"Rendering {len(text):,} characters in the background. The complete payload remains available."
        )
        self._render_timer.start()

    def clear_rendered_text(self) -> None:
        self._render_token += 1
        self._render_timer.stop()
        self._render_text = ""
        self._render_offset = 0
        self._syntax_kind = "plain"
        self._json_highlighter.setDocument(None)
        self._header_highlighter.setDocument(None)
        self.clear()

    def _apply_wrap_policy(self) -> None:
        should_wrap = self._wrap_requested and len(self._render_text) <= DETAIL_NOWRAP_CHARS
        self.setWordWrapMode(
            QTextOption.WrapAtWordBoundaryOrAnywhere if should_wrap else QTextOption.NoWrap
        )

    def _append_render_chunk(self) -> None:
        if self._render_offset >= len(self._render_text):
            self._render_timer.stop()
            self.setToolTip("")
            return

        chunk_end = min(self._render_offset + DETAIL_RENDER_CHUNK_CHARS, len(self._render_text))
        cursor = self.textCursor()
        cursor.movePosition(QTextCursor.End)
        cursor.insertText(self._render_text[self._render_offset : chunk_end])
        self._render_offset = chunk_end


class HarLoadWorker(QObject):
    loaded = Signal(str, object)
    failed = Signal(str, str)

    def __init__(self, path: Path) -> None:
        super().__init__()
        self.path = path

    @Slot()
    def run(self) -> None:
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
            self.loaded.emit(str(self.path), parse_har(payload))
        except Exception as exc:
            self.failed.emit(str(self.path), f"{type(exc).__name__}: {exc}")


class EntryFilterWorker(QObject):
    filtered = Signal(int, str, object)

    def __init__(self, serial: int, query: str, entries: list[HarEntry]) -> None:
        super().__init__()
        self.serial = serial
        self.query = query
        self.entries = entries

    @Slot()
    def run(self) -> None:
        needle = self.query.casefold()
        matches = [entry for entry in self.entries if entry.matches_query(needle)]
        self.filtered.emit(self.serial, self.query, matches)


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
        self.setWindowTitle(f"{APP_NAME} {APP_VERSION}")
        self.resize(1500, 900)

        self.model = EntryTableModel()
        self.current_path: Path | None = None
        self._theme_thread: QThread | None = None
        self._column_actions: dict[str, QAction] = {}
        self._width_preset_actions: dict[str, QAction] = {}
        self._syntax_theme_actions: dict[str, QAction] = {}
        self._syntax_color_theme = DEFAULT_SYNTAX_COLOR_THEME
        self._is_dark_theme = False
        self._waterfall_delegate = WaterfallDelegate(self)
        self.settings = QSettings("Montel G.", APP_NAME)
        self._current_entry: HarEntry | None = None
        self._mcp_server = None
        self._mcp_service = None
        self._load_thread: QThread | None = None
        self._load_worker: HarLoadWorker | None = None
        self._filter_thread: QThread | None = None
        self._filter_worker: EntryFilterWorker | None = None
        self._filter_serial = 0
        self._pending_filter_query = ""
        self._filter_timer = QTimer(self)
        self._filter_timer.setSingleShot(True)
        self._filter_timer.timeout.connect(self._run_scheduled_filter)

        self._build_ui()
        self._start_mcp_service()
        self._restore_window_state()
        self._restore_syntax_color_theme()
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
        self.main_splitter = splitter

        self.table = QTableView()
        self.table.setModel(self.model)
        self.table.setSelectionBehavior(QTableView.SelectRows)
        self.table.setSelectionMode(QTableView.SingleSelection)
        self.table.setAlternatingRowColors(True)
        self.table.setSortingEnabled(False)
        self.table.setShowGrid(True)
        self.table.setWordWrap(False)
        self.table.setCornerButtonEnabled(False)
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Interactive)
        self.table.horizontalHeader().setStretchLastSection(False)
        self.table.horizontalHeader().setSectionsMovable(True)
        self.table.horizontalHeader().setSectionsClickable(True)
        self.table.horizontalHeader().setContextMenuPolicy(Qt.CustomContextMenu)
        self.table.horizontalHeader().customContextMenuRequested.connect(self._show_header_menu)
        self.table.horizontalHeader().sectionMoved.connect(self._save_column_state)
        self.table.horizontalHeader().sectionResized.connect(self._save_column_state)
        self.table.verticalHeader().setVisible(False)
        self.table.setContextMenuPolicy(Qt.CustomContextMenu)
        self.table.customContextMenuRequested.connect(self._show_entry_copy_menu)
        self.table.selectionModel().currentRowChanged.connect(self._table_row_changed)
        splitter.addWidget(self.table)

        details_splitter = QSplitter(Qt.Horizontal)
        splitter.addWidget(details_splitter)
        splitter.setSizes([480, 380])

        request_panel = QWidget()
        request_layout = QVBoxLayout(request_panel)
        request_layout.setContentsMargins(0, 0, 0, 0)
        request_layout.setSpacing(6)
        request_layout.addWidget(QLabel("Request"))
        self.request_tabs = QTabWidget()
        request_layout.addWidget(self.request_tabs, 1)

        response_panel = QWidget()
        response_layout = QVBoxLayout(response_panel)
        response_layout.setContentsMargins(0, 0, 0, 0)
        response_layout.setSpacing(6)
        response_layout.addWidget(QLabel("Response"))
        self.response_tabs = QTabWidget()
        response_layout.addWidget(self.response_tabs, 1)

        details_splitter.addWidget(request_panel)
        details_splitter.addWidget(response_panel)
        details_splitter.setSizes([1, 1])

        self.request_headers = self._make_text_tab("Request Headers")
        self.request_query = self._make_text_tab("Request Parameters")
        self.request_cookies = self._make_text_tab("Request Cookies")
        self.request_body = self._make_text_tab("Request Body")
        self.request_saml = self._make_text_tab("Request SAML")
        self.response_headers = self._make_text_tab("Response Headers")
        self.response_params = self._make_text_tab("Response Parameters")
        self.response_cookies = self._make_text_tab("Response Cookies")
        self.response_body = self._make_text_tab("Response Body")

        self.request_tabs.addTab(self.request_body, "Body")
        self.request_tabs.addTab(self.request_query, "Parameters")
        self.request_tabs.addTab(self.request_cookies, "Cookies")
        self.request_tabs.addTab(self.request_headers, "Headers")
        self.request_tabs.addTab(self.request_saml, "SAML")

        self.response_tabs.addTab(self.response_body, "Body")
        self.response_tabs.addTab(self.response_params, "Parameters")
        self.response_tabs.addTab(self.response_cookies, "Cookies")
        self.response_tabs.addTab(self.response_headers, "Headers")
        self.request_tabs.currentChanged.connect(self._active_detail_tab_changed)
        self.response_tabs.currentChanged.connect(self._active_detail_tab_changed)

        self._request_widget_field_map = {
            self.request_body: "request_body",
            self.request_query: "request_query",
            self.request_cookies: "request_cookies",
            self.request_headers: "request_headers",
            self.request_saml: "request_saml",
        }
        self._response_widget_field_map = {
            self.response_body: "response_body",
            self.response_params: "response_params",
            self.response_cookies: "response_cookies",
            self.response_headers: "response_headers",
        }

        self.setCentralWidget(root)
        self.setStatusBar(QStatusBar())
        self.mcp_status_button = QPushButton("MCP Server: inactive")
        self.mcp_status_button.setMinimumWidth(160)
        self.mcp_status_button.setCursor(Qt.PointingHandCursor)
        self.mcp_status_button.setToolTip("Click to start or stop the MCP server")
        self.mcp_status_button.clicked.connect(self._toggle_mcp_service)
        self.statusBar().addPermanentWidget(self.mcp_status_button)
        self._set_mcp_status(False)
        self._build_column_actions()
        self._build_width_preset_actions()
        self._build_syntax_theme_actions()
        self._apply_special_column_behavior()

    def _build_menu(self) -> None:
        file_menu = self.menuBar().addMenu("&File")
        self.view_menu = self.menuBar().addMenu("&View")
        self.settings_menu = self.menuBar().addMenu("&Settings")
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

        self.wrap_action = QAction("Word &Wrap", self, checkable=True)
        self.wrap_action.setChecked(True)
        self.wrap_action.triggered.connect(self._toggle_wrap)
        self.view_menu.addAction(self.wrap_action)

        self.view_menu.addSeparator()
        self.columns_menu = self.view_menu.addMenu("Columns")
        self.width_presets_menu = self.view_menu.addMenu("Column Width Preset")

        self.reset_columns_action = QAction("Reset Columns to Default", self)
        self.reset_columns_action.triggered.connect(self._reset_columns_to_default)
        self.view_menu.addAction(self.reset_columns_action)

        self.syntax_theme_menu = self.settings_menu.addMenu("Text Color Theme")

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

    def _build_column_actions(self) -> None:
        self.columns_menu.clear()
        self._column_actions.clear()
        for index, column in enumerate(self.model.columns):
            action = QAction(column, self, checkable=True)
            action.setChecked(True)
            action.triggered.connect(lambda checked, i=index: self._set_column_visible(i, checked))
            self.columns_menu.addAction(action)
            self._column_actions[column] = action

    def _build_width_preset_actions(self) -> None:
        self.width_presets_menu.clear()
        self._width_preset_actions.clear()
        for preset_name in COLUMN_WIDTH_PRESETS:
            action = QAction(preset_name, self, checkable=True)
            action.triggered.connect(lambda checked, name=preset_name: self._apply_column_width_preset(name))
            self.width_presets_menu.addAction(action)
            self._width_preset_actions[preset_name] = action

    def _build_syntax_theme_actions(self) -> None:
        self.syntax_theme_menu.clear()
        self._syntax_theme_actions.clear()
        for theme_name in SYNTAX_COLOR_THEMES:
            action = QAction(theme_name, self, checkable=True)
            action.triggered.connect(
                lambda _checked, name=theme_name: self._set_syntax_color_theme(name)
            )
            self.syntax_theme_menu.addAction(action)
            self._syntax_theme_actions[theme_name] = action
        self._set_checked_syntax_color_theme(self._syntax_color_theme)

    def _make_text_tab(self, _name: str) -> DetailTextEdit:
        edit = DetailTextEdit()
        edit.setContextMenuPolicy(Qt.CustomContextMenu)
        edit.customContextMenuRequested.connect(
            lambda position, widget=edit: self._show_detail_copy_menu(widget, position)
        )
        return edit

    def _toggle_wrap(self, checked: bool) -> None:
        for widget in self._detail_widgets():
            widget.set_wrap_enabled(checked)

    def _detail_widgets(self) -> list[DetailTextEdit]:
        return [
            self.request_headers,
            self.request_query,
            self.request_cookies,
            self.request_body,
            self.request_saml,
            self.response_headers,
            self.response_params,
            self.response_cookies,
            self.response_body,
        ]

    def _set_checked_syntax_color_theme(self, theme_name: str) -> None:
        for name, action in self._syntax_theme_actions.items():
            action.blockSignals(True)
            action.setChecked(name == theme_name)
            action.blockSignals(False)

    def _restore_syntax_color_theme(self) -> None:
        self.settings.beginGroup(SETTINGS_GROUP)
        saved_theme = str(self.settings.value("syntax_color_theme", DEFAULT_SYNTAX_COLOR_THEME))
        self.settings.endGroup()
        self._set_syntax_color_theme(saved_theme, save=False)

    def _set_syntax_color_theme(self, theme_name: str, save: bool = True) -> None:
        if theme_name not in SYNTAX_COLOR_THEMES:
            theme_name = DEFAULT_SYNTAX_COLOR_THEME
        self._syntax_color_theme = theme_name
        self._set_checked_syntax_color_theme(theme_name)
        for widget in self._detail_widgets():
            widget.set_syntax_theme(self._is_dark_theme, theme_name)
        if save:
            self.settings.beginGroup(SETTINGS_GROUP)
            self.settings.setValue("syntax_color_theme", theme_name)
            self.settings.endGroup()
            self.statusBar().showMessage(f"Text color theme: {theme_name}", 2500)

    def _show_about(self) -> None:
        QMessageBox.information(
            self,
            "About Harshark Next",
            (
                f"Harshark Next {APP_VERSION}\n\n"
                "A modernized offline HAR viewer inspired by the original Harshark project.\n"
                "Built with PySide6, live macOS light/dark mode handling, status color coding, and saved table layout preferences.\n"
                "Credit to @MarcoPolo (GitHub) for the original Harshark project.\n"
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
        self._save_window_state()
        self._stop_mcp_service()
        if self._theme_thread is not None:
            self._theme_thread.quit()
            self._theme_thread.wait(1000)
        super().closeEvent(event)

    def _start_mcp_service(self) -> None:
        if self._mcp_service is not None:
            self._set_mcp_status(True)
            return
        try:
            from .mcp_server import DEFAULT_HOST, DEFAULT_PORT, HarMcpServer, McpTcpService

            self._mcp_server = HarMcpServer()
            self._mcp_service = McpTcpService(self._mcp_server, DEFAULT_HOST, DEFAULT_PORT)
            port = self._mcp_service.start()
            self._set_mcp_status(True)
            self.statusBar().showMessage(f"MCP service listening on {DEFAULT_HOST}:{port}", 5000)
        except Exception as exc:
            self._mcp_server = None
            self._mcp_service = None
            self._set_mcp_status(False)
            self.statusBar().showMessage(f"MCP service unavailable: {type(exc).__name__}: {exc}", 8000)

    def _stop_mcp_service(self) -> None:
        if self._mcp_service is not None:
            self._mcp_service.stop()
            self._mcp_service = None
        self._mcp_server = None
        self._set_mcp_status(False)

    def _toggle_mcp_service(self) -> None:
        if self._mcp_service is None:
            self._start_mcp_service()
        else:
            self._stop_mcp_service()
            self.statusBar().showMessage("MCP service stopped", 5000)

    def _set_mcp_status(self, active: bool) -> None:
        if not hasattr(self, "mcp_status_button"):
            return
        if active:
            self.mcp_status_button.setText("MCP Server: active")
            self.mcp_status_button.setStyleSheet(
                "QPushButton { color: #1b5e20; background: #dff6dd; border: 1px solid #2e7d32; "
                "border-radius: 6px; padding: 3px 8px; font-weight: 600; }"
                "QPushButton:hover { background: #c9efc8; }"
            )
            self.mcp_status_button.setToolTip("MCP server is active. Click to stop it.")
        else:
            self.mcp_status_button.setText("MCP Server: inactive")
            self.mcp_status_button.setStyleSheet(
                "QPushButton { color: #7f1d1d; background: #fde2e2; border: 1px solid #c62828; "
                "border-radius: 6px; padding: 3px 8px; font-weight: 600; }"
                "QPushButton:hover { background: #f9cccc; }"
            )
            self.mcp_status_button.setToolTip("MCP server is inactive. Click to start it.")

    def _build_palette(self, dark: bool) -> QPalette:
        palette = QPalette()
        if dark:
            palette.setColor(QPalette.Window, QColor("#1e1f22"))
            palette.setColor(QPalette.WindowText, QColor("#e8e8e8"))
            palette.setColor(QPalette.Base, QColor("#25262b"))
            palette.setColor(QPalette.AlternateBase, QColor("#20242c"))
            palette.setColor(QPalette.ToolTipBase, QColor("#25262b"))
            palette.setColor(QPalette.ToolTipText, QColor("#f2f2f2"))
            palette.setColor(QPalette.Text, QColor("#e8e8e8"))
            palette.setColor(QPalette.Button, QColor("#2d2f36"))
            palette.setColor(QPalette.ButtonText, QColor("#e8e8e8"))
            palette.setColor(QPalette.BrightText, QColor("#ffffff"))
            palette.setColor(QPalette.Highlight, QColor("#0a84ff"))
            palette.setColor(QPalette.HighlightedText, QColor("#ffffff"))
            palette.setColor(QPalette.Link, QColor("#4da3ff"))
            palette.setColor(QPalette.PlaceholderText, QColor("#9aa0aa"))
        else:
            palette.setColor(QPalette.Window, QColor("#f5f5f7"))
            palette.setColor(QPalette.WindowText, QColor("#1f2328"))
            palette.setColor(QPalette.Base, QColor("#ffffff"))
            palette.setColor(QPalette.AlternateBase, QColor("#f6f8fa"))
            palette.setColor(QPalette.ToolTipBase, QColor("#ffffff"))
            palette.setColor(QPalette.ToolTipText, QColor("#1f2328"))
            palette.setColor(QPalette.Text, QColor("#1f2328"))
            palette.setColor(QPalette.Button, QColor("#f6f8fa"))
            palette.setColor(QPalette.ButtonText, QColor("#1f2328"))
            palette.setColor(QPalette.BrightText, QColor("#000000"))
            palette.setColor(QPalette.Highlight, QColor("#0a84ff"))
            palette.setColor(QPalette.HighlightedText, QColor("#ffffff"))
            palette.setColor(QPalette.Link, QColor("#0969da"))
            palette.setColor(QPalette.PlaceholderText, QColor("#6e7781"))
        return palette

    def _refresh_widget_tree(self) -> None:
        app = QApplication.instance()
        if app is None:
            return
        self.style().unpolish(self)
        self.style().polish(self)
        for widget in app.allWidgets():
            widget.style().unpolish(widget)
            widget.style().polish(widget)
            widget.update()
        self.table.viewport().update()
        self.menuBar().update()
        self.statusBar().update()

    def _apply_theme(self, theme: str) -> None:
        app = QApplication.instance()
        if app is None:
            return

        dark = theme == "dark"
        self._is_dark_theme = dark
        app.setStyle(QStyleFactory.create("Fusion"))
        app.setPalette(self._build_palette(dark))

        if dark:
            app.setStyleSheet(
                """
                QMainWindow, QWidget {
                    background: #1e1f22;
                    color: #e8e8e8;
                }
                QMenuBar, QMenu, QToolBar, QStatusBar {
                    background: #1e1f22;
                    color: #e8e8e8;
                }
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
                QTabBar::tab:selected {
                    background: #25262b;
                    color: #ffffff;
                }
                """
            )
        else:
            app.setStyleSheet(
                """
                QLineEdit, QPlainTextEdit, QTableView, QTabWidget::pane {
                    background: white;
                    color: #1f2328;
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
                    color: #1f2328;
                }
                QTabBar::tab {
                    background: #f6f8fa;
                    color: #1f2328;
                    padding: 8px 12px;
                    border: 1px solid #d0d7de;
                    border-bottom: none;
                    border-top-left-radius: 6px;
                    border-top-right-radius: 6px;
                }
                QTabBar::tab:selected {
                    background: white;
                    color: #1f2328;
                }
                """
            )

        self._refresh_widget_tree()
        for widget in self._detail_widgets():
            widget.set_syntax_theme(dark, self._syntax_color_theme)
        self.table.viewport().update()

    def _apply_special_column_behavior(self) -> None:
        waterfall_index = self.model.columns.index("Waterfall")
        self.table.setItemDelegateForColumn(waterfall_index, self._waterfall_delegate)

    def _show_header_menu(self, position) -> None:
        menu = QMenu(self)
        for column in self.model.columns:
            menu.addAction(self._column_actions[column])
        menu.addSeparator()
        width_menu = menu.addMenu("Column Width Preset")
        for preset_name in COLUMN_WIDTH_PRESETS:
            width_menu.addAction(self._width_preset_actions[preset_name])
        menu.addSeparator()
        menu.addAction(self.reset_columns_action)
        header = self.table.horizontalHeader()
        menu.exec(header.mapToGlobal(position))

    def _show_entry_copy_menu(self, position) -> None:
        index = self.table.indexAt(position)
        if index.isValid():
            self.table.setCurrentIndex(index)
            self.table.selectRow(index.row())
            entry = self.model.entry_at(index.row())
            selected_column = self.model.columns[index.column()]
            selected_field = COLUMN_COPY_FIELD_MAP.get(selected_column)
        else:
            entry = self._current_entry
            selected_field = None

        if entry is None:
            return

        menu = self._build_copy_menu(entry, selected_field)
        menu.exec(self.table.viewport().mapToGlobal(position))

    def _show_detail_copy_menu(self, widget: QPlainTextEdit, position) -> None:
        if self._current_entry is None:
            return

        selected_field = self._request_widget_field_map.get(widget) or self._response_widget_field_map.get(widget)
        selected_spec = None
        if selected_field is not None:
            selected_spec = next((spec for spec in COPY_FIELD_SPECS if spec[1] == selected_field), None)

        selected_text = widget.textCursor().selectedText().replace("\u2029", "\n")
        extra_action = ("Selected Text", selected_text) if selected_text else None
        menu = self._build_copy_menu(self._current_entry, selected_spec, extra_action)
        menu.exec(widget.mapToGlobal(position))

    def _build_copy_menu(
        self,
        entry: HarEntry,
        selected_field: tuple[str, str] | None = None,
        extra_after_first: tuple[str, str] | None = None,
    ) -> QMenu:
        menu = QMenu(self)
        specs = COPY_FIELD_SPECS[:]
        if selected_field is not None:
            specs = [selected_field] + [spec for spec in specs if spec[1] != selected_field[1]]

        for index, (label, attr_name) in enumerate(specs):
            value = self._copy_value(entry, attr_name)
            action = QAction(f"Copy {label}", self)
            action.setEnabled(bool(value))
            action.triggered.connect(
                lambda _checked=False, text=value, field_label=label: self._copy_to_clipboard(text, field_label)
            )
            menu.addAction(action)
            if index == 0 and selected_field is not None:
                if extra_after_first is not None:
                    extra_label, extra_text = extra_after_first
                    extra_action = QAction(f"Copy {extra_label}", self)
                    extra_action.triggered.connect(
                        lambda _checked=False, text=extra_text, field_label=extra_label: self._copy_to_clipboard(
                            text,
                            field_label,
                        )
                    )
                    menu.addAction(extra_action)
                menu.addSeparator()

        menu.addSeparator()
        raw_action = QAction("Copy Raw Entry JSON", self)
        raw_text = json.dumps(entry.raw, indent=2, ensure_ascii=False)
        raw_action.triggered.connect(
            lambda _checked=False, text=raw_text: self._copy_to_clipboard(text, "Raw Entry JSON")
        )
        menu.addAction(raw_action)
        return menu

    def _copy_value(self, entry: HarEntry, attr_name: str) -> str:
        value = getattr(entry, attr_name, "")
        return str(value) if value is not None else ""

    def _copy_to_clipboard(self, text: str, label: str) -> None:
        clipboard = QApplication.clipboard()
        clipboard.setText(text)
        self.statusBar().showMessage(f"Copied {label}", 2500)

    def _set_column_visible(self, logical_index: int, visible: bool) -> None:
        currently_visible = sum(not self.table.isColumnHidden(i) for i in range(self.model.columnCount()))
        if not visible and currently_visible <= 1:
            action = self._column_actions[self.model.columns[logical_index]]
            action.blockSignals(True)
            action.setChecked(True)
            action.blockSignals(False)
            return
        self.table.setColumnHidden(logical_index, not visible)
        self._save_column_state()

    def _set_checked_width_preset(self, preset_name: str) -> None:
        for name, action in self._width_preset_actions.items():
            action.blockSignals(True)
            action.setChecked(name == preset_name)
            action.blockSignals(False)

    def _apply_column_width_preset(self, preset_name: str) -> None:
        widths = COLUMN_WIDTH_PRESETS[preset_name]
        for column, width in widths.items():
            logical_index = self.model.columns.index(column)
            self.table.setColumnWidth(logical_index, width)
        self._set_checked_width_preset(preset_name)
        self.settings.beginGroup(SETTINGS_GROUP)
        self.settings.setValue("width_preset", preset_name)
        self.settings.endGroup()
        self._save_column_state()

    def _reset_columns_to_default(self, save: bool = True) -> None:
        header = self.table.horizontalHeader()
        for index, column in enumerate(DEFAULT_COLUMNS):
            current_logical = self.model.columns.index(column)
            header.moveSection(header.visualIndex(current_logical), index)
            self.table.setColumnHidden(current_logical, False)
            action = self._column_actions[column]
            action.blockSignals(True)
            action.setChecked(True)
            action.blockSignals(False)
        self._apply_column_width_preset(DEFAULT_WIDTH_PRESET)
        if save:
            self._save_column_state()

    def _restore_window_state(self) -> None:
        self.settings.beginGroup(SETTINGS_GROUP)
        geometry = self.settings.value("geometry")
        if geometry is not None:
            self.restoreGeometry(geometry)
        splitter_state = self.settings.value("splitter")
        if splitter_state is not None:
            self.main_splitter.restoreState(splitter_state)
        self.settings.endGroup()
        self._restore_column_state()

    def _save_window_state(self) -> None:
        self.settings.beginGroup(SETTINGS_GROUP)
        self.settings.setValue("geometry", self.saveGeometry())
        self.settings.setValue("splitter", self.main_splitter.saveState())
        self.settings.endGroup()
        self._save_column_state()

    def _restore_column_state(self) -> None:
        self.settings.beginGroup(SETTINGS_GROUP)
        stored_layout_version = self.settings.value("layout_version", 0)
        header_state = self.settings.value("header_state")
        hidden_columns = self.settings.value("hidden_columns", [])
        width_preset = self.settings.value("width_preset", DEFAULT_WIDTH_PRESET)
        self.settings.endGroup()

        use_saved_header_state = False
        try:
            use_saved_header_state = int(stored_layout_version) == SETTINGS_LAYOUT_VERSION and isinstance(
                header_state, QByteArray
            )
        except Exception:
            use_saved_header_state = False

        if use_saved_header_state:
            use_saved_header_state = self.table.horizontalHeader().restoreState(header_state)

        if not use_saved_header_state:
            self._reset_columns_to_default(save=False)
        else:
            self._set_checked_width_preset(str(width_preset))

        if isinstance(hidden_columns, str):
            hidden_columns = [hidden_columns]
        hidden_set = set(hidden_columns or [])
        for index, column in enumerate(self.model.columns):
            hidden = column in hidden_set
            self.table.setColumnHidden(index, hidden)
            action = self._column_actions[column]
            action.blockSignals(True)
            action.setChecked(not hidden)
            action.blockSignals(False)

        self._apply_special_column_behavior()

    def _save_column_state(self, *_args) -> None:
        hidden_columns = [
            column for index, column in enumerate(self.model.columns) if self.table.isColumnHidden(index)
        ]
        self.settings.beginGroup(SETTINGS_GROUP)
        self.settings.setValue("layout_version", SETTINGS_LAYOUT_VERSION)
        self.settings.setValue("header_state", self.table.horizontalHeader().saveState())
        self.settings.setValue("hidden_columns", hidden_columns)
        self.settings.endGroup()

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
        if self._load_thread is not None and self._load_thread.isRunning():
            self.statusBar().showMessage("A HAR file is already loading", 3000)
            return

        # Results from a search against the previous HAR must never replace this file's rows.
        self._filter_serial += 1
        self._filter_timer.stop()
        self.statusBar().showMessage(f"Loading {path.name}…")
        self.summary_label.setText(f"Loading {path.name}…")
        self._load_thread = QThread(self)
        self._load_worker = HarLoadWorker(path)
        self._load_worker.moveToThread(self._load_thread)
        self._load_thread.started.connect(self._load_worker.run)
        self._load_worker.loaded.connect(self._har_loaded)
        self._load_worker.failed.connect(self._har_load_failed)
        self._load_worker.loaded.connect(lambda *_args: self._load_thread and self._load_thread.quit())
        self._load_worker.failed.connect(lambda *_args: self._load_thread and self._load_thread.quit())
        self._load_thread.finished.connect(self._load_worker.deleteLater)
        self._load_thread.finished.connect(self._load_thread_finished)
        self._load_thread.start()

    def _load_thread_finished(self) -> None:
        if self._load_thread is not None:
            self._load_thread.deleteLater()
        self._load_thread = None
        self._load_worker = None

    def _har_loaded(self, path_text: str, entries: list[HarEntry]) -> None:
        path = Path(path_text)

        self.current_path = path
        self.model.set_entries(entries)
        if self._mcp_server is not None:
            self._mcp_server.set_loaded_har(path, entries)
        self.summary_label.setText(f"{path.name} — {len(entries)} entries loaded")
        self.statusBar().showMessage(f"Loaded {path}", 5000)
        self._restore_column_state()
        if entries:
            self.table.selectRow(0)
            self._display_entry(entries[0])
        else:
            self._clear_details()
        self.table.viewport().update()
        if self.search_box.text().strip():
            self._search_changed(self.search_box.text())

    def _har_load_failed(self, _path_text: str, error: str) -> None:
        QMessageBox.critical(self, "Failed to open HAR", error)
        if self.current_path is None:
            self.summary_label.setText("Open a HAR file to begin.")

    def _search_changed(self, text: str) -> None:
        self._filter_serial += 1
        self._pending_filter_query = text.strip()
        self._filter_timer.start(SEARCH_DEBOUNCE_MS)
        self.statusBar().showMessage("Filtering entries…")

    def _run_scheduled_filter(self) -> None:
        if self._filter_thread is not None and self._filter_thread.isRunning():
            return

        query = self._pending_filter_query
        if not query:
            self._apply_filtered_entries(self._filter_serial, query, self.model.entries[:])
            return

        self._filter_thread = QThread(self)
        self._filter_worker = EntryFilterWorker(self._filter_serial, query, self.model.entries)
        self._filter_worker.moveToThread(self._filter_thread)
        self._filter_thread.started.connect(self._filter_worker.run)
        self._filter_worker.filtered.connect(self._filtered_entries_ready)
        self._filter_worker.filtered.connect(lambda *_args: self._filter_thread and self._filter_thread.quit())
        self._filter_thread.finished.connect(self._filter_worker.deleteLater)
        self._filter_thread.finished.connect(self._filter_thread_finished)
        self._filter_thread.start()

    def _filter_thread_finished(self) -> None:
        if self._filter_thread is not None:
            self._filter_thread.deleteLater()
        self._filter_thread = None
        self._filter_worker = None
        if self._pending_filter_query != self.model.query:
            self._filter_timer.start(1)

    def _filtered_entries_ready(self, serial: int, query: str, entries: list[HarEntry]) -> None:
        if serial != self._filter_serial:
            return
        self._apply_filtered_entries(serial, query, entries)

    def _apply_filtered_entries(self, serial: int, query: str, entries: list[HarEntry]) -> None:
        if serial != self._filter_serial:
            return
        self.model.set_filtered_entries(entries, query)
        self.summary_label.setText(
            f"{self.current_path.name if self.current_path else 'No file'} — {len(entries)} visible entries"
        )
        if entries:
            self.table.selectRow(0)
            self._display_entry(entries[0])
        else:
            self._clear_details()
        self.table.viewport().update()
        self.statusBar().showMessage("", 1)

    def _table_row_changed(self, current: QModelIndex, _previous: QModelIndex) -> None:
        entry = self.model.entry_at(current.row())
        if entry is not None:
            self._display_entry(entry)

    def _display_entry(self, entry: HarEntry) -> None:
        self._current_entry = entry
        self._refresh_active_detail_tabs()

    def _active_detail_tab_changed(self, _index: int) -> None:
        self._refresh_active_detail_tabs()

    def _refresh_active_detail_tabs(self) -> None:
        if self._current_entry is None:
            return

        request_widget = self.request_tabs.currentWidget()
        if isinstance(request_widget, DetailTextEdit):
            request_field = self._request_widget_field_map.get(request_widget)
            if request_field is not None:
                text = str(getattr(self._current_entry, request_field, ""))
                request_widget.render_text(text, _detail_syntax_kind(request_field, text))

        response_widget = self.response_tabs.currentWidget()
        if isinstance(response_widget, DetailTextEdit):
            response_field = self._response_widget_field_map.get(response_widget)
            if response_field is not None:
                text = str(getattr(self._current_entry, response_field, ""))
                response_widget.render_text(text, _detail_syntax_kind(response_field, text))

    def _clear_details(self) -> None:
        self._current_entry = None
        for widget in self._detail_widgets():
            widget.clear_rendered_text()


def _fmt_pairs(items: list[dict[str, Any]] | None, key_name: str = "name", value_name: str = "value") -> str:
    if not items:
        return ""
    lines = []
    for item in items:
        key = str(item.get(key_name, ""))
        value = _stringify_value(item.get(value_name, ""))
        lines.append(f"{key}: {value}")
    return "\n".join(lines)


def _fmt_har_params(items: list[dict[str, Any]] | None) -> str:
    if not items:
        return ""
    lines: list[str] = []
    for item in items:
        name = str(item.get("name", ""))
        details: list[str] = []
        value = item.get("value")
        file_name = item.get("fileName")
        content_type = item.get("contentType")

        if value not in (None, ""):
            details.append(f"value={_stringify_value(value)}")
        if file_name:
            details.append(f"filename={file_name}")
        if content_type:
            details.append(f"content-type={content_type}")
        if not details:
            details.append("present")

        lines.append(f"{name}: {', '.join(details)}")
    return "\n".join(lines)


def _fmt_query_from_url(url: str) -> str:
    parsed = urlparse(url)
    parts = parse_qsl(parsed.query, keep_blank_values=True)
    if not parts:
        return ""
    return "\n".join(f"{k}: {_stringify_value(v)}" for k, v in parts)


def _stringify_value(value: Any) -> str:
    if isinstance(value, (dict, list)):
        try:
            return json.dumps(value, ensure_ascii=False)
        except Exception:
            return str(value)
    return str(value)


def _join_sections(sections: list[tuple[str, str]]) -> str:
    chunks = [f"{title}\n{body}" for title, body in sections if body]
    return "\n\n".join(chunks)


def _is_json_text(text: str) -> bool:
    stripped = text.lstrip()
    return bool(stripped) and stripped[0] in "{["


def _detail_syntax_kind(field_name: str, text: str) -> str:
    if field_name.endswith("_headers"):
        return "headers"
    return "json" if _is_json_text(text) else "plain"


def _maybe_pretty_json(text: str, mime_hint: str) -> str:
    stripped = text.strip()
    if not stripped:
        return text
    hinted_json = "json" in mime_hint.lower()
    if not hinted_json and stripped[0] not in "{[":
        return text
    try:
        payload = json.loads(stripped)
    except Exception:
        return text
    try:
        return json.dumps(payload, indent=2, ensure_ascii=False)
    except Exception:
        return text


def _is_probably_binary(raw: bytes, mime_hint: str) -> bool:
    mime = mime_hint.lower()
    if "application/octet-stream" in mime:
        return True
    if mime and "json" not in mime and "xml" not in mime and "text/" not in mime and "javascript" not in mime:
        if any(token in mime for token in ("image/", "audio/", "video/", "font/", "application/pdf", "protobuf")):
            return True

    sample = raw[:8192]
    if not sample:
        return False
    if b"\x00" in sample:
        return True
    controls = sum(b < 32 and b not in (9, 10, 13) for b in sample)
    return (controls / len(sample)) > 0.20


def _decode_bytes_to_text(raw: bytes, mime_hint: str) -> str:
    if _is_probably_binary(raw, mime_hint):
        mime = mime_hint or "unknown"
        return f"[Binary content omitted from text view: {len(raw):,} bytes, mime={mime}]"

    for encoding in ("utf-8", "utf-16"):
        try:
            return raw.decode(encoding)
        except Exception:
            continue
    return raw.decode("utf-8", errors="replace")


def _redact_multipart_binary_parts(text: str, mime_hint: str) -> str:
    if "multipart/form-data" not in mime_hint.lower():
        return text
    if "application/octet-stream" not in text.lower():
        return text

    newline = "\r\n" if "\r\n" in text else "\n"
    boundary = ""
    for line in text.splitlines():
        if line.startswith("--"):
            boundary = line.strip()
            break
    if not boundary:
        return text

    header_sep = f"{newline}{newline}"
    chunks = text.split(boundary)
    rebuilt: list[str] = []
    for index, chunk in enumerate(chunks):
        if index == 0:
            rebuilt.append(chunk)
            continue
        if "application/octet-stream" not in chunk.lower():
            rebuilt.append(boundary + chunk)
            continue

        split_at = chunk.find(header_sep)
        if split_at == -1:
            rebuilt.append(boundary + chunk)
            continue
        headers = chunk[:split_at]
        trailing = chunk[split_at + len(header_sep) :]
        replacement = (
            f"{headers}{header_sep}"
            "[Binary multipart payload omitted from text view]"
        )
        if trailing.endswith("--"):
            replacement += "--"
        rebuilt.append(boundary + replacement)
    return "".join(rebuilt)


def _extract_body_text(blob: dict[str, Any] | None, mime_hint: str = "") -> str:
    if not blob:
        return ""
    raw_text = blob.get("text", "")
    if raw_text is None:
        return ""
    encoding = str(blob.get("encoding", "")).lower()
    effective_mime = mime_hint or str(blob.get("mimeType", ""))
    text = str(raw_text)

    if encoding == "base64":
        try:
            decoded = base64.b64decode(text, validate=False)
            text = _decode_bytes_to_text(decoded, effective_mime)
        except (binascii.Error, ValueError):
            pass

    text = _redact_multipart_binary_parts(text, effective_mime)
    return _maybe_pretty_json(text, effective_mime)


def _extract_saml(text: str) -> str:
    if not text:
        return ""
    if len(text) > MAX_SAML_PARSE_CHARS:
        return (
            f"SAML parsing skipped for stability ({len(text):,} characters; "
            f"limit is {MAX_SAML_PARSE_CHARS:,})."
        )
    if "<saml" not in text.lower() and "samlresponse" not in text.lower() and "samlrequest" not in text.lower():
        return ""

    try:
        parser = etree.XMLParser(remove_blank_text=True, recover=True)
        root = etree.fromstring(text.encode("utf-8"), parser=parser)
        return etree.tostring(root, pretty_print=True, encoding="unicode")
    except Exception:
        pass

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


def _normalize_ms(value: Any) -> tuple[str, float]:
    try:
        numeric = float(value)
    except Exception:
        text = str(value or "")
        return text, 0.0

    if numeric.is_integer():
        return str(int(numeric)), numeric
    return f"{numeric:.2f}", numeric


def parse_har(payload: dict[str, Any]) -> list[HarEntry]:
    log = payload.get("log", {})
    raw_entries = log.get("entries", [])
    entries: list[HarEntry] = []

    for item in raw_entries:
        request = item.get("request", {})
        response = item.get("response", {})
        request_post = request.get("postData", {})
        response_content = response.get("content", {})
        url = str(request.get("url", ""))
        parsed = urlparse(url)

        query_params = _fmt_pairs(request.get("queryString")) or _fmt_query_from_url(url)
        body_params = _fmt_har_params(request_post.get("params"))
        request_params = _join_sections(
            [("Query Parameters", query_params), ("Body Parameters", body_params)]
        )
        if not request_params:
            request_params = query_params

        body_text = _extract_body_text(request_post, mime_hint=str(request_post.get("mimeType", "")))
        response_text = _extract_body_text(response_content, mime_hint=str(response_content.get("mimeType", "")))
        response_params = _fmt_har_params(response_content.get("params"))
        protocol = parsed.scheme.upper() if parsed.scheme else ""
        total_time_text, total_time_value = _normalize_ms(item.get("time", ""))

        entry = HarEntry(
            started=_timestamp(str(item.get("startedDateTime", ""))),
            method=str(request.get("method", "")),
            status=str(response.get("status", "")),
            protocol=protocol,
            host=parsed.hostname or "",
            path=parsed.path or "/",
            mime_type=str(response_content.get("mimeType", "")),
            total_time_ms=total_time_text,
            total_time_value=total_time_value,
            request_headers=_fmt_pairs(request.get("headers")),
            request_query=request_params,
            request_cookies=_fmt_pairs(request.get("cookies")),
            request_body=body_text,
            request_saml=_extract_saml(body_text),
            response_headers=_fmt_pairs(response.get("headers")),
            response_params=response_params,
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
    app.setOrganizationName("teezyyoxo")
    window = MainWindow()
    window.show()
    sys.exit(app.exec())
