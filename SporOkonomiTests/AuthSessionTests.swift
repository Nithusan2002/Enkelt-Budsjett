import Foundation
import SwiftData
import Testing
@testable import SporOkonomi

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
    func sessionStoreRestoresAuthenticatedSessionFromPreference() {
        let preference = UserPreference(
            authSessionModeRaw: AuthSessionMode.authenticated.rawValue,
            authProviderRaw: AuthProvider.email.rawValue,
            authUserID: "email-user-1",
            authEmail: "hei@example.com",
            authDisplayName: "Test Bruker"
        )
        let sessionStore = SessionStore(authClient: MockAuthClient())

        sessionStore.restore(from: preference)

        #expect(sessionStore.sessionMode == .authenticated)
        #expect(sessionStore.currentSession?.provider == .email)
        #expect(sessionStore.currentSession?.userID == "email-user-1")
        #expect(sessionStore.currentSession?.email == "hei@example.com")
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
}

private final class MockAuthClient: AuthClientProtocol {
    var signUpResult: AuthClientSession?
    var signInResult: AuthClientSession?
    var signInError: Error?
    var googleResult: AuthClientSession?
    var lastSignInEmail: String?

    init(
        signUpResult: AuthClientSession? = nil,
        signInResult: AuthClientSession? = nil,
        signInError: Error? = nil,
        googleResult: AuthClientSession? = nil
    ) {
        self.signUpResult = signUpResult
        self.signInResult = signInResult
        self.signInError = signInError
        self.googleResult = googleResult
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

    func signOut(accessToken: String?) async {}

    func storedAccessToken() -> String? { nil }

    func clearStoredSession() {}
}
