import SwiftUI

struct PeopleEnrichTool: View {
    struct EduRow: Identifiable {
        let id = UUID()
        var institution = ""
        var degree = ""
        var field = ""
        var year = ""
    }

    @EnvironmentObject private var model: AppModel
    @State private var first = ""
    @State private var last = ""
    @State private var email = ""
    @State private var social = ""
    @State private var company = ""
    @State private var domain = ""
    @State private var city = ""
    @State private var region = ""
    @State private var country = ""
    @State private var education: [EduRow] = []

    private var runner: ToolRunner { model.runner(for: .peopleEnrich) }

    private var hasClue: Bool {
        [first, last, email, social, company, domain].contains { $0.nilIfBlank != nil } || education.contains { $0.institution.nilIfBlank != nil }
    }

    var body: some View {
        ToolScaffold(tool: .peopleEnrich, runner: runner, canRun: hasClue, onRun: run) {
            Section("Name") {
                TextField("First name", text: $first)
                TextField("Last name", text: $last)
                    .onSubmit(run)
            }
            Section("Contact & profiles") {
                TextField("Work email", text: $email, prompt: Text("name@company.com"))
                TextField("Profile links, one per line", text: $social, prompt: Text("linkedin.com/in/…"), axis: .vertical)
                    .lineLimit(2...5)
            }
            Section("Employer") {
                TextField("Company name", text: $company)
                TextField("Company domain", text: $domain, prompt: Text("example.com"))
            }
            Section("Location") {
                TextField("City", text: $city)
                TextField("State / region", text: $region)
                TextField("Country", text: $country)
            }
            Section("Education") {
                ForEach($education) { $row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Institution", text: $row.institution)
                            Button { education.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle.fill") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary)
                        }
                        TextField("Degree", text: $row.degree)
                        TextField("Field of study", text: $row.field)
                        TextField("Graduation year", text: $row.year)
                    }
                }
                Button { education.append(EduRow()) } label: { Label("Add education", systemImage: "plus.circle") }
                    .buttonStyle(.borderless)
            }
            Section {
                Text("The more clues you give, the better the match. Results include a match score so weak guesses are easy to spot.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } results: { runner in
            if let result = runner.latest { EnrichResultView(result: result.json) }
        }
        .onHandoff(for: .peopleEnrich) { v, go in
            first = v["first"] ?? first
            last = v["last"] ?? last
            email = v["email"] ?? email
            company = v["company"] ?? company
            domain = v["domain"] ?? domain
            social = v["social"] ?? social
            if go { run() }
        }
    }

    private func run() {
        guard hasClue else { return }
        var body: [String: Any] = [:]
        body.put("social_urls", nonEmpty: social.tokens)
        var name: [String: Any] = [:]
        name.put("first", first.nilIfBlank); name.put("last", last.nilIfBlank)
        if !name.isEmpty { body["name"] = name }
        body.put("email", email.nilIfBlank)
        var co: [String: Any] = [:]
        co.put("name", company.nilIfBlank); co.put("domain", domain.nilIfBlank)
        if !co.isEmpty { body["company"] = co }
        var loc: [String: Any] = [:]
        loc.put("city", city.nilIfBlank); loc.put("region", region.nilIfBlank); loc.put("country", country.nilIfBlank)
        if !loc.isEmpty { body["location"] = loc }
        let edu: [[String: Any]] = education.compactMap { row in
            guard let inst = row.institution.nilIfBlank else { return nil }
            var e: [String: Any] = ["institution": ["name": inst]]
            e.put("degree", row.degree.nilIfBlank)
            e.put("field_of_study", row.field.nilIfBlank)
            e.put("graduation_year", row.year.asInt)
            return e
        }
        body.put("education", nonEmpty: edu)

        if let who = [first, last].compactMap(\.nilIfBlank).joined(separator: " ").nilIfBlank ?? email.nilIfBlank {
            Recents.add(who, for: .peopleEnrich)
        }
        let client = model.client
        runner.run { _ in try await client.post("people/enrich", body) }
    }
}

struct EnrichResultView: View {
    let result: JSON

    var body: some View {
        let match = result["match"]
        if match["status"].str == "candidate" {
            let score = match["score"].int ?? 0
            VStack(spacing: 14) {
                GlassCard {
                    HStack(spacing: 16) {
                        ScoreRing(score: score, size: 72)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verdict(score)).font(Brand.display(26))
                            Text("Match score \(score) out of 100. Check the details below before relying on a low score.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                PersonProfileCard(person: match["person"])
            }
        } else {
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    Label("No match found", systemImage: "person.fill.questionmark").font(.headline)
                    Text("Nothing confident came back for those clues. Add an employer, a profile link or a location and try again.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func verdict(_ score: Int) -> String {
        switch score {
        case 85...: "Very likely a match"
        case 60..<85: "Probable match"
        default: "Weak match"
        }
    }
}

struct PersonProfileCard: View {
    @EnvironmentObject private var model: AppModel
    let person: JSON

    var body: some View {
        let name = person["name"]["full"].nonEmpty ?? [person["name"]["first"].nonEmpty, person["name"]["last"].nonEmpty].compactMap { $0 }.joined(separator: " ")
        let current = person["current_role"]
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    Avatar(url: person["avatar_url"].nonEmpty, name: name, size: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name.isEmpty ? "Unnamed" : name).font(Brand.display(38))
                        if let title = current["title"].nonEmpty {
                            Text([title, current["organization"]["name"].nonEmpty].compactMap { $0 }.joined(separator: " at "))
                                .font(.title3).foregroundStyle(.primary.opacity(0.85))
                        } else if person["current_role_status"].str == "none" {
                            Text("No current role found").foregroundStyle(.secondary)
                        }
                        if let bio = person["bio"].nonEmpty {
                            Text(bio).font(.callout).foregroundStyle(.secondary).lineSpacing(2).padding(.top, 2)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    InfoRow(label: "Location", value: person["location"]["display"].nonEmpty ?? locationText, systemImage: "mappin.and.ellipse")
                    InfoRow(label: "Email", value: person["email"].nonEmpty, systemImage: "envelope")
                    InfoRow(label: "Last updated", value: relativeDate(person["last_updated"].nonEmpty), systemImage: "arrow.triangle.2.circlepath")
                }

                if !person["social_urls"].list.isEmpty || !person["website_urls"].list.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(person["social_urls"].strings, id: \.self) { LinkChip(urlString: $0) }
                        ForEach(person["website_urls"].strings, id: \.self) { LinkChip(urlString: $0) }
                        if let domain = current["organization"]["domain"].nonEmpty {
                            Button { model.open(.brand, values: ["mode": "retrieve", "kind": "domain", "value": domain]) } label: {
                                Label("Company brand", systemImage: "paintpalette")
                            }
                            .buttonStyle(.softGlass).controlSize(.small)
                        }
                    }
                }

                if !person["experience"].list.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Experience")
                        ForEach(Array(person["experience"].list.enumerated()), id: \.offset) { _, job in ExperienceRow(job: job) }
                    }
                }
                if !person["education"].list.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Education")
                        ForEach(Array(person["education"].list.enumerated()), id: \.offset) { _, ed in EducationRow(ed: ed) }
                    }
                }
                if !person["skills"].list.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Skills")
                        ChipFlow(items: person["skills"].strings, limit: 30)
                    }
                }
            }
        }
    }

    private var locationText: String? {
        let l = person["location"]
        let parts = [l["city"].nonEmpty, l["region"].nonEmpty, l["country"].nonEmpty].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

private func monthYear(_ d: JSON) -> String? {
    guard let y = d["year"].int else { return nil }
    if let m = d["month"].int, (1...12).contains(m) {
        return "\(Calendar.current.shortMonthSymbols[m - 1]) \(y)"
    }
    return "\(y)"
}

private func range(_ start: JSON, _ end: JSON, current: Bool = false) -> String? {
    let s = monthYear(start)
    let e = current ? "Present" : monthYear(end)
    switch (s, e) {
    case let (s?, e?): return "\(s) – \(e)"
    case let (s?, nil): return "\(s) –"
    case let (nil, e?): return "Until \(e)"
    default: return nil
    }
}

private struct ExperienceRow: View {
    let job: JSON

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(job["is_current"].flag == true ? Brand.orange : Color.secondary.opacity(0.4))
                .frame(width: 9, height: 9).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(job["title"].nonEmpty ?? "Role").font(.headline)
                Text([job["organization"]["name"].nonEmpty, job["location"].nonEmpty].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                if let r = range(job["start_date"], job["end_date"], current: job["is_current"].flag == true) {
                    Text(r).font(.caption).foregroundStyle(.tertiary)
                }
                if let d = job["description"].nonEmpty {
                    Text(d).font(.callout).foregroundStyle(.secondary).lineLimit(4).padding(.top, 2)
                }
            }
        }
    }
}

private struct EducationRow: View {
    let ed: JSON

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "graduationcap.fill").foregroundStyle(Brand.orange).frame(width: 9).padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(ed["institution"]["name"].nonEmpty ?? "School").font(.headline)
                Text([ed["degree"].nonEmpty, ed["field_of_study"].nonEmpty].compactMap { $0 }.joined(separator: ", "))
                    .foregroundStyle(.secondary)
                if let r = range(ed["start_date"], ed["end_date"]) { Text(r).font(.caption).foregroundStyle(.tertiary) }
            }
        }
    }
}
