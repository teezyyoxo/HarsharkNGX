import AppKit
import SwiftUI

struct InspectorPane: View {
    let entry: HAREntry
    let response: Bool
    @Binding var tab: HARDetailTab
    let workspace: Workspace
    @AppStorage("wordWrap") private var wordWrap = true
    @AppStorage("syntaxTheme") private var syntaxTheme = "Default"
    @AppStorage("prettyPrint") private var pretty = true
    @AppStorage("previewMiB") private var previewMiB = 8
    @AppStorage("syntaxHighlighting") private var highlighting = true
    @AppStorage("colorizeStatus") private var colorizeStatus = true
    @State private var detail = HARDetail()
    @State private var loading = false
    @State private var page = 0
    private let pageSize = 100_000
    @Environment(\.colorScheme) private var colorScheme

    private var request: DetailRequest {
        DetailRequest(id: entry.id, tab: tab, pretty: pretty, response: response, previewBytes: min(32, max(1, previewMiB)) * 1_048_576)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(response ? "Response" : "Request", systemImage: response ? "arrow.down.left" : "arrow.up.right")
                    .font(.headline)
                Spacer()
                Text(entry.method)
                    .font(.callout.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                if response {
                    Text(entry.status.map(String.init) ?? "—")
                        .font(.callout.monospaced().weight(.semibold))
                        .foregroundStyle(Color(nsColor: colorizeStatus ? NativeColors.status(entry.status ?? 0) : .labelColor))
                }
                Menu {
                    Toggle("Pretty Print JSON", isOn: $pretty)
                    Toggle("Word Wrap", isOn: $wordWrap)
                    Divider()
                    Button("Copy Visible Text") { copy(String(detail.text.dropFirst(page * pageSize).prefix(pageSize))) }.disabled(detail.text.isEmpty)
                    Button("Copy URL") { copy(entry.url) }
                    Button("Export Body…") { workspace.exportBody(response ? entry.responseBody : entry.requestBody) }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Inspector options").accessibilityLabel(response ? "Response options" : "Request options")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            ScrollView(.horizontal) {
                HStack(spacing: 3) {
                    ForEach(HARDetailTab.allCases.filter { !response || $0 != .saml }) { item in
                        Button { tab = item } label: {
                            Text(item.rawValue)
                                .font(.callout.weight(tab == item ? .semibold : .regular))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(tab == item ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(tab == item ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("\(response ? "response" : "request")\(item.rawValue)")
                        .accessibilityAddTraits(tab == item ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            Divider()
            if loading {
                ProgressView("Preparing \(tab.rawValue.lowercased())…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if detail.text.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: tab == .body ? "doc.text" : "info.circle").font(.title2)
                    Text(detail.notice).multilineTextAlignment(.center).textSelection(.enabled)
                }
                .foregroundStyle(.secondary).padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if !detail.notice.isEmpty {
                    Label(detail.notice, systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary).padding(10)
                }
                DetailTextView(text: String(detail.text.dropFirst(page * pageSize).prefix(pageSize)),
                               syntax: highlighting ? detail.syntax : "plain", wrap: wordWrap,
                               theme: syntaxTheme, dark: colorScheme == .dark)
                    .accessibilityIdentifier(response ? "responseText" : "requestText")
                if detail.text.count > pageSize {
                    HStack {
                        Button("Previous") { page -= 1 }.disabled(page == 0)
                        Text("Page \(page + 1) of \((detail.text.count + pageSize - 1) / pageSize)")
                        Button("Next") { page += 1 }
                            .disabled((page + 1) * pageSize >= detail.text.count)
                        Spacer()
                        Text("Export Body saves all content").lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption).padding(8)
                }
            }
        }
        .background(.background)
        .task(id: request) {
            // Finish small previews in one UI update, without publishing a loading state.
            if let immediate = InspectorPreparation.immediateDetail(entry: entry, response: response,
                    tab: request.tab, pretty: request.pretty, maximumBodyBytes: request.previewBytes) {
                page = 0
                detail = immediate
                loading = false
                return
            }
            loading = true
            page = 0
            detail = HARDetail()
            let worker = Task.detached(priority: .userInitiated) {
                HARFormatter.detail(entry: entry, response: response, tab: request.tab, pretty: request.pretty, maximumBodyBytes: request.previewBytes)
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            detail = result
            loading = false
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum InspectorPreparation {
    static func immediateDetail(entry: HAREntry, response: Bool, tab: HARDetailTab,
                                pretty: Bool, maximumBodyBytes: Int) -> HARDetail? {
        // Bound synchronous decoding and formatting, including lazy file-backed text.
        // Larger entries continue through the cancellable background path.
        guard JSONValue.object(entry.raw).fitsJSONBudget(64 * 1024) else { return nil }
        return HARFormatter.detail(entry: entry, response: response, tab: tab,
                                   pretty: pretty, maximumBodyBytes: maximumBodyBytes)
    }
}

private struct DetailRequest: Equatable {
    let id: HAREntryID
    let tab: HARDetailTab
    let pretty: Bool
    let response: Bool
    let previewBytes: Int
}

struct DetailTextView: NSViewRepresentable {
    let text: String
    let syntax: String
    let wrap: Bool
    let theme: String
    let dark: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.allowsUndo = false
        view.isRichText = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isVerticallyResizable = true
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.backgroundColor = .textBackgroundColor
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        scroll.documentView = view
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let key = "\(syntax)|\(theme)|\(dark)"
        if context.coordinator.text != text || context.coordinator.style != key {
            context.coordinator.text = text
            context.coordinator.style = key
            let attributed = NSMutableAttributedString(string: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ])
            // Bound highlighting work. Large bodies remain readable without regex/layout stalls.
            if text.utf8.count <= 256_000 {
                SyntaxColors.highlight(attributed, syntax: syntax, theme: theme, dark: dark)
            }
            view.textStorage?.setAttributedString(attributed)
            view.scrollToBeginningOfDocument(nil)
        }
        let shouldWrap = wrap && text.utf8.count <= 1_048_576
        view.isHorizontallyResizable = !shouldWrap
        view.autoresizingMask = shouldWrap ? [.width] : []
        view.textContainer?.widthTracksTextView = shouldWrap
        view.textContainer?.containerSize = NSSize(
            width: shouldWrap ? max(100, scroll.contentSize.width - 24) : CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        if shouldWrap { view.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(view.frame.height, scroll.contentSize.height))) }
        scroll.hasHorizontalScroller = !shouldWrap
    }

    final class Coordinator {
        var text = ""
        var style = ""
    }
}

enum SyntaxColors {
    static func highlight(_ text: NSMutableAttributedString, syntax: String, theme: String, dark: Bool) {
        let colors = palette(theme, dark: dark)
        let source = text.string as NSString
        let range = NSRange(location: 0, length: source.length)
        if syntax == "json" {
            // A single tokenizer prevents numbers/literals inside strings being recolored.
            let pattern = #""(?:\\.|[^"\\])*"\s*:|"(?:\\.|[^"\\])*"|\b(?:true|false|null)\b|-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for match in regex.matches(in: text.string, range: range) {
                let token = source.substring(with: match.range)
                let index = token.hasSuffix(":") ? 0 : (token.hasPrefix("\"") ? 1 : (["true", "false", "null"].contains(token) ? 3 : 2))
                text.addAttribute(.foregroundColor, value: colors[index], range: match.range)
                if index == 0 { text.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold), range: match.range) }
            }
        } else if syntax == "headers" {
            let rules: [(String, Int)] = [
                (#"https?://[^\s;,]+"#, 1),
                (#"\b(?:application|audio|font|image|multipart|text|video)/[^\s;,]+"#, 2),
                (#"\b[1-5]\d\d\b"#, 4),
                (#"\b(?:no-cache|no-store|max-age|private|public|same-origin|strict|upgrade-insecure-requests)\b"#, 5),
                (#"^:?[^\s:][^:\r\n]*(?=:)"#, 0)
            ]
            for (pattern, color) in rules {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
                for match in regex.matches(in: text.string, range: range) {
                    text.addAttribute(.foregroundColor, value: colors[color], range: match.range)
                }
            }
        }
    }

    private static func palette(_ name: String, dark: Bool) -> [NSColor] {
        let hex: [UInt32]
        switch (name, dark) {
        case ("Nord", false): hex = [0x2e5d74, 0x3d7a5e, 0xa35d2d, 0x7c4d8e, 0xb14c57, 0x7c4d8e]
        case ("Nord", true): hex = [0x88c0d0, 0xa3be8c, 0xebcb8b, 0xb48ead, 0xbf616a, 0xb48ead]
        case ("Solarized", _): hex = [0x268bd2, 0x2aa198, 0xb58900, 0xd33682, 0xdc322f, 0xd33682]
        case ("Monokai", false): hex = [0x0077aa, 0x5f7800, 0x8b4dcc, 0xc92762, 0xc92762, 0x8b4dcc]
        case ("Monokai", true): hex = [0x66d9ef, 0xe6db74, 0xae81ff, 0xf92672, 0xf92672, 0xae81ff]
        case (_, true): hex = [0x79c0ff, 0xa5d6a7, 0xffcc80, 0xf48fb1, 0xf48fb1, 0xc4b5fd]
        default: hex = [0x0550ae, 0x0a7f3f, 0x953800, 0x8250df, 0xcf222e, 0x8250df]
        }
        return hex.map { NSColor(srgbRed: CGFloat(($0 >> 16) & 255) / 255, green: CGFloat(($0 >> 8) & 255) / 255, blue: CGFloat($0 & 255) / 255, alpha: 1) }
    }
}
