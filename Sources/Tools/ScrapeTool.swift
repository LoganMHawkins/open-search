import SwiftUI
import UniformTypeIdentifiers

struct ScrapeTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var url = ""

    @State private var markdown = true
    @State private var mdLinks = true
    @State private var mdImages = false
    @State private var html = false
    @State private var screenshot = false
    @State private var shotFull = false
    @State private var shotFormat = "png"
    @State private var images = false
    @State private var imageEnrich = Set<String>()
    @State private var highlights = false
    @State private var highlightQuery = ""
    @State private var json = false
    @State private var jsonInstructions = ""
    @State private var jsonSchema = """
    {
      "type": "object",
      "properties": {
        "title": { "type": "string" }
      }
    }
    """
    @State private var product = false

    @State private var country = ""
    @State private var theme = ""
    @State private var mainOnly = false
    @State private var dismissCookies = true
    @State private var dismissPopups = false
    @State private var settle = false
    @State private var waitMs = ""
    @State private var viewportW = ""
    @State private var viewportH = ""
    @State private var maxAge = ""
    @State private var headers = ""

    private var runner: ToolRunner { model.runner(for: .scrape) }

    private var parsedSchema: [String: Any]? {
        guard let data = jsonSchema.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private var formatsChosen: Bool { markdown || html || screenshot || images || highlights || json || product }
    private var optionsValid: Bool { (!json || parsedSchema != nil) && (!highlights || highlightQuery.nilIfBlank != nil) }

    var body: some View {
        ToolScaffold(tool: .scrape, runner: runner, canRun: url.nilIfBlank != nil && formatsChosen && optionsValid, onRun: run) {
            Section("Page") {
                QueryField(tool: .scrape, title: "https://example.com/article", text: $url, onSubmit: run)
            }
            Section("Capture") {
                Toggle("Markdown", isOn: $markdown)
                if markdown {
                    Toggle("Keep links", isOn: $mdLinks).padding(.leading, 14)
                    Toggle("Include images", isOn: $mdImages).padding(.leading, 14)
                }
                Toggle("HTML", isOn: $html)
                Toggle("Screenshot", isOn: $screenshot)
                if screenshot {
                    Picker("Area", selection: $shotFull) { Text("Viewport").tag(false); Text("Full page").tag(true) }
                        .padding(.leading, 14)
                    Picker("Format", selection: $shotFormat) { Text("PNG").tag("png"); Text("JPEG").tag("jpeg"); Text("WebP").tag("webp") }
                        .padding(.leading, 14)
                }
                Toggle("Images", isOn: $images)
                if images {
                    ForEach([("dimensions", "Sizes"), ("classification", "Kind"), ("file", "File info")], id: \.0) { key, label in
                        Toggle(label, isOn: Binding(get: { imageEnrich.contains(key) },
                                                    set: { if $0 { imageEnrich.insert(key) } else { imageEnrich.remove(key) } }))
                            .padding(.leading, 14)
                    }
                }
                Toggle("Highlights", isOn: $highlights)
                if highlights {
                    TextField("What are you looking for?", text: $highlightQuery).padding(.leading, 14)
                }
                Toggle("Structured JSON", isOn: $json)
                if json {
                    TextField("Instructions (optional)", text: $jsonInstructions, axis: .vertical).padding(.leading, 14)
                    TextEditor(text: $jsonSchema)
                        .font(.system(.callout, design: .monospaced))
                        .frame(height: 130)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    if parsedSchema == nil { Label("Schema isn't valid JSON yet.", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red) }
                }
                Toggle("Product details", isOn: $product)
            }
            Section("Browser") {
                OptionPicker("Appear from", selection: $country, codes: Options.webCountries)
                Picker("Appearance", selection: $theme) { Text("Site default").tag(""); Text("Light").tag("light"); Text("Dark").tag("dark") }
                Toggle("Main content only", isOn: $mainOnly)
                Toggle("Dismiss cookie banners", isOn: $dismissCookies)
                Toggle("Dismiss pop-ups", isOn: $dismissPopups)
                Toggle("Wait for animations to settle", isOn: $settle)
                TextField("Extra wait (ms)", text: $waitMs, prompt: Text("0"))
                HStack {
                    TextField("Viewport W", text: $viewportW, prompt: Text("1440"))
                    TextField("Viewport H", text: $viewportH, prompt: Text("900"))
                }
                TextField("Max cache age (ms)", text: $maxAge, prompt: Text("Default; 0 forces fresh"))
                TextField("Extra request headers", text: $headers, prompt: Text("Name: value, one per line"), axis: .vertical)
                    .lineLimit(1...4)
            }
        } results: { runner in
            if let r = runner.latest { ScrapeResult(result: r.json) }
        }
        .onHandoff(for: .scrape) { v, go in
            url = v["url"] ?? url
            if go { run() }
        }
    }

    private func run() {
        guard let u = url.nilIfBlank, formatsChosen, optionsValid else { return }
        Recents.add(u, for: .scrape)
        let target = u.contains("://") ? u : "https://\(u)"
        var formats: [String: Any] = [:]
        if markdown { formats["markdown"] = true }
        if html { formats["html"] = true }
        if screenshot { formats["screenshot"] = true }
        if images { formats["images"] = true }
        if highlights { formats["highlights"] = true }
        if json { formats["json"] = true }
        if product { formats["product"] = true }
        var body: [String: Any] = ["url": target, "formats": formats]

        if markdown && (!mdLinks || mdImages) { body["markdownParams"] = ["includeLinks": mdLinks, "includeImages": mdImages] }
        if screenshot { body["screenshotParams"] = ["area": shotFull ? "fullPage" : "viewport", "format": shotFormat] }
        if images && !imageEnrich.isEmpty { body["imageParams"] = ["enrich": imageEnrich.sorted()] }
        if highlights, let q = highlightQuery.nilIfBlank { body["highlightsParams"] = ["query": q] }
        if json, let schema = parsedSchema {
            var p: [String: Any] = ["schema": schema]
            p.put("instructions", jsonInstructions.nilIfBlank)
            body["jsonParams"] = p
        }

        var shared: [String: Any] = ["dismissCookies": dismissCookies, "dismissPopups": dismissPopups]
        if let c = country.nilIfBlank { shared["country"] = c }
        if let t = theme.nilIfBlank { shared["theme"] = t }
        if mainOnly { shared["mainContentOnly"] = true }
        if settle { shared["settleAnimations"] = true }
        shared.put("waitFor", waitMs.asInt)
        if let w = viewportW.asInt, let h = viewportH.asInt { shared["viewport"] = ["width": w, "height": h] }
        var hdrs: [String: String] = [:]
        for line in headers.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty { hdrs[parts[0]] = parts[1] }
        }
        if !hdrs.isEmpty { shared["headers"] = hdrs }
        body["sharedParams"] = shared
        body.put("maxAgeMs", maxAge.asInt)

        let client = model.client
        runner.run { _ in try await client.post("web/scrape", body, timeout: 240) }
    }
}

// MARK: - Result

struct ScrapeResult: View {
    enum Tab: String, CaseIterable {
        case markdown = "Markdown", html = "HTML", screenshot = "Screenshot", images = "Images"
        case highlights = "Highlights", json = "JSON", product = "Product", page = "Page info"
    }

    let result: JSON
    @State private var tab: Tab?

    private var available: [Tab] {
        var tabs: [Tab] = []
        for (tab, key) in [(Tab.markdown, "markdown"), (.html, "html"), (.screenshot, "screenshot"), (.images, "images"),
                           (.highlights, "highlights"), (.json, "json"), (.product, "product")] {
            if result[key]["requested"].flag == true { tabs.append(tab) }
        }
        tabs.append(.page)
        return tabs
    }

    var body: some View {
        let current = tab ?? available.first ?? .page
        VStack(spacing: 14) {
            GlassCard {
                HStack(alignment: .top, spacing: 14) {
                    Avatar(url: result["metadata"]["favicon"].nonEmpty, name: result["metadata"]["siteName"].nonEmpty ?? "?", size: 44, round: false)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result["metadata"]["title"].nonEmpty ?? hostName(result["url"].nonEmpty ?? "")).font(Brand.display(30))
                        if let u = result["url"].nonEmpty { LinkChip(urlString: u, label: u) }
                        if result["isPartial"].flag == true { Chip(text: "Partial capture", systemImage: "hourglass", tint: .yellow) }
                    }
                    Spacer()
                }
            }
            Picker("", selection: Binding(get: { current }, set: { tab = $0 })) {
                ForEach(available, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            GlassCard { panel(for: current) }
        }
    }

    @ViewBuilder
    private func panel(for tab: Tab) -> some View {
        switch tab {
        case .markdown: payload("markdown") { MarkdownPanel(markdown: $0.nonEmpty ?? "", title: "Markdown") }
        case .html: payload("html") { SourcePanel(text: $0.nonEmpty ?? "", title: "HTML") }
        case .screenshot: payload("screenshot") { ScreenshotPanel(dataURI: $0.nonEmpty ?? "") }
        case .images: imagesPanel
        case .highlights:
            payload("highlights") { _ in
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(result["highlights"]["data"].strings.enumerated()), id: \.offset) { _, h in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(Brand.orange.opacity(0.75)).frame(width: 3)
                            Text(h).textSelection(.enabled).lineSpacing(2)
                        }
                    }
                }
            }
        case .json:
            VStack(alignment: .leading, spacing: 10) {
                if result["json"]["isTruncated"].flag == true { Chip(text: "Output was truncated", systemImage: "scissors", tint: .yellow) }
                status("json")
                JSONOutline(value: result["json"]["data"])
            }
        case .product:
            VStack(alignment: .leading, spacing: 10) {
                status("product")
                if result["product"]["data"]["isProductPage"].flag == false {
                    Text("This doesn't look like a product page.").foregroundStyle(.secondary)
                }
                JSONOutline(value: result["product"]["data"]["product"].isNull ? result["product"]["data"] : result["product"]["data"]["product"])
            }
        case .page: pageInfo
        }
    }

    /// Shows an error line when the format failed, otherwise the string payload.
    @ViewBuilder
    private func payload<V: View>(_ key: String, @ViewBuilder _ content: @escaping (JSON) -> V) -> some View {
        let part = result[key]
        if part["success"].flag == false {
            status(key)
        } else {
            content(part["data"])
        }
    }

    @ViewBuilder
    private func status(_ key: String) -> some View {
        let part = result[key]
        if part["success"].flag == false {
            Label(part["message"].nonEmpty ?? part["error_code"].nonEmpty ?? "This format failed.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    private var imagesPanel: some View {
        let list = result["images"]["data"].list
        return VStack(alignment: .leading, spacing: 12) {
            status("images")
            SectionLabel("\(list.count) images")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
                ForEach(Array(list.enumerated()), id: \.offset) { _, img in
                    VStack(alignment: .leading, spacing: 5) {
                        if let s = img["url"].nonEmpty, let u = URL(string: s) {
                            Link(destination: u) {
                                RemoteImage(url: u, contentMode: .fit) { Rectangle().fill(.quaternary) }
                                .frame(height: 120).frame(maxWidth: .infinity)
                                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                        HStack(spacing: 4) {
                            if let c = img["classification"].nonEmpty { Chip(text: c) }
                            if let w = img["width"].int, let h = img["height"].int { Text("\(w)×\(h)").font(.caption2).foregroundStyle(.secondary) }
                        }
                        if let alt = img["alt"].nonEmpty { Text(alt).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                }
            }
        }
    }

    private var pageInfo: some View {
        let m = result["metadata"]
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                InfoRow(label: "Title", value: m["title"].nonEmpty)
                InfoRow(label: "Description", value: m["description"].nonEmpty)
                InfoRow(label: "Site", value: m["siteName"].nonEmpty)
                InfoRow(label: "Author", value: m["author"].nonEmpty)
                InfoRow(label: "Language", value: m["language"].nonEmpty)
                InfoRow(label: "Canonical", value: m["canonicalUrl"].nonEmpty)
                InfoRow(label: "Published", value: m["publishedTime"].nonEmpty)
                InfoRow(label: "Modified", value: m["modifiedTime"].nonEmpty)
                InfoRow(label: "Robots", value: m["robots"].nonEmpty)
            }
            if !m["keywords"].list.isEmpty { ChipFlow(items: m["keywords"].strings) }
            if !m["headings"].list.isEmpty {
                SectionLabel("Outline")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(m["headings"].list.prefix(60).enumerated()), id: \.offset) { _, h in
                        Text(h["text"].nonEmpty ?? "")
                            .font(h["level"].int == 1 ? .headline : .callout)
                            .foregroundStyle(h["level"].int ?? 2 <= 2 ? Color.primary : Color.secondary)
                            .padding(.leading, CGFloat(max((h["level"].int ?? 1) - 1, 0)) * 14)
                    }
                }
            }
            if !m["openGraph"].isBlank { DisclosureGroup("Open Graph") { JSONOutline(value: m["openGraph"], depth: 1) } }
            if !m["twitter"].isBlank { DisclosureGroup("Twitter card") { JSONOutline(value: m["twitter"], depth: 1) } }
            if !m["jsonLd"].isBlank { DisclosureGroup("Structured data (JSON-LD)") { JSONOutline(value: m["jsonLd"], depth: 1) } }
        }
    }
}

struct SourcePanel: View {
    let text: String
    var title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(title)
                Text("\(text.count.formatted()) characters").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                CopyButton(text: text)
            }
            ScrollView {
                Text(text.prefix(80_000)).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 520)
        }
    }
}

struct ScreenshotPanel: View {
    let dataURI: String

    private var image: NSImage? {
        guard let comma = dataURI.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURI[dataURI.index(after: comma)...])) else { return nil }
        return NSImage(data: data)
    }

    var body: some View {
        if let image {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel("Screenshot")
                    Text("\(Int(image.size.width)) × \(Int(image.size.height))").font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    Button { save(image) } label: { Label("Save…", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.softGlass).controlSize(.small)
                }
                Image(nsImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.1)))
            }
        } else {
            Text("The screenshot couldn't be decoded.").foregroundStyle(.secondary)
        }
    }

    private func save(_ image: NSImage) {
        let panel = NSSavePanel()
        let ext = dataURI.contains("image/jpeg") ? "jpg" : dataURI.contains("image/webp") ? "webp" : "png"
        panel.nameFieldStringValue = "screenshot.\(ext)"
        guard panel.runModal() == .OK, let url = panel.url,
              let comma = dataURI.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURI[dataURI.index(after: comma)...])) else { return }
        try? data.write(to: url)
    }
}
