import Foundation

struct APIResult {
    var json: JSON
    var requestID: String?
    var consumed: Int
    var remaining: Int?
    var status: Int
    var elapsed: TimeInterval
}

struct APIError: LocalizedError {
    var status: Int
    var message: String
    var code: String?
    var requestID: String?

    var errorDescription: String? { message }
    var isOutOfCredits: Bool { status == 402 }

    static let missingKey = APIError(
        status: 0, message: "Add your Context.dev API key in Settings to start searching.", code: "NO_KEY")
}

/// Thin wrapper over https://api.context.dev/v1. Every network call in the app goes through here.
/// Retries 429 (honouring Retry-After) and 408/5xx with a short bounded backoff; never retries validation errors.
final class ContextClient {
    static let base = URL(string: "https://api.context.dev/v1")!

    private let session: URLSession
    private let apiKey: () -> String?

    init(apiKey: @escaping () -> String?) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 330
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    func post(_ path: String, _ body: [String: Any], timeout: TimeInterval = 150) async throws -> APIResult {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await send(path, method: "POST", query: [], body: data, contentType: "application/json", timeout: timeout)
    }

    func get(_ path: String, _ query: [URLQueryItem] = [], timeout: TimeInterval = 120) async throws -> APIResult {
        try await send(path, method: "GET", query: query, body: nil, contentType: nil, timeout: timeout)
    }

    func upload(_ path: String, query: [URLQueryItem], data: Data, contentType: String) async throws -> APIResult {
        try await send(path, method: "POST", query: query, body: data, contentType: contentType, timeout: 300)
    }

    private func send(_ path: String, method: String, query: [URLQueryItem], body: Data?,
                      contentType: String?, timeout: TimeInterval) async throws -> APIResult {
        guard let key = apiKey(), !key.isEmpty else { throw APIError.missingKey }

        var comps = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var request = URLRequest(url: comps.url!, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.httpBody = body

        var attempt = 0
        while true {
            try Task.checkCancellation()
            let started = Date()
            let (data, response) = try await session.data(for: request)
            let http = response as! HTTPURLResponse
            let rid = http.value(forHTTPHeaderField: "X-Request-Id")
            let parsed = try? JSONDecoder().decode(JSON.self, from: data)

            if (200..<300).contains(http.statusCode) {
                let json = parsed ?? .null
                let meta = json["key_metadata"]
                return APIResult(
                    json: json, requestID: json["request_id"].nonEmpty ?? rid,
                    consumed: meta["credits_consumed"].int ?? 0, remaining: meta["credits_remaining"].int,
                    status: http.statusCode, elapsed: Date().timeIntervalSince(started))
            }

            if attempt < 2, [408, 429, 500, 502, 503, 504].contains(http.statusCode) {
                attempt += 1
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                try await Task.sleep(for: .seconds(min(retryAfter ?? Double(1 << attempt), 20)))
                continue
            }

            throw Self.error(status: http.statusCode, body: parsed, requestID: rid)
        }
    }

    private static func error(status: Int, body: JSON?, requestID: String?) -> APIError {
        let code = body?["error_code"].nonEmpty
        var message = body?["message"].nonEmpty ?? body?["error"].nonEmpty
        if message == nil {
            message = HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        }
        switch status {
        case 401: message = "The API key was rejected. Check it in Settings. (\(message ?? "Unauthorized"))"
        case 402: message = "Out of Context.dev credits. \(message ?? "")"
        case 429: message = "Rate limited by Context.dev. Wait a moment and try again."
        default: break
        }
        return APIError(status: status, message: message ?? "Request failed", code: code, requestID: requestID ?? body?["request_id"].nonEmpty)
    }
}
