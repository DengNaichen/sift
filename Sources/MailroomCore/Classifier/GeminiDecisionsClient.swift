import Foundation

public enum GeminiDecisionsError: Error, LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case invalidEndpoint(String)
    case httpError(statusCode: Int, message: String)
    case networkError(String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 API Key。"
        case .invalidEndpoint(let endpoint):
            return "无效的 API 端点：\(endpoint)"
        case .httpError(let statusCode, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "HTTP \(statusCode)" : "HTTP \(statusCode): \(trimmed)"
        case .networkError(let message):
            return "网络请求失败：\(message)"
        case .invalidResponse(let message):
            return "模型响应无效：\(message)"
        }
    }
}

/// Google Gemini Decisions API (`POST /v1beta/decisions`) 原生客户端：
/// - 兼容传入基础端点（`.../v1beta`）或完整端点（`.../v1beta/decisions`）
/// - 支持 429 / 502 / 503 / 504 及瞬时网络故障退避重试
/// - 所有抛出错误均严格脱敏 API Key
public struct GeminiDecisionsClient: Sendable {
    public static let defaultBaseEndpoint = "https://generativelanguage.googleapis.com/v1beta"
    public static let defaultModel = "gemini-decision-1"

    private let session: URLSession
    private let maxRetries: Int
    private let maxRetryDelaySeconds: Double
    private let requestTimeout: TimeInterval
    private let sleep: @Sendable (_ nanoseconds: UInt64) async throws -> Void

    public init(
        session: URLSession = .shared,
        maxRetries: Int = 2,
        maxRetryDelaySeconds: Double = 8.0,
        requestTimeout: TimeInterval = 35.0,
        sleep: @escaping @Sendable (_ nanoseconds: UInt64) async throws -> Void = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.session = session
        self.maxRetries = max(0, maxRetries)
        self.maxRetryDelaySeconds = max(0, maxRetryDelaySeconds)
        self.requestTimeout = max(1.0, requestTimeout)
        self.sleep = sleep
    }

    public static func redact(_ text: String, apiKey: String) -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return text }
        var out = text.replacingOccurrences(of: trimmedKey, with: "[REDACTED]")
        if let urlEncoded = trimmedKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           !urlEncoded.isEmpty,
           urlEncoded != trimmedKey {
            out = out.replacingOccurrences(of: urlEncoded, with: "[REDACTED]")
        }
        return out
    }

    public static func resolveDecisionsURL(from endpoint: String, apiKeyForRedaction: String = "") throws -> URL {
        var trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trimmed = defaultBaseEndpoint
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        let targetString: String
        if trimmed.lowercased().hasSuffix("/decisions") {
            targetString = trimmed
        } else {
            targetString = trimmed + "/decisions"
        }

        guard let url = URL(string: targetString),
              let scheme = url.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              let host = url.host,
              !host.isEmpty else {
            throw GeminiDecisionsError.invalidEndpoint(redact(endpoint, apiKey: apiKeyForRedaction))
        }
        return url
    }

    public func decide(
        request payload: GeminiDecisionRequest,
        endpoint: String = GeminiDecisionsClient.defaultBaseEndpoint,
        apiKey: String
    ) async throws -> GeminiDecisionResponse {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw GeminiDecisionsError.missingAPIKey
        }

        let url = try Self.resolveDecisionsURL(from: endpoint, apiKeyForRedaction: trimmedKey)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let bodyData = try encoder.encode(payload)

        for attempt in 0...maxRetries {
            try Task.checkCancellation()

            var urlRequest = URLRequest(url: url, timeoutInterval: requestTimeout)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")
            urlRequest.httpBody = bodyData

            do {
                let (data, rawResponse) = try await session.data(for: urlRequest)
                guard let http = rawResponse as? HTTPURLResponse else {
                    throw GeminiDecisionsError.invalidResponse("非 HTTP 响应。")
                }

                if (200...299).contains(http.statusCode) {
                    do {
                        return try JSONDecoder().decode(GeminiDecisionResponse.self, from: data)
                    } catch {
                        let snippet = String(decoding: data.prefix(240), as: UTF8.self)
                        let safeDetail = Self.redact("\(error.localizedDescription) (\(snippet))", apiKey: trimmedKey)
                        throw GeminiDecisionsError.invalidResponse(safeDetail)
                    }
                }

                let rawDetail = String(decoding: data, as: UTF8.self)
                let safeDetail = Self.redact(Self.extractConciseErrorMessage(from: rawDetail), apiKey: trimmedKey)
                let retryableStatus = [429, 502, 503, 504].contains(http.statusCode)

                if retryableStatus && attempt < maxRetries {
                    let delaySec = Self.computeRetryDelaySeconds(
                        detail: rawDetail,
                        statusCode: http.statusCode,
                        attempt: attempt,
                        maxCap: maxRetryDelaySeconds
                    )
                    if delaySec > 0 {
                        try await sleep(UInt64(delaySec * 1_000_000_000))
                    }
                    continue
                }

                throw GeminiDecisionsError.httpError(statusCode: http.statusCode, message: safeDetail)
            } catch let error as GeminiDecisionsError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let safeMessage = Self.redact(error.localizedDescription, apiKey: trimmedKey)
                if attempt < maxRetries {
                    let delaySec = min(maxRetryDelaySeconds, 0.5 * pow(2.0, Double(attempt)))
                    if delaySec > 0 {
                        try await sleep(UInt64(delaySec * 1_000_000_000))
                    }
                    continue
                }
                throw GeminiDecisionsError.networkError(safeMessage)
            }
        }

        throw GeminiDecisionsError.networkError("重试耗尽。")
    }

    /// 使用单问题最小 `noul` 探针实测连通性与往返延迟（返回毫秒数 `Double`）。
    public func testConnection(
        endpoint: String = GeminiDecisionsClient.defaultBaseEndpoint,
        model: String = GeminiDecisionsClient.defaultModel,
        apiKey: String
    ) async throws -> Double {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveModel = trimmedModel.isEmpty ? Self.defaultModel : trimmedModel
        let probe = GeminiDecisionRequest(
            model: effectiveModel,
            input: "Order confirmation receipt.",
            questions: [
                "ping": SiftQuestion(type: "noul", instructions: "Is this an order confirmation?")
            ]
        )

        let start = ContinuousClock.now
        let response = try await decide(request: probe, endpoint: endpoint, apiKey: apiKey)
        let elapsed = ContinuousClock.now - start

        guard let ping = response.answers["ping"],
              ping.type == "noul",
              let score = ping.noul,
              score.isFinite,
              (0.0...1.0).contains(score) else {
            throw GeminiDecisionsError.invalidResponse("探针未返回有效的 noul 概率。")
        }

        let components = elapsed.components
        let ms = Double(components.seconds) * 1_000.0 + Double(components.attoseconds) / 1_000_000_000_000_000.0
        return max(1.0, (ms * 10.0).rounded() / 10.0)
    }

    // MARK: - Helpers

    private static let retryDelayRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"retry in (\d+(?:\.\d+)?)s"#, options: [.caseInsensitive])
    }()

    private static func computeRetryDelaySeconds(
        detail: String,
        statusCode: Int,
        attempt: Int,
        maxCap: Double
    ) -> Double {
        guard maxCap > 0 else { return 0 }
        let ns = detail as NSString
        if let match = retryDelayRegex.firstMatch(in: detail, range: NSRange(location: 0, length: ns.length)),
           match.range(at: 1).location != NSNotFound,
           let parsed = Double(ns.substring(with: match.range(at: 1))) {
            return min(maxCap, parsed + 0.5)
        }
        if statusCode == 429 {
            return min(maxCap, 2.0 * pow(2.0, Double(attempt)))
        }
        return min(maxCap, 0.5 * pow(2.0, Double(attempt)))
    }

    private static func extractConciseErrorMessage(from rawBody: String) -> String {
        if let data = rawBody.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errDict = obj["error"] as? [String: Any],
               let msg = errDict["message"] as? String,
               !msg.isEmpty {
                return msg
            }
            if let msg = obj["message"] as? String, !msg.isEmpty {
                return msg
            }
        }
        let collapsed = rawBody
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.count > 200 ? String(collapsed.prefix(200)) + "…" : collapsed
    }
}
