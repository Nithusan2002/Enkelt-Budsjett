#if DEBUG
import SwiftUI
import SwiftData

struct ComponentStatesDebugView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                componentSection("Knapper") {
                    VStack(spacing: 12) {
                        Button("Primær handling") {}
                            .appProminentCTAStyle()
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Sekundær handling") {}
                            .buttonStyle(.bordered)
                            .tint(AppTheme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Deaktivert handling") {}
                            .appProminentCTAStyle()
                            .disabled(true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        BudgetBottomAddTransactionButton(onTap: {})
                    }
                }

                componentSection("Budsjettheader") {
                    VStack(spacing: 14) {
                        BudgetHeroCardView(
                            hasPlannedBudget: true,
                            remaining: 4_250,
                            trackedActual: 11_750,
                            expenseTotal: 13_600,
                            planned: 16_000,
                            overBudgetCount: 0,
                            isOverBudgetFilterActive: false,
                            onToggleOverBudget: {}
                        )

                        BudgetHeroCardView(
                            hasPlannedBudget: true,
                            remaining: -980,
                            trackedActual: 8_980,
                            expenseTotal: 8_980,
                            planned: 8_000,
                            overBudgetCount: 2,
                            isOverBudgetFilterActive: true,
                            onToggleOverBudget: {}
                        )
                    }
                }

                componentSection("Budsjettrader") {
                    VStack(spacing: 0) {
                        GroupRowView(
                            row: BudgetGroupRow(
                                id: "food",
                                group: .hverdags,
                                title: "Mat",
                                planned: 5_000,
                                spent: 4_100,
                                categoryIDs: []
                            ),
                            fixedSpent: 1_300
                        )

                        Divider()
                            .overlay(AppTheme.divider)

                        GroupRowView(
                            row: BudgetGroupRow(
                                id: "transport",
                                group: .fast,
                                title: "Transport",
                                planned: 1_800,
                                spent: 1_790,
                                categoryIDs: []
                            ),
                            fixedSpent: 890
                        )

                        Divider()
                            .overlay(AppTheme.divider)

                        GroupRowView(
                            row: BudgetGroupRow(
                                id: "shopping",
                                group: .fritid,
                                title: "Shopping",
                                planned: 1_500,
                                spent: 2_240,
                                categoryIDs: []
                            ),
                            fixedSpent: 0
                        )
                    }
                    .padding()
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
                }

                componentSection("Inputs") {
                    ComponentStateInputExamples()
                }
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Komponentstates")
    }
}

struct EmptyStatesDebugView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                emptyStateCard(
                    title: "Ingen data ennå",
                    body: "Legg til første transaksjon eller innsjekk for å se utvikling her.",
                    actionTitle: "Legg til første post"
                )

                emptyStateCard(
                    title: "Ingen kategorier ennå",
                    body: "Opprett en kategori før du begynner å føre eller planlegge budsjett."
                )

                emptyStateCard(
                    title: "Ingen faste poster ennå",
                    body: "Legg inn husleie, lån og andre faste kostnader for automatisk oppfølging.",
                    tone: AppTheme.secondary
                )

                emptyStateCard(
                    title: "Ingen utviklingsdata ennå",
                    body: "Legg inn minst to måneder for å se trend og endring over tid.",
                    tone: AppTheme.warning
                )
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Tomtilstander")
    }

    private func emptyStateCard(
        title: String,
        body: String,
        actionTitle: String? = nil,
        tone: Color = AppTheme.primary
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "tray")
                .font(.title2.weight(.semibold))
                .foregroundStyle(tone)
            Text(title)
                .appCardTitleStyle()
            Text(body)
                .appSecondaryStyle()

            if let actionTitle {
                Button(actionTitle) {}
                    .buttonStyle(.borderedProminent)
                    .tint(tone)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
    }
}

struct DemoDataDebugView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SettingsViewModel()
    @State private var statusMessage: String?
    @State private var showResetConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Button("Last inn demo (3 år realistisk)") {
                    runDemoSeed()
                }
                .disabled(PersistenceGate.isReadOnlyMode)

                Button("Tøm alle demo-data", role: .destructive) {
                    showResetConfirm = true
                }
                .disabled(PersistenceGate.isReadOnlyMode)
            } header: {
                Text("Handlinger")
            } footer: {
                Text(PersistenceGate.isReadOnlyMode
                     ? "Skrivende handlinger er låst fordi appen kjører uten varig lagring."
                     : "Brukes for raske demo- og QA-scenarier i debug.")
            }

            Section("Status") {
                LabeledContent("Lagringsmodus", value: storeModeLabel)
                if let statusMessage {
                    Text(statusMessage)
                        .appSecondaryStyle()
                } else {
                    Text("Ingen handling kjørt ennå.")
                        .appSecondaryStyle()
                }
            }
        }
        .navigationTitle("Demo-data")
        .alert("Kunne ikke kjøre handling", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Tøm alle demo-data?", isPresented: $showResetConfirm) {
            Button("Avbryt", role: .cancel) { }
            Button("Tøm data", role: .destructive) {
                wipeDemoData()
            }
        } message: {
            Text("Dette sletter alle lokale data og bygger opp standardoppsett på nytt.")
        }
    }

    private var storeModeLabel: String {
        switch Simple_Budget___Budskjett_planlegger_gjort_enkeltApp.activeStoreMode {
        case .primary:
            return "Primær"
        case .primaryWithoutCloud:
            return "Primær (lokal)"
        case .recovery:
            return "Recovery"
        case .memoryOnly:
            return "Midlertidig"
        }
    }

    private func runDemoSeed() {
        do {
            let report = try viewModel.seedDemoRealisticYear(context: modelContext, year: nil)
            statusMessage = "Demo lastet: \(report.transactions) transaksjoner, \(report.snapshots) snapshots, \(report.budgetMonths) måneder."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func wipeDemoData() {
        do {
            try viewModel.wipeAllDataForDemo(context: modelContext)
            statusMessage = "Alle lokale data ble tømt og standardoppsett ble gjenopprettet."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ComponentStateInputExamples: View {
    @State private var amount = "4 250"
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Beløp", text: $amount)
                .textFieldStyle(.appInput)

            TextField("Notat", text: $note)
                .textFieldStyle(.appInput)

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
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
    }
}

private extension View {
    func componentSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            content()
        }
    }
}

#Preview("Komponentstates") {
    NavigationStack {
        ComponentStatesDebugView()
    }
}

#Preview("Tomtilstander") {
    NavigationStack {
        EmptyStatesDebugView()
    }
}

#Preview("Demo-data") {
    NavigationStack {
        DemoDataDebugView()
    }
    .modelContainer(DebugPreviewData.container)
}

private enum DebugPreviewData {
    static let container: ModelContainer = {
        let schema = Schema([
            BudgetMonth.self,
            Category.self,
            BudgetPlan.self,
            BudgetGroupPlan.self,
            Transaction.self,
            Account.self,
            InvestmentBucket.self,
            InvestmentSnapshot.self,
            FixedItem.self,
            FixedItemSkip.self,
            Goal.self,
            Challenge.self,
            UserPreference.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
            fatalError("Kunne ikke opprette debug preview-container")
        }
        let context = container.mainContext
        context.insert(UserPreference())
        try? context.save()
        return container
    }()
}
#endif
