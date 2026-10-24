import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            ZStack {
                BrandBackdrop()
                ForEach(Tool.allCases) { tool in
                    if model.visited.contains(tool) {
                        let active = model.selection == tool
                        ToolHost(tool: tool)
                            .opacity(active ? 1 : 0)
                            .allowsHitTesting(active)
                            .disabled(!active)
                            .accessibilityHidden(!active)
                            .zIndex(active ? 1 : 0)
                    }
                }
            }
            .navigationTitle(model.selection.title)
        }
        .sheet(isPresented: $model.showSettings) { SettingsView().environmentObject(model) }
        .onAppear { if !model.hasKey { model.showSettings = true } }
    }
}

/// Keeps each tool's form state alive after its first visit, so switching tools never loses work.
private struct ToolHost: View {
    let tool: Tool

    var body: some View {
        switch tool {
        case .peopleSearch: PeopleSearchTool()
        case .peopleEnrich: PeopleEnrichTool()
        case .webSearch: WebSearchTool()
        case .news: NewsTool()
        case .answers: AnswersTool()
        case .scrape: ScrapeTool()
        case .map: MapTool()
        case .crawl: CrawlTool()
        case .companySearch: CompanySearchTool()
        case .brand: BrandTool()
        case .styleguide: StyleguideTool()
        case .parse: ParseTool()
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: Binding<Tool?>(get: { model.selection }, set: { if let t = $0 { model.select(t) } })) {
            ForEach(ToolGroup.allCases) { group in
                Section(group.rawValue) {
                    ForEach(group.tools) { tool in
                        Label(tool.title, systemImage: tool.symbol).tag(tool).listItemTint(Brand.orange)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                LogoMark(size: 34)
                Wordmark(size: 24)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { CreditsFooter().padding(10) }
    }
}

private struct CreditsFooter: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button { model.showSettings = true } label: {
            HStack(spacing: 10) {
                Image(systemName: model.hasKey ? "bolt.fill" : "key.fill").foregroundStyle(Brand.orange)
                VStack(alignment: .leading, spacing: 1) {
                    if model.hasKey {
                        Text(model.credits.map { "\($0.formatted()) credits" } ?? "Checking credits…").font(.callout.weight(.semibold))
                        Text(refill).font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("Add API key").font(.callout.weight(.semibold))
                        Text("Needed to search").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "gearshape").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Credits and API key")
    }

    private var refill: String {
        guard let iso = model.usage?["next_refill"]["at"].nonEmpty, let when = relativeDate(iso) else { return "Open settings" }
        return "Refills \(when)"
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                LogoMark(size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Wordmark(size: 32)
                    Text("People, companies, brands and the web, in one place.").font(.callout).foregroundStyle(.secondary)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Context.dev API key")
                    SecureField(model.hasKey ? "A key is saved in your Keychain" : "ctxt_secret_…", text: $key)
                        .textFieldStyle(.roundedBorder)
                    Text("Stored in the macOS Keychain on this Mac. It is only ever sent to api.context.dev.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Link("Get or rotate a key", destination: URL(string: "https://www.context.dev/dashboard/api-keys")!)
                            .font(.callout)
                        Spacer()
                        if model.hasKey {
                            Button("Remove", role: .destructive) { model.removeKey(); key = "" }.buttonStyle(.softGlass)
                        }
                        Button("Save Key") { model.saveKey(key); key = "" }
                            .buttonStyle(.glassProminent).tint(Brand.orange)
                            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }

            if model.hasKey {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionLabel("Credits")
                            Spacer()
                            Button { Task { checking = true; await model.refreshUsage(); checking = false } } label: {
                                if checking { ProgressView().controlSize(.small) } else { Label("Refresh", systemImage: "arrow.clockwise") }
                            }
                            .buttonStyle(.softGlass).controlSize(.small)
                        }
                        HStack(spacing: 10) {
                            StatTile(value: model.credits?.formatted() ?? "–", label: "Remaining")
                            StatTile(value: model.usage?["period"]["credits_used"].int?.formatted() ?? "–", label: "Used this period")
                            StatTile(value: model.usage?["next_refill"]["credits"].int?.formatted() ?? "–", label: "Next refill")
                        }
                        if let iso = model.usage?["next_refill"]["at"].nonEmpty, let when = relativeDate(iso) {
                            Text("Refills \(when). Auto top-up is \(model.usage?["auto_topup"]["enabled"].flag == true ? "on" : "off").")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack {
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.softGlass).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(BrandBackdrop())
    }
}
