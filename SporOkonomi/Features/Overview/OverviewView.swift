import SwiftUI
import SwiftData
struct OverviewView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @AppStorage("overview_amounts_hidden") private var areAmountsHidden = false

    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]
    @Query(sort: \InvestmentSnapshot.periodKey) private var snapshots: [InvestmentSnapshot]
    @Query(sort: \InvestmentBucket.sortOrder) private var buckets: [InvestmentBucket]
    @Query private var budgetPlans: [BudgetPlan]
    @Query private var accounts: [Account]
    @Query private var transactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var preferences: [UserPreference]

    @StateObject private var viewModel = OverviewViewModel()
    @State private var showCheckIn = false
    @State private var displayedWealth: Double = 0

    private var activeGoal: Goal? { viewModel.activeGoal(from: goals) }
    private var latestSnapshot: InvestmentSnapshot? { viewModel.latestSnapshot(from: snapshots) }
    private var previousSnapshot: InvestmentSnapshot? { InvestmentService.previousSnapshot(snapshots) }
    private var preference: UserPreference? { preferences.first }
    private var overviewTitle: String { viewModel.overviewTitle(firstName: preference?.firstName) }
    private var budgetStatus: OverviewBudgetStatus {
        viewModel.budgetStatus(plans: budgetPlans, transactions: transactions)
    }
    private var shouldShowEmptyState: Bool {
        viewModel.shouldShowEmptyState(
            transactions: transactions,
            snapshots: snapshots,
            plans: budgetPlans,
            accounts: accounts
        )
    }

    private var currentWealth: Double {
        viewModel.currentWealth(activeGoal: activeGoal, latestSnapshot: latestSnapshot, accounts: accounts)
    }

    private var registeredSavingYTD: Double {
        viewModel.registeredSavingYTD(transactions: transactions, categories: categories)
    }

    private var hasSavedData: Bool {
        abs(registeredSavingYTD) >= 1
    }

    private var shouldShowRegisteredSavingsCard: Bool {
        abs(registeredSavingYTD) >= 1
    }

    private var shouldShowPrimaryCTA: Bool {
        latestSnapshot == nil || isCheckInDue
    }

    private var isCheckInDue: Bool {
        guard preference?.checkInReminderEnabled ?? true else { return false }
        let day = min(max(preference?.checkInReminderDay ?? 5, 1), 28)
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month], from: now)
        components.day = day
        components.hour = preference?.checkInReminderHour ?? 19
        components.minute = preference?.checkInReminderMinute ?? 0
        let thisMonthCheckIn = calendar.date(from: components) ?? now
        return now >= thisMonthCheckIn
    }

    private var heroChange: (kr: Double, pct: Double?) {
        InvestmentService.monthChange(current: latestSnapshot, previous: previousSnapshot)
    }

    var body: some View {
        ScrollView {
            if shouldShowEmptyState {
                emptyStateModule
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    monthlyStatusHeroModule
                    goalModule
                    investmentsSummaryModule
                    if hasSavedData {
                        historicalSavingsModule
                    }
                }
                .padding()
            }
        }
        .refreshable {
            viewModel.onAppear(preference: preference)
            withAnimation(.easeOut(duration: 0.35)) {
                displayedWealth = currentWealth
            }
        }
        .background(AppTheme.background)
        .navigationTitle(overviewTitle)
        .sheet(isPresented: $viewModel.showGoalEditor) {
            GoalEditorView(goal: activeGoal)
        }
        .sheet(isPresented: $showCheckIn) {
            InvestmentCheckInWizardView(
                buckets: buckets,
                snapshots: snapshots
            )
        }
        .onAppear {
            viewModel.onAppear(preference: preference)
            displayedWealth = currentWealth
        }
        .onChange(of: currentWealth) { _, newValue in
            withAnimation(.easeOut(duration: 0.45)) {
                displayedWealth = newValue
            }
        }
    }

    private var monthlyStatusHeroModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(viewModel.heroTitle())
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
                .accessibilityHint("Bytter mellom synlige og skjulte beløp.")
                Spacer()
            }

            Text(areAmountsHidden ? "Beløp skjult" : viewModel.heroAmountText(status: budgetStatus))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(heroAmountTone)
                .contentTransition(.numericText(value: budgetStatus.net))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(
                viewModel.heroStatusLine(
                    status: budgetStatus,
                    hasTransactions: !transactions.isEmpty,
                    areAmountsHidden: areAmountsHidden
                )
            )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(budgetStatus.net >= 0 ? AppTheme.positive : AppTheme.textSecondary)

            HStack(alignment: .top, spacing: 12) {
                overviewMetric(
                    title: "Brukt så langt",
                    value: areAmountsHidden ? "Skjult" : viewModel.heroMetricValue(amount: budgetStatus.spent),
                    tone: AppTheme.textPrimary
                )

                Divider()

                overviewMetric(
                    title: "Planlagt",
                    value: areAmountsHidden ? "Skjult" : viewModel.heroMetricValue(amount: budgetStatus.planned),
                    tone: AppTheme.textPrimary
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let progress = viewModel.monthlyProgress(status: budgetStatus) {
                ProgressView(value: progress.value, total: progress.total)
                    .tint(AppTheme.primary)
            }

            Button(viewModel.heroPrimaryCTATitle()) {
                navigationState.selectedTab = .budget
            }
            .appProminentCTAStyle()

            if isCheckInDue && latestSnapshot == nil {
                Text("Du kan legge til snapshot senere i Investeringer.")
                    .appSecondaryStyle()
            }
        }
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.heroTitle())
        .accessibilityValue(areAmountsHidden ? "Beløp skjult" : viewModel.heroAmountText(status: budgetStatus))
    }

    private var investmentsSummaryModule: some View {
        Button {
            openInvestments()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Investeringer")
                        .appCardTitleStyle()
                    Spacer()
                }

                if let latestSnapshot {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total verdi")
                                .appSecondaryStyle()
                            Text(displayedAmount(latestSnapshot.totalValue))
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.textPrimary)
                        }

                        Text(changeSincePreviousText())
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(heroChange.kr >= 0 ? AppTheme.positive : AppTheme.negative)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total verdi")
                                .appSecondaryStyle()
                            Text(displayedAmount(0))
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.textPrimary)
                        }

                        Text(viewModel.investmentsEmptyTitle())
                            .appSecondaryStyle()
                            .foregroundStyle(AppTheme.textSecondary)
                        Text(viewModel.investmentsEmptySupportText())
                            .appSecondaryStyle()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Investeringsoppsummering")
        .accessibilityHint("Åpner investeringer")
    }

    private var emptyStateModule: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ingen føringer ennå")
                .appCardTitleStyle()

            Text("Legg til en inntekt eller utgift for å få oversikt over måneden.")
                .appBodyStyle()
                .foregroundStyle(AppTheme.textSecondary)

            Button(viewModel.heroPrimaryCTATitle()) {
                navigationState.selectedTab = .budget
            }
            .appProminentCTAStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
    }

    private var goalModule: some View {
        let summary = viewModel.goalSummary(activeGoal: activeGoal, currentWealth: currentWealth)

        return AnyView(
            Button {
                viewModel.showGoalEditor = true
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    if activeGoal == nil {
                        Text("Mål")
                            .appCardTitleStyle()
                        Text("Sett et mål")
                            .appBodyStyle()
                            .foregroundStyle(AppTheme.textSecondary)
                        Text(viewModel.goalEmptySupportText())
                            .appSecondaryStyle()
                    } else {
                        HStack {
                            Text(viewModel.goalProgressTitle())
                                .appCardTitleStyle()
                            Spacer()
                            Image(systemName: "pencil")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.primary)
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text("\(Int((summary.progress * 100).rounded())) %")
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.primary.opacity(0.12), in: Capsule())
                            Spacer()
                            Text(areAmountsHidden ? "Ca. beløp skjult per måned" : "Ca. \(formatNOK(summary.perMonth)) per måned")
                                .appSecondaryStyle()
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }

                        Text(goalTrajectoryText(summary: summary))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)

                        let progress = clampedProgress(value: summary.progress, total: 1)
                        ProgressView(value: progress.value, total: progress.total)
                            .tint(AppTheme.primary)

                        Text(areAmountsHidden ? "Beløp skjult / beløp skjult" : "\(formatNOK(currentWealth)) / \(formatNOK(summary.targetAmount))")
                            .appBodyStyle()
                            .foregroundStyle(AppTheme.textPrimary)
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

    private var savedModule: some View {
        historicalSavingsModule
    }

    private var historicalSavingsModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            if shouldShowRegisteredSavingsCard {
                Button {
                    navigationState.selectedTab = .budget
                } label: {
                    savingsCard(
                        title: viewModel.registeredSavingsHeadline(),
                        value: displayedAmount(registeredSavingYTD),
                        support: viewModel.registeredSavingsSupportText(),
                        tone: registeredSavingYTD >= 0 ? AppTheme.positive : AppTheme.textPrimary
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.registeredSavingsHeadline())
                .accessibilityValue(areAmountsHidden ? "Beløp skjult" : formatNOK(registeredSavingYTD))
            }
        }
    }

    private func savingsCard(title: String, value: String, support: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appCardTitleStyle()
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tone)
            Text(support)
                .appBodyStyle()
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
    }

    private func overviewMetric(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appSecondaryStyle()
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tone)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func changeSincePreviousText() -> String {
        if previousSnapshot == nil {
            return "Siden forrige registrering: ikke tilgjengelig ennå"
        }
        if areAmountsHidden {
            return "Siden forrige registrering: beløp skjult"
        }
        let sign = heroChange.kr >= 0 ? "+" : "−"
        return "Siden forrige registrering: \(sign)\(formatNOK(abs(heroChange.kr)))"
    }

    private func goalTrajectoryText(summary: GoalSummary) -> String {
        if summary.progress >= 1 {
            return "På mål allerede."
        }
        if summary.monthsRemaining <= 0 {
            return "Fristen er passert. Oppdater mål for ny plan."
        }
        if areAmountsHidden {
            return "For å nå målet innen \(formatMonthYearShort(summary.targetDate)): månedlig beløp er skjult."
        }
        return "For å nå målet innen \(formatMonthYearShort(summary.targetDate)): ca. \(formatNOK(summary.perMonth)) per måned."
    }

    private func displayedAmount(_ value: Double) -> String {
        areAmountsHidden ? "•••• kr" : formatNOK(value)
    }

    private func displayedSignedAmount(_ value: Double, keepSignWhenHidden: Bool) -> String {
        if areAmountsHidden {
            if keepSignWhenHidden {
                let sign = value >= 0 ? "+" : "−"
                return "\(sign)•••• kr"
            }
            return "•••• kr"
        }
        let sign = value >= 0 ? "+" : "−"
        return "\(sign)\(formatNOK(abs(value)))"
    }

    private var heroAmountTone: Color {
        let focusAmount = budgetStatus.hasPlan ? budgetStatus.remaining : budgetStatus.net
        return focusAmount < 0 ? AppTheme.warning : AppTheme.textPrimary
    }

    private func openInvestments() {
        navigationState.selectedTab = .investments
    }
}
