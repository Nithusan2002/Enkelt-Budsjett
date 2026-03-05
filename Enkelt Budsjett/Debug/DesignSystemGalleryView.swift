#if DEBUG
import SwiftUI

struct DesignSystemGalleryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("Farger") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(colorSwatches) { swatch in
                            ColorSwatchCard(swatch: swatch)
                        }
                    }
                }

                section("Typografi") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Stor verdi 128 400 kr")
                            .appBigNumberStyle()
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Korttittel")
                            .appCardTitleStyle()
                        Text("Brødtekst brukes til rader, oppsummeringer og standardinnhold.")
                            .appBodyStyle()
                        Text("Sekundærtekst brukes til støtteinfo og mikrocopy.")
                            .appSecondaryStyle()
                        Text("Primær handling")
                            .appCTAStyle()
                            .foregroundStyle(AppTheme.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
                }

                section("Handlinger") {
                    VStack(spacing: 12) {
                        Button("Lagre endringer") {}
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Sekundær handling") {}
                            .buttonStyle(.bordered)
                            .tint(AppTheme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        BudgetBottomAddTransactionButton(onTap: {})
                    }
                }

                section("Inputs og states") {
                    DesignSystemInputExamples()
                }

                section("Kort og tomtilstander") {
                    VStack(spacing: 14) {
                        BudgetHeroCardView(
                            hasPlannedBudget: true,
                            remaining: 4_250,
                            trackedActual: 11_750,
                            expenseTotal: 13_600,
                            planned: 16_000,
                            overBudgetCount: 2,
                            isOverBudgetFilterActive: false,
                            onToggleOverBudget: {}
                        )

                        BudgetHeroCardView(
                            hasPlannedBudget: false,
                            remaining: 0,
                            trackedActual: 0,
                            expenseTotal: 3_240,
                            planned: 0,
                            overBudgetCount: 0,
                            isOverBudgetFilterActive: false,
                            onToggleOverBudget: {}
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Ingen data ennå")
                                .appCardTitleStyle()
                            Text("Legg til første transaksjon eller innsjekk for å se utvikling her.")
                                .appSecondaryStyle()
                            Button("Legg til første post") {}
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
                    }
                }

                section("Budsjettrader") {
                    VStack(spacing: 0) {
                        GroupRowView(
                            row: BudgetGroupRow(
                                id: "mat",
                                group: .hverdags,
                                title: "Mat",
                                planned: 5_000,
                                spent: 4_200,
                                categoryIDs: []
                            ),
                            fixedSpent: 1_200
                        )

                        Divider()
                            .overlay(AppTheme.divider)

                        GroupRowView(
                            row: BudgetGroupRow(
                                id: "shopping",
                                group: .fritid,
                                title: "Shopping",
                                planned: 1_500,
                                spent: 1_980,
                                categoryIDs: []
                            ),
                            fixedSpent: 0
                        )
                    }
                    .padding()
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
                }
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Design system")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            content()
        }
    }

    private var colorSwatches: [ColorSwatch] {
        [
            ColorSwatch(name: "Primary", color: AppTheme.primary, hex: "#EA580C"),
            ColorSwatch(name: "Secondary", color: AppTheme.secondary, hex: "#0EA5E9"),
            ColorSwatch(name: "Surface", color: AppTheme.surface, hex: "#FFFFFF"),
            ColorSwatch(name: "Background", color: AppTheme.background, hex: "#FFF8F1"),
            ColorSwatch(name: "Positive", color: AppTheme.positive, hex: "#16A34A"),
            ColorSwatch(name: "Warning", color: AppTheme.warning, hex: "#D97706"),
            ColorSwatch(name: "Negative", color: AppTheme.negative, hex: "#DC2626"),
            ColorSwatch(name: "Divider", color: AppTheme.divider, hex: "#F1E7DC")
        ]
    }
}

private struct DesignSystemInputExamples: View {
    @State private var amount = "12 500"
    @State private var category = "Dagligvarer"
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Beløp")
                    .appSecondaryStyle()
                TextField("0 kr", text: $amount)
                    .textFieldStyle(.appInput)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Kategori")
                    .appSecondaryStyle()
                TextField("Velg kategori", text: $category)
                    .textFieldStyle(.appInput)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notat")
                    .appSecondaryStyle()
                TextField("Valgfritt notat", text: $notes)
                    .textFieldStyle(.appInput)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Valideringsfeil")
                    .appSecondaryStyle()
                HStack {
                    Text("Beløp mangler")
                        .appBodyStyle()
                        .foregroundStyle(AppTheme.negative)
                    Spacer()
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(AppTheme.negative)
                }
                .appInputShellStyle()
            }
        }
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
    }
}

private struct ColorSwatch: Identifiable {
    let id: String
    let name: String
    let color: Color
    let hex: String

    init(name: String, color: Color, hex: String) {
        self.id = name
        self.name = name
        self.color = color
        self.hex = hex
    }
}

private struct ColorSwatchCard: View {
    let swatch: ColorSwatch

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 12)
                .fill(swatch.color)
                .frame(height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.divider, lineWidth: 1)
                )

            Text(swatch.name)
                .appCardTitleStyle()
            Text(swatch.hex)
                .appSecondaryStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
    }
}

#Preview("Design System") {
    NavigationStack {
        DesignSystemGalleryView()
    }
    .preferredColorScheme(.light)
}

#Preview("Design System Dark") {
    NavigationStack {
        DesignSystemGalleryView()
    }
    .preferredColorScheme(.dark)
}
#endif
