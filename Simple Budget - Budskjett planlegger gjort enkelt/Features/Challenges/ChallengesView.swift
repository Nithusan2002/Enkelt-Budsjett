import SwiftUI

struct ChallengesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Utfordringer")
                        .font(.title2.weight(.semibold))
                    Text("Under utvikling")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                    Text("Vi bygger en lett og motiverende utfordringsmodul. Kommer snart.")
                        .appBodyStyle()
                        .foregroundStyle(AppTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("No-coffee-week", systemImage: "cup.and.saucer")
                    Label("1 000 kr på 30 dager", systemImage: "target")
                    Label("Rund opp kjøp", systemImage: "arrow.uturn.left.circle")
                    Label("Matbudsjett-uke", systemImage: "cart")
                }
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)

                Text("Takk for tålmodigheten. Du får beskjed når dette er klart.")
                    .appSecondaryStyle()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Utfordringer")
    }
}
