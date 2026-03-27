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
from PySide6.QtCore import QByteArray, QAbstractTableModel, QModelIndex, QObject, QRectF, QSettings, Qt, QThread, Signal
from PySide6.QtGui import QAction, QColor, QGuiApplication, QKeySequence, QPainter, QPalette, QTextOption
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

APP_NAME = "HarsharkNGX"
APP_VERSION = "1.3.0"
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
            self.response_cookies,
            self.response_body,
            self.full_url,
        ]
        return "\n".join(part for part in parts if part)


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

    def max_time_ms(self) -> float:
        if not self.filtered_entries:
            return 1.0
        return max(entry.total_time_value for entry in self.filtered_entries) or 1.0


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
        self._waterfall_delegate = WaterfallDelegate(self)
        self.settings = QSettings("Montel G.", APP_NAME)

        self._build_ui()
        self._restore_window_state()
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
        self._build_column_actions()
        self._build_width_preset_actions()
        self._apply_special_column_behavior()

    def _build_menu(self) -> None:
        file_menu = self.menuBar().addMenu("&File")
        self.view_menu = self.menuBar().addMenu("&View")
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
        self.view_menu.addAction(wrap_action)

        self.view_menu.addSeparator()
        self.columns_menu = self.view_menu.addMenu("Columns")
        self.width_presets_menu = self.view_menu.addMenu("Column Width Preset")

        self.reset_columns_action = QAction("Reset Columns to Default", self)
        self.reset_columns_action.triggered.connect(self._reset_columns_to_default)
        self.view_menu.addAction(self.reset_columns_action)

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
        if self._theme_thread is not None:
            self._theme_thread.quit()
            self._theme_thread.wait(1000)
        super().closeEvent(event)

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
        try:
            text = path.read_text(encoding="utf-8")
            payload = json.loads(text)
            entries = parse_har(payload)
        except Exception as exc:
            QMessageBox.critical(self, "Failed to open HAR", f"{type(exc).__name__}: {exc}")
            return

        self.current_path = path
        self.model.set_entries(entries)
        self.summary_label.setText(f"{path.name} — {len(entries)} entries loaded")
        self.statusBar().showMessage(f"Loaded {path}", 5000)
        self._restore_column_state()
        if entries:
            self.table.selectRow(0)
            self._display_entry(entries[0])
        else:
            self._clear_details()
        self.table.viewport().update()

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
        self.table.viewport().update()

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
        url = str(request.get("url", ""))
        parsed = urlparse(url)

        body_text = _extract_body_text(request.get("postData"))
        response_text = _extract_body_text(response.get("content"))
        protocol = parsed.scheme.upper() if parsed.scheme else ""
        total_time_text, total_time_value = _normalize_ms(item.get("time", ""))

        entry = HarEntry(
            started=_timestamp(str(item.get("startedDateTime", ""))),
            method=str(request.get("method", "")),
            status=str(response.get("status", "")),
            protocol=protocol,
            host=parsed.hostname or "",
            path=parsed.path or "/",
            mime_type=str(response.get("content", {}).get("mimeType", "")),
            total_time_ms=total_time_text,
            total_time_value=total_time_value,
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
    app.setOrganizationName("teezyyoxo")
    window = MainWindow()
    window.show()
    sys.exit(app.exec())