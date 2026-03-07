import SwiftUI

struct SettingsAccountSection: View {
    @EnvironmentObject private var sessionStore: SessionStore

    let authEmail: String?
    let isReadOnlyMode: Bool
    let onCreateAccount: () -> Void
    let onSignInWithEmail: () -> Void
    let onSignInWithGoogle: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(accountHeaderTitle())
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(accountHeaderSubtitle())
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.vertical, 4)

            settingsRow(title: "Status", value: accountStatusText(), showsChevron: false)

            if sessionStore.isAuthenticated {
                if let authEmail, !authEmail.isEmpty {
                    settingsRow(title: "E-post", value: authEmail, showsChevron: false)
                }

                Button {
                    onSignOut()
                } label: {
                    settingsRow(title: "Logg ut", value: "", showsChevron: false)
                }
                .buttonStyle(.plain)
                .disabled(isReadOnlyMode || sessionStore.isWorking)
            } else {
                Button(action: onCreateAccount) {
                    settingsRow(title: "Opprett konto med e-post", value: "", showsChevron: true)
                }
                .buttonStyle(.plain)
                .disabled(isReadOnlyMode || sessionStore.isWorking)

                Button(action: onSignInWithEmail) {
                    settingsRow(title: "Logg inn med e-post", value: "", showsChevron: true)
                }
                .buttonStyle(.plain)
                .disabled(isReadOnlyMode || sessionStore.isWorking)

                Button(action: onSignInWithGoogle) {
                    settingsRow(title: "Logg inn med Google", value: "", showsChevron: true)
                }
                .buttonStyle(.plain)
                .disabled(isReadOnlyMode || sessionStore.isWorking)
            }
        } header: {
            Text("Konto og synk")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(nil)
                .padding(.top, 6)
        } footer: {
            if sessionStore.isAuthenticated {
                Text("Du kan fortsatt bruke appen lokalt etter utlogging.")
            } else {
                Text("Konto brukes senere til synkronisering og gjenoppretting.")
            }
        }
    }

    private func accountHeaderTitle() -> String {
        if let authEmail, !authEmail.isEmpty, sessionStore.isAuthenticated {
            return authEmail
        }
        return "Lokal bruker"
    }

    private func accountHeaderSubtitle() -> String {
        sessionStore.isAuthenticated ? "Klar for synkronisering" : "Ikke synkronisert"
    }

    private func accountStatusText() -> String {
        switch sessionStore.sessionMode {
        case .undecided:
            return "Ikke logget inn"
        case .local:
            return "Kun lagret lokalt"
        case .authenticated:
            if let provider = sessionStore.currentSession?.provider {
                return "Logget inn med \(provider.title)"
            }
            return "Logget inn"
        }
    }

    private func settingsRow(title: String, value: String, showsChevron: Bool) -> some View {
        HStack {
            Text(title)
                .appBodyStyle()
            Spacer()
            if !value.isEmpty {
                Text(value)
                    .appSecondaryStyle()
                    .multilineTextAlignment(.trailing)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .contentShape(Rectangle())
    }
}
