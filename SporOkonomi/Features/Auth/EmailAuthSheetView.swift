import SwiftUI

enum EmailAuthMode: String, Identifiable {
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

    var subtitle: String {
        switch self {
        case .signUp:
            return "Lag konto hvis du vil kunne logge inn igjen senere og beholde tilgang til dataene dine."
        case .signIn:
            return "Logg inn for å få tilgang til lagrede data og eventuell synk mellom dine egne enheter."
        }
    }
}

struct EmailAuthSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let mode: EmailAuthMode
    let onSubmit: (String, String, String?) async -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(mode.title)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(mode.subtitle)
                            .appSecondaryStyle()
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        if mode == .signUp {
                            authField(title: "Navn", footer: "Valgfritt") {
                                TextField("Nithusan", text: $displayName)
                                    .textInputAutocapitalization(.words)
                            }
                        }

                        authField(title: "E-post") {
                            TextField("navn@epost.no", text: $email)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                        }

                        authField(title: "Passord") {
                            SecureField("Skriv passord", text: $password)
                        }

                        if mode == .signUp {
                            Text("Minst 8 tegn, med små og store bokstaver, tall og symbol.")
                                .appSecondaryStyle()
                                .padding(.top, 2)
                        }
                    }
                    .padding(20)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(AppTheme.divider, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") {
                        dismiss()
                    }
                    .font(.body.weight(.medium))
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

    @ViewBuilder
    private func authField<Content: View>(title: String, footer: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                if let footer {
                    Text(footer)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            content()
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.divider, lineWidth: 1)
                )
        }
    }
}
