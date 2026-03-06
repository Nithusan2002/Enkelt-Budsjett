import SwiftUI
import SwiftData

struct WelcomeAuthView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionStore: SessionStore

    let preference: UserPreference
    @State private var emailFlow: EmailAuthMode?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    Spacer(minLength: 8)

                    VStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(AppTheme.primary)

                        Text("Bruk appen med eller uten konto")
                            .appCardTitleStyle()
                            .multilineTextAlignment(.center)

                        Text("Start lokalt nå. Du kan logge inn senere hvis du vil synkronisere og gjenopprette data.")
                            .appBodyStyle()
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 420)

                    Button("Fortsett uten konto") {
                        sessionStore.continueWithoutAccount(preference: preference, context: modelContext)
                    }
                    .appProminentCTAStyle()
                    .disabled(sessionStore.isWorking)
                    .frame(maxWidth: 420)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Med konto")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)

                        Button {
                            Task {
                                await sessionStore.signInWithGoogle(preference: preference, context: modelContext)
                            }
                        } label: {
                            authButtonLabel(
                                title: "Fortsett med Google",
                                systemImage: "globe",
                                tint: AppTheme.primary.opacity(0.08),
                                stroke: AppTheme.primary.opacity(0.18)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(sessionStore.isWorking)

                        Button {
                            emailFlow = .signUp
                        } label: {
                            authButtonLabel(
                                title: "Opprett konto med e-post",
                                systemImage: "envelope"
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(sessionStore.isWorking)

                        HStack(spacing: 4) {
                            Text("Har du allerede konto?")
                                .appSecondaryStyle()
                            Button("Logg inn") {
                                emailFlow = .signIn
                            }
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.primary)
                            .buttonStyle(.plain)
                            .disabled(sessionStore.isWorking)
                        }
                    }
                    .frame(maxWidth: 420, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        authValueRow(title: "Uten konto", detail: "Data lagres på denne enheten.")
                        authValueRow(title: "Med konto", detail: "Data kan gjenopprettes senere.")
                    }
                    .frame(maxWidth: 420, alignment: .leading)
                    .padding()
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(AppTheme.divider, lineWidth: 1)
                    )

                    Spacer(minLength: 20)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(AppTheme.background)
            .navigationTitle("Kom i gang")
            .sheet(item: $emailFlow) { mode in
                EmailAuthSheetView(mode: mode) { email, password, displayName in
                    switch mode {
                    case .signUp:
                        await sessionStore.createAccountWithEmail(
                            email: email,
                            password: password,
                            displayName: displayName,
                            preference: preference,
                            context: modelContext
                        )
                    case .signIn:
                        await sessionStore.signInWithEmail(
                            email: email,
                            password: password,
                            preference: preference,
                            context: modelContext
                        )
                    }
                }
            }
            .alert(
                "Konto",
                isPresented: Binding(
                    get: { sessionStore.authErrorMessage != nil },
                    set: { if !$0 { sessionStore.clearError() } }
                )
            ) {
                Button("OK", role: .cancel) {
                    sessionStore.clearError()
                }
            } message: {
                Text(sessionStore.authErrorMessage ?? "")
            }
        }
    }

    private func authButtonLabel(
        title: String,
        systemImage: String,
        tint: Color = AppTheme.surface,
        stroke: Color = AppTheme.divider
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
            Text(title)
                .appCTAStyle()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(tint, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(stroke, lineWidth: 1)
        )
    }

    private func authValueRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(detail)
                .appSecondaryStyle()
        }
    }
}
