import SwiftUI

struct ChallengesView: View {
    @AppStorage("challenges_waitlist_optin") private var waitlistOptIn = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "flag.checkered.2.crossed")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                    Spacer()
                    Text("Kommer snart")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.primary.opacity(0.12), in: Capsule())
                }

                Text("Utfordringer er under utvikling")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Snart får du små utfordringer med tydelig progresjon og varm tone.")
                    .appBodyStyle()
                    .foregroundStyle(AppTheme.textSecondary)

                VStack(alignment: .leading, spacing: 10) {
                    challengeRow("No-coffee-week", icon: "cup.and.saucer")
                    challengeRow("1 000 kr på 30 dager", icon: "target")
                    challengeRow("Rund opp kjøp", icon: "arrow.uturn.left.circle")
                    challengeRow("Matbudsjett-uke", icon: "cart")
                }
                .padding(12)
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))

                Button {
                    waitlistOptIn.toggle()
                } label: {
                    HStack {
                        Image(systemName: waitlistOptIn ? "checkmark.circle.fill" : "bell.badge")
                        Text(waitlistOptIn ? "Varsel er slått på" : "Gi beskjed når den er klar")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(waitlistOptIn ? AppTheme.positive : AppTheme.primary)

                Text(waitlistOptIn ? "Du får et lite varsel i appen når funksjonen er klar." : "Du kan slå på varsel nå, eller vente til senere.")
                    .appSecondaryStyle()

                Text("I mellomtiden finner du samme fremdriftsfølelse i Budsjett og Oversikt.")
                    .appSecondaryStyle()
            }
            .padding()
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
            .padding(.horizontal)

            Spacer()
        }
        .background(AppTheme.background)
        .navigationTitle("Utfordringer")
    }

    private func challengeRow(_ title: String, icon: String) -> some View {
        Label {
            Text(title)
                .appBodyStyle()
                .foregroundStyle(AppTheme.textPrimary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.secondary)
        }
    }
}
