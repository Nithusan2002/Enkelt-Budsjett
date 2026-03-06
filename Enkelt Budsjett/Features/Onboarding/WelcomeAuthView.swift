import SwiftUI
import SwiftData

struct WelcomeAuthView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionStore: SessionStore

    let preference: UserPreference
    @State private var emailFlow: EmailAuthMode?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer(minLength: 24)

                VStack(spacing: 10) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)

                    Text("Bruk appen med eller uten konto")
                        .appCardTitleStyle()
                        .multilineTextAlignment(.center)

                    Text("Du kan starte lokalt nå, og logge inn senere for synkronisering og gjenoppretting.")
                        .appBodyStyle()
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 420)

                VStack(spacing: 12) {
                    Button("Fortsett uten konto") {
                        sessionStore.continueWithoutAccount(preference: preference, context: modelContext)
                    }
                    .appProminentCTAStyle()
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

                    Button {
                        emailFlow = .signIn
                    } label: {
                        authButtonLabel(
                            title: "Logg inn med e-post",
                            systemImage: "person.crop.circle"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(sessionStore.isWorking)

                    Button {
                        Task {
                            await sessionStore.signInWithGoogle(preference: preference, context: modelContext)
                        }
                    } label: {
                        authButtonLabel(
                            title: "Fortsett med Google",
                            systemImage: "globe"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(sessionStore.isWorking)
                }
                .frame(maxWidth: 420)

                VStack(alignment: .leading, spacing: 8) {
                    authValueRow(title: "Uten konto", detail: "Data lagres på denne enheten.")
                    authValueRow(title: "Med konto", detail: "Konto brukes senere til synkronisering og gjenoppretting.")
                }
                .frame(maxWidth: 420, alignment: .leading)
                .padding()
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppTheme.divider, lineWidth: 1)
                )

                Spacer()
            }
            .padding()
            .background(AppTheme.background)
            .navigationTitle("Kom i gang")
            .sheet(item: $emailFlow) { mode in
                EmailAuthSheet(mode: mode) { email, password, displayName in
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

    private func authButtonLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
            Text(title)
                .appCTAStyle()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.divider, lineWidth: 1)
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

private enum EmailAuthMode: String, Identifiable {
    case signUp
    case signIn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signUp:
            return "Opprett konto"
        case .signIn:
            return "Logg inn"
        }
    }

    var actionTitle: String {
        switch self {
        case .signUp:
            return "Opprett konto"
        case .signIn:
            return "Logg inn"
        }
    }
}

private struct EmailAuthSheet: View {
    @Environment(\.dismiss) private var dismiss

    let mode: EmailAuthMode
    let onSubmit: (String, String, String?) async -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Konto") {
                    if mode == .signUp {
                        TextField("Navn (valgfritt)", text: $displayName)
                            .textInputAutocapitalization(.words)
                    }

                    TextField("E-post", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)

                    SecureField("Passord", text: $password)

                    if mode == .signUp {
                        Text("Passord må ha minst 8 tegn.")
                            .appSecondaryStyle()
                    }
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.actionTitle) {
                        Task {
                            await onSubmit(email, password, displayName)
                            dismiss()
                        }
                    }
                    .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                }
            }
        }
    }
}
