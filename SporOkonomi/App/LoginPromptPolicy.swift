import Foundation

struct LoginPromptPolicy {
    static func shouldNormalizeUndecidedMode(preference: UserPreference?) -> Bool {
        guard let preference, preference.onboardingCompleted else {
            return false
        }

        return resolvedSessionMode(for: preference) == .undecided
    }

    static func shouldPresentPrompt(
        preference: UserPreference?,
        sessionMode: AuthSessionMode,
        hasSeenPrompt: Bool
    ) -> Bool {
        guard let preference, preference.onboardingCompleted, !hasSeenPrompt else {
            return false
        }

        return sessionMode != .authenticated
    }

    private static func resolvedSessionMode(for preference: UserPreference) -> AuthSessionMode {
        AuthSessionMode(rawValue: preference.authSessionModeRaw) ?? .undecided
    }
}
