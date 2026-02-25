import SwiftUI
import SwiftData
import Charts

struct OverviewView: View {
    @EnvironmentObject private var navigationState: AppNavigationState

    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]
    @Query(sort: \InvestmentSnapshot.periodKey) private var snapshots: [InvestmentSnapshot]
    @Query(sort: \InvestmentBucket.sortOrder) private var buckets: [InvestmentBucket]
    @Query private var accounts: [Account]
    @Query private var transactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var plans: [BudgetPlan]

    @StateObject private var viewModel = OverviewViewModel()
    @State private var showCheckIn = false
    @State private var displayedWealth: Double = 0

    private var activeGoal: Goal? { viewModel.activeGoal(from: goals) }
    private var latestSnapshot: InvestmentSnapshot? { viewModel.latestSnapshot(from: snapshots) }

    private var currentWealth: Double {
        viewModel.currentWealth(activeGoal: activeGoal, latestSnapshot: latestSnapshot, accounts: accounts)
    }

    private var savedYTD: Double {
        viewModel.savedYTD(definition: .incomeMinusExpense, transactions: transactions, categories: categories)
    }

    private var firstInputDone: Bool {
        if !snapshots.isEmpty { return true }
        if !transactions.isEmpty { return true }
        if goals.contains(where: \.isActive) { return true }
        if plans.contains(where: { $0.plannedAmount > 0 }) { return true }
        if accounts.contains(where: { abs($0.currentBalance) > 0.0001 }) { return true }
        return false
    }

    private var budgetStatus: (hasPlan: Bool, remaining: Double, net: Double) {
        viewModel.budgetStatus(plans: plans, transactions: transactions)
    }

    private var budgetSetupDone: Bool {
        let monthKey = DateService.periodKey(from: .now)
        return plans.contains { $0.monthPeriodKey == monthKey && $0.plannedAmount > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !firstInputDone {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.primary)
                                .frame(width: 30, height: 30)
                                .background(AppTheme.primary.opacity(0.12), in: Circle())
                            Text("Kom i gang")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            Text("Ny")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.primary.opacity(0.12), in: Capsule())
                        }

                        Text("Registrer første tall for å aktivere full oversikt.")
                            .appBodyStyle()
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.primary.opacity(0.06), AppTheme.surface],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
                }

                wealthHeroModule
                goalModule
                statusModule
                portfolioModule
                budgetStatusModule
                scopeModule
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Oversikt")
        .sheet(isPresented: $viewModel.showGoalEditor) {
            GoalEditorView(goal: activeGoal)
        }
        .sheet(isPresented: $showCheckIn) {
            InvestmentCheckInView(buckets: buckets, latestSnapshot: latestSnapshot)
        }
        .onAppear {
            viewModel.onAppear(preference: nil)
            displayedWealth = currentWealth
        }
        .onChange(of: currentWealth) { _, newValue in
            withAnimation(.easeOut(duration: 0.45)) {
                displayedWealth = newValue
            }
        }
    }

    private var wealthHeroModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Total formue")
                .appSecondaryStyle()
            Text(formatNOK(displayedWealth))
                .appBigNumberStyle()
                .foregroundStyle(AppTheme.textPrimary)
                .contentTransition(.numericText(value: displayedWealth))

            HStack {
                Label(nextCheckInText(), systemImage: "calendar")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.secondary.opacity(0.12), in: Capsule())
                Spacer()
            }

        }
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
    }

    private var goalModule: some View {
        let summary = viewModel.goalSummary(activeGoal: activeGoal, currentWealth: currentWealth)

        if !firstInputDone && activeGoal == nil {
            return AnyView(
                VStack(alignment: .leading, spacing: 10) {
                    Text("Formue-mål")
                        .appCardTitleStyle()
                    Text("Sett et mål når du vil - det tar 10 sek.")
                        .appBodyStyle()
                        .foregroundStyle(AppTheme.textSecondary)
                    Button("Opprett mål") {
                        viewModel.showGoalEditor = true
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.primary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
            )
        }

        return AnyView(
            Button {
                viewModel.showGoalEditor = true
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    if activeGoal == nil {
                        Text("Mål")
                            .appCardTitleStyle()
                        Text("Sett et formuemål for å få tydelig fremdrift på oversikten.")
                            .appBodyStyle()
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        HStack {
                            Text("Mål")
                                .appCardTitleStyle()
                            Spacer()
                            Image(systemName: "pencil")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.primary)
                        }

                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nåværende formue")
                                    .appSecondaryStyle()
                                Text(formatNOK(currentWealth))
                                    .appBigNumberStyle()
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                            Spacer()
                            Text("\(Int((summary.progress * 100).rounded())) %")
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.primary.opacity(0.12), in: Capsule())
                        }

                        ProgressView(value: summary.progress, total: 1)
                            .tint(AppTheme.primary)

                        Text("Jeg vil ha en formue på \(formatNOK(summary.targetAmount)) innen \(formatDate(summary.targetDate))")
                            .appSecondaryStyle()
                    }
                }
            }
            .buttonStyle(.plain)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        )
    }

    private var statusModule: some View {
        let statusLine = viewModel.positiveStatusLine(savedAmount: savedYTD, period: "hittil i år", tone: .warm)
        return Button {
            navigationState.selectedTab = .budget
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(statusLine)
                    .appCoachStyle()
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Trykk for detaljer i Budsjett.")
                    .appSecondaryStyle()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppTheme.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sparing hittil i år")
        .accessibilityValue(statusLine)
    }

    private var portfolioModule: some View {
        Button {
            navigationState.selectedTab = .investments
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Porteføljefordeling")
                        .appCardTitleStyle()
                    Spacer()
                    Text("Se mer")
                        .appSecondaryStyle()
                }

                if let latestSnapshot {
                    let positiveValues = latestSnapshot.bucketValues.filter { $0.amount > 0 }
                    if positiveValues.count >= 2 {
                        Chart(positiveValues, id: \.bucketID) { value in
                            SectorMark(
                                angle: .value("Beløp", value.amount),
                                innerRadius: .ratio(0.55),
                                angularInset: 2
                            )
                            .foregroundStyle(bucketColor(for: value.bucketID))
                        }
                        .frame(height: 220)
                        .accessibilityLabel("Porteføljefordeling")
                        .accessibilityValue(portfolioAccessibilitySummary(latestSnapshot))
                    } else if let only = positiveValues.first {
                        Text("\(bucketName(for: only.bucketID)): 100% (\(formatNOK(only.amount)))")
                            .appBodyStyle()
                            .foregroundStyle(AppTheme.textPrimary)
                    } else {
                        Text("Legg inn første tall for å se fordeling.")
                            .appBodyStyle()
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                } else {
                    Text("Legg inn første tall for å se fordeling.")
                        .appBodyStyle()
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding()
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Porteføljekort")
        .accessibilityHint("Åpner investeringer")
    }

    private var budgetStatusModule: some View {
        Button {
            navigationState.selectedTab = .budget
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Budsjettstatus")
                    .appCardTitleStyle()

                if !budgetSetupDone {
                    Text("Velg en startpakke for å se igjen å bruke.")
                        .appBodyStyle()
                        .foregroundStyle(AppTheme.textSecondary)
                } else if budgetStatus.hasPlan {
                    Text("Igjen å bruke: \(formatNOK(budgetStatus.remaining))")
                        .appBodyStyle()
                        .foregroundStyle(budgetStatus.remaining < 0 ? AppTheme.negative : AppTheme.textPrimary)
                } else {
                    Text("Netto hittil: \(formatNOK(budgetStatus.net))")
                        .appBodyStyle()
                        .foregroundStyle(budgetStatus.net < 0 ? AppTheme.negative : AppTheme.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var scopeModule: some View {
        Text(viewModel.scopeText(activeGoal: activeGoal))
            .appSecondaryStyle()
    }

    private func bucketName(for id: String) -> String {
        viewModel.bucketName(for: id, buckets: buckets)
    }

    private func bucketColor(for id: String) -> Color {
        guard let bucket = buckets.first(where: { $0.id == id }) else {
            return AppTheme.secondary
        }
        return AppTheme.portfolioColor(for: bucket)
    }

    private func nextCheckInText() -> String {
        let day = 5
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month], from: now)
        comps.day = day
        let candidate = cal.date(from: comps) ?? now
        let next = candidate >= now ? candidate : cal.date(byAdding: .month, value: 1, to: candidate) ?? candidate
        return "Neste insjekk: \(formatDate(next))"
    }

    private func portfolioAccessibilitySummary(_ snapshot: InvestmentSnapshot) -> String {
        let total = max(snapshot.totalValue, 0)
        guard total > 0 else { return "Ingen fordeling ennå." }
        let parts = snapshot.bucketValues
            .sorted { $0.amount > $1.amount }
            .prefix(3)
            .map { value in
                let share = value.amount / total
                return "\(bucketName(for: value.bucketID)) \(formatPercent(share))"
            }
        return parts.joined(separator: ", ")
    }

}
