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
    @State private var showAssistantSheet = false
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
            accounts: accounts,
            activeGoal: activeGoal
        )
    }

    private var currentWealth: Double {
        viewModel.currentWealth(activeGoal: activeGoal, latestSnapshot: latestSnapshot, accounts: accounts)
    }

    private var goalSummary: GoalSummary {
        viewModel.goalSummary(activeGoal: activeGoal, currentWealth: currentWealth)
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
                VStack(alignment: .leading, spacing: 12) {
                    overviewStatusLine
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
        .sheet(isPresented: $showAssistantSheet) {
            OverviewAssistantSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAssistantSheet = true
                } label: {
                    Image(systemName: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.surface.opacity(0.92), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(AppTheme.divider.opacity(0.72), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Åpne AI-assistent")
                .padding(.trailing, 2)
            }
        }
    }

    private var overviewStatusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusLineColor)
                .frame(width: 8, height: 8)

            Text(
                viewModel.screenStatusText(
                    status: budgetStatus,
                    goalSummary: activeGoal == nil ? nil : goalSummary,
                    hasTransactions: !transactions.isEmpty
                )
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(statusLineColor)
        }
        .padding(.horizontal, 4)
    }

    private var monthlyStatusHeroModule: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            if let dailyBudgetText = viewModel.dailyBudgetText(
                status: budgetStatus,
                areAmountsHidden: areAmountsHidden
            ) {
                Text(dailyBudgetText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let spentPlannedText = viewModel.spentPlannedText(
                    status: budgetStatus,
                    areAmountsHidden: areAmountsHidden
                ) {
                    Text(spentPlannedText)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .monospacedDigit()
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        overviewMetric(
                            title: "Inntekt",
                            value: areAmountsHidden ? "Skjult" : viewModel.heroMetricValue(amount: budgetStatus.income),
                            tone: AppTheme.textPrimary
                        )

                        Divider()

                        overviewMetric(
                            title: "Brukt",
                            value: areAmountsHidden ? "Skjult" : viewModel.heroMetricValue(amount: budgetStatus.spent),
                            tone: AppTheme.textPrimary
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(
                    viewModel.heroStatusLine(
                        status: budgetStatus,
                        hasTransactions: !transactions.isEmpty,
                        areAmountsHidden: areAmountsHidden
                    )
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(heroProgressTone)
            }

            if let progress = viewModel.monthlyProgress(status: budgetStatus) {
                OverviewProgressBar(
                    progress: progress.value / max(progress.total, 1),
                    tone: heroProgressTone
                )
            }

            Button(viewModel.heroPrimaryCTATitle()) {
                navigationState.selectedTab = .budget
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.primary.opacity(0.12), in: Capsule())
            .buttonStyle(.plain)

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

                        if let updatedText = viewModel.investmentLastUpdatedText(snapshot: latestSnapshot) {
                            Text(updatedText)
                                .appSecondaryStyle()
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
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.divider, lineWidth: 1))
    }

    private var goalModule: some View {
        let summary = goalSummary

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
                        let planState = viewModel.goalPlanState(summary: summary)
                        HStack {
                            Text(viewModel.goalProgressTitle())
                                .appCardTitleStyle()
                            Spacer()
                            Image(systemName: "pencil")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.primary)
                        }

                        Text(viewModel.goalPercentText(summary: summary))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.primary.opacity(0.12), in: Capsule())

                        let progress = clampedProgress(value: summary.progress, total: 1)
                        OverviewProgressBar(
                            progress: progress.value / max(progress.total, 1),
                            tone: AppTheme.positive
                        )

                        Text(viewModel.goalPlanStatusText(summary: summary))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(goalStatusColor(planState))

                        Text(viewModel.goalAmountsText(currentWealth: currentWealth, summary: summary, areAmountsHidden: areAmountsHidden))
                            .appBodyStyle()
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(viewModel.goalMonthlyNeedText(summary: summary, areAmountsHidden: areAmountsHidden))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(viewModel.goalContextText(summary: summary, areAmountsHidden: areAmountsHidden))
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

    private func goalStatusColor(_ state: GoalPlanState) -> Color {
        switch state {
        case .ahead, .complete:
            return AppTheme.positive
        case .onTrack:
            return AppTheme.textSecondary
        case .behind, .expired:
            return AppTheme.warning
        }
    }

    private struct OverviewProgressBar: View {
        let progress: Double
        let tone: Color

        var body: some View {
            GeometryReader { proxy in
                let clamped = min(max(progress, 0), 1)
                let width = max(proxy.size.width * clamped, clamped > 0 ? 8 : 0)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.background)
                    Capsule()
                        .fill(tone.opacity(0.9))
                        .frame(width: width)
                }
            }
            .frame(height: 10)
        }
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
        viewModel.investmentChangeText(
            change: heroChange.kr,
            previousSnapshot: previousSnapshot,
            areAmountsHidden: areAmountsHidden
        )
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

    private var heroProgressTone: Color {
        toneColor(viewModel.monthlyProgressTone(status: budgetStatus))
    }

    private var statusLineColor: Color {
        toneColor(
            viewModel.screenStatusTone(
                status: budgetStatus,
                goalSummary: activeGoal == nil ? nil : goalSummary
            )
        )
    }

    private func toneColor(_ tone: OverviewToneRole) -> Color {
        switch tone {
        case .positive:
            return AppTheme.positive
        case .warning:
            return AppTheme.warning
        case .neutral:
            return AppTheme.textSecondary
        }
    }

    private func openInvestments() {
        navigationState.selectedTab = .investments
    }
}

private struct OverviewAssistantSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigationState: AppNavigationState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Spacer()

                Button("Lukk") {
                    dismiss()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.surface, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppTheme.divider, lineWidth: 1)
                )
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("AI-assistent kommer snart")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Få hjelp til å forstå tallene dine, oppsummere måneden og finne neste steg.")
                    .appBodyStyle()
                    .foregroundStyle(AppTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                    Text("Kommer snart")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Text("Denne funksjonen blir en del av Premium.")
                    .appBodyStyle()
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .padding(18)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppTheme.divider, lineWidth: 1)
            )

            VStack(spacing: 12) {
                Button("Se Premium") {
                    dismiss()
                    navigationState.selectedTab = .settings
                    navigationState.pendingSettingsRoute = .premium
                }
                .appProminentCTAStyle()

                Button("Lukk") {
                    dismiss()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(AppTheme.background)
                .ignoresSafeArea()
        )
        .presentationBackground(.clear)
    }
}
