import SwiftUI

struct NewsTool: View {
    enum SearchMode: String, CaseIterable { case topic = "Topic", company = "Company" }
    enum EntityKind: String, CaseIterable { case name = "Name", domain = "Domain", ticker = "Ticker", isin = "ISIN" }
    enum FilterKind: String, CaseIterable { case none = "None", domain = "Publisher", country = "Country", language = "Language", type = "Article type" }

    @EnvironmentObject private var model: AppModel
    @State private var mode = SearchMode.topic
    @State private var query = ""
    @State private var entityKind = EntityKind.name
    @State private var exchange = ""
    @State private var filterKind = FilterKind.none
    @State private var publishers = ""
    @State private var countries = Set<String>()
    @State private var languages = Set<String>()
    @State private var types = Set<String>()
    @State private var useDates = false
    @State private var from = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    @State private var to = Date.now
    @State private var newestFirst = false
    @State private var limit = 10

    private var runner: ToolRunner { model.runner(for: .news) }

    var body: some View {
        ToolScaffold(tool: .news, runner: runner, canRun: (query.nilIfBlank?.count ?? 0) >= 2,
                     costNote: "About \(Int(ceil(Double(limit) / 10))) credit\(limit > 10 ? "s" : "") per page", onRun: run) {
            Section("What news?") {
                Picker("Search by", selection: $mode) {
                    ForEach(SearchMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if mode == .company {
                    Picker("Company", selection: $entityKind) {
                        ForEach(EntityKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    if entityKind == .ticker {
                        OptionPicker("Exchange", selection: $exchange, codes: Options.exchanges, kind: .plain, anyLabel: "Auto")
                    }
                }
                QueryField(tool: .news, title: placeholder, text: $query, axis: mode == .topic ? .vertical : .horizontal, onSubmit: run)
            }
            Section("Filter articles") {
                Picker("Only by", selection: $filterKind) {
                    ForEach(FilterKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                switch filterKind {
                case .none: EmptyView()
                case .domain: TextField("Up to 3 publisher domains", text: $publishers, prompt: Text("reuters.com, bbc.com"))
                case .country: MultiPicker(title: "Publisher country", selection: $countries, codes: Options.newsCountries, limit: 3)
                case .language: MultiPicker(title: "Language", selection: $languages, codes: Options.newsLanguages, kind: .language, limit: 3)
                case .type:
                    ForEach(["editorial", "press_release", "regulatory_filing", "advisory"], id: \.self) { t in
                        Toggle(t.replacingOccurrences(of: "_", with: " ").capitalized, isOn: Binding(
                            get: { types.contains(t) }, set: { if $0 { types.insert(t) } else { types.remove(t) } }))
                    }
                }
                if filterKind != .none {
                    Text("The API accepts one of these filters at a time.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Limit by date", isOn: $useDates)
                if useDates {
                    DatePicker("From", selection: $from, in: ...to, displayedComponents: .date)
                    DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
                }
            }
            Section("Order") {
                Picker("Sort", selection: $newestFirst) {
                    Text("Most relevant").tag(false)
                    Text("Newest first").tag(true)
                }
                Stepper("Per page: \(limit)", value: $limit, in: 10...100, step: 10)
            }
        } results: { runner in
            NewsResults(runner: runner)
        }
        .onHandoff(for: .news) { v, go in
            query = v["query"] ?? query
            if let m = v["mode"], m == "company" { mode = .company }
            if let k = v["kind"], k == "domain" { entityKind = .domain }
            if go { run() }
        }
    }

    private var placeholder: String {
        switch (mode, entityKind) {
        case (.topic, _): "e.g. solid-state battery breakthroughs"
        case (.company, .name): "e.g. Stripe"
        case (.company, .domain): "e.g. stripe.com"
        case (.company, .ticker): "e.g. AAPL"
        case (.company, .isin): "e.g. US0378331005"
        }
    }

    private func run() {
        guard let q = query.nilIfBlank, q.count >= 2 else { return }
        Recents.add(q, for: .news)
        let searchBy: [String: Any]
        if mode == .topic {
            searchBy = ["type": "natural_language", "query": q]
        } else {
            var entity: [String: Any]
            switch entityKind {
            case .name: entity = ["type": "name", "name": q]
            case .domain: entity = ["type": "domain", "domain": q]
            case .ticker: entity = ["type": "ticker", "ticker": q]; entity.put("exchange", exchange.nilIfBlank)
            case .isin: entity = ["type": "isin", "isin": q]
            }
            searchBy = ["type": "entity", "entity": entity]
        }
        var filterBy: [String: Any] = [:]
        switch filterKind {
        case .none: break
        case .domain: filterBy.put("sourceDomain", nonEmpty: Array(publishers.tokens.prefix(3)))
        case .country: filterBy.put("sourceCountry", nonEmpty: countries.sorted())
        case .language: filterBy.put("articleLanguage", nonEmpty: languages.sorted())
        case .type: filterBy.put("articleType", nonEmpty: types.sorted())
        }
        if useDates {
            let start = Calendar.current.startOfDay(for: from)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to))!.addingTimeInterval(-1)
            filterBy["date"] = ["from": Int(start.timeIntervalSince1970 * 1000), "to": Int(end.timeIntervalSince1970 * 1000)]
        }
        let sortBy = newestFirst ? "newest" : "relevance"
        let limit = limit
        let client = model.client
        runner.run(cursor: { $0["has_more"].flag == true ? $0["next_cursor"].nonEmpty : nil }) { cursor in
            var body: [String: Any] = ["searchBy": searchBy, "sortBy": ["type": sortBy], "limit": limit]
            if !filterBy.isEmpty { body["filterBy"] = filterBy }
            if let cursor { body["cursor"] = cursor }
            return try await client.post("news/search", body)
        }
    }
}

private struct NewsResults: View {
    @ObservedObject var runner: ToolRunner

    var body: some View {
        let articles = runner.pages.flatMap { $0.json["data"].list }
        VStack(spacing: 14) {
            HStack {
                StatTile(value: "\(articles.count)", label: articles.count == 1 ? "article" : "articles")
                Spacer()
            }
            if articles.isEmpty {
                GlassCard { Text("No articles found. Try a wider date range or fewer filters.").foregroundStyle(.secondary) }
            }
            ForEach(Array(articles.enumerated()), id: \.offset) { _, a in ArticleCard(article: a) }
        }
    }
}

struct ArticleCard: View {
    @EnvironmentObject private var model: AppModel
    let article: JSON

    var body: some View {
        let url = article["url"].nonEmpty ?? ""
        let source = article["source"]
        GlassCard {
            HStack(alignment: .top, spacing: 14) {
                if let image = article["image_url"].nonEmpty, let u = URL(string: image) {
                    RemoteImage(url: u, contentMode: .fill) { Rectangle().fill(.quaternary) }
                    .frame(width: 128, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(source["name"].nonEmpty ?? hostName(url)).font(.callout.weight(.semibold)).foregroundStyle(Brand.orange)
                        if let when = relativeDate(article["published_at"].nonEmpty) { Text(when).font(.callout).foregroundStyle(.secondary) }
                        if let t = article["type"].nonEmpty, t != "editorial" { Chip(text: t.replacingOccurrences(of: "_", with: " ").capitalized) }
                    }
                    if let u = URL(string: url) {
                        Link(article["title"].nonEmpty ?? url, destination: u).font(.title3.weight(.semibold)).foregroundStyle(.primary).lineLimit(3)
                    }
                    if let d = article["description"].nonEmpty { Text(d).foregroundStyle(.secondary).lineLimit(4).lineSpacing(2) }
                    HStack(spacing: 8) {
                        if !article["authors"].list.isEmpty {
                            Text("By " + article["authors"].strings.prefix(3).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        }
                        if let lang = article["language"].nonEmpty { Chip(text: lang.uppercased()) }
                        if let level = article["match"]["level"].nonEmpty {
                            Chip(text: level == "primary" ? "Main subject" : "Mentioned")
                        }
                        if let domain = source["domain"].nonEmpty {
                            Button { model.open(.brand, values: ["mode": "retrieve", "kind": "domain", "value": domain]) } label: {
                                Label("Publisher", systemImage: "paintpalette")
                            }
                            .buttonStyle(.softGlass).controlSize(.small)
                        }
                    }
                }
            }
        }
    }
}
