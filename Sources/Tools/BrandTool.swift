import SwiftUI

struct BrandTool: View {
    enum Mode: String, CaseIterable { case find = "Find", retrieve = "Profile" }
    enum Kind: String, CaseIterable, Identifiable {
        case domain = "Domain", name = "Company name", email = "Email", ticker = "Stock ticker"
        case url = "Page URL", transaction = "Card transaction"
        var id: String { rawValue }
        var key: String {
            switch self {
            case .domain: "domain"
            case .name: "name"
            case .email: "email"
            case .ticker: "ticker"
            case .url: "url"
            case .transaction: "transaction"
            }
        }
        var placeholder: String {
            switch self {
            case .domain: "stripe.com"
            case .name: "Stripe"
            case .email: "someone@stripe.com"
            case .ticker: "AAPL"
            case .url: "https://stripe.com/pricing"
            case .transaction: "e.g. STRIPE* 4829 SAN FRANCISCO CA"
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @State private var mode = Mode.find

    // Find
    @State private var term = ""
    @State private var byName = true
    @State private var byDomain = true
    @State private var country = ""
    @State private var language = ""
    @State private var typo = 0
    @State private var autocomplete = true

    // Profile
    @State private var kind = Kind.domain
    @State private var value = ""
    @State private var city = ""
    @State private var mcc = ""
    @State private var phone = ""
    @State private var highConfidence = false
    @State private var maxSpeed = false

    private var runner: ToolRunner { model.runner(for: .brand) }
    private var canRun: Bool { mode == .find ? term.nilIfBlank != nil && (byName || byDomain) : value.nilIfBlank != nil }

    var body: some View {
        ToolScaffold(tool: .brand, runner: runner, canRun: canRun,
                     costNote: mode == .find ? "1 credit (free on paid plans)" : "10 credits", onRun: run) {
            Section {
                Picker("Mode", selection: $mode) {
                    Text("Find a brand").tag(Mode.find)
                    Text("Full profile").tag(Mode.retrieve)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            if mode == .find {
                Section("Search brands") {
                    QueryField(tool: .brand, title: "Company name or domain prefix", text: $term, onSubmit: run)
                    Toggle("Match names", isOn: $byName)
                    Toggle("Match domains", isOn: $byDomain)
                    Toggle("Suggest as I type (prefix match)", isOn: $autocomplete)
                    Stepper("Typo tolerance: \(typo)", value: $typo, in: 0...2)
                }
                Section("Bias results") {
                    OptionPicker("Country", selection: $country, codes: Options.brandCountries)
                    OptionPicker("Language", selection: $language, codes: Options.brandLanguages, kind: .plain)
                }
            } else {
                Section("Look up by") {
                    Picker("Identifier", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }
                    QueryField(tool: .brand, title: kind.placeholder, text: $value, axis: kind == .transaction ? .vertical : .horizontal, onSubmit: run)
                    if kind == .transaction {
                        TextField("City", text: $city)
                        TextField("Merchant category code", text: $mcc)
                        TextField("Phone", text: $phone)
                        Toggle("High-confidence matches only", isOn: $highConfidence)
                    }
                }
                Section("Speed") {
                    Toggle("Fastest (skip slower enrichment)", isOn: $maxSpeed)
                }
            }
        } results: { runner in
            BrandResults(runner: runner)
        }
        .onHandoff(for: .brand) { v, go in
            if let m = v["mode"] { mode = m == "find" ? .find : .retrieve }
            if let k = v["kind"], let match = Kind.allCases.first(where: { $0.key == k }) { kind = match }
            if mode == .retrieve { value = v["value"] ?? value } else { term = v["value"] ?? term }
            if go { run() }
        }
    }

    private func run() {
        guard canRun else { return }
        let client = model.client
        if mode == .find {
            guard let t = term.nilIfBlank else { return }
            Recents.add(t, for: .brand)
            var query: [URLQueryItem] = [
                .init(name: "query", value: t),
                .init(name: "autocomplete", value: autocomplete ? "true" : "false"),
                .init(name: "typoTolerance", value: String(typo)),
                .init(name: "queryBy", value: [byName ? "name" : nil, byDomain ? "domain" : nil].compactMap { $0 }.joined(separator: ",")),
            ]
            if let c = country.nilIfBlank { query.append(.init(name: "country", value: c)) }
            if let l = language.nilIfBlank { query.append(.init(name: "language", value: l)) }
            runner.run { _ in try await client.get("brand/search", query) }
        } else {
            guard let v = value.nilIfBlank else { return }
            Recents.add(v, for: .brand)
            var body: [String: Any]
            switch kind {
            case .domain: body = ["type": "by_domain", "domain": v]
            case .name: body = ["type": "by_name", "name": v]
            case .email: body = ["type": "by_email", "email": v]
            case .ticker: body = ["type": "by_ticker", "ticker": v]
            case .url: body = ["type": "by_direct_url", "direct_url": v]
            case .transaction:
                body = ["type": "by_transaction", "transaction_info": v]
                body.put("city", city.nilIfBlank)
                body.put("mcc", mcc.nilIfBlank)
                body.put("phone", phone.nilIfBlank)
                if highConfidence { body["high_confidence_only"] = true }
            }
            if maxSpeed, kind != .url { body["maxSpeed"] = true }
            runner.run { _ in try await client.post("brand/retrieve", body, timeout: 200) }
        }
    }
}

// MARK: - Results

private struct BrandResults: View {
    @ObservedObject var runner: ToolRunner

    var body: some View {
        let json = runner.latest?.json ?? .null
        if !json["brand"].isNull {
            BrandProfileView(brand: json["brand"], partial: json["partial"].flag == true)
        } else {
            BrandSearchList(results: json["results"].list)
        }
    }
}

private struct BrandSearchList: View {
    @EnvironmentObject private var model: AppModel
    let results: [JSON]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                StatTile(value: "\(results.count)", label: results.count == 1 ? "brand" : "brands")
                Text("Select one for its full profile.").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            if results.isEmpty {
                GlassCard { Text("No brands matched that.").foregroundStyle(.secondary) }
            }
            ForEach(Array(results.enumerated()), id: \.offset) { _, r in
                Button {
                    if let d = r["domain"].nonEmpty { model.open(.brand, values: ["mode": "retrieve", "kind": "domain", "value": d]) }
                } label: {
                    HStack(spacing: 14) {
                        Avatar(url: r["logo"].nonEmpty, name: r["name"].nonEmpty ?? "?", size: 52, round: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r["name"].nonEmpty ?? r["domain"].nonEmpty ?? "Brand").font(Brand.display(26))
                            Text(r["domain"].nonEmpty ?? "").foregroundStyle(Brand.orange).font(.callout)
                            if let d = r["description"].nonEmpty { Text(d).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                        }
                        Spacer()
                        if let c = r["country"].nonEmpty { Chip(text: displayName(c, .region)) }
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct BrandProfileView: View {
    enum Preview: String { case auto = "Auto", light = "Light", dark = "Dark" }

    @EnvironmentObject private var model: AppModel
    let brand: JSON
    var partial = false
    @State private var preview = Preview.auto

    var body: some View {
        let domain = brand["domain"].nonEmpty
        VStack(spacing: 14) {
            header(domain: domain)
            if partial { Chip(text: "Partial profile: some enrichment timed out", systemImage: "hourglass", tint: .yellow).frame(maxWidth: .infinity, alignment: .leading) }
            if !brand["colors"].list.isEmpty { colors }
            if !logoList.isEmpty { logos }
            if !brand["backdrops"].list.isEmpty { backdrops }
            details
        }
    }

    // MARK: Sections

    private func header(domain: String?) -> some View {
        let logo = bestLogo
        return GlassCard {
            HStack(alignment: .top, spacing: 18) {
                Avatar(url: logo, name: brand["title"].nonEmpty ?? domain ?? "?", size: 84, round: false)
                VStack(alignment: .leading, spacing: 6) {
                    Text(brand["title"].nonEmpty ?? domain ?? "Brand").font(Brand.display(44))
                    if let slogan = brand["slogan"].nonEmpty { Text(slogan).font(Brand.displayItalic(22)).foregroundStyle(.secondary) }
                    if let domain { LinkChip(urlString: domain, label: domain) }
                    if let d = brand["description"].nonEmpty { Text(d).foregroundStyle(.secondary).lineSpacing(3).padding(.top, 4) }
                    FlowLayout(spacing: 6) {
                        if brand["is_nsfw"].flag == true { Chip(text: "Adult content", systemImage: "exclamationmark.triangle", tint: .red) }
                        ForEach(industryLabels, id: \.self) { Chip(text: $0) }
                    }
                    if let domain {
                        FlowLayout(spacing: 6) {
                            Button { model.open(.styleguide, values: ["domain": domain]) } label: { Label("Style guide", systemImage: "textformat.size") }
                                .buttonStyle(.softGlass).controlSize(.small)
                            Button { model.open(.news, values: ["mode": "company", "kind": "domain", "query": domain]) } label: { Label("News", systemImage: "newspaper") }
                                .buttonStyle(.softGlass).controlSize(.small)
                            Button { model.open(.peopleSearch, values: ["query": "People who work at \(brand["title"].nonEmpty ?? domain)"]) } label: { Label("People", systemImage: "person.2") }
                                .buttonStyle(.softGlass).controlSize(.small)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private var colors: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Colours")
                FlowLayout(spacing: 10) {
                    ForEach(Array(brand["colors"].list.enumerated()), id: \.offset) { _, c in
                        if let hex = c["hex"].nonEmpty { Swatch(hex: hex, name: c["name"].nonEmpty, note: c["source"].nonEmpty) }
                    }
                }
            }
        }
    }

    private var logos: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel("Logos")
                    Spacer()
                    Picker("Preview on", selection: $preview) {
                        ForEach([Preview.auto, .light, .dark], id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).frame(width: 190).labelsHidden()
                }
                FlowLayout(spacing: 12) {
                    ForEach(Array(logoList.enumerated()), id: \.offset) { _, logo in
                        LogoTile(logo: logo, preview: preview)
                    }
                }
            }
        }
    }

    private var backdrops: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Backdrops")
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(brand["backdrops"].list.enumerated()), id: \.offset) { _, b in
                            if let s = b["url"].nonEmpty, let u = URL(string: s) {
                                Link(destination: u) {
                                    RemoteImage(url: u, contentMode: .fill) { Rectangle().fill(.quaternary) }
                                    .frame(width: 300, height: 170)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var details: some View {
        let a = brand["address"]
        let address = [a["street"].nonEmpty, a["city"].nonEmpty, a["state_province"].nonEmpty ?? a["state_code"].nonEmpty,
                       a["postal_code"].nonEmpty, a["country"].nonEmpty].compactMap { $0 }.joined(separator: ", ")
        let emp = brand["employees"]
        let stock = brand["stock"]
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Details")
                VStack(alignment: .leading, spacing: 6) {
                    InfoRow(label: "Address", value: address.isEmpty ? brand["location"].nonEmpty : address, systemImage: "mappin.and.ellipse")
                    InfoRow(label: "Employees", value: emp["exact"].int.map { $0.formatted() } ?? emp["range"].nonEmpty, systemImage: "person.2")
                    InfoRow(label: "Stock", value: [stock["ticker"].nonEmpty, stock["exchange"].nonEmpty].compactMap { $0 }.joined(separator: " · "), systemImage: "chart.line.uptrend.xyaxis")
                    InfoRow(label: "Email", value: brand["email"].nonEmpty, systemImage: "envelope")
                    InfoRow(label: "Phone", value: brand["phone"].nonEmpty, systemImage: "phone")
                }
                let socials = brand["socials"].list
                if !socials.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Social profiles")
                        FlowLayout(spacing: 6) {
                            ForEach(Array(socials.enumerated()), id: \.offset) { _, s in
                                if let u = s["url"].nonEmpty { LinkChip(urlString: u, label: s["type"].nonEmpty.map { $0.capitalized }) }
                            }
                        }
                    }
                }
                let links = usefulLinks
                if !links.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Useful pages")
                        FlowLayout(spacing: 6) { ForEach(links, id: \.1) { LinkChip(urlString: $0.1, label: $0.0) } }
                    }
                }
            }
        }
    }

    // MARK: Helpers

    /// Full logo list, or the single `logo` URL some responses carry instead.
    private var logoList: [JSON] {
        let logos = brand["logos"].list
        if !logos.isEmpty { return logos }
        if let single = brand["logo"].nonEmpty { return [.object(["url": .string(single), "type": .string("logo"), "mode": .string("has_opaque_background")])] }
        return []
    }

    private var bestLogo: String? {
        let logos = logoList
        return (logos.first { $0["type"].str == "icon" } ?? logos.first)?["url"].nonEmpty
    }

    /// Useful pages as (label, url), from either an object keyed by page or a list of {label, url}.
    private var usefulLinks: [(String, String)] {
        let l = brand["links"]
        if case .array(let items) = l {
            return items.compactMap { i in
                guard let u = i["url"].nonEmpty else { return nil }
                return (i["label"].nonEmpty ?? hostName(u), u)
            }
        }
        return ["careers", "pricing", "blog", "contact", "terms", "privacy"].compactMap { key in
            l[key].nonEmpty.map { (key.capitalized, $0) }
        }
    }

    private var industryLabels: [String] {
        brand["industries"]["eic"].list.compactMap { i in
            guard let ind = i["industry"].nonEmpty else { return nil }
            return [ind, i["subindustry"].nonEmpty].compactMap { $0 }.joined(separator: " › ")
        }
    }
}

private struct Swatch: View {
    let hex: String
    let name: String?
    let note: String?
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(css: hex) ?? .gray)
                    .frame(width: 112, height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.12)))
                    .overlay { if copied { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.white).shadow(radius: 3) } }
                Text(hex.uppercased()).font(.system(.callout, design: .monospaced).weight(.semibold))
                if let name { Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if let note { Text(note).font(.caption2).foregroundStyle(.tertiary) }
            }
            .frame(width: 112, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("Copy \(hex)")
    }
}

private struct LogoTile: View {
    let logo: JSON
    let preview: BrandProfileView.Preview

    var body: some View {
        let mode = logo["mode"].nonEmpty ?? "light"
        let dark: Bool = switch preview {
        case .auto: mode == "dark"
        case .light: false
        case .dark: true
        }
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                (dark ? Color(white: 0.09) : Color.white)
                if let s = logo["url"].nonEmpty, let u = URL(string: s) {
                    RemoteImage(url: u, contentMode: .fit) { ProgressView().controlSize(.small) }
                        .padding(14)
                }
            }
            .frame(width: 168, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.12)))

            HStack(spacing: 6) {
                Text((logo["type"].nonEmpty ?? "logo").capitalized).font(.caption.weight(.semibold))
                Text(mode.replacingOccurrences(of: "_", with: " ")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let s = logo["url"].nonEmpty { CopyButton(text: s, compact: true).help("Copy logo URL") }
            }
            if let w = logo["resolution"]["width"].int, let h = logo["resolution"]["height"].int {
                Text("\(w) × \(h)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(width: 168)
    }
}
