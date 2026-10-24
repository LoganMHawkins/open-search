import SwiftUI

struct StyleguideTool: View {
    enum Source: String, CaseIterable { case domain = "Domain", url = "Exact page" }

    @EnvironmentObject private var model: AppModel
    @State private var source = Source.domain
    @State private var target = ""
    @State private var scheme = ""
    @State private var maxAge = ""

    private var runner: ToolRunner { model.runner(for: .styleguide) }

    var body: some View {
        ToolScaffold(tool: .styleguide, runner: runner, canRun: target.nilIfBlank != nil, onRun: run) {
            Section("Which site?") {
                Picker("Read from", selection: $source) { ForEach(Source.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                QueryField(tool: .styleguide, title: source == .domain ? "stripe.com" : "https://stripe.com/pricing", text: $target, onSubmit: run)
            }
            Section("Options") {
                Picker("Appearance", selection: $scheme) {
                    Text("Site default").tag("")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                TextField("Max cache age (ms)", text: $maxAge, prompt: Text("Default; 0 forces fresh"))
            }
        } results: { runner in
            if let r = runner.latest { StyleguideResult(result: r.json) }
        }
        .onHandoff(for: .styleguide) { v, go in
            if let d = v["domain"] { source = .domain; target = d }
            if go { run() }
        }
    }

    private func run() {
        guard let t = target.nilIfBlank else { return }
        Recents.add(t, for: .styleguide)
        var query: [URLQueryItem] = [.init(name: source == .domain ? "domain" : "directUrl", value: t)]
        if let s = scheme.nilIfBlank { query.append(.init(name: "colorScheme", value: s)) }
        if let m = maxAge.asInt { query.append(.init(name: "maxAgeMs", value: String(m))) }
        let client = model.client
        runner.run { _ in try await client.get("web/styleguide", query, timeout: 200) }
    }
}

private func px(_ s: String?) -> CGFloat? {
    guard let s else { return nil }
    let digits = s.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber || $0 == "." || $0 == "-" }
    return Double(digits).map { CGFloat($0) }
}

private func weight(_ n: Double?) -> Font.Weight {
    switch n ?? 400 {
    case ..<150: .ultraLight
    case ..<250: .thin
    case ..<350: .light
    case ..<450: .regular
    case ..<550: .medium
    case ..<650: .semibold
    case ..<750: .bold
    case ..<850: .heavy
    default: .black
    }
}

struct StyleguideResult: View {
    let result: JSON

    var body: some View {
        let g = result["styleguide"]
        let domain = result["domain"].nonEmpty
        VStack(spacing: 14) {
            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(domain ?? "Style guide").font(Brand.display(36))
                        Text("\((g["mode"].nonEmpty ?? "light").capitalized) appearance").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            colors(g["colors"])
            typography(g["typography"])
            components(g["components"])
            tokens(g)
        }
    }

    private func colors(_ c: JSON) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Core colours")
                HStack(spacing: 12) {
                    ForEach(["accent", "background", "text"], id: \.self) { key in
                        if let v = c[key].nonEmpty { ColorChip(name: key.capitalized, css: v) }
                    }
                    Spacer()
                }
            }
        }
    }

    private func typography(_ t: JSON) -> some View {
        let rows: [(String, JSON)] = ["h1", "h2", "h3", "h4"].map { ($0.uppercased(), t["headings"][$0]) } + [("Body", t["p"])]
        return GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionLabel("Typography")
                ForEach(rows, id: \.0) { label, spec in
                    if let family = spec["fontFamily"].nonEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("The quick brown fox jumps over the lazy dog")
                                .font(.custom(family, size: min(max(px(spec["fontSize"].nonEmpty) ?? 16, 12), 44)).weight(weight(spec["fontWeight"].num)))
                                .lineLimit(1)
                            Text("\(label) · \(family) · \(spec["fontSize"].nonEmpty ?? "–") · weight \(spec["fontWeight"].int.map(String.init) ?? "–") · line \(spec["lineHeight"].nonEmpty ?? "–")")
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                let links = t["fontLinks"].dict
                if !links.isEmpty { fontLinks(links) }
            }
        }
    }

    private func fontLinks(_ links: [String: JSON]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Font files")
            FlowLayout(spacing: 6) {
                ForEach(links.keys.sorted(), id: \.self) { name in
                    if let s = links[name]?.nonEmpty { LinkChip(urlString: s, label: name) }
                }
            }
        }
    }

    private func components(_ c: JSON) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Components")
                FlowLayout(spacing: 14) {
                    ForEach(["primary", "secondary", "link"], id: \.self) { kind in
                        let b = c["button"][kind]
                        if !b.isNull {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(kind.capitalized) button")
                                    .font(.system(size: min(px(b["fontSize"].nonEmpty) ?? 15, 20), weight: weight(b["fontWeight"].num)))
                                    .foregroundStyle(Color(css: b["color"].nonEmpty ?? "") ?? .primary)
                                    .padding(.horizontal, 18).padding(.vertical, 10)
                                    .background(Color(css: b["backgroundColor"].nonEmpty ?? "") ?? .clear,
                                                in: RoundedRectangle(cornerRadius: min(px(b["borderRadius"].nonEmpty) ?? 8, 30)))
                                    .overlay(RoundedRectangle(cornerRadius: min(px(b["borderRadius"].nonEmpty) ?? 8, 30))
                                        .strokeBorder(Color(css: b["borderColor"].nonEmpty ?? "") ?? .clear, lineWidth: min(px(b["borderWidth"].nonEmpty) ?? 0, 4)))
                                if let css = b["css"].nonEmpty { CopyButton(text: css, label: "Copy CSS") }
                            }
                        }
                    }
                    let card = c["card"]
                    if !card.isNull {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Card")
                                .foregroundStyle(Color(css: card["textColor"].nonEmpty ?? "") ?? .primary)
                                .frame(width: 150, height: 70)
                                .background(Color(css: card["backgroundColor"].nonEmpty ?? "") ?? .clear,
                                            in: RoundedRectangle(cornerRadius: min(px(card["borderRadius"].nonEmpty) ?? 12, 30)))
                                .overlay(RoundedRectangle(cornerRadius: min(px(card["borderRadius"].nonEmpty) ?? 12, 30))
                                    .strokeBorder(Color(css: card["borderColor"].nonEmpty ?? "") ?? .secondary.opacity(0.3), lineWidth: 1))
                            if let css = card["css"].nonEmpty { CopyButton(text: css, label: "Copy CSS") }
                        }
                    }
                }
            }
        }
    }

    private func tokens(_ g: JSON) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Spacing")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(["xs", "sm", "md", "lg", "xl"], id: \.self) { key in
                        if let v = g["elementSpacing"][key].nonEmpty {
                            HStack(spacing: 10) {
                                Text(key).font(.system(.callout, design: .monospaced)).frame(width: 28, alignment: .leading)
                                RoundedRectangle(cornerRadius: 3).fill(Brand.gradient).frame(width: min(max(px(v) ?? 4, 2), 240), height: 10)
                                Text(v).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                SectionLabel("Shadows")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(["sm", "md", "lg", "xl", "inner"], id: \.self) { key in
                        if let v = g["shadows"][key].nonEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(key).font(.system(.callout, design: .monospaced)).frame(width: 40, alignment: .leading)
                                Text(v).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ColorChip: View {
    let name: String
    let css: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(css: css) ?? .gray)
                .frame(width: 130, height: 70)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.12)))
            Text(name).font(.callout.weight(.semibold))
            HStack(spacing: 6) {
                Text(css).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                CopyButton(text: css, compact: true)
            }
        }
        .frame(width: 130, alignment: .leading)
    }
}
