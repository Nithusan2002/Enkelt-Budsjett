import Foundation

struct AIInsightResponse: Decodable, Equatable {
    let summary: String
    let keyDriver: String
    let nextStep: String
}

enum AIInsightsServiceError: LocalizedError {
    case missingConfiguration(String)
    case invalidResponse
    case backend(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let message):
            return message
        case .invalidResponse:
            return "AI-svaret kunne ikke leses akkurat nå."
        case .backend(let message):
            return message
        }
    }
}

final class AIInsightsService {
    private let configuration: SupabaseConfiguration
    private let session: URLSession
    private let tokenStore: AuthTokenStore

    init(
        configuration: SupabaseConfiguration,
        session: URLSession = .shared,
        tokenStore: AuthTokenStore = AuthTokenStore()
    ) {
        self.configuration = configuration
        self.session = session
        self.tokenStore = tokenStore
    }

    convenience init(bundle: Bundle = .main) throws {
        try self.init(configuration: SupabaseConfiguration.load(from: bundle))
    }

    func fetchInsight(summary: AIInsightRequestSummary) async throws -> AIInsightResponse {
        let request = try makeRequest(summary: summary)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIInsightsServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let payload = try? JSONDecoder().decode(AIInsightsServiceErrorPayload.self, from: data)
            let message = payload?.userMessage
            throw AIInsightsServiceError.backend(
                message?.isEmpty == false ? message! : "AI-hjelperen er ikke tilgjengelig akkurat nå."
            )
        }

        guard let decoded = try? JSONDecoder().decode(AIInsightResponse.self, from: data) else {
            throw AIInsightsServiceError.invalidResponse
        }
        return decoded
    }

    private func makeRequest(summary: AIInsightRequestSummary) throws -> URLRequest {
        let functionURL = configuration.projectURL
            .appending(path: "functions")
            .appending(path: "v1")
            .appending(path: "ai-insight")

        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")

        if let accessToken = tokenStore.load()?.accessToken,
           !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(summary)
        return request
    }
}

private struct AIInsightsServiceErrorPayload: Decodable {
    let error: String?
    let message: String?

    var userMessage: String {
        [message, error]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }
}
