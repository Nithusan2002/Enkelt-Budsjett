import SwiftUI
import SwiftData

struct OverviewView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @Environment(\.modelContext) private var modelContext
    @AppStorage("overview_amounts_hidden") private var areAmountsHidden = false

    @Query(sort: \InvestmentSnapshot.periodKey) private var snapshots: [InvestmentSnapshot]
    @Query(sort: \BudgetPlan.monthPeriodKey) private var budgetPlans: [BudgetPlan]
    @Query(sort: \FixedItem.dayOfMonth) private var fixedItems: [FixedItem]
    @Query private var transactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var preferences: [UserPreference]

    @StateObject private var viewModel = OverviewViewModel()
    @StateObject private var budgetEntryViewModel = BudgetViewModel()
    @State private var displayedAvailable: Double = 0

    private var preference: UserPreference? { preferences.first }
    private var latestSnapshot: InvestmentSnapshot? { viewModel.latestSnapshot(from: snapshots) }
    private var previousSnapshot: InvestmentSnapshot? { InvestmentService.previousSnapshot(snapshots) }
    private var overviewTitle: String {
        let name = preference?.firstName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return "Oversikt" }
        return "\(name)´s oversikt"
    }
    private var budgetStatus: (hasPlan: Bool, remaining: Double, net: Double, spent: Double, planned: Double) {
        viewModel.budgetStatus(plans: budgetPlans, transactions: transactions)
    }
    private var availableNow: Double {
        viewModel.availableNowAmount(budgetStatus: budgetStatus)
    }
    private var upcomingFixedExpense: OverviewUpcomingFixedExpense? {
        viewModel.upcomingFixedExpense(fixedItems: fixedItems)
    }
    private var investmentChange: (kr: Double, pct: Double?) {
        InvestmentService.monthChange(current: latestSnapshot, previous: previousSnapshot)
    }
    private var isReadOnlyMode: Bool { PersistenceGate.isReadOnlyMode }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                availableNowHero
                budgetSummaryCard
                investmentsSummaryCard
                if let upcomingFixedExpense {
                    upcomingFixedExpenseCard(upcomingFixedExpense)
                }
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle(overviewTitle)
        .refreshable {
            displayedAvailable = availableNow
        }
        .sheet(isPresented: $budgetEntryViewModel.showAddTransaction) {
            AddTransactionSheet(
                categories: categories.filter(\.isActive),
                initialType: .expense,
                initialTransaction: nil
            ) { date, amount, kind, categoryID, note in
                budgetEntryViewModel.addTransaction(
                    context: modelContext,
                    date: date,
                    amount: amount,
                    kind: kind,
                    categoryID: categoryID,
                    note: note
                )
            }
        }
        .onAppear {
            displayedAvailable = availableNow
        }
        .onChange(of: availableNow) { _, newValue in
            withAnimation(.easeOut(duration: 0.35)) {
                displayedAvailable = newValue
            }
        }
        .alert(
            "Kunne ikke lagre",
            isPresented: Binding(
                get: { budgetEntryViewModel.persistenceErrorMessage != nil },
                set: { if !$0 { budgetEntryViewModel.clearPersistenceError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                budgetEntryViewModel.clearPersistenceError()
            }
        } message: {
            Text(budgetEntryViewModel.persistenceErrorMessage ?? "")
        }
    }

    private var availableNowHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Tilgjengelig nå")
                    .appSecondaryStyle()

                Button {
                    areAmountsHidden.toggle()
                } label: {
                    Image(systemName: areAmountsHidden ? "eye.slash" : "eye")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(6)
                        .background(AppTheme.background.opacity(0.6), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(areAmountsHidden ? "Vis beløp" : "Skjul beløp")

                Spacer()
            }

            Text(displayedAmount(displayedAvailable))
                .appBigNumberStyle()
                .foregroundStyle(AppTheme.textPrimary)
                .contentTransition(.numericText(value: displayedAvailable))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(budgetStatus.hasPlan ? "Basert på det som er igjen i planen denne måneden." : "Basert på inntekter og utgifter registrert denne måneden.")
                .appBodyStyle()
                .foregroundStyle(AppTheme.textSecondary)

            Button("Legg til") {
                budgetEntryViewModel.showAddTransaction = true
            }
            .appProminentCTAStyle()
            .disabled(isReadOnlyMode)

            if isReadOnlyMode {
                Text("Skrivende handlinger er låst fordi appen kjører uten varig lagring.")
                    .appSecondaryStyle()
            }
        }
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
    }

    private var budgetSummaryCard: some View {
        Button {
            navigationState.selectedTab = .budget
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Budsjett")
                        .appCardTitleStyle()
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                if budgetStatus.hasPlan {
                    Text("Igjen denne måneden")
                        .appSecondaryStyle()
                    Text(displayedAmount(budgetStatus.remaining))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(budgetStatus.remaining < 0 ? AppTheme.warning : AppTheme.textPrimary)
                    Text(areAmountsHidden ? "Brukt så langt: skjult av skjult" : "Brukt så langt: \(formatNOK(budgetStatus.spent)) av \(formatNOK(budgetStatus.planned))")
                        .appSecondaryStyle()
                } else {
                    Text("Brukt så langt")
                        .appSecondaryStyle()
                    Text(displayedAmount(budgetStatus.spent))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Sett grenser i Budsjett for å se hva som er igjen denne måneden.")
                        .appSecondaryStyle()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var investmentsSummaryCard: some View {
        Button {
            navigationState.selectedTab = .investments
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Investeringer")
                        .appCardTitleStyle()
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                if let latestSnapshot {
                    Text("Total verdi")
                        .appSecondaryStyle()
                    Text(displayedAmount(latestSnapshot.totalValue))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(investmentChangeText())
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(changeColor(for: investmentChange.kr))
                } else {
                    Text("Total verdi")
                        .appSecondaryStyle()
                    Text("Ingen snapshots ennå")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Legg inn første snapshot i Investeringer for å følge utviklingen.")
                        .appSecondaryStyle()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func upcomingFixedExpenseCard(_ item: OverviewUpcomingFixedExpense) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Neste faste utgift")
                .appCardTitleStyle()
            Text(item.title)
                .appBodyStyle()
                .foregroundStyle(AppTheme.textPrimary)

            HStack {
                Text("Forfaller \(formatDayMonth(item.dueDate))")
                    .appSecondaryStyle()
                Spacer()
                Text(displayedAmount(item.amount))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
    }

    private func formatDayMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "dd.MM"
        return formatter.string(from: date)
    }

    private func displayedAmount(_ value: Double) -> String {
        areAmountsHidden ? "•••• kr" : formatNOK(value)
    }

    private func investmentChangeText() -> String {
        guard previousSnapshot != nil else {
            return areAmountsHidden ? "Siden forrige registrering: skjult" : "Siden forrige registrering: Ingen tidligere snapshot"
        }
        if areAmountsHidden {
            return "Siden forrige registrering: •••• kr"
        }
        let sign = investmentChange.kr >= 0 ? "+" : "−"
        return "Siden forrige registrering: \(sign)\(formatNOK(abs(investmentChange.kr)))"
    }

    private func changeColor(for amount: Double) -> Color {
        if amount > 0 { return AppTheme.positive }
        if amount < 0 { return AppTheme.negative }
        return AppTheme.textSecondary
    }
}
