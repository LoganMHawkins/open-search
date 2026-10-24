import SwiftUI
import AppKit

// MARK: - Glass surfaces

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = 22
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(tint.map { .regular.tint($0.opacity(0.18)) } ?? .regular,
                         in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.caption2) }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(tint.map { .regular.tint($0.opacity(0.30)) } ?? .regular, in: Capsule())
    }
}

/// Wraps children onto new lines, for chips and link rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct ChipFlow: View {
    let items: [String]
    var tint: Color?
    var limit = 14

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.prefix(limit).enumerated()), id: \.offset) { _, item in Chip(text: item, tint: tint) }
            if items.count > limit { Chip(text: "+\(items.count - limit) more") }
        }
    }
}

// MARK: - Text bits

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

struct InfoRow: View {
    let label: String
    let value: String?
    var systemImage: String?

    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(Brand.orange).frame(width: 18)
                }
                Text(label).foregroundStyle(.secondary).frame(width: systemImage == nil ? 110 : 92, alignment: .leading)
                Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout)
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Brand.display(28)).foregroundStyle(Brand.gradient)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minWidth: 96, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Links, images, copying

struct LinkChip: View {
    let urlString: String
    var label: String?

    var body: some View {
        if let url = URL(string: urlString.contains("://") ? urlString : "https://\(urlString)") {
            Link(destination: url) {
                HStack(spacing: 4) {
                    Text(label ?? Self.name(for: url)).lineLimit(1)
                    Image(systemName: "arrow.up.right").font(.caption2.weight(.bold))
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(url.absoluteString)
        }
    }

    static func name(for url: URL) -> String {
        let host = (url.host ?? url.absoluteString).replacingOccurrences(of: "www.", with: "")
        let known: [(String, String)] = [
            ("linkedin.com", "LinkedIn"), ("github.com", "GitHub"), ("x.com", "X"), ("twitter.com", "X"),
            ("facebook.com", "Facebook"), ("instagram.com", "Instagram"), ("youtube.com", "YouTube"),
            ("tiktok.com", "TikTok"), ("medium.com", "Medium"), ("crunchbase.com", "Crunchbase"),
            ("reddit.com", "Reddit"), ("pinterest.com", "Pinterest"), ("dribbble.com", "Dribbble"),
            ("behance.net", "Behance"), ("twitch.tv", "Twitch"), ("discord.com", "Discord"),
        ]
        return known.first { host == $0.0 || host.hasSuffix("." + $0.0) }?.1 ?? host
    }
}

/// Loads an image from the web, including SVG (which `AsyncImage` can't draw), with an in-memory cache.
enum ImageCache {
    static let shared = NSCache<NSURL, NSImage>()
}

struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fit
    var loadedBackground: Color?
    var loadedPadding: CGFloat = 0
    @ViewBuilder var placeholder: Placeholder
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
                    .padding(loadedPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(loadedBackground ?? .clear)
            } else {
                placeholder
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        if let cached = ImageCache.shared.object(forKey: url as NSURL) { image = cached; return }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let loaded = NSImage(data: data), loaded.isValid else { return }
        if loaded.size.width < 1 || loaded.size.height < 1 { loaded.size = NSSize(width: 512, height: 512) }
        ImageCache.shared.setObject(loaded, forKey: url as NSURL)
        image = loaded
    }
}

/// Neutral liquid-glass button that ignores the app tint, for secondary actions beside the orange primary.
struct SoftGlassButtonStyle: ButtonStyle {
    @Environment(\.controlSize) private var size
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let small = size == .small || size == .mini
        configuration.label
            .font(small ? .caption.weight(.medium) : .callout.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, small ? 10 : 14)
            .padding(.vertical, small ? 5 : (size == .large ? 10 : 7))
            .glassEffect(.regular.interactive(), in: Capsule())
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

extension ButtonStyle where Self == SoftGlassButtonStyle {
    static var softGlass: SoftGlassButtonStyle { SoftGlassButtonStyle() }
}

struct Avatar: View {
    let url: String?
    let name: String
    var size: CGFloat = 56
    var round = true

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                RemoteImage(url: u, contentMode: round ? .fill : .fit,
                            loadedBackground: round ? nil : .white, loadedPadding: round ? 0 : size * 0.12) { initials }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: round ? size / 2 : size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }

    private var initials: some View {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return ZStack {
            Brand.gradient.opacity(0.9)
            Text(String(parts).uppercased().isEmpty ? "?" : String(parts).uppercased())
                .font(Brand.display(size * 0.42))
                .foregroundStyle(.white)
        }
    }
}

struct CopyButton: View {
    let text: String
    var label: String?
    var compact = false
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.4)); copied = false }
        } label: {
            if compact {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").contentTransition(.symbolEffect(.replace))
            } else {
                Label(copied ? "Copied" : (label ?? "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.softGlass)
        .controlSize(.small)
    }
}

struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 64

    var body: some View {
        let fraction = min(max(Double(score) / 100, 0), 1)
        ZStack {
            Circle().stroke(.quaternary, lineWidth: size * 0.12)
            Circle().trim(from: 0, to: fraction)
                .stroke(Brand.gradient, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)").font(Brand.display(size * 0.42))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Match score \(score)")
    }
}

// MARK: - Pickers

enum NameKind { case region, language, plain }

func displayName(_ code: String, _ kind: NameKind) -> String {
    switch kind {
    case .region: Locale.current.localizedString(forRegionCode: code.uppercased()) ?? code.uppercased()
    case .language: Locale.current.localizedString(forLanguageCode: code) ?? code
    case .plain: code.prefix(1).uppercased() + code.dropFirst()
    }
}

struct OptionPicker: View {
    let title: String
    @Binding var selection: String
    let codes: [String]
    var kind: NameKind = .region
    var anyLabel = "Any"
    private let sorted: [(code: String, name: String)]

    init(_ title: String, selection: Binding<String>, codes: [String], kind: NameKind = .region, anyLabel: String = "Any") {
        self.title = title
        self._selection = selection
        self.codes = codes
        self.kind = kind
        self.anyLabel = anyLabel
        sorted = codes.map { ($0, displayName($0, kind)) }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Text(anyLabel).tag("")
            Divider()
            ForEach(sorted, id: \.code) { Text($0.name).tag($0.code) }
        }
    }
}

struct MultiPicker: View {
    let title: String
    @Binding var selection: Set<String>
    let codes: [String]
    var kind: NameKind = .region
    var limit: Int?
    var emptyLabel = "Any"
    @State private var open = false
    @State private var search = ""

    private var items: [(code: String, name: String)] {
        codes.map { ($0, displayName($0, kind)) }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.code.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var summary: String {
        switch selection.count {
        case 0: emptyLabel
        case 1: displayName(selection.first!, kind)
        default: "\(selection.count) selected"
        }
    }

    var body: some View {
        LabeledContent(title) {
            Button(summary) { open = true }
                .buttonStyle(.softGlass)
                .controlSize(.small)
                .popover(isPresented: $open, arrowEdge: .bottom) { picker }
        }
    }

    private var picker: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Search", text: $search).textFieldStyle(.roundedBorder)
                if !selection.isEmpty { Button("Clear") { selection = [] }.buttonStyle(.softGlass).controlSize(.small) }
            }
            if let limit { Text("Pick up to \(limit)").font(.caption).foregroundStyle(.secondary) }
            List(items, id: \.code) { item in
                let on = selection.contains(item.code)
                Button {
                    if on { selection.remove(item.code) }
                    else if limit == nil || selection.count < limit! { selection.insert(item.code) }
                } label: {
                    HStack {
                        Text(item.name)
                        Spacer()
                        if on { Image(systemName: "checkmark").foregroundStyle(Brand.orange) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .frame(width: 260, height: 300)
        }
        .padding(12)
    }
}

/// Main text field of a tool, with a menu of recent queries.
struct QueryField: View {
    let tool: Tool
    let title: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var onSubmit: () -> Void = {}
    @State private var recents: [String] = []

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            TextField(title, text: $text, axis: axis)
                .textFieldStyle(.plain)
                .lineLimit(axis == .vertical ? 2...6 : 1...1)
                .onSubmit(onSubmit)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.08)))
            if !recents.isEmpty {
                Menu {
                    ForEach(recents, id: \.self) { r in Button(r) { text = r } }
                    Divider()
                    Button("Clear Recents") { Recents.clear(tool); recents = [] }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Recent")
            }
        }
        .onAppear { recents = Recents.list(tool) }
        .onChange(of: text) { _, _ in recents = Recents.list(tool) }
    }
}

// MARK: - Cross-tool handoff

struct HandoffModifier: ViewModifier {
    @EnvironmentObject private var model: AppModel
    let tool: Tool
    let apply: ([String: String], Bool) -> Void
    @State private var seen: UUID?

    func body(content: Content) -> some View {
        content.onReceive(model.$handoff) { h in
            guard let h, h.tool == tool, h.id != seen else { return }
            seen = h.id
            apply(h.values, h.run)
        }
    }
}

extension View {
    func onHandoff(for tool: Tool, _ apply: @escaping ([String: String], Bool) -> Void) -> some View {
        modifier(HandoffModifier(tool: tool, apply: apply))
    }
}

// MARK: - Misc helpers

/// "c_suite" -> "C-suite", "vp" -> "VP", "business development" -> "Business development".
func prettyLabel(_ raw: String) -> String {
    let acronyms: [String: String] = ["vp": "VP", "svp": "SVP", "evp": "EVP", "cxo": "CXO", "c_suite": "C-suite", "hr": "HR", "it": "IT", "ceo": "CEO", "cto": "CTO", "cfo": "CFO", "coo": "COO"]
    let key = raw.lowercased()
    if let a = acronyms[key] { return a }
    let spaced = raw.replacingOccurrences(of: "_", with: " ")
    return spaced.prefix(1).uppercased() + spaced.dropFirst()
}

func hostName(_ urlString: String) -> String {
    URL(string: urlString)?.host?.replacingOccurrences(of: "www.", with: "") ?? urlString
}

func formattedUSD(_ value: Int?) -> String? {
    guard let value else { return nil }
    let v = Double(value)
    switch abs(v) {
    case 1e9...: return String(format: "$%.1fB", v / 1e9)
    case 1e6...: return String(format: "$%.1fM", v / 1e6)
    case 1e3...: return String(format: "$%.0fK", v / 1e3)
    default: return "$\(value)"
    }
}

func relativeDate(_ iso: String?) -> String? {
    guard let iso else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let g = ISO8601DateFormatter()
    guard let date = f.date(from: iso) ?? g.date(from: iso) else { return iso }
    return date.formatted(.relative(presentation: .named))
}
