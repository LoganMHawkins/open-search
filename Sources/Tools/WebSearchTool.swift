import SwiftUI

struct WebSearchTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var numResults = 10
    @State private var freshness = ""
    @State private var country = ""
    @State private var languages = Set<String>()
    @State private var include = ""
    @State private var exclude = ""
    @State private var fanout = false

    @State private var highlights = false
    @State private var highlightChars = 4000
    @State private var markdown = false
    @State private var mdLinks = true
    @State private var mdImages = false
    @State private var mdMain = false
    @State private var mdFrames = false
    @State private var pdfParse = true
    @State private var mdMaxAge = ""
    @State private var mdWait = ""

    @State private var descriptionMax = ""
    @State private var timeoutSeconds = ""
    @State private var partialOnTimeout = true
    @State private var zdr = false

    private var runner: ToolRunner { model.runner(for: .webSearch) }

    private var credits: Int {
        let pages = Int(ceil(Double(numResults) / 10))
        return pages * (1 + (highlights ? 1 : 0) + (markdown ? 1 : 0))
    }

    var body: some View {
        ToolScaffold(tool: .webSearch, runner: runner, canRun: query.nilIfBlank != nil,
                     costNote: "About \(credits) credit\(credits == 1 ? "" : "s") for this search", onRun: run) {
            Section("Search") {
                QueryField(tool: .webSearch, title: "Search the web", text: $query, axis: .vertical, onSubmit: run)
                Stepper("Results: \(numResults)", value: $numResults, in: 10...100, step: 10)
                Text("Operators work: site:, -site:, inurl:, intitle:, \"quotes\" and OR.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Filters") {
                Picker("Published", selection: $freshness) {
                    Text("Any time").tag("")
                    Text("Last 24 hours").tag("last_24_hours")
                    Text("Last week").tag("last_week")
                    Text("Last month").tag("last_month")
                    Text("Last year").tag("last_year")
                }
                OptionPicker("Country", selection: $country, codes: Options.webCountries)
                MultiPicker(title: "Languages", selection: $languages, codes: Options.webLanguages, kind: .language, emptyLabel: "All")
                TextField("Only these sites", text: $include, prompt: Text("github.com, arxiv.org"), axis: .vertical)
                TextField("Never these sites", text: $exclude, prompt: Text("pinterest.com"), axis: .vertical)
                Toggle("Expand the query (fan-out)", isOn: $fanout)
            }
            Section("Page content") {
                Toggle("Relevant highlights", isOn: $highlights)
                if highlights {
                    Stepper("Highlight length: \(highlightChars)", value: $highlightChars, in: 500...20000, step: 500)
                }
                Toggle("Full page as Markdown", isOn: $markdown)
                if markdown {
                    Toggle("Keep links", isOn: $mdLinks)
                    Toggle("Include images", isOn: $mdImages)
                    Toggle("Main content only", isOn: $mdMain)
                    Toggle("Include iframes", isOn: $mdFrames)
                    Toggle("Read PDFs", isOn: $pdfParse)
                    TextField("Max cache age (ms)", text: $mdMaxAge, prompt: Text("Default; 0 forces fresh"))
                    TextField("Extra wait (ms)", text: $mdWait, prompt: Text("0"))
                }
            }
            Section("Advanced") {
                TextField("Cap description length", text: $descriptionMax, prompt: Text("No cap"))
                TextField("Timeout (seconds)", text: $timeoutSeconds, prompt: Text("Default"))
                if timeoutSeconds.nilIfBlank != nil {
                    Toggle("Return partial results on timeout", isOn: $partialOnTimeout)
                }
                Toggle("Zero data retention", isOn: $zdr)
            }
        } results: { runner in
            WebSearchResults(runner: runner)
        }
        .onHandoff(for: .webSearch) { v, go in
            query = v["query"] ?? query
            if go { run() }
        }
    }

    private func run() {
        guard let q = query.nilIfBlank else { return }
        Recents.add(q, for: .webSearch)
        var body: [String: Any] = ["query": q, "numResults": numResults]
        body.put("freshness", freshness.nilIfBlank)
        body.put("country", country.nilIfBlank)
        if !languages.isEmpty { body["languages"] = languages.sorted() }
        body.put("includeDomains", nonEmpty: include.tokens)
        body.put("excludeDomains", nonEmpty: exclude.tokens)
        if fanout { body["queryFanout"] = true }
        if highlights { body["highlightsOptions"] = ["enabled": true, "maxCharacters": highlightChars] }
        if markdown {
            var md: [String: Any] = [
                "enabled": true, "includeLinks": mdLinks, "includeImages": mdImages,
                "useMainContentOnly": mdMain, "includeFrames": mdFrames, "pdf": ["shouldParse": pdfParse],
            ]
            md.put("maxAgeMs", mdMaxAge.asInt)
            md.put("waitForMs", mdWait.asInt)
            body["markdownOptions"] = md
        }
        body.put("descriptionMaxCharacters", descriptionMax.asInt)
        if let secs = Double(timeoutSeconds.trimmingCharacters(in: .whitespaces)), secs > 0 {
            body["timeoutOpts"] = ["milliseconds": Int(secs * 1000), "behavior": partialOnTimeout && secs >= 5 ? "return-partial" : "fail"]
        }
        if zdr { body["zdr"] = "enabled" }
        let client = model.client
        runner.run { _ in try await client.post("web/search", body, timeout: 300) }
    }
}

private struct WebSearchResults: View {
    @ObservedObject var runner: ToolRunner

    var body: some View {
        let json = runner.latest?.json ?? .null
        let results = json["results"].list
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                StatTile(value: "\(results.count)", label: "results")
                if let cache = json["cache_metadata"]["status"].nonEmpty {
                    StatTile(value: cache == "hit" ? "Cached" : "Live", label: cache == "hit" ? "\((json["cache_metadata"]["age_ms"].int ?? 0) / 1000)s old" : "fresh fetch")
                }
                if json["partial"].flag == true { Chip(text: "Partial results", systemImage: "hourglass", tint: .yellow) }
                Spacer()
            }
            if results.isEmpty {
                GlassCard { Text("Nothing came back. Loosen the filters or rephrase.").foregroundStyle(.secondary) }
            }
            ForEach(Array(results.enumerated()), id: \.offset) { i, r in WebResultCard(index: i + 1, result: r) }
        }
    }
}

struct WebResultCard: View {
    let index: Int
    let result: JSON

    var body: some View {
        let url = result["url"].nonEmpty ?? ""
        let highlights = result["highlights"]["highlights"].strings
        let md = result["markdown"]["markdown"].nonEmpty
        GlassCard {
            HStack(alignment: .top, spacing: 14) {
                Text("\(index)").font(Brand.display(30)).foregroundStyle(Brand.gradient).frame(width: 34, alignment: .trailing)
                VStack(alignment: .leading, spacing: 8) {
                    if let u = URL(string: url) {
                        Link(result["title"].nonEmpty ?? url, destination: u).font(.title3.weight(.semibold)).foregroundStyle(.primary).lineLimit(3)
                    } else {
                        Text(result["title"].nonEmpty ?? url).font(.title3.weight(.semibold))
                    }
                    HStack(spacing: 8) {
                        Text(hostName(url)).font(.callout).foregroundStyle(Brand.orange)
                        if let rel = result["relevance"].nonEmpty { Chip(text: rel.capitalized + " relevance") }
                        if let code = result["markdown"]["code"].nonEmpty, code != "SUCCESS", code != "NOT_REQUESTED" {
                            Chip(text: "Content: \(code.lowercased().replacingOccurrences(of: "_", with: " "))", tint: .red)
                        }
                    }
                    if let d = result["description"].nonEmpty { Text(d).foregroundStyle(.secondary).lineSpacing(2) }
                    ForEach(Array(highlights.enumerated()), id: \.offset) { _, h in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(Brand.orange.opacity(0.75)).frame(width: 3)
                            Text(h).font(.callout).lineSpacing(2).textSelection(.enabled)
                        }
                    }
                    if let md {
                        DisclosureGroup("Page content") { MarkdownPanel(markdown: md, title: "Markdown").padding(.top, 8) }
                    }
                }
            }
        }
    }
}
