import SwiftUI

// MARK: - Markdown

enum MDBlock {
    case heading(Int, String)
    case paragraph(String)
    case bullet(Int, String)
    case numbered(String, String)
    case quote(String)
    case code(String)
    case tableRow(String)
    case rule

    static func parse(_ text: String) -> [MDBlock] {
        var out: [MDBlock] = []
        var para: [String] = []
        var code: [String]?

        func flush() {
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))); para = [] }
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code { out.append(.code(c.joined(separator: "\n"))); code = nil }
                else { flush(); code = [] }
                continue
            }
            if code != nil { code!.append(raw); continue }
            if line.isEmpty { flush(); continue }

            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                if level <= 6, line.dropFirst(level).first == " " {
                    flush()
                    out.append(.heading(level, String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)))
                    continue
                }
            }
            if line == "---" || line == "***" || line == "___" { flush(); out.append(.rule); continue }
            if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
                flush()
                let indent = raw.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
                out.append(.bullet(indent, String(line.dropFirst(2))))
                continue
            }
            if let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }),
               line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
               line[line.index(after: dot)...].first == " " {
                flush()
                out.append(.numbered(String(line[..<dot]), String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if line.hasPrefix(">") {
                flush()
                out.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if line.hasPrefix("|") {
                flush()
                if !line.allSatisfy({ "|-: ".contains($0) }) { out.append(.tableRow(line)) }
                continue
            }
            para.append(line)
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        flush()
        return out
    }
}

struct MarkdownView: View {
    private let blocks: [MDBlock]
    private let truncated: Bool

    init(_ source: String, limit: Int = 40_000) {
        truncated = source.utf8.count > limit
        blocks = MDBlock.parse(truncated ? String(source.prefix(limit)) : source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in view(for: block) }
            if truncated {
                Text("Preview shortened. Copy or save the result for the full text.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level <= 1 ? Brand.display(30) : level == 2 ? Brand.display(24) : .system(level == 3 ? .title3 : .headline, weight: .semibold))
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            Text(inline(text)).lineSpacing(3)
        case .bullet(let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(Brand.orange).frame(width: 5, height: 5).offset(y: -2)
                Text(inline(text)).lineSpacing(2)
            }
            .padding(.leading, CGFloat(indent) * 16 + 4)
        case .numbered(let n, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).").foregroundStyle(Brand.orange).monospacedDigit()
                Text(inline(text)).lineSpacing(2)
            }
            .padding(.leading, 4)
        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Brand.orange.opacity(0.7)).frame(width: 3)
                Text(inline(text)).foregroundStyle(.secondary).italic()
            }
        case .code(let text):
            ScrollView(.horizontal) {
                Text(text).font(.system(.callout, design: .monospaced)).padding(10)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .tableRow(let text):
            Text(text).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        case .rule:
            Divider()
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// Rendered Markdown with a switch to the source text.
struct MarkdownPanel: View {
    let markdown: String
    var title = "Content"
    @State private var showSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(title)
                Text("\(markdown.count.formatted()) characters").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Picker("", selection: $showSource) {
                    Text("Rendered").tag(false)
                    Text("Source").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                CopyButton(text: markdown)
            }
            if showSource {
                ScrollView {
                    Text(markdown.prefix(60_000))
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 520)
            } else {
                MarkdownView(markdown)
            }
        }
    }
}

// MARK: - JSON

/// Structured, readable JSON: objects become labelled rows, arrays become lists. Used for Answers output,
/// structured scrape data and anything without a bespoke layout.
struct JSONOutline: View {
    let value: JSON
    var depth = 0

    var body: some View {
        switch value {
        case .object(let o):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(o.keys.sorted(), id: \.self) { key in JSONEntry(label: key, value: o[key] ?? .null, depth: depth) }
            }
        case .array(let a):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(a.enumerated()), id: \.offset) { i, item in
                    if item.isScalar {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Brand.orange).frame(width: 5, height: 5).offset(y: -2)
                            JSONScalar(value: item)
                        }
                    } else {
                        JSONEntry(label: Self.title(for: item, index: i), value: item, depth: depth)
                    }
                }
            }
        default:
            JSONScalar(value: value)
        }
    }

    static func title(for item: JSON, index: Int) -> String {
        for key in ["name", "title", "url", "domain", "id"] {
            if let s = item[key].nonEmpty { return s.count > 70 ? String(s.prefix(70)) + "…" : s }
        }
        return "Item \(index + 1)"
    }
}

private struct JSONEntry: View {
    let label: String
    let value: JSON
    let depth: Int
    @State private var open: Bool

    init(label: String, value: JSON, depth: Int) {
        self.label = label
        self.value = value
        self.depth = depth
        _open = State(initialValue: depth < 1)
    }

    var body: some View {
        if value.isScalar {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label).font(.callout).foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
                JSONScalar(value: value)
            }
        } else if value.isBlank {
            HStack(spacing: 10) {
                Text(label).font(.callout).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
                Text("none").foregroundStyle(.tertiary)
            }
        } else {
            DisclosureGroup(isExpanded: $open) {
                JSONOutline(value: value, depth: depth + 1).padding(.leading, 14).padding(.top, 6)
            } label: {
                HStack(spacing: 6) {
                    Text(label).font(.callout.weight(.medium))
                    Text(count).font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var count: String {
        switch value {
        case .array(let a): "\(a.count) items"
        case .object(let o): "\(o.count) fields"
        default: ""
        }
    }
}

struct JSONScalar: View {
    let value: JSON

    var body: some View {
        Group {
            if case .string(let s) = value {
                if (s.hasPrefix("http://") || s.hasPrefix("https://")), let url = URL(string: s) {
                    Link(s, destination: url).lineLimit(2)
                } else {
                    Text(s)
                }
            } else if let d = value.display {
                Text(d).monospacedDigit()
            } else {
                Text("null").foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RawJSONView: View {
    let json: JSON
    private let text: String
    private let truncated: Bool

    init(json: JSON) {
        self.json = json
        let full = json.pretty
        truncated = full.utf8.count > 200_000
        text = truncated ? String(full.prefix(200_000)) : full
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if truncated {
                Label("Showing the first 200,000 characters. Use Save to export everything.", systemImage: "scissors")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
