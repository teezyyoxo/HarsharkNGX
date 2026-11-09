import AppKit

@MainActor enum CaptureWindowLayout {
    /// Bound measurement work independently of capture size. Full values remain in tooltips.
    static func columnWidths(rows: [HARRow], timestampStyle: String) -> [String: CGFloat] {
        var widths: [String: CGFloat] = [:]
        for (key, title, base) in RequestTable.Coordinator.columns {
            let font = ["status", "method", "duration"].contains(key)
                ? NSFont.monospacedSystemFont(ofSize: 12, weight: key == "status" ? .semibold : .regular)
                : NSFont.systemFont(ofSize: 12)
            var width = max(base, (title as NSString).size(withAttributes: [.font: font]).width + 24)
            if key != "waterfall" {
                for row in rows.prefix(256) {
                    let text = key == "started" && timestampStyle != "ISO" ? "2026-28-12 23:59:59Z" : row.value(for: key)
                    width = max(width, (String(text.prefix(1024)) as NSString).size(withAttributes: [.font: font]).width + 20)
                }
            }
            widths[key] = ceil(width)
        }
        return widths
    }

    static func preferredContentSize(for session: HARSession, defaults: UserDefaults = .standard) -> NSSize {
        let widths = columnWidths(rows: session.rows, timestampStyle: defaults.string(forKey: "timestampStyle") ?? "Local")
        let visible = RequestTable.Coordinator.columns.filter { key, _, _ in
            key == "path" || !((defaults.object(forKey: "columnHidden.\(key)") as? Bool) ?? ["protocol", "size"].contains(key))
        }
        let tableWidth = visible.reduce(CGFloat.zero) { $0 + (widths[$1.0] ?? $1.2) + 10 } + 36
        let tableHeight = preferredTableHeight(for: session, defaults: defaults)
        var inspectorHeight: CGFloat = 0
        if let entry = session.selectedEntry {
            inspectorHeight = [false, true].map { response -> CGFloat in
                guard let detail = InspectorPreparation.immediateDetail(entry: entry, response: response, tab: .body,
                    pretty: defaults.object(forKey: "prettyPrint") as? Bool ?? true, maximumBodyBytes: 64 * 1024) else { return 480 }
                let lines = detail.text.prefix(12_000).split(separator: "\n", omittingEmptySubsequences: false).count
                return CGFloat(min(32, max(8, lines))) * 16 + 130
            }.max() ?? 300
        }
        // Reserve the sidebar and enough space for every request/response tab.
        return NSSize(width: max(1280, tableWidth + 320),
                      height: max(600, tableHeight + inspectorHeight + 190))
    }

    static func preferredTableHeight(for session: HARSession, defaults: UserDefaults = .standard) -> CGFloat {
        let rowHeight: CGFloat = defaults.string(forKey: "tableDensity") == "Compact" ? 23 : 30
        return CGFloat(min(12, max(4, session.rows.count))) * rowHeight + 36
    }

    static func fittingFrame(contentSize: NSSize, window: NSWindow, visibleFrame: NSRect) -> NSRect {
        let available = visibleFrame.insetBy(dx: 12, dy: 12)
        let desired = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        let size = NSSize(width: min(desired.width, available.width), height: min(desired.height, available.height))
        let x = max(available.minX, min(window.frame.minX, available.maxX - size.width))
        let top = max(available.minY + size.height, min(window.frame.maxY, available.maxY))
        return NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }
}
