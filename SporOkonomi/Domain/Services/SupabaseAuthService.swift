import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

enum AuthServiceError: LocalizedError, Equatable {
    case missingConfiguration(String? = nil)
    case missingOAuthConfiguration
    case invalidResponse
    case invalidCredentials
    case emailNotConfirmed
    case requestFailed(String)
    case tokenStoreFailure
    case callbackCancelled
    case unsupportedOAuthCallback

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let detail):
            if let detail, !detail.isEmpty {
                return detail
            }
            return "Supabase er ikke konfigurert i appen ennå."
        case .missingOAuthConfiguration:
            return "Google-innlogging er ikke konfigurert i appen ennå."
        case .invalidResponse:
            return "Kunne ikke tolke svar fra kontotjenesten. Prøv igjen."
        case .invalidCredentials:
            return "E-post eller passord er feil."
        case .emailNotConfirmed:
            return "Bekreft e-posten din før du logger inn."
        case .requestFailed(let message):
            return message
        case .tokenStoreFailure:
            return "Kunne ikke lagre innloggingsøkten sikkert på enheten."
        case .callbackCancelled:
            return "Innloggingen ble avbrutt."
        case .unsupportedOAuthCallback:
            return "Google-innloggingen returnerte et uventet svar."
        }
    }
}

struct AuthClientSession: Equatable {
    let userID: String
    let email: String?
    let displayName: String?
    let accessToken: String
    let refreshToken: String?
}

protocol AuthClientProtocol {
    func signUp(email: String, password: String, displayName: String?) async throws -> AuthClientSession?
    func signIn(email: String, password: String) async throws -> AuthClientSession
    func signInWithGoogle() async throws -> AuthClientSession
    func restoreSession() async throws -> AuthClientSession?
    func deleteAccount() async throws
    func signOut(accessToken: String?) async
    func storedAccessToken() -> String?
    func clearStoredSession()
}

struct SupabaseConfiguration {
    static let urlKey = "SUPABASE_URL"
    static let publishableKeyKey = "SUPABASE_PUBLISHABLE_KEY"
    static let redirectSchemeKey = "SUPABASE_REDIRECT_SCHEME"
    static let redirectHostKey = "SUPABASE_REDIRECT_HOST"

    let projectURL: URL
    let publishableKey: String
    let redirectScheme: String?
    let redirectHost: String?

    var redirectURL: URL? {
        guard let redirectScheme, !redirectScheme.isEmpty,
              let redirectHost, !redirectHost.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = redirectScheme
        components.host = redirectHost
        return components.url
    }

    static func load(from bundle: Bundle = .main) throws -> SupabaseConfiguration {
        try load(
            projectURLString: stringValue(for: urlKey, in: bundle),
            publishableKey: stringValue(for: publishableKeyKey, in: bundle),
            redirectScheme: stringValue(for: redirectSchemeKey, in: bundle),
            redirectHost: stringValue(for: redirectHostKey, in: bundle)
        )
    }

    static func load(
        projectURLString: String?,
        publishableKey: String?,
        redirectScheme: String?,
        redirectHost: String?
    ) throws -> SupabaseConfiguration {
        let normalizedProjectURLString = normalized(projectURLString)
        let normalizedPublishableKey = normalized(publishableKey)

        if normalizedProjectURLString == nil, normalizedPublishableKey == nil {
            throw AuthServiceError.missingConfiguration(
                "Supabase mangler `SUPABASE_URL` og `SUPABASE_PUBLISHABLE_KEY` i appens Info.plist."
            )
        }
        if normalizedProjectURLString == nil {
            throw AuthServiceError.missingConfiguration(
                "Supabase mangler `SUPABASE_URL` i appens Info.plist."
            )
        }
        if normalizedPublishableKey == nil {
            throw AuthServiceError.missingConfiguration(
                "Supabase mangler `SUPABASE_PUBLISHABLE_KEY` i appens Info.plist."
            )
        }

        guard let projectURLString = normalizedProjectURLString,
              let url = URL(string: projectURLString) else {
            throw AuthServiceError.missingConfiguration(
                "`SUPABASE_URL` i appens Info.plist er ikke en gyldig URL."
            )
        }

        return SupabaseConfiguration(
            projectURL: url,
            publishableKey: normalizedPublishableKey ?? "",
            redirectScheme: normalized(redirectScheme),
            redirectHost: normalized(redirectHost)
        )
    }

    private static func stringValue(for key: String, in bundle: Bundle) -> String? {
        (bundle.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

@MainActor
final class SupabaseAuthClient: AuthClientProtocol {
    private let configuration: SupabaseConfiguration
    private let session: URLSession
    private let tokenStore: AuthTokenStore
    private let webAuthCoordinator: OAuthWebAuthenticationCoordinating

    init(
        configuration: SupabaseConfiguration,
        session: URLSession = .shared,
        tokenStore: AuthTokenStore? = nil,
        webAuthCoordinator: OAuthWebAuthenticationCoordinating? = nil
    ) {
        self.configuration = configuration
        self.session = session
        self.tokenStore = tokenStore ?? AuthTokenStore()
        self.webAuthCoordinator = webAuthCoordinator ?? OAuthWebAuthenticationCoordinator()
    }

    func signUp(email: String, password: String, displayName: String?) async throws -> AuthClientSession? {
        var metadata: [String: String] = [:]
        if let displayName, !displayName.isEmpty {
            metadata["display_name"] = displayName
            metadata["full_name"] = displayName
        }

        let payload = SignUpPayload(
            email: email,
            password: password,
            data: metadata.isEmpty ? nil : metadata
        )

        let response: AuthResponse = try await performRequest(
            path: "auth/v1/signup",
            method: "POST",
            body: payload
        )

        guard let session = response.session else {
            return nil
        }

        try persist(tokensFrom: session)
        return session.user.toAuthClientSession(from: session)
    }

    func signIn(email: String, password: String) async throws -> AuthClientSession {
        let payload = SignInPayload(email: email, password: password)
        let response: AuthResponse = try await performRequest(
            path: "auth/v1/token?grant_type=password",
            method: "POST",
            body: payload
        )

        guard let session = response.session else {
            throw AuthServiceError.invalidResponse
        }

        try persist(tokensFrom: session)
        return session.user.toAuthClientSession(from: session)
    }

    func signInWithGoogle() async throws -> AuthClientSession {
        let codeVerifier = OAuthPKCE.makeCodeVerifier()
        let callbackURL = try await webAuthCoordinator.authenticate(
            url: try googleOAuthURL(codeVerifier: codeVerifier),
            callbackScheme: try redirectScheme()
        )

        if let tokens = try parseOAuthTokens(from: callbackURL) {
            try tokenStore.saveOrThrow(tokens)

            let user = try await fetchUser(accessToken: tokens.accessToken)
            return user.toAuthClientSession(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken
            )
        }

        let authorizationCode = try parseOAuthCode(from: callbackURL)
        let exchangedSession = try await exchangeAuthorizationCodeForSession(
            authorizationCode,
            codeVerifier: codeVerifier
        )
        try persist(tokensFrom: exchangedSession)
        return exchangedSession.user.toAuthClientSession(from: exchangedSession)
    }

    func restoreSession() async throws -> AuthClientSession? {
        guard let storedTokens = tokenStore.load() else { return nil }

        do {
            let user = try await fetchUser(accessToken: storedTokens.accessToken)
            return user.toAuthClientSession(
                accessToken: storedTokens.accessToken,
                refreshToken: storedTokens.refreshToken
            )
        } catch let error as AuthServiceError {
            guard case .invalidCredentials = error else {
                throw error
            }

            guard let refreshToken = storedTokens.refreshToken, !refreshToken.isEmpty else {
                clearStoredSession()
                return nil
            }

            do {
                let refreshedSession = try await refreshSession(refreshToken: refreshToken)
                return refreshedSession.user.toAuthClientSession(from: refreshedSession)
            } catch let refreshError as AuthServiceError {
                if case .invalidCredentials = refreshError {
                    clearStoredSession()
                    return nil
                }
                throw refreshError
            }
        }
    }

    func signOut(accessToken: String?) async {
        defer { clearStoredSession() }
        guard let accessToken, !accessToken.isEmpty else { return }

        var request = URLRequest(url: endpointURL(for: "auth/v1/logout"))
        request.httpMethod = "POST"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        _ = try? await session.data(for: request)
    }

    func deleteAccount() async throws {
        guard let authenticatedSession = try await restoreSession() else {
            throw AuthServiceError.requestFailed("Du må være logget inn for å slette kontoen.")
        }

        var request = URLRequest(url: endpointURL(for: "functions/v1/delete-account"))
        request.httpMethod = "POST"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(authenticatedSession.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw mapError(from: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        clearStoredSession()
    }

    func storedAccessToken() -> String? {
        tokenStore.load()?.accessToken
    }

    func clearStoredSession() {
        tokenStore.clear()
    }

    private func googleOAuthURL(codeVerifier: String) throws -> URL {
        guard let redirectURL = configuration.redirectURL else {
            throw AuthServiceError.missingOAuthConfiguration
        }

        var components = URLComponents(url: endpointURL(for: "auth/v1/authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: redirectURL.absoluteString),
            URLQueryItem(name: "prompt", value: "select_account"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: OAuthPKCE.codeChallenge(for: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components?.url ?? configuration.projectURL
    }

    private func redirectScheme() throws -> String {
        guard let redirectScheme = configuration.redirectScheme, !redirectScheme.isEmpty else {
            throw AuthServiceError.missingOAuthConfiguration
        }
        return redirectScheme
    }

    private func fetchUser(accessToken: String) async throws -> AuthUserPayload {
        var request = URLRequest(url: endpointURL(for: "auth/v1/user"))
        request.httpMethod = "GET"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw mapError(from: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        do {
            return try JSONDecoder().decode(AuthUserPayload.self, from: data)
        } catch {
            throw AuthServiceError.invalidResponse
        }
    }

    private func parseOAuthTokens(from url: URL) throws -> StoredAuthTokens? {
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = parts?.queryItems ?? []
        let fragmentItems = URLComponents(string: "https://callback.invalid?\(url.fragment ?? "")")?.queryItems ?? []
        let allItems = Dictionary(uniqueKeysWithValues: (queryItems + fragmentItems).map { ($0.name, $0.value ?? "") })

        if let errorDescription = allItems["error_description"], !errorDescription.isEmpty {
            throw AuthServiceError.requestFailed(errorDescription.removingPercentEncoding ?? errorDescription)
        }
        if let error = allItems["error"], !error.isEmpty {
            throw AuthServiceError.requestFailed(error.removingPercentEncoding ?? error)
        }

        guard let accessToken = allItems["access_token"], !accessToken.isEmpty else {
            return nil
        }

        return StoredAuthTokens(
            accessToken: accessToken,
            refreshToken: allItems["refresh_token"],
            tokenType: allItems["token_type"]
        )
    }

    private func parseOAuthCode(from url: URL) throws -> String {
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = parts?.queryItems ?? []
        let fragmentItems = URLComponents(string: "https://callback.invalid?\(url.fragment ?? "")")?.queryItems ?? []
        let allItems = Dictionary(uniqueKeysWithValues: (queryItems + fragmentItems).map { ($0.name, $0.value ?? "") })

        guard let code = allItems["code"], !code.isEmpty else {
            throw AuthServiceError.unsupportedOAuthCallback
        }

        return code
    }

    private func exchangeAuthorizationCodeForSession(
        _ authorizationCode: String,
        codeVerifier: String
    ) async throws -> AuthSessionPayload {
        let payload = PKCEExchangePayload(
            authCode: authorizationCode,
            codeVerifier: codeVerifier
        )
        let response: AuthResponse = try await performRequest(
            path: "auth/v1/token?grant_type=pkce",
            method: "POST",
            body: payload
        )

        guard let session = response.session else {
            throw AuthServiceError.invalidResponse
        }

        return session
    }

    private func persist(tokensFrom session: AuthSessionPayload) throws {
        try tokenStore.saveOrThrow(
            StoredAuthTokens(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                tokenType: session.tokenType
            )
        )
    }

    private func refreshSession(refreshToken: String) async throws -> AuthSessionPayload {
        let payload = RefreshSessionPayload(refreshToken: refreshToken)
        let response: AuthResponse = try await performRequest(
            path: "auth/v1/token?grant_type=refresh_token",
            method: "POST",
            body: payload
        )

        guard let session = response.session else {
            throw AuthServiceError.invalidResponse
        }

        try persist(tokensFrom: session)
        return session
    }

    private func performRequest<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        var request = URLRequest(url: endpointURL(for: path))
        request.httpMethod = method
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapError(from: data, statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AuthServiceError.invalidResponse
        }
    }

    private func endpointURL(for path: String) -> URL {
        guard var components = URLComponents(url: configuration.projectURL, resolvingAgainstBaseURL: false) else {
            return configuration.projectURL
        }

        if let separator = path.firstIndex(of: "?") {
            let route = String(path[..<separator])
            let query = String(path[path.index(after: separator)...])
            components.path = "/\(route)"
            components.percentEncodedQuery = query
        } else {
            components.path = "/\(path)"
        }

        return components.url ?? configuration.projectURL
    }

    private func mapError(from data: Data, statusCode: Int) -> Error {
        if let payload = try? JSONDecoder().decode(SupabaseErrorPayload.self, from: data) {
            let message = payload.userMessage
            if payload.error == "invalid_grant" || statusCode == 400 && message.lowercased().contains("invalid login") {
                return AuthServiceError.invalidCredentials
            }
            if message.lowercased().contains("email not confirmed") {
                return AuthServiceError.emailNotConfirmed
            }
            if !message.isEmpty {
                return AuthServiceError.requestFailed(message)
            }
        }

        if statusCode == 400 || statusCode == 401 {
            return AuthServiceError.invalidCredentials
        }
        return AuthServiceError.requestFailed("Kunne ikke fullføre innloggingen nå. Prøv igjen senere.")
    }
}

protocol OAuthWebAuthenticationCoordinating {
    @MainActor
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

@MainActor
final class OAuthWebAuthenticationCoordinator: NSObject, OAuthWebAuthenticationCoordinating, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
                guard let self else { return }
                defer {
                    self.session = nil
                    self.continuation = nil
                }

                if let error {
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        continuation.resume(throwing: AuthServiceError.callbackCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: AuthServiceError.invalidResponse)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private struct SignUpPayload: Encodable {
    let email: String
    let password: String
    let data: [String: String]?
}

private struct SignInPayload: Encodable {
    let email: String
    let password: String
}

private struct RefreshSessionPayload: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct PKCEExchangePayload: Encodable {
    let authCode: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authCode = "auth_code"
        case codeVerifier = "code_verifier"
    }
}

private struct AuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let tokenType: String?
    let user: AuthUserPayload?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case user
    }

    var session: AuthSessionPayload? {
        guard let accessToken, let user else { return nil }
        return AuthSessionPayload(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            user: user
        )
    }
}

private struct AuthSessionPayload {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String?
    let user: AuthUserPayload
}

private struct AuthUserPayload: Decodable {
    let id: String
    let email: String?
    let userMetadata: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case userMetadata = "user_metadata"
    }

    func toAuthClientSession(from session: AuthSessionPayload) -> AuthClientSession {
        toAuthClientSession(accessToken: session.accessToken, refreshToken: session.refreshToken)
    }

    func toAuthClientSession(accessToken: String, refreshToken: String?) -> AuthClientSession {
        let displayName = userMetadata?["display_name"]?.stringValue ?? userMetadata?["full_name"]?.stringValue
        return AuthClientSession(
            userID: id,
            email: email,
            displayName: displayName,
            accessToken: accessToken,
            refreshToken: refreshToken
        )
    }
}


private enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}

private struct SupabaseErrorPayload: Decodable {
    let error: String?
    let errorDescription: String?
    let message: String?
    let msg: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case message
        case msg
    }

    var userMessage: String {
        [errorDescription, message, msg, error]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }
}

struct StoredAuthTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String?
}

class AuthTokenStore {
    private let service = "com.nithusan.SporOkonomi.auth"
    private let account = "supabase.session"
    let keychainAccessibility: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    func save(_ tokens: StoredAuthTokens) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens) else { return false }

        let query = baseQuery()
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    func saveOrThrow(_ tokens: StoredAuthTokens) throws {
        guard save(tokens) else {
            throw AuthServiceError.tokenStoreFailure
        }
    }

    func load() -> StoredAuthTokens? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let tokens = try? JSONDecoder().decode(StoredAuthTokens.self, from: data) else {
            return nil
        }
        return tokens
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: keychainAccessibility
        ]
    }
}

private enum OAuthPKCE {
    static func makeCodeVerifier() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        return Data(bytes).base64URLEncodedString()
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
