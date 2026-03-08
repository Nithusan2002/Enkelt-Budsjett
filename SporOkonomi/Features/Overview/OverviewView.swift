import SwiftUI
import SwiftData
struct OverviewView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @AppStorage("overview_amounts_hidden") private var areAmountsHidden = false

    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]
    @Query(sort: \InvestmentSnapshot.periodKey) private var snapshots: [InvestmentSnapshot]
    @Query(sort: \InvestmentBucket.sortOrder) private var buckets: [InvestmentBucket]
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
    private var savingsDefinition: SavingsDefinition { preference?.savingsDefinition ?? .incomeMinusExpense }
    private var overviewTitle: String {
        let name = preference?.firstName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return "Oversikt" }
        return "\(name)´s oversikt"
    }

    private var currentWealth: Double {
        viewModel.currentWealth(activeGoal: activeGoal, latestSnapshot: latestSnapshot, accounts: accounts)
    }

    private var savedYTD: Double {
        viewModel.savedYTD(definition: savingsDefinition, transactions: transactions, categories: categories)
    }

    private var savingsCategoryIDs: Set<String> {
        Set(categories.filter { $0.type == .savings && $0.isActive }.map(\.id))
    }

    private var hasSavedData: Bool {
        guard abs(savedYTD) >= 1 else { return false }
        switch savingsDefinition {
        case .incomeMinusExpense:
            return transactions.contains { $0.kind != .transfer }
        case .savingsCategoryOnly:
            return transactions.contains { transaction in
                if transaction.kind == .manualSaving { return true }
                guard let categoryID = transaction.categoryID else { return false }
                return savingsCategoryIDs.contains(categoryID)
            }
        }
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
            VStack(alignment: .leading, spacing: 16) {
                wealthHeroModule
                quickStatsModule
                investmentsSummaryModule
                goalModule
                if hasSavedData {
                    savedModule
                }
            }
            .padding()
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

    private var wealthHeroModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Total formue")
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

            Text(displayedAmount(displayedWealth))
                .appBigNumberStyle()
                .foregroundStyle(AppTheme.textPrimary)
                .contentTransition(.numericText(value: displayedWealth))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 8) {
                Label(checkInChipText(), systemImage: isCheckInDue ? "bell.badge.fill" : "calendar")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isCheckInDue ? AppTheme.primary : AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((isCheckInDue ? AppTheme.primary : AppTheme.secondary).opacity(0.12), in: Capsule())

                Spacer()
            }

            if previousSnapshot != nil {
                Text(changeSincePreviousText())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(heroChange.kr >= 0 ? AppTheme.positive : AppTheme.negative)
            }

            if shouldShowPrimaryCTA {
                Button(latestSnapshot == nil ? "Ny innsjekk" : "Oppdater formue nå") {
                    showCheckIn = true
                }
                .appProminentCTAStyle()
            }

            Divider()
                .overlay(AppTheme.divider)
                .padding(.vertical, 4)
        }
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total formue")
        .accessibilityValue(areAmountsHidden ? "Beløp skjult" : formatNOK(displayedWealth))
    }

    private var quickStatsModule: some View {
        HStack(spacing: 10) {
            Button {
                navigationState.selectedTab = .budget
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spart hittil i år")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(displayedAmount(savedYTD))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(savedYTD >= 0 ? AppTheme.positive : AppTheme.negative)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                viewModel.showGoalEditor = true
            } label: {
                let summary = viewModel.goalSummary(activeGoal: activeGoal, currentWealth: currentWealth)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Målprogresjon")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(activeGoal == nil ? "Ikke satt" : "\(Int((summary.progress * 100).rounded())) %")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
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
                    Text("Åpne")
                        .appSecondaryStyle()
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

                        Text("Siden forrige registrering: ikke tilgjengelig ennå")
                            .appSecondaryStyle()
                            .foregroundStyle(AppTheme.textSecondary)
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
                        Text("Sett formuemål")
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
        let statusLine = areAmountsHidden
            ? "Sparing hittil i år er skjult."
            : viewModel.positiveStatusLine(savedAmount: savedYTD, period: "hittil i år", tone: .warm)
        return Button {
            navigationState.selectedTab = .budget
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Spart hittil")
                    .appCardTitleStyle()
                Text(statusLine)
                    .appBodyStyle()
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Se detaljer i Budsjett")
                    .appSecondaryStyle()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppTheme.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Spart hittil")
        .accessibilityValue(statusLine)
    }

    private func checkInChipText() -> String {
        if isCheckInDue {
            return "Innsjekk klar"
        }
        let day = min(max(preference?.checkInReminderDay ?? 5, 1), 28)
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month], from: now)
        components.day = day
        let candidate = calendar.date(from: components) ?? now
        let next = candidate >= now ? candidate : calendar.date(byAdding: .month, value: 1, to: candidate) ?? candidate
        return "Neste innsjekk: \(formatDayMonth(next))"
    }

    private func formatDayMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "dd.MM"
        return formatter.string(from: date)
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

    private func openInvestments() {
        navigationState.selectedTab = .investments
    }
}
