import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import SporOkonomi

private typealias Category = SporOkonomi.Category
private typealias Transaction = SporOkonomi.Transaction

struct AuthSessionTests {

    @Test
    @MainActor
    func bootstrapMarksLegacyUsersAsLocalAuthMode() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(
            authSessionModeRaw: AuthSessionMode.undecided.rawValue,
            onboardingCompleted: true
        )
        context.insert(preference)
        try context.save()

        try BootstrapService.ensurePreference(context: context)

        let stored = try context.fetch(FetchDescriptor<UserPreference>()).first
        #expect(stored?.authSessionModeRaw == AuthSessionMode.local.rawValue)
    }

    @Test
    @MainActor
    func bootstrapAlwaysDeduplicatesCategoriesByID() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        context.insert(Category(id: "cat_housing", name: "Bolig", type: .expense, sortOrder: 1))
        context.insert(Category(id: "cat_housing", name: "Bolig", type: .expense, sortOrder: 1))
        try context.save()

        UserDefaults.standard.set(Date(), forKey: "bootstrap_dedupe_last_run_at")

        try BootstrapService.ensurePreference(context: context)

        let categories = try context.fetch(FetchDescriptor<Category>())
        #expect(categories.filter { $0.id == "cat_housing" }.count == 1)
    }

    @Test
    @MainActor
    func bootstrapCreatesSimplifiedDefaultCategoriesForNewUsers() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        try BootstrapService.ensurePreference(context: context)

        let categories = try context.fetch(FetchDescriptor<Category>())
        let ids = Set(categories.map(\.id))

        #expect(ids.contains("cat_food"))
        #expect(ids.contains("cat_housing"))
        #expect(ids.contains("cat_transport"))
        #expect(ids.contains("cat_leisure"))
        #expect(ids.contains("cat_fixed_costs"))
        #expect(ids.contains("cat_savings_account"))
        #expect(ids.contains("cat_other"))
        #expect(!ids.contains("cat_expense_spotify"))
        #expect(!ids.contains("cat_savings_travel"))
    }

    @Test
    @MainActor
    func bootstrapCreatesDefaultInvestmentBucketsForNewUsers() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        try BootstrapService.ensurePreference(context: context)

        let buckets = try context.fetch(FetchDescriptor<InvestmentBucket>())
        let names = Set(buckets.map(\.name))

        #expect(names == ["Fond", "Aksjer", "Krypto", "Kontanter"])
    }

    @Test
    @MainActor
    func bootstrapKeepsExistingLegacyCategoriesUntouched() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        context.insert(Category(id: "cat_expense_spotify", name: "Spotify", type: .expense, sortOrder: 1))
        try context.save()

        try BootstrapService.ensurePreference(context: context)

        let categories = try context.fetch(FetchDescriptor<Category>())
        #expect(categories.contains { $0.id == "cat_expense_spotify" })
    }

    @Test
    @MainActor
    func bootstrapKeepsManuallyLoadedDemoData() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        _ = try DemoDataSeeder.seedRealisticYear(context: context, year: 2026)
        let viewModel = AppRootViewModel()

        viewModel.bootstrap(context: context)
        try await Task.sleep(for: .milliseconds(100))

        let fixedItems = try context.fetch(FetchDescriptor<FixedItem>())
        let snapshots = try context.fetch(FetchDescriptor<InvestmentSnapshot>())
        let preferences = try context.fetch(FetchDescriptor<UserPreference>())
        let months = try context.fetch(FetchDescriptor<BudgetMonth>())

        #expect(fixedItems.contains { $0.id.hasPrefix("fixed_demo_") })
        #expect(!snapshots.isEmpty)
        #expect(preferences.count == 1)
        #expect(!months.isEmpty)
    }

    @Test
    @MainActor
    func activeLifecycleTransitionKeepsManuallyLoadedDemoData() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        _ = try DemoDataSeeder.seedRealisticYear(context: context, year: 2026)
        let viewModel = AppRootViewModel()

        viewModel.handleScenePhaseChange(.background)
        viewModel.handleScenePhaseChange(.active)

        let fixedItems = try context.fetch(FetchDescriptor<FixedItem>())
        let snapshots = try context.fetch(FetchDescriptor<InvestmentSnapshot>())

        #expect(fixedItems.contains { $0.id.hasPrefix("fixed_demo_") })
        #expect(!snapshots.isEmpty)
    }

    @Test
    @MainActor
    func sessionStoreRestoresAuthenticatedSessionFromPreference() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(
            authSessionModeRaw: AuthSessionMode.authenticated.rawValue,
            authProviderRaw: AuthProvider.email.rawValue,
            authUserID: "email-user-1",
            authEmail: "hei@example.com",
            authDisplayName: "Test Bruker"
        )
        let sessionStore = SessionStore(
            authClient: MockAuthClient(
                restoredSession: AuthClientSession(
                    userID: "email-user-1",
                    email: "hei@example.com",
                    displayName: "Test Bruker",
                    accessToken: "restored-access",
                    refreshToken: "restored-refresh"
                )
            )
        )

        await sessionStore.restore(from: preference, context: context)

        #expect(sessionStore.sessionMode == .authenticated)
        #expect(sessionStore.currentSession?.provider == .email)
        #expect(sessionStore.currentSession?.userID == "email-user-1")
        #expect(sessionStore.currentSession?.email == "hei@example.com")
    }

    @Test
    @MainActor
    func sessionStoreDowngradesToLocalWhenAuthenticatedPreferenceHasNoValidBackendSession() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(
            authSessionModeRaw: AuthSessionMode.authenticated.rawValue,
            authProviderRaw: AuthProvider.google.rawValue,
            authUserID: "stale-user",
            authEmail: "stale@example.com"
        )
        context.insert(preference)
        try context.save()

        let sessionStore = SessionStore(authClient: MockAuthClient(restoredSession: nil))

        await sessionStore.restore(from: preference, context: context)

        #expect(sessionStore.sessionMode == .local)
        #expect(sessionStore.currentSession == nil)
        #expect(preference.authSessionModeRaw == AuthSessionMode.local.rawValue)
        #expect(preference.authUserID == nil)
    }

    @Test
    @MainActor
    func signInWithEmailStoresAuthenticatedSession() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(authSessionModeRaw: AuthSessionMode.local.rawValue)
        context.insert(preference)
        try context.save()

        let authClient = MockAuthClient(
            signInResult: AuthClientSession(
                userID: "user-42",
                email: "hei@example.com",
                displayName: "Nithu",
                accessToken: "access-token",
                refreshToken: "refresh-token"
            )
        )
        let sessionStore = SessionStore(authClient: authClient)

        await sessionStore.signInWithEmail(
            email: "hei@example.com",
            password: "passord123",
            preference: preference,
            context: context
        )

        #expect(sessionStore.sessionMode == .authenticated)
        #expect(sessionStore.currentSession?.provider == .email)
        #expect(sessionStore.currentSession?.userID == "user-42")
        #expect(preference.authSessionModeRaw == AuthSessionMode.authenticated.rawValue)
        #expect(preference.authEmail == "hei@example.com")
        #expect(sessionStore.authErrorMessage == nil)
        #expect(authClient.lastSignInEmail == "hei@example.com")
    }

    @Test
    @MainActor
    func signInWithGoogleStoresAuthenticatedSession() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(authSessionModeRaw: AuthSessionMode.local.rawValue)
        context.insert(preference)
        try context.save()

        let authClient = MockAuthClient(
            googleResult: AuthClientSession(
                userID: "google-user-7",
                email: "google@example.com",
                displayName: "Google Bruker",
                accessToken: "google-access",
                refreshToken: "google-refresh"
            )
        )
        let sessionStore = SessionStore(authClient: authClient)

        await sessionStore.signInWithGoogle(preference: preference, context: context)

        #expect(sessionStore.sessionMode == .authenticated)
        #expect(sessionStore.currentSession?.provider == .google)
        #expect(sessionStore.currentSession?.userID == "google-user-7")
        #expect(preference.authProviderRaw == AuthProvider.google.rawValue)
        #expect(sessionStore.authErrorMessage == nil)
    }

    @Test
    @MainActor
    func deleteAccountRemovesRemoteSessionAndLocalData() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(
            authSessionModeRaw: AuthSessionMode.authenticated.rawValue,
            authProviderRaw: AuthProvider.email.rawValue,
            authUserID: "user-42",
            authEmail: "hei@example.com"
        )
        context.insert(preference)
        context.insert(Transaction(date: .now, amount: 499, kind: .expense, categoryID: "cat_food"))
        try context.save()

        let authClient = MockAuthClient(
            restoredSession: AuthClientSession(
                userID: "user-42",
                email: "hei@example.com",
                displayName: nil,
                accessToken: "access-token",
                refreshToken: "refresh-token"
            ),
            storedAccessToken: "access-token"
        )
        let sessionStore = SessionStore(authClient: authClient)

        await sessionStore.restore(from: preference, context: context)
        await sessionStore.deleteAccount(preference: preference, context: context)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let preferences = try context.fetch(FetchDescriptor<UserPreference>())

        #expect(authClient.deleteAccountCallCount == 1)
        #expect(authClient.clearedStoredSession)
        #expect(sessionStore.sessionMode == .local)
        #expect(sessionStore.currentSession == nil)
        #expect(sessionStore.authErrorMessage == nil)
        #expect(transactions.isEmpty)
        #expect(preferences.count == 1)
        #expect(preferences.first?.authSessionModeRaw == AuthSessionMode.local.rawValue)
        #expect(preferences.first?.authUserID == nil)
    }

    @Test
    @MainActor
    func deleteAccountKeepsLocalDataWhenRemoteDeletionFails() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(
            authSessionModeRaw: AuthSessionMode.authenticated.rawValue,
            authProviderRaw: AuthProvider.email.rawValue,
            authUserID: "user-42",
            authEmail: "hei@example.com"
        )
        context.insert(preference)
        context.insert(Transaction(date: .now, amount: 499, kind: .expense, categoryID: "cat_food"))
        try context.save()

        let authClient = MockAuthClient(
            restoredSession: AuthClientSession(
                userID: "user-42",
                email: "hei@example.com",
                displayName: nil,
                accessToken: "access-token",
                refreshToken: "refresh-token"
            ),
            storedAccessToken: "access-token",
            deleteAccountError: AuthServiceError.requestFailed("Kunne ikke slette kontoen nå.")
        )
        let sessionStore = SessionStore(authClient: authClient)

        await sessionStore.restore(from: preference, context: context)
        await sessionStore.deleteAccount(preference: preference, context: context)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())

        #expect(authClient.deleteAccountCallCount == 1)
        #expect(!authClient.clearedStoredSession)
        #expect(sessionStore.sessionMode == .authenticated)
        #expect(sessionStore.currentSession?.userID == "user-42")
        #expect(sessionStore.authErrorMessage == "Kunne ikke slette kontoen nå.")
        #expect(transactions.count == 1)
        #expect(preference.authSessionModeRaw == AuthSessionMode.authenticated.rawValue)
        #expect(preference.authUserID == "user-42")
    }

    @Test
    @MainActor
    func deleteAccountForcesLocalSignOutWhenRemoteDeletionSucceedsButLocalCleanupFails() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(
            authSessionModeRaw: AuthSessionMode.authenticated.rawValue,
            authProviderRaw: AuthProvider.google.rawValue,
            authUserID: "user-42",
            authEmail: "hei@example.com"
        )
        context.insert(preference)
        context.insert(Transaction(date: .now, amount: 499, kind: .expense, categoryID: "cat_food"))
        try context.save()

        let authClient = MockAuthClient(
            restoredSession: AuthClientSession(
                userID: "user-42",
                email: "hei@example.com",
                displayName: nil,
                accessToken: "access-token",
                refreshToken: "refresh-token"
            ),
            storedAccessToken: "access-token"
        )
        let sessionStore = SessionStore(
            authClient: authClient,
            localAccountCleanup: { _, _ in
                throw AuthServiceError.requestFailed("Lokal cleanup feilet.")
            }
        )

        await sessionStore.restore(from: preference, context: context)
        let result = await sessionStore.deleteAccount(preference: preference, context: context)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())

        #expect(result == false)
        #expect(authClient.deleteAccountCallCount == 1)
        #expect(authClient.clearedStoredSession)
        #expect(sessionStore.sessionMode == .local)
        #expect(sessionStore.currentSession == nil)
        #expect(sessionStore.authErrorMessage == "Kontoen er slettet, men lokal opprydding feilet. Start appen på nytt.")
        #expect(transactions.count == 1)
        #expect(preference.authSessionModeRaw == AuthSessionMode.local.rawValue)
        #expect(preference.authUserID == nil)
    }

    @Test
    @MainActor
    func signUpWithoutSessionPromptsForEmailConfirmation() async throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let preference = UserPreference(authSessionModeRaw: AuthSessionMode.local.rawValue)
        context.insert(preference)
        try context.save()

        let sessionStore = SessionStore(authClient: MockAuthClient(signUpResult: nil))

        await sessionStore.createAccountWithEmail(
            email: "hei@example.com",
            password: "passord123",
            displayName: "Nithu",
            preference: preference,
            context: context
        )

        #expect(sessionStore.sessionMode == .local)
        #expect(sessionStore.currentSession == nil)
        #expect(sessionStore.authErrorMessage == "Kontoen er opprettet. Bekreft e-posten din før du logger inn.")
    }

    @Test
    func supabaseConfigurationRequiresExplicitValues() {
        do {
            _ = try SupabaseConfiguration.load(
                projectURLString: nil,
                publishableKey: nil,
                redirectScheme: nil,
                redirectHost: nil
            )
            Issue.record("Expected missingConfiguration to be thrown")
        } catch let error as AuthServiceError {
            #expect(
                error == .missingConfiguration(
                    "Supabase mangler `SUPABASE_URL` og `SUPABASE_PUBLISHABLE_KEY` i appens Info.plist."
                )
            )
        } catch {
            Issue.record("Expected AuthServiceError.missingConfiguration, got \(error)")
        }
    }

    @Test
    func supabaseConfigurationReportsWhichKeyIsMissing() {
        do {
            _ = try SupabaseConfiguration.load(
                projectURLString: "https://example.supabase.co",
                publishableKey: nil,
                redirectScheme: nil,
                redirectHost: nil
            )
            Issue.record("Expected missingConfiguration to be thrown")
        } catch let error as AuthServiceError {
            #expect(
                error == .missingConfiguration(
                    "Supabase mangler `SUPABASE_PUBLISHABLE_KEY` i appens Info.plist."
                )
            )
        } catch {
            Issue.record("Expected AuthServiceError.missingConfiguration, got \(error)")
        }
    }

    @Test
    @MainActor
    func restoreSessionRefreshesExpiredAccessToken() async throws {
        let configuration = try SupabaseConfiguration.load(
            projectURLString: "https://example.supabase.co",
            publishableKey: "publishable-key",
            redirectScheme: "sporokonomi",
            redirectHost: "auth-callback"
        )
        let tokenStore = MockTokenStore(
            initialTokens: StoredAuthTokens(
                accessToken: "expired-access",
                refreshToken: "refresh-123",
                tokenType: "bearer"
            )
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        let client = SupabaseAuthClient(
            configuration: configuration,
            session: session,
            tokenStore: tokenStore,
            webAuthCoordinator: MockOAuthCoordinator()
        )

        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/auth/v1/user",
               request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-access" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                let data = #"{"error":"invalid_grant","message":"invalid login credentials"}"#.data(using: .utf8)!
                return (response, data)
            }

            if request.url?.path == "/auth/v1/token",
               request.url?.query == "grant_type=refresh_token" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let data = #"""
                {
                  "access_token": "fresh-access",
                  "refresh_token": "fresh-refresh",
                  "token_type": "bearer",
                  "user": {
                    "id": "user-123",
                    "email": "hei@example.com",
                    "user_metadata": {
                      "display_name": "Hei"
                    }
                  }
                }
                """#.data(using: .utf8)!
                return (response, data)
            }

            throw URLError(.badServerResponse)
        }

        let restored = try await client.restoreSession()

        #expect(restored?.userID == "user-123")
        #expect(restored?.accessToken == "fresh-access")
        #expect(tokenStore.savedTokens?.accessToken == "fresh-access")
        #expect(tokenStore.savedTokens?.refreshToken == "fresh-refresh")
    }

    @Test
    @MainActor
    func signInWithGoogleExchangesAuthorizationCodeCallback() async throws {
        let configuration = try SupabaseConfiguration.load(
            projectURLString: "https://example.supabase.co",
            publishableKey: "publishable-key",
            redirectScheme: "sporokonomi",
            redirectHost: "auth-callback"
        )
        let tokenStore = MockTokenStore(initialTokens: nil)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        let client = SupabaseAuthClient(
            configuration: configuration,
            session: session,
            tokenStore: tokenStore,
            webAuthCoordinator: MockOAuthCoordinator(
                callbackURL: URL(string: "sporokonomi://auth-callback?code=oauth-code-123")!
            )
        )

        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/auth/v1/token",
               request.url?.query == "grant_type=pkce" {
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                #expect(body.contains("\"auth_code\":\"oauth-code-123\""))
                #expect(body.contains("\"code_verifier\":"))

                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let data = #"""
                {
                  "access_token": "google-access",
                  "refresh_token": "google-refresh",
                  "token_type": "bearer",
                  "user": {
                    "id": "google-user-1",
                    "email": "google@example.com",
                    "user_metadata": {
                      "full_name": "Google Bruker"
                    }
                  }
                }
                """#.data(using: .utf8)!
                return (response, data)
            }

            throw URLError(.badServerResponse)
        }

        let authenticatedSession = try await client.signInWithGoogle()

        #expect(authenticatedSession.userID == "google-user-1")
        #expect(authenticatedSession.email == "google@example.com")
        #expect(authenticatedSession.accessToken == "google-access")
        #expect(tokenStore.savedTokens?.accessToken == "google-access")
        #expect(tokenStore.savedTokens?.refreshToken == "google-refresh")
    }

    @Test
    @MainActor
    func deleteAccountRefreshesExpiredAccessTokenBeforeCallingFunction() async throws {
        let configuration = try SupabaseConfiguration.load(
            projectURLString: "https://example.supabase.co",
            publishableKey: "publishable-key",
            redirectScheme: "sporokonomi",
            redirectHost: "auth-callback"
        )
        let tokenStore = MockTokenStore(
            initialTokens: StoredAuthTokens(
                accessToken: "expired-access",
                refreshToken: "refresh-123",
                tokenType: "bearer"
            )
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        let client = SupabaseAuthClient(
            configuration: configuration,
            session: session,
            tokenStore: tokenStore,
            webAuthCoordinator: MockOAuthCoordinator()
        )

        var functionAuthorizationHeader: String?

        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/auth/v1/user",
               request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-access" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                let data = #"{"error":"invalid_grant","message":"invalid login credentials"}"#.data(using: .utf8)!
                return (response, data)
            }

            if request.url?.path == "/auth/v1/token",
               request.url?.query == "grant_type=refresh_token" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let data = #"""
                {
                  "access_token": "fresh-access",
                  "refresh_token": "fresh-refresh",
                  "token_type": "bearer",
                  "user": {
                    "id": "user-123",
                    "email": "hei@example.com",
                    "user_metadata": {
                      "display_name": "Hei"
                    }
                  }
                }
                """#.data(using: .utf8)!
                return (response, data)
            }

            if request.url?.path == "/functions/v1/delete-account" {
                functionAuthorizationHeader = request.value(forHTTPHeaderField: "Authorization")
                let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }

            throw URLError(.badServerResponse)
        }

        try await client.deleteAccount()

        #expect(functionAuthorizationHeader == "Bearer fresh-access")
        #expect(tokenStore.savedTokens?.accessToken == "fresh-access")
        #expect(tokenStore.savedTokens?.refreshToken == "fresh-refresh")
        #expect(tokenStore.load() == nil)
    }
}

private final class MockAuthClient: AuthClientProtocol {
    var signUpResult: AuthClientSession?
    var signInResult: AuthClientSession?
    var signInError: Error?
    var googleResult: AuthClientSession?
    var restoredSession: AuthClientSession?
    var storedAccessTokenValue: String?
    var deleteAccountError: Error?
    var deleteAccountCallCount = 0
    var clearedStoredSession = false
    var lastSignInEmail: String?

    init(
        signUpResult: AuthClientSession? = nil,
        signInResult: AuthClientSession? = nil,
        signInError: Error? = nil,
        googleResult: AuthClientSession? = nil,
        restoredSession: AuthClientSession? = nil,
        storedAccessToken: String? = nil,
        deleteAccountError: Error? = nil
    ) {
        self.signUpResult = signUpResult
        self.signInResult = signInResult
        self.signInError = signInError
        self.googleResult = googleResult
        self.restoredSession = restoredSession
        self.storedAccessTokenValue = storedAccessToken
        self.deleteAccountError = deleteAccountError
    }

    func signUp(email: String, password: String, displayName: String?) async throws -> AuthClientSession? {
        signUpResult
    }

    func signIn(email: String, password: String) async throws -> AuthClientSession {
        lastSignInEmail = email
        if let signInError {
            throw signInError
        }
        guard let signInResult else {
            throw AuthServiceError.invalidCredentials
        }
        return signInResult
    }

    func signInWithGoogle() async throws -> AuthClientSession {
        guard let googleResult else {
            throw AuthServiceError.invalidResponse
        }
        return googleResult
    }

    func restoreSession() async throws -> AuthClientSession? {
        restoredSession
    }

    func signOut(accessToken: String?) async {}

    func deleteAccount() async throws {
        deleteAccountCallCount += 1
        if let deleteAccountError {
            throw deleteAccountError
        }
    }

    func storedAccessToken() -> String? { storedAccessTokenValue }

    func clearStoredSession() {
        clearedStoredSession = true
        storedAccessTokenValue = nil
    }
}

private final class MockOAuthCoordinator: OAuthWebAuthenticationCoordinating {
    let callbackURL: URL?

    init(callbackURL: URL? = nil) {
        self.callbackURL = callbackURL
    }

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        if let callbackURL {
            return callbackURL
        }
        throw AuthServiceError.invalidResponse
    }
}

private final class MockTokenStore: AuthTokenStore {
    var savedTokens: StoredAuthTokens?
    private var currentTokens: StoredAuthTokens?

    init(initialTokens: StoredAuthTokens?) {
        self.currentTokens = initialTokens
    }

    override func save(_ tokens: StoredAuthTokens) -> Bool {
        currentTokens = tokens
        savedTokens = tokens
        return true
    }

    override func load() -> StoredAuthTokens? {
        currentTokens
    }

    override func clear() {
        currentTokens = nil
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
