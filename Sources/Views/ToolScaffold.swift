import SwiftUI
import UniformTypeIdentifiers

/// Shared layout for every tool: a glass form panel on the left, results on the right.
/// Handles the empty, loading, error, formatted/raw and "load more" states so each tool only supplies its form and result views.
struct ToolScaffold<FormContent: View, ResultContent: View>: View {
    enum Mode: String { case formatted = "Formatted", raw = "Raw JSON" }

    @EnvironmentObject private var model: AppModel
    let tool: Tool
    @ObservedObject var runner: ToolRunner
    var canRun = true
    var costNote: String?
    var onRun: () -> Void
    @ViewBuilder var form: FormContent
    @ViewBuilder var results: (ToolRunner) -> ResultContent
    @State private var mode: Mode = .formatted

    var body: some View {
        HStack(spacing: 0) {
            formPanel
                .frame(width: 356)
                .padding([.leading, .vertical], 12)
            resultsPanel
        }
    }

    // MARK: Form

    private var formPanel: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tool.title).font(Brand.display(34))
                Text(tool.blurb).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 6)

            Form { form }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)

            runBar
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var runBar: some View {
        VStack(spacing: 8) {
            if runner.isLoading {
                Button(role: .cancel) { runner.cancel() } label: {
                    Label("Cancel", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.softGlass).controlSize(.large)
            } else {
                Button(action: onRun) {
                    Label(tool.verb, systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).tint(Brand.orange).controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canRun || !model.hasKey)
            }
            if !model.hasKey {
                Button("Add your API key to start") { model.showSettings = true }
                    .buttonStyle(.link).font(.caption)
            } else {
                Text(costNote ?? tool.cost).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    // MARK: Results

    private var resultsPanel: some View {
        VStack(spacing: 0) {
            if runner.phase == .loaded || runner.error != nil && !runner.pages.isEmpty { toolbar }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch runner.phase {
        case .idle: emptyState
        case .loading: loadingState
        case .failed: ScrollView { ErrorCard(error: runner.error).padding(24) }
        case .loaded:
            ScrollView {
                VStack(spacing: 14) {
                    if mode == .formatted {
                        results(runner)
                    } else {
                        RawJSONView(json: runner.rawJSON)
                    }
                    if let error = runner.error { ErrorCard(error: error) }
                    if runner.canLoadMore && mode == .formatted { loadMore }
                }
                .padding(20)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("View", selection: $mode) {
                Text(Mode.formatted.rawValue).tag(Mode.formatted)
                Text(Mode.raw.rawValue).tag(Mode.raw)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 210)

            Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if let rid = runner.latest?.requestID { CopyButton(text: rid, label: "Request ID") }
            CopyButton(text: runner.rawJSON.pretty, label: "Copy JSON")
            Button { save() } label: { Label("Save…", systemImage: "square.and.arrow.down") }
                .buttonStyle(.softGlass).controlSize(.small)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var summary: String {
        var parts: [String] = []
        if runner.creditsSpent > 0 { parts.append("\(runner.creditsSpent) credit\(runner.creditsSpent == 1 ? "" : "s")") }
        if let left = runner.latest?.remaining { parts.append("\(left.formatted()) left") }
        if let t = runner.latest?.elapsed { parts.append(String(format: "%.1fs", t)) }
        return parts.joined(separator: " · ")
    }

    private var loadMore: some View {
        Button { runner.loadMore() } label: {
            HStack {
                if runner.loadingMore { ProgressView().controlSize(.small) }
                Text(runner.loadingMore ? "Loading…" : "Load more results")
            }
            .frame(maxWidth: 260)
        }
        .buttonStyle(.softGlass).controlSize(.large)
        .disabled(runner.loadingMore)
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            LogoMark(size: 92)
            Wordmark(size: 30)
            Text(tool.blurb).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
            Chip(text: tool.cost, systemImage: "bolt.fill", tint: Brand.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("\(tool.verb)ing…".replacingOccurrences(of: "eing…", with: "ing…"))
                .font(Brand.displayItalic(24)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let stamp = Date().formatted(.verbatim("\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)", locale: .current, timeZone: .current, calendar: .current))
        panel.nameFieldStringValue = "open-search-\(tool.rawValue)-\(stamp).json"
        if panel.runModal() == .OK, let url = panel.url {
            try? runner.rawJSON.pretty.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct ErrorCard: View {
    let error: APIError?

    var body: some View {
        GlassCard(tint: .red) {
            VStack(alignment: .leading, spacing: 8) {
                Label(error?.isOutOfCredits == true ? "Out of credits" : "That didn't work", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.red)
                Text(error?.message ?? "Something went wrong.").textSelection(.enabled)
                HStack(spacing: 8) {
                    if let code = error?.code { Chip(text: code) }
                    if let status = error?.status, status > 0 { Chip(text: "HTTP \(status)") }
                    if let rid = error?.requestID { CopyButton(text: rid, label: "Request ID") }
                }
            }
        }
    }
}
