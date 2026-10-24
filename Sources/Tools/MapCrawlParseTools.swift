import SwiftUI
import UniformTypeIdentifiers

// MARK: - Map

struct MapTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var domain = ""
    @State private var subdomains = false
    @State private var maxLinks = ""
    @State private var sitemap = ""
    @State private var include = ""
    @State private var exclude = ""
    @State private var search = ""

    private var runner: ToolRunner { model.runner(for: .map) }

    var body: some View {
        ToolScaffold(tool: .map, runner: runner, canRun: domain.nilIfBlank != nil,
                     costNote: search.nilIfBlank == nil ? "1 credit" : "2 credits (with search)", onRun: run) {
            Section("Site") {
                QueryField(tool: .map, title: "example.com", text: $domain, onSubmit: run)
                Toggle("Include subdomains", isOn: $subdomains)
            }
            Section("Narrow it down") {
                TextField("Rank by relevance to", text: $search, prompt: Text("e.g. pricing"))
                TextField("Only URLs matching (regex)", text: $include)
                TextField("Skip URLs matching (regex)", text: $exclude)
                TextField("Sitemap URL", text: $sitemap, prompt: Text("Auto-detected"))
                TextField("Max links", text: $maxLinks, prompt: Text("10000"))
            }
        } results: { runner in
            if let r = runner.latest { MapResult(result: r.json) }
        }
        .onHandoff(for: .map) { v, go in
            domain = v["domain"] ?? domain
            if go { run() }
        }
    }

    private func run() {
        guard let d = domain.nilIfBlank else { return }
        Recents.add(d, for: .map)
        var q: [URLQueryItem] = [.init(name: "domain", value: d)]
        if subdomains { q.append(.init(name: "includeSubdomains", value: "true")) }
        if let m = maxLinks.asInt { q.append(.init(name: "maxLinks", value: String(m))) }
        for (name, value) in [("sitemapUrl", sitemap), ("urlRegex", include), ("excludeUrlRegex", exclude), ("search", search)] {
            if let v = value.nilIfBlank { q.append(.init(name: name, value: v)) }
        }
        let client = model.client
        runner.run { _ in try await client.get("web/urls", q, timeout: 200) }
    }
}

private struct MapResult: View {
    let result: JSON
    @State private var filter = ""

    var body: some View {
        let urls = result["urls"].list
        let shown = filter.isEmpty ? urls : urls.filter {
            ($0["url"].str ?? "").localizedCaseInsensitiveContains(filter) || ($0["title"].str ?? "").localizedCaseInsensitiveContains(filter)
        }
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                StatTile(value: urls.count.formatted(), label: "URLs on \(result["domain"].nonEmpty ?? "site")")
                if result["partial"].flag == true { Chip(text: "Partial", systemImage: "hourglass", tint: .yellow) }
                Spacer()
                TextField("Filter these", text: $filter).textFieldStyle(.roundedBorder).frame(width: 220)
                CopyButton(text: shown.compactMap { $0["url"].nonEmpty }.joined(separator: "\n"), label: "Copy URLs")
            }
            LazyVStack(spacing: 8) {
                ForEach(Array(shown.prefix(500).enumerated()), id: \.offset) { _, u in
                    VStack(alignment: .leading, spacing: 3) {
                        if let s = u["url"].nonEmpty, let url = URL(string: s) {
                            Link(s, destination: url).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                        }
                        if let t = u["title"].nonEmpty { Text(t).font(.callout) }
                        if let d = u["description"].nonEmpty { Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                if shown.count > 500 {
                    Text("Showing the first 500 of \(shown.count.formatted()). Copy URLs or save the JSON for all of them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Crawl

struct CrawlTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var url = ""
    @State private var maxPages = 20
    @State private var maxDepth = ""
    @State private var include = ""
    @State private var exclude = ""
    @State private var subdomains = false
    @State private var links = true
    @State private var images = false
    @State private var mainOnly = false
    @State private var pdf = true
    @State private var country = ""
    @State private var maxAge = ""
    @State private var waitMs = ""

    private var runner: ToolRunner { model.runner(for: .crawl) }

    var body: some View {
        ToolScaffold(tool: .crawl, runner: runner, canRun: url.nilIfBlank != nil,
                     costNote: "Up to \(maxPages) credits (1 per page)", onRun: run) {
            Section("Start from") {
                QueryField(tool: .crawl, title: "https://example.com/docs", text: $url, onSubmit: run)
                Stepper("Max pages: \(maxPages)", value: $maxPages, in: 1...500, step: 5)
                TextField("Max depth", text: $maxDepth, prompt: Text("No limit"))
            }
            Section("Scope") {
                TextField("Only URLs matching (regex)", text: $include)
                TextField("Skip URLs matching (regex)", text: $exclude)
                Toggle("Follow subdomains", isOn: $subdomains)
            }
            Section("Content") {
                Toggle("Keep links", isOn: $links)
                Toggle("Include images", isOn: $images)
                Toggle("Main content only", isOn: $mainOnly)
                Toggle("Read PDFs", isOn: $pdf)
                OptionPicker("Appear from", selection: $country, codes: Options.webCountries)
                TextField("Max cache age (ms)", text: $maxAge, prompt: Text("1 day"))
                TextField("Wait per page (ms)", text: $waitMs, prompt: Text("3500"))
            }
        } results: { runner in
            if let r = runner.latest { CrawlResult(result: r.json) }
        }
        .onHandoff(for: .crawl) { v, go in
            url = v["url"] ?? url
            if go { run() }
        }
    }

    private func run() {
        guard let u = url.nilIfBlank else { return }
        Recents.add(u, for: .crawl)
        var body: [String: Any] = [
            "url": u.contains("://") ? u : "https://\(u)", "maxPages": maxPages,
            "includeLinks": links, "includeImages": images, "useMainContentOnly": mainOnly,
            "followSubdomains": subdomains, "pdf": ["shouldParse": pdf],
        ]
        body.put("maxDepth", maxDepth.asInt)
        body.put("urlRegex", include.nilIfBlank)
        body.put("excludeUrlRegex", exclude.nilIfBlank)
        body.put("country", country.nilIfBlank)
        body.put("maxAgeMs", maxAge.asInt)
        body.put("waitForMs", waitMs.asInt)
        let client = model.client
        runner.run { _ in try await client.post("web/crawl", body, timeout: 330) }
    }
}

private struct CrawlResult: View {
    let result: JSON

    var body: some View {
        let pages = result["results"].list
        let meta = result["metadata"]
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                StatTile(value: "\(meta["numSucceeded"].int ?? pages.count)", label: "pages read")
                if let f = meta["numFailed"].int, f > 0 { StatTile(value: "\(f)", label: "failed") }
                if let s = meta["numSkipped"].int, s > 0 { StatTile(value: "\(s)", label: "skipped") }
                StatTile(value: "\(meta["maxCrawlDepth"].int ?? 0)", label: "levels deep")
                if result["partial"].flag == true { Chip(text: "Stopped early", systemImage: "hourglass", tint: .yellow) }
                Spacer()
                CopyButton(text: pages.compactMap { $0["markdown"].nonEmpty }.joined(separator: "\n\n---\n\n"), label: "Copy all Markdown")
            }
            ForEach(Array(pages.enumerated()), id: \.offset) { _, page in CrawledPage(page: page) }
        }
    }
}

private struct CrawledPage: View {
    let page: JSON
    @State private var open = false

    var body: some View {
        let m = page["metadata"]
        GlassCard {
            DisclosureGroup(isExpanded: $open) {
                if let md = page["markdown"].nonEmpty { MarkdownPanel(markdown: md, title: "Markdown").padding(.top, 10) }
                else { Text("No content.").foregroundStyle(.secondary).padding(.top, 8) }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(m["title"].nonEmpty ?? hostName(m["finalUrl"].nonEmpty ?? m["url"].nonEmpty ?? "")).font(.headline).lineLimit(1)
                        if let d = m["crawlDepth"].int { Chip(text: "Depth \(d)") }
                        if let s = m["statusCode"].int, s >= 400 { Chip(text: "HTTP \(s)", tint: .red) }
                    }
                    if let u = m["finalUrl"].nonEmpty ?? m["url"].nonEmpty { Text(u).font(.caption).foregroundStyle(Brand.orange).lineLimit(1).truncationMode(.middle) }
                }
            }
        }
    }
}

// MARK: - Parse

struct ParseTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var fileURL: URL?
    @State private var links = true
    @State private var images = false
    @State private var mainOnly = false
    @State private var ocr = false
    @State private var dropping = false

    private var runner: ToolRunner { model.runner(for: .parse) }

    var body: some View {
        ToolScaffold(tool: .parse, runner: runner, canRun: fileURL != nil,
                     costNote: ocr ? "1 credit per file, +1 per OCR page" : "1 credit per file", onRun: run) {
            Section("File") {
                dropZone
            }
            Section("Options") {
                Toggle("Keep links", isOn: $links)
                Toggle("Include images", isOn: $images)
                Toggle("Main content only (HTML)", isOn: $mainOnly)
                Toggle("Read text in images and scans (OCR)", isOn: $ocr)
            }
        } results: { runner in
            if let r = runner.latest { ParseResult(result: r.json, name: fileURL?.lastPathComponent) }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: fileURL == nil ? "square.and.arrow.down.on.square" : "doc.fill")
                .font(.system(size: 30)).foregroundStyle(Brand.orange)
            Text(fileURL?.lastPathComponent ?? "Drop a file here").font(.headline).lineLimit(1)
            Text(fileURL == nil ? "PDF, Word, Excel, PowerPoint, images, HTML, CSV, text and more" : sizeText)
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(fileURL == nil ? "Choose File…" : "Choose Another…") { choose() }.buttonStyle(.softGlass).controlSize(.small)
        }
        .frame(maxWidth: .infinity).padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(dropping ? Brand.orange : Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .dropDestination(for: URL.self) { urls, _ in
            guard let first = urls.first else { return false }
            fileURL = first
            return true
        } isTargeted: { dropping = $0 }
    }

    private var sizeText: String {
        guard let fileURL, let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { fileURL = panel.url }
    }

    private func run() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        var q: [URLQueryItem] = [
            .init(name: "includeLinks", value: links ? "true" : "false"),
            .init(name: "includeImages", value: images ? "true" : "false"),
            .init(name: "useMainContentOnly", value: mainOnly ? "true" : "false"),
            .init(name: "ocr", value: ocr ? "true" : "false"),
        ]
        let ext = fileURL.pathExtension.lowercased()
        if !ext.isEmpty { q.append(.init(name: "extension", value: ext)) }
        let client = model.client
        runner.run { _ in try await client.upload("parse", query: q, data: data, contentType: "application/octet-stream") }
    }
}

private struct ParseResult: View {
    let result: JSON
    let name: String?

    var body: some View {
        VStack(spacing: 14) {
            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name ?? "Parsed file").font(Brand.display(30))
                        if let t = result["type"].nonEmpty { Text("Detected as \(t)").foregroundStyle(.secondary) }
                    }
                    Spacer()
                }
            }
            GlassCard { MarkdownPanel(markdown: result["markdown"].str ?? "", title: "Markdown") }
        }
    }
}
