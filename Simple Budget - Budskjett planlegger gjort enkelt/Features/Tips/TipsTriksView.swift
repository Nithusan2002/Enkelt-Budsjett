import SwiftUI

struct TipsTriksView: View {
    private let tips: [TipsItem] = [
        TipsItem(
            title: "Gjør ukentlig innsjekk",
            body: "Sett av 5 minutter én fast dag i uka. Små justeringer ofte gir bedre kontroll enn store skippertak."
        ),
        TipsItem(
            title: "Juster kun det som har endret seg",
            body: "I Ny innsjekk kan du la uendrede typer stå. Fokuser på det som faktisk har flyttet seg siden sist."
        ),
        TipsItem(
            title: "Hold antall typer lavt",
            body: "Start med 3–6 beholdningstyper. Færre typer gir mer lesbar graf og raskere vedlikehold."
        ),
        TipsItem(
            title: "Bruk historikk for mønster",
            body: "Se etter trender over 3–12 måneder i stedet for daglige svingninger."
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                ForEach(tips) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .appCardTitleStyle()
                        Text(item.body)
                            .appBodyStyle()
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(AppTheme.divider, lineWidth: 1)
                    )
                }
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Tips & Triks")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Små grep, stor effekt")
                .font(.title3.weight(.semibold))
            Text("Enkle råd for å holde budsjett og investeringer oppdatert uten ekstra friksjon.")
                .appSecondaryStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.divider, lineWidth: 1)
        )
    }
}

private struct TipsItem: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}
