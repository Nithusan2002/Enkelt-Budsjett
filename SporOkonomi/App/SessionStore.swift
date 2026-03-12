import Foundation
import Combine
import SwiftData

enum AuthSessionMode: String, Codable {
    case undecided
    case local
    case authenticated
}

enum AuthProvider: String, Codable {
    case email
    case google

    var title: String {
        switch self {
        case .email:
            return "E-post"
        case .google:
            return "Google"
        }
    }
}

struct UserSession: Equatable, Codable {
    let userID: String
    let provider: AuthProvider
    let email: String?
    let displayName: String?
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessionMode: AuthSessionMode = .undecided
    @Published private(set) var currentSession: UserSession?
    @Published var authErrorMessage: String?
    @Published var isWorking = false

    private let authClient: AuthClientProtocol
    private let localAccountCleanup: @MainActor (_ preference: UserPreference, _ context: ModelContext) throws -> Void

    init(
        authClient: AuthClientProtocol? = nil,
        localAccountCleanup: (@MainActor (_ preference: UserPreference, _ context: ModelContext) throws -> Void)? = nil
    ) {
        if let authClient {
            self.authClient = authClient
        } else {
            do {
                self.authClient = try SupabaseAuthClient(configuration: SupabaseConfiguration.load())
            } catch let error as AuthServiceError {
                self.authClient = UnconfiguredAuthClient(configurationError: error)
            } catch {
                self.authClient = UnconfiguredAuthClient()
            }
        }

        self.localAccountCleanup = localAccountCleanup ?? { preference, context in
            try DemoDataSeeder.wipeAllData(context: context)
            try BootstrapService.ensurePreference(context: context)
            try BootstrapService.ensureCurrentBudgetMonthAndRecurring(context: context)

            let refreshedPreference = try context.fetch(FetchDescriptor<UserPreference>()).first ?? preference
            preference.authSessionModeRaw = refreshedPreference.authSessionModeRaw
            preference.authProviderRaw = refreshedPreference.authProviderRaw
            preference.authUserID = refreshedPreference.authUserID
            preference.authEmail = refreshedPreference.authEmail
            preference.authDisplayName = refreshedPreference.authDisplayName
        }
    }

    var requiresAuthChoice: Bool {
        sessionMode == .undecided
    }

    var isAuthenticated: Bool {
        sessionMode == .authenticated && currentSession != nil
    }

    func restore(from preference: UserPreference?, context: ModelContext) async {
        guard let preference else {
            sessionMode = .undecided
            currentSession = nil
            return
        }

        let restoredMode = AuthSessionMode(rawValue: preference.authSessionModeRaw) ?? .undecided
        sessionMode = restoredMode

        guard restoredMode == .authenticated,
              let providerRaw = preference.authProviderRaw,
              let provider = AuthProvider(rawValue: providerRaw),
              let userID = preference.authUserID,
              !userID.isEmpty else {
            currentSession = nil
            return
        }

        currentSession = UserSession(
            userID: userID,
            provider: provider,
            email: normalized(preference.authEmail),
            displayName: normalized(preference.authDisplayName)
        )

        do {
            if let restoredSession = try await authClient.restoreSession() {
                let updatedSession = UserSession(
                    userID: restoredSession.userID,
                    provider: provider,
                    email: restoredSession.email ?? normalized(preference.authEmail),
                    displayName: restoredSession.displayName ?? normalized(preference.authDisplayName)
                )

                if currentSession != updatedSession {
                    updatePreference(
                        preference,
                        mode: .authenticated,
                        session: updatedSession,
                        context: context
                    )
                }
            } else {
                updatePreference(
                    preference,
                    mode: .local,
                    session: nil,
                    context: context
                )
            }
        } catch {
            // Behold lokal session-state ved midlertidige nettverks- eller backend-feil.
        }
    }

    func continueWithoutAccount(preference: UserPreference, context: ModelContext) {
        authClient.clearStoredSession()
        updatePreference(
            preference,
            mode: .local,
            session: nil,
            context: context
        )
    }

    func createAccountWithEmail(
        email: String,
        password: String,
        displayName: String?,
        preference: UserPreference,
        context: ModelContext
    ) async {
        guard let normalizedEmail = normalized(email) else {
            authErrorMessage = "Skriv inn en gyldig e-postadresse."
            return
        }
        guard password.count >= 8 else {
            authErrorMessage = "Passord må ha minst 8 tegn."
            return
        }

        await performAuthRequest {
            let session = try await self.authClient.signUp(
                email: normalizedEmail,
                password: password,
                displayName: self.normalized(displayName)
            )

            guard let session else {
                self.authErrorMessage = "Kontoen er opprettet. Bekreft e-posten din før du logger inn."
                return
            }

            self.updatePreference(
                preference,
                mode: .authenticated,
                session: UserSession(
                    userID: session.userID,
                    provider: .email,
                    email: session.email ?? normalizedEmail,
                    displayName: session.displayName ?? self.normalized(displayName)
                ),
                context: context
            )
        }
    }

    func signInWithEmail(
        email: String,
        password: String,
        preference: UserPreference,
        context: ModelContext
    ) async {
        guard let normalizedEmail = normalized(email) else {
            authErrorMessage = "Skriv inn en gyldig e-postadresse."
            return
        }
        guard !password.isEmpty else {
            authErrorMessage = "Skriv inn passordet ditt."
            return
        }

        await performAuthRequest {
            let session = try await self.authClient.signIn(email: normalizedEmail, password: password)
            self.updatePreference(
                preference,
                mode: .authenticated,
                session: UserSession(
                    userID: session.userID,
                    provider: .email,
                    email: session.email ?? normalizedEmail,
                    displayName: session.displayName
                ),
                context: context
            )
        }
    }

    func signInWithGoogle(preference: UserPreference, context: ModelContext) async {
        await performAuthRequest {
            let session = try await self.authClient.signInWithGoogle()
            self.updatePreference(
                preference,
                mode: .authenticated,
                session: UserSession(
                    userID: session.userID,
                    provider: .google,
                    email: session.email,
                    displayName: session.displayName
                ),
                context: context
            )
        }
    }

    func signOut(preference: UserPreference, context: ModelContext) {
        let accessToken = authClient.storedAccessToken()
        authClient.clearStoredSession()
        updatePreference(
            preference,
            mode: .local,
            session: nil,
            context: context
        )

        Task {
            await self.authClient.signOut(accessToken: accessToken)
        }
    }

    func deleteAccount(preference: UserPreference, context: ModelContext) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }

        do {
            try await authClient.deleteAccount()
            do {
                try localAccountCleanup(preference, context)
                let refreshedPreference = try context.fetch(FetchDescriptor<UserPreference>()).first ?? preference
                updatePreference(
                    refreshedPreference,
                    mode: .local,
                    session: nil,
                    context: context
                )
            } catch {
                authClient.clearStoredSession()
                forceLocalSession(preference)
                authErrorMessage = "Kontoen er slettet, men lokal opprydding feilet. Start appen på nytt."
                return false
            }
            return true
        } catch {
            authErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke slette kontoen nå."
            return false
        }
    }

    func clearError() {
        authErrorMessage = nil
    }

    private func performAuthRequest(_ operation: @escaping @MainActor () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            try await operation()
        } catch {
            authErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke fullføre innloggingen nå."
        }
    }

    private func updatePreference(
        _ preference: UserPreference,
        mode: AuthSessionMode,
        session: UserSession?,
        context: ModelContext
    ) {
        preference.authSessionModeRaw = mode.rawValue
        preference.authProviderRaw = session?.provider.rawValue
        preference.authUserID = session?.userID
        preference.authEmail = session?.email
        preference.authDisplayName = session?.displayName

        do {
            try context.guardedSave(feature: "Auth", operation: "update_session", enforceReadOnly: false)
            sessionMode = mode
            currentSession = session
            authErrorMessage = nil
        } catch {
            authErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke lagre kontovalget nå."
        }
    }

    private func forceLocalSession(_ preference: UserPreference) {
        preference.authSessionModeRaw = AuthSessionMode.local.rawValue
        preference.authProviderRaw = nil
        preference.authUserID = nil
        preference.authEmail = nil
        preference.authDisplayName = nil
        sessionMode = .local
        currentSession = nil
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

private struct UnconfiguredAuthClient: AuthClientProtocol {
    private let configurationError: AuthServiceError

    init(configurationError: AuthServiceError = .missingConfiguration()) {
        self.configurationError = configurationError
    }

    func signUp(email: String, password: String, displayName: String?) async throws -> AuthClientSession? {
        throw configurationError
    }

    func signIn(email: String, password: String) async throws -> AuthClientSession {
        throw configurationError
    }

    func signInWithGoogle() async throws -> AuthClientSession {
        throw configurationError
    }

    func restoreSession() async throws -> AuthClientSession? { nil }

    func deleteAccount() async throws {
        throw configurationError
    }

    func signOut(accessToken: String?) async {}

    func storedAccessToken() -> String? { nil }

    func clearStoredSession() {}
}
