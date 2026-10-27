import AppKit
import SwiftUI

struct RequestTable: NSViewRepresentable {
    let session: HARSession
    @AppStorage("timestampStyle") private var timestampStyle = "Local"
    @AppStorage("tableDensity") private var density = "Comfortable"
    @AppStorage("colorizeStatus") private var colorize = true
    @AppStorage("columnPreferencesRevision") private var columnRevision = 0

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = FittingTableScrollView()
        let table = NSTableView()
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 29
        table.intercellSpacing = NSSize(width: 10, height: 0)
        table.allowsMultipleSelection = false
        table.allowsColumnReordering = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.autosaveName = "HarsharkRequestColumnsV2"
        table.autosaveTableColumns = true
        table.setAccessibilityIdentifier("requestTable")
        for (key, title, width) in Coordinator.columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
            column.title = title
            column.width = width
            column.minWidth = key == "path" ? 120 : key == "host" ? 90 : 50
            column.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: true)
            table.addTableColumn(column)
        }
        let menu = NSMenu()
        for column in table.tableColumns {
            let item = NSMenuItem(title: column.title, action: #selector(Coordinator.toggleColumn(_:)), keyEquivalent: "")
            item.representedObject = column
            item.target = context.coordinator
            column.isHidden = (UserDefaults.standard.object(forKey: "columnHidden.\(column.identifier.rawValue)") as? Bool) ?? ["protocol", "size"].contains(column.identifier.rawValue)
            item.state = column.isHidden ? .off : .on
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for preset in ["Compact", "Balanced", "Comfortable"] {
            let item = NSMenuItem(title: "\(preset) Widths", action: #selector(Coordinator.widthPreset(_:)), keyEquivalent: "")
            item.representedObject = preset
            item.target = context.coordinator
            menu.addItem(item)
        }
        table.headerView?.menu = menu
        let copyMenu = NSMenu()
        for (label, selector) in [("Copy URL", #selector(Coordinator.copyURL)),
                                  ("Copy Raw Entry JSON", #selector(Coordinator.copyRaw))] {
            let item = NSMenuItem(title: label, action: selector, keyEquivalent: "")
            item.target = context.coordinator
            copyMenu.addItem(item)
        }
        table.menu = copyMenu
        context.coordinator.table = table
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.session = session
        guard let table = coordinator.table else { return }
        let presentation = "\(timestampStyle)|\(density)|\(colorize)|\(columnRevision)"
        let presentationChanged = coordinator.presentation != presentation
        coordinator.presentation = presentation
        coordinator.timestampStyle = timestampStyle
        coordinator.colorize = colorize
        table.rowHeight = density == "Compact" ? 23 : 30
        if presentationChanged {
            for column in table.tableColumns {
                let key = column.identifier.rawValue
                column.isHidden = key == "path" ? false : UserDefaults.standard.bool(forKey: "columnHidden.\(key)")
            }
            for item in table.headerView?.menu?.items ?? [] {
                if let column = item.representedObject as? NSTableColumn {
                    item.state = column.isHidden ? .off : .on
                }
            }
        }
        if coordinator.revision != session.rowRevision || presentationChanged {
            coordinator.revision = session.rowRevision
            coordinator.rows = session.visibleRows
            coordinator.rowIndexes = Dictionary(uniqueKeysWithValues: coordinator.rows.enumerated().map { ($0.element.id, $0.offset) })
            coordinator.updating = true
            table.reloadData()
            coordinator.updating = false
        }
        let selectedIndex = session.selection.flatMap { coordinator.rowIndexes[$0] }
        if table.selectedRow != (selectedIndex ?? -1) {
            coordinator.updating = true
            if let selectedIndex {
                table.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            } else {
                table.deselectAll(nil)
            }
            coordinator.updating = false
        }
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let columns: [(String, String, CGFloat)] = [
            ("started", "Started", 115), ("method", "Method", 65), ("status", "Status", 55),
            ("protocol", "Protocol", 80), ("host", "Host", 165), ("path", "Path", 240),
            ("mime", "MIME Type", 125), ("waterfall", "Waterfall", 130),
            ("duration", "Time", 85), ("size", "Size", 80)
        ]
        var session: HARSession
        var rows: [HARRow] = []
        var rowIndexes: [Int: Int] = [:]
        var revision = -1
        var presentation = ""
        var timestampStyle = "Local"
        var colorize = true
        private let fractionalTimestamp = ISO8601DateFormatter()
        private let timestamp = ISO8601DateFormatter()
        private let localTime: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .medium
            return formatter
        }()
        weak var table: NSTableView?
        var updating = false

        init(session: HARSession) {
            self.session = session
            fractionalTimestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        }

        private func startedText(_ value: String) -> String {
            guard timestampStyle != "ISO",
                  let date = fractionalTimestamp.date(from: value) ?? timestamp.date(from: value) else { return value }
            return localTime.string(from: date)
        }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let tableColumn else { return nil }
            let item = rows[row]
            let key = tableColumn.identifier.rawValue
            if key == "waterfall" {
                let view = (tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? DurationBar) ?? DurationBar()
                view.identifier = tableColumn.identifier
                view.ratio = max(0, item.duration) / session.maximumDuration
                view.status = item.status
                view.colorize = colorize
                view.toolTip = item.value(for: "duration")
                view.setAccessibilityLabel("Duration \(item.value(for: "duration"))")
                view.needsDisplay = true
                return view
            }
            let cell = (tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? RequestTableCell) ?? RequestTableCell()
            cell.identifier = tableColumn.identifier
            if cell.textField == nil {
                let field = NSTextField(labelWithString: "")
                field.translatesAutoresizingMaskIntoConstraints = false
                field.lineBreakMode = .byTruncatingTail
                cell.addSubview(field)
                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                    field.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                    field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
                cell.textField = field
            }
            let field = cell.textField
            field?.stringValue = key == "started" ? startedText(item.started) : item.value(for: key)
            field?.font = ["status", "method", "duration"].contains(key)
                ? .monospacedSystemFont(ofSize: 12, weight: key == "status" ? .semibold : .regular)
                : .systemFont(ofSize: 12)
            cell.normalTextColor = !colorize ? .labelColor : key == "status" ? NativeColors.status(item.status) : key == "method" ? NativeColors.method(item.method) : .labelColor
            field?.setAccessibilityLabel(key == "status" ? "HTTP status \(item.status)" : field?.stringValue)
            cell.toolTip = key == "path" ? item.url : item.value(for: key)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            session.selection = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id : nil
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let sort = tableView.sortDescriptors.first else { return }
            session.sortColumn = sort.key ?? "started"
            session.ascending = sort.ascending
            session.filter()
        }

        @objc func toggleColumn(_ sender: NSMenuItem) {
            guard let column = sender.representedObject as? NSTableColumn, column.identifier.rawValue != "path" else { return }
            if !column.isHidden, table?.tableColumns.filter({ !$0.isHidden }).count == 1 { return }
            column.isHidden.toggle()
            sender.state = column.isHidden ? .off : .on
            UserDefaults.standard.set(column.isHidden, forKey: "columnHidden.\(column.identifier.rawValue)")
            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "columnPreferencesRevision") + 1, forKey: "columnPreferencesRevision")
        }

        @objc func widthPreset(_ sender: NSMenuItem) {
            let scale = sender.representedObject as? String == "Compact" ? 0.75 : (sender.representedObject as? String == "Comfortable" ? 1.25 : 1.0)
            for column in table?.tableColumns ?? [] {
                column.width = (Self.columns.first { $0.0 == column.identifier.rawValue }?.2 ?? 100) * scale
            }
        }

        private var contextRow: HARRow? {
            guard let table else { return nil }
            let index = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
            return rows.indices.contains(index) ? rows[index] : nil
        }

        @objc func copyURL() {
            guard let row = contextRow else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row.url, forType: .string)
        }

        @objc func copyRaw() {
            guard let row = contextRow else { return }
            let raw = JSONValue.object(session.archive.entries[row.id].raw)
            guard raw.fitsJSONBudget(2 * 1_048_576) else {
                Workspace.shared.errorMessage = "Raw entry exceeds the 2 MiB copy limit. Use Export Body to save the payload."
                return
            }
            let text = HARFormatter.json(raw)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

/// AppKit updates backgroundStyle for selection and window focus changes.
final class RequestTableCell: NSTableCellView {
    var normalTextColor: NSColor = .labelColor {
        didSet { updateTextColor() }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateTextColor() }
    }

    private func updateTextColor() {
        textField?.textColor = backgroundStyle == .emphasized
            ? .alternateSelectedControlTextColor : normalTextColor
    }
}

/// Shrink excess column width when the viewport narrows, respecting readable minima.
/// Once the minima are reached, horizontal scrolling remains available for every column.
final class FittingTableScrollView: NSScrollView {
    private var lastWidth: CGFloat = 0
    override func layout() {
        super.layout()
        let available = contentSize.width
        guard abs(available - lastWidth) > 1, available > 0,
              let table = documentView as? NSTableView else { return }
        lastWidth = available
        let columns = table.tableColumns.filter { !$0.isHidden }
        let spacing = CGFloat(columns.count) * table.intercellSpacing.width + 32
        let target = max(0, available - spacing)
        let total = columns.reduce(CGFloat.zero) { $0 + $1.width }
        let minimum = columns.reduce(CGFloat.zero) { $0 + $1.minWidth }
        guard total > target, total > minimum else { return }
        let fraction = max(0, min(1, (target - minimum) / (total - minimum)))
        for column in columns {
            column.width = column.minWidth + (column.width - column.minWidth) * fraction
        }
    }
}

final class DurationBar: NSView {
    var ratio = 0.0
    var status = 0
    var colorize = true
    override func draw(_ dirtyRect: NSRect) {
        let track = bounds.insetBy(dx: 2, dy: 10)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
        guard ratio > 0 else { return }
        var fill = track
        fill.size.width = max(3, track.width * min(ratio, 1))
        (colorize ? NativeColors.status(status) : NSColor.labelColor).setFill()
        NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
    }
}

enum NativeColors {
    static func method(_ value: String) -> NSColor {
        switch value.uppercased() {
        case "GET": return adaptive(light: 0x0550AE, dark: 0x79C0FF)
        case "POST": return status(200)
        case "PUT", "PATCH": return status(400)
        case "DELETE": return status(500)
        default: return .labelColor
        }
    }

    static func status(_ code: Int) -> NSColor {
        switch code {
        case 100..<200: return adaptive(light: 0x6639BA, dark: 0xBC8CFF)
        case 200..<300: return adaptive(light: 0x116329, dark: 0x7EE787)
        case 300..<400: return adaptive(light: 0x7139C9, dark: 0xD2A8FF)
        case 400..<500: return adaptive(light: 0x953800, dark: 0xFFA657)
        case 500..<600: return adaptive(light: 0xCF222E, dark: 0xFF7B72)
        default: return .secondaryLabelColor
        }
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
}
