import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var selection: Tool = .peopleSearch
    @Published private(set) var visited: Set<Tool> = [.peopleSearch]
    @Published private(set) var hasKey = false
    @Published private(set) var credits: Int?
    @Published private(set) var usage: JSON?
    @Published var showSettings = false
    @Published var handoff: Handoff?

    private var key: String?
    private var runners: [Tool: ToolRunner] = [:]
    private(set) lazy var client = ContextClient(apiKey: { [weak self] in self?.key })

    private static let keyAccount = "context-dev-api-key"

    init() {
        key = Keychain.read(Self.keyAccount) ?? ProcessInfo.processInfo.environment["CONTEXT_DEV_API_KEY"]
        hasKey = key?.isEmpty == false
        #if DEBUG
        if CommandLine.arguments.contains("--demo") { loadDemo(); return }
        #endif
        if hasKey { Task { await refreshUsage() } }
    }

    #if DEBUG
    /// Fills every tool with synthetic results so screens can be checked without spending credits.
    private func loadDemo() {
        hasKey = true
        credits = 998
        let args = CommandLine.arguments
        if !args.contains("--empty") {
            for tool in Tool.allCases {
                if let json = DemoData.response(for: tool) { runner(for: tool).loadDemo(json) }
            }
        }
        if let i = args.firstIndex(of: "--tool"), args.indices.contains(i + 1), let t = Tool(rawValue: args[i + 1]) { select(t) }
    }
    #endif

    // MARK: Key

    func saveKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Keychain.write(trimmed, account: Self.keyAccount)
        key = trimmed
        hasKey = true
        Task { await refreshUsage() }
    }

    func removeKey() {
        Keychain.delete(Self.keyAccount)
        key = ProcessInfo.processInfo.environment["CONTEXT_DEV_API_KEY"]
        hasKey = key?.isEmpty == false
        if !hasKey { credits = nil; usage = nil }
    }

    // MARK: Navigation

    func select(_ tool: Tool) {
        visited.insert(tool)
        selection = tool
    }

    /// Opens another tool with fields pre-filled, optionally running it straight away.
    func open(_ tool: Tool, values: [String: String], run: Bool = true) {
        select(tool)
        handoff = Handoff(tool: tool, values: values, run: run)
    }

    func runner(for tool: Tool) -> ToolRunner {
        if let r = runners[tool] { return r }
        let r = ToolRunner(model: self)
        runners[tool] = r
        return r
    }

    // MARK: Credits

    func refreshUsage() async {
        guard hasKey else { return }
        if let r = try? await client.get("org/usage") {
            usage = r.json
            credits = r.json["credits_remaining"].int
        }
    }

    func noteRemaining(_ value: Int?) {
        if let value { credits = value }
    }
}

/// Owns one tool's in-flight request, its results (including extra pages) and its error state,
/// so results survive switching tools in the sidebar.
@MainActor
final class ToolRunner: ObservableObject {
    enum Phase: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var pages: [APIResult] = []
    @Published private(set) var error: APIError?
    @Published private(set) var loadingMore = false
    @Published private(set) var creditsSpent = 0

    private weak var model: AppModel?
    private var task: Task<Void, Never>?
    private var fetch: ((String?) async throws -> APIResult)?
    private var cursorOf: (JSON) -> String? = { _ in nil }
    private(set) var nextCursor: String?

    init(model: AppModel) { self.model = model }

    var canLoadMore: Bool { nextCursor != nil && phase == .loaded }
    var latest: APIResult? { pages.last }
    var isLoading: Bool { phase == .loading }

    /// Raw JSON for every page, for the Raw tab and exports.
    var rawJSON: JSON {
        pages.count == 1 ? pages[0].json : .array(pages.map(\.json))
    }

    func run(cursor: @escaping (JSON) -> String? = { _ in nil },
             _ fetch: @escaping (String?) async throws -> APIResult) {
        task?.cancel()
        self.fetch = fetch
        cursorOf = cursor
        nextCursor = nil
        error = nil
        creditsSpent = 0
        phase = .loading
        task = Task { [weak self] in
            do {
                let result = try await fetch(nil)
                guard let self, !Task.isCancelled else { return }
                self.pages = [result]
                self.absorb(result)
                self.phase = .loaded
            } catch is CancellationError {
                self?.phase = self?.pages.isEmpty == false ? .loaded : .idle
            } catch let urlError as URLError where urlError.code == .cancelled {
                self?.phase = self?.pages.isEmpty == false ? .loaded : .idle
            } catch {
                self?.fail(error)
            }
        }
    }

    func loadMore() {
        guard let fetch, let cursor = nextCursor, !loadingMore else { return }
        loadingMore = true
        task = Task { [weak self] in
            defer { self?.loadingMore = false }
            do {
                let result = try await fetch(cursor)
                guard let self, !Task.isCancelled else { return }
                self.pages.append(result)
                self.absorb(result)
            } catch is CancellationError {
            } catch {
                self?.fail(error, keepResults: true)
            }
        }
    }

    #if DEBUG
    func loadDemo(_ json: JSON) {
        pages = [APIResult(json: json, requestID: "demo", consumed: json["key_metadata"]["credits_consumed"].int ?? 0,
                           remaining: json["key_metadata"]["credits_remaining"].int, elapsed: 0.8)]
        nextCursor = json["next_cursor"].nonEmpty
        phase = .loaded
    }
    #endif

    func cancel() {
        task?.cancel()
        loadingMore = false
        if phase == .loading { phase = pages.isEmpty ? .idle : .loaded }
    }

    private func absorb(_ result: APIResult) {
        creditsSpent += result.consumed
        nextCursor = cursorOf(result.json)
        model?.noteRemaining(result.remaining)
    }

    private func fail(_ error: Error, keepResults: Bool = false) {
        let apiError = (error as? APIError) ?? APIError(status: 0, message: error.localizedDescription)
        self.error = apiError
        phase = keepResults && !pages.isEmpty ? .loaded : .failed(apiError.message)
        if apiError.isOutOfCredits { Task { await model?.refreshUsage() } }
    }
}

/// Recent queries per tool, shown in a menu beside the main field.
enum Recents {
    private static func key(_ tool: Tool) -> String { "recents.\(tool.rawValue)" }

    static func list(_ tool: Tool) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(tool)) ?? []
    }

    static func add(_ text: String, for tool: Tool) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var items = list(tool).filter { $0.caseInsensitiveCompare(t) != .orderedSame }
        items.insert(t, at: 0)
        UserDefaults.standard.set(Array(items.prefix(10)), forKey: key(tool))
    }

    static func clear(_ tool: Tool) {
        UserDefaults.standard.removeObject(forKey: key(tool))
    }
}
