import SwiftUI

struct PeopleSearchTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var countries = Set<String>()
    @State private var minYears = ""
    @State private var maxYears = ""

    private var runner: ToolRunner { model.runner(for: .peopleSearch) }

    var body: some View {
        ToolScaffold(tool: .peopleSearch, runner: runner, canRun: query.nilIfBlank != nil, onRun: run) {
            Section("Who are you looking for?") {
                QueryField(tool: .peopleSearch, title: "e.g. VPs of sales at solar companies in California",
                           text: $query, axis: .vertical, onSubmit: run)
            }
            Section("Filters") {
                MultiPicker(title: "Lives in", selection: $countries,
                            codes: Options.webCountries.map { $0.uppercased() }, kind: .region)
                TextField("Min. years of experience", text: $minYears, prompt: Text("Any"))
                TextField("Max. years of experience", text: $maxYears, prompt: Text("Any"))
            }
            Section {
                Text("Each page returns up to 10 people. Use “Load more” to continue the same search.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } results: { runner in
            PeopleSearchResults(runner: runner)
        }
        .onHandoff(for: .peopleSearch) { values, go in
            query = values["query"] ?? query
            if go { run() }
        }
    }

    private func run() {
        guard let q = query.nilIfBlank else { return }
        Recents.add(q, for: .peopleSearch)
        var filters: [String: Any] = [:]
        filters.put("countries", nonEmpty: countries.sorted())
        filters.put("years_of_experience_min", minYears.asInt)
        filters.put("years_of_experience_max", maxYears.asInt)
        let client = model.client
        runner.run(cursor: { $0["next_cursor"].nonEmpty }) { cursor in
            var body: [String: Any] = ["query": q]
            if !filters.isEmpty { body["filters"] = filters }
            if let cursor { body["cursor"] = cursor }
            return try await client.post("people/search", body)
        }
    }
}

private struct PeopleSearchResults: View {
    @ObservedObject var runner: ToolRunner

    var body: some View {
        let people = runner.pages.flatMap { $0.json["results"].list }
        VStack(spacing: 14) {
            HStack {
                StatTile(value: "\(people.count)", label: people.count == 1 ? "person" : "people")
                Spacer()
            }
            if people.isEmpty {
                GlassCard { Text("No one matched that description. Try fewer filters or a broader query.").foregroundStyle(.secondary) }
            }
            ForEach(Array(people.enumerated()), id: \.offset) { _, person in PersonSearchCard(person: person) }
        }
    }
}

struct PersonSearchCard: View {
    @EnvironmentObject private var model: AppModel
    let person: JSON

    var body: some View {
        let name = person["name"].nonEmpty ?? "Unnamed"
        let role = person["role"]
        let company = role["company"]
        GlassCard {
            HStack(alignment: .top, spacing: 16) {
                Avatar(url: nil, name: name, size: 60)
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(Brand.display(30))
                        if let headline = headline(role, company) {
                            Text(headline).font(.headline).foregroundStyle(.primary.opacity(0.85))
                        }
                    }
                    if let d = person["description"].nonEmpty {
                        Text(d).font(.callout).foregroundStyle(.secondary).lineSpacing(2)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        InfoRow(label: "Location", value: location(person["location"]), systemImage: "mappin.and.ellipse")
                        InfoRow(label: "Experience", value: person["years_of_experience"].int.map { "\($0) years" }, systemImage: "clock")
                        InfoRow(label: "In role since", value: role["started_on"].nonEmpty, systemImage: "calendar")
                        InfoRow(label: "Education", value: person["schools"].strings.joined(separator: " · "), systemImage: "graduationcap")
                    }
                    FlowLayout(spacing: 6) {
                        if person["is_founder"].flag == true { Chip(text: "Founder", systemImage: "flag.fill", tint: Brand.orange) }
                        if let s = role["seniority"].nonEmpty { Chip(text: prettyLabel(s)) }
                        ForEach(role["functions"].strings, id: \.self) { Chip(text: prettyLabel($0)) }
                    }
                    if !person["skills"].list.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel("Skills")
                            ChipFlow(items: person["skills"].strings, limit: 12)
                        }
                    }
                    actions(name: name, company: company)
                }
            }
        }
    }

    private func headline(_ role: JSON, _ company: JSON) -> String? {
        switch (role["title"].nonEmpty, company["name"].nonEmpty) {
        case let (t?, c?): "\(t) at \(c)"
        case let (t?, nil): t
        case let (nil, c?): c
        default: nil
        }
    }

    private func location(_ l: JSON) -> String? {
        let parts = [l["city"].nonEmpty, l["region"].nonEmpty, l["country_code"].nonEmpty].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func actions(name: String, company: JSON) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(person["profiles"].strings, id: \.self) { LinkChip(urlString: $0) }
            Button {
                let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
                model.open(.peopleEnrich, values: [
                    "first": parts.first ?? "", "last": parts.count > 1 ? parts[1] : "",
                    "company": company["name"].nonEmpty ?? "", "domain": company["domain"].nonEmpty ?? "",
                    "social": person["profiles"].strings.joined(separator: "\n"),
                ])
            } label: { Label("Full profile", systemImage: "person.text.rectangle") }
                .buttonStyle(.softGlass).controlSize(.small)
            if let domain = company["domain"].nonEmpty {
                Button { model.open(.brand, values: ["mode": "retrieve", "kind": "domain", "value": domain]) } label: {
                    Label("Company brand", systemImage: "paintpalette")
                }
                .buttonStyle(.softGlass).controlSize(.small)
            }
        }
    }
}
