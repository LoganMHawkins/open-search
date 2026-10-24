import SwiftUI

struct CompanySearchTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var countries = Set<String>()
    @State private var minEmployees = ""
    @State private var maxEmployees = ""

    private var runner: ToolRunner { model.runner(for: .companySearch) }

    var body: some View {
        ToolScaffold(tool: .companySearch, runner: runner, canRun: query.nilIfBlank != nil, onRun: run) {
            Section("Which companies?") {
                QueryField(tool: .companySearch, title: "e.g. Robotics companies, or “companies like stripe.com”",
                           text: $query, axis: .vertical, onSubmit: run)
                Text("Describe industry, headquarters, headcount, founding year, technology, traffic or funding stage.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Filters") {
                MultiPicker(title: "Headquartered in", selection: $countries,
                            codes: Options.webCountries.map { $0.uppercased() }, kind: .region)
                TextField("Min. employees", text: $minEmployees, prompt: Text("Any"))
                TextField("Max. employees", text: $maxEmployees, prompt: Text("Any"))
            }
            Section {
                Text("Up to 10 companies per page. Searches with no matches are free.").font(.caption).foregroundStyle(.secondary)
            }
        } results: { runner in
            CompanyResults(runner: runner)
        }
        .onHandoff(for: .companySearch) { v, go in
            query = v["query"] ?? query
            if go { run() }
        }
    }

    private func run() {
        guard let q = query.nilIfBlank else { return }
        Recents.add(q, for: .companySearch)
        var filters: [String: Any] = [:]
        filters.put("countries", nonEmpty: countries.sorted())
        filters.put("employees_min", minEmployees.asInt)
        filters.put("employees_max", maxEmployees.asInt)
        let client = model.client
        runner.run(cursor: { $0["next_cursor"].nonEmpty }) { cursor in
            var body: [String: Any] = ["query": q]
            if !filters.isEmpty { body["filters"] = filters }
            if let cursor { body["cursor"] = cursor }
            return try await client.post("company/search", body)
        }
    }
}

private struct CompanyResults: View {
    @ObservedObject var runner: ToolRunner

    var body: some View {
        let companies = runner.pages.flatMap { $0.json["results"].list }
        VStack(spacing: 14) {
            HStack {
                StatTile(value: "\(companies.count)", label: companies.count == 1 ? "company" : "companies")
                Spacer()
            }
            if companies.isEmpty {
                GlassCard { Text("No companies matched. Try a broader description.").foregroundStyle(.secondary) }
            }
            ForEach(Array(companies.enumerated()), id: \.offset) { _, c in CompanyCard(company: c) }
        }
    }
}

struct CompanyCard: View {
    @EnvironmentObject private var model: AppModel
    let company: JSON

    var body: some View {
        let name = company["name"].nonEmpty ?? "Company"
        let domain = company["domain"].nonEmpty
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Avatar(url: nil, name: name, size: 56, round: false)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(Brand.display(30))
                        HStack(spacing: 8) {
                            if let domain { Text(domain).foregroundStyle(Brand.orange) }
                            if let t = company["organization_type"].nonEmpty { Chip(text: t.replacingOccurrences(of: "_", with: " ").capitalized) }
                            if let s = company["operating_status"].nonEmpty { Chip(text: s.capitalized, tint: s.lowercased() == "active" ? .green : .gray) }
                            ForEach(company["stock_symbols"].strings, id: \.self) { Chip(text: $0, systemImage: "chart.line.uptrend.xyaxis") }
                        }
                        if let d = company["description"].nonEmpty { Text(d).foregroundStyle(.secondary).lineSpacing(2).padding(.top, 2) }
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    InfoRow(label: "Headquarters", value: hq, systemImage: "mappin.and.ellipse")
                    InfoRow(label: "Employees", value: employees, systemImage: "person.2")
                    InfoRow(label: "Founded", value: company["founded_year"].int.map(String.init), systemImage: "calendar")
                    InfoRow(label: "Revenue", value: revenue, systemImage: "dollarsign.circle")
                }

                if !company["industries"].list.isEmpty { ChipFlow(items: company["industries"].strings) }
                funding

                FlowLayout(spacing: 6) {
                    if let domain { LinkChip(urlString: domain, label: "Website") }
                    if let domain {
                        Button { model.open(.brand, values: ["mode": "retrieve", "kind": "domain", "value": domain]) } label: {
                            Label("Brand", systemImage: "paintpalette")
                        }
                        .buttonStyle(.softGlass).controlSize(.small)
                        Button { model.open(.news, values: ["mode": "company", "kind": "domain", "query": domain]) } label: {
                            Label("News", systemImage: "newspaper")
                        }
                        .buttonStyle(.softGlass).controlSize(.small)
                    }
                    Button { model.open(.peopleSearch, values: ["query": "People who work at \(name)"]) } label: {
                        Label("People", systemImage: "person.2")
                    }
                    .buttonStyle(.softGlass).controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var funding: some View {
        let f = company["funding"]
        if f["round_count"].int ?? 0 > 0 || f["total_usd"].int != nil || f["stage"].nonEmpty != nil {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Funding")
                HStack(spacing: 8) {
                    if let total = formattedUSD(f["total_usd"].int) { Chip(text: "\(total) raised", systemImage: "banknote", tint: Brand.orange) }
                    if let stage = f["stage"].nonEmpty { Chip(text: stage) }
                    if let n = f["round_count"].int, n > 0 { Chip(text: "\(n) round\(n == 1 ? "" : "s")") }
                }
                ForEach(Array(f["rounds"].list.prefix(6).enumerated()), id: \.offset) { _, r in
                    HStack {
                        Text(r["type"].nonEmpty ?? "Round").font(.callout.weight(.medium))
                        Spacer()
                        Text([formattedUSD(r["amount_usd"].int), r["date"].nonEmpty].compactMap { $0 }.joined(separator: " · "))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var hq: String? {
        let h = company["headquarters"]
        let parts = [h["street_address"].nonEmpty, h["city"].nonEmpty, h["region"].nonEmpty, h["country_code"].nonEmpty].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private var employees: String? {
        let e = company["employees"]
        if let c = e["count"].int { return c.formatted() }
        if let lo = e["min"].int, let hi = e["max"].int { return "\(lo.formatted())–\(hi.formatted())" }
        if let lo = e["min"].int { return "\(lo.formatted())+" }
        return nil
    }

    private var revenue: String? {
        let r = company["revenue"]
        switch (formattedUSD(r["min_usd"].int), formattedUSD(r["max_usd"].int)) {
        case let (lo?, hi?): return "\(lo) – \(hi) a year"
        case let (lo?, nil): return "\(lo)+ a year"
        case let (nil, hi?): return "Up to \(hi) a year"
        default: return nil
        }
    }
}
