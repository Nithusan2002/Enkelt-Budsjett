import SwiftUI
import SwiftData

struct WelcomeAuthView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionStore: SessionStore

    let preference: UserPreference
    @State private var emailFlow: EmailAuthMode?

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

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

                            Text("Start lokalt på denne enheten. Du kan legge til konto senere hvis du vil gjenopprette data eller bruke iCloud-synk der den er tilgjengelig.")
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
                                    tint: AppTheme.surface,
                                    stroke: AppTheme.divider
                                ) {
                                    Image("Google-logo")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(sessionStore.isWorking)

                            Button {
                                emailFlow = .signUp
                            } label: {
                                authButtonLabel(
                                    title: "Opprett konto med e-post",
                                    tint: AppTheme.primary.opacity(0.08),
                                    stroke: AppTheme.primary.opacity(0.18)
                                ) {
                                    Image(systemName: "envelope")
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                }
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
                            authValueRow(title: "Uten konto", detail: "Data lagres kun på denne enheten.")
                            authValueRow(title: "Med konto", detail: "Du kan logge inn igjen senere og hente tilbake lagrede data.")
                            authValueRow(title: "iCloud-synk", detail: "Skjer via Apple-kontoen din når iCloud er aktiv på enheten.")
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
    }

    private func authButtonLabel<Leading: View>(
        title: String,
        tint: Color = AppTheme.surface,
        stroke: Color = AppTheme.divider,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        HStack(spacing: 10) {
            leading()

            Text(title)
                .appCTAStyle()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
