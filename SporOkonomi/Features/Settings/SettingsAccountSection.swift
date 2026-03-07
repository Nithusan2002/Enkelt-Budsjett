import SwiftUI

struct SettingsAccountSection: View {
    @EnvironmentObject private var sessionStore: SessionStore

    let authEmail: String?
    let isReadOnlyMode: Bool
    let onContinueWithoutAccount: () -> Void
    let onCreateAccount: () -> Void
    let onSignInWithEmail: () -> Void
    let onSignInWithGoogle: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        Section("Konto og synk") {
            HStack {
                Text("Status")
                    .appBodyStyle()
                Spacer()
                Text(accountStatusText())
                    .appSecondaryStyle()
                    .multilineTextAlignment(.trailing)
            }

            if sessionStore.isAuthenticated {
                if let authEmail, !authEmail.isEmpty {
                    HStack {
                        Text("Konto")
                            .appBodyStyle()
                        Spacer()
                        Text(authEmail)
                            .appSecondaryStyle()
                    }
                }

                Button("Logg ut") {
                    onSignOut()
                }
                .buttonStyle(.plain)
                .disabled(isReadOnlyMode || sessionStore.isWorking)

                Text("Du kan fortsatt bruke appen lokalt etter utlogging.")
                    .appSecondaryStyle()
            } else {
                Button(action: onContinueWithoutAccount) {
                    settingsRow(title: "Fortsett uten konto")
                }
                .buttonStyle(.plain)
                .disabled(isReadOnlyMode || sessionStore.isWorking)

                Button(action: onCreateAccount) {
                    settingsRow(title: "Opprett konto med e-post")
                }
                .buttonStyle(.plain)
                .disabled(isReadOnlyMode || sessionStore.isWorking)

                Button(action: onSignInWithEmail) {
                    settingsRow(title: "Logg inn med e-post")
                }
                .buttonStyle(.plain)
                .disabled(isReadOnlyMode || sessionStore.isWorking)

                Button(action: onSignInWithGoogle) {
                    settingsRow(title: "Logg inn med Google")
                }
                .buttonStyle(.plain)
                .disabled(isReadOnlyMode || sessionStore.isWorking)

                Text("Konto brukes senere til synkronisering og gjenoppretting.")
                    .appSecondaryStyle()
            }
        }
    }

    private func accountStatusText() -> String {
        switch sessionStore.sessionMode {
        case .undecided:
            return "Ikke valgt"
        case .local:
            return "Lokal bruker"
        case .authenticated:
            if let provider = sessionStore.currentSession?.provider {
                return "Logget inn med \(provider.title)"
            }
            return "Logget inn"
        }
    }

    private func settingsRow(title: String) -> some View {
        HStack {
            Text(title)
                .appBodyStyle()
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
