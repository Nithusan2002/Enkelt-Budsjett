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
    @Query private var preferences: [UserPreference]

    @StateObject private var viewModel = OverviewViewModel()
    @State private var showCheckIn = false
    @State private var displayedWealth: Double = 0

    private var activeGoal: Goal? { viewModel.activeGoal(from: goals) }
    private var latestSnapshot: InvestmentSnapshot? { viewModel.latestSnapshot(from: snapshots) }
    private var previousSnapshot: InvestmentSnapshot? { InvestmentService.previousSnapshot(snapshots) }
    private var preference: UserPreference? { preferences.first }

    private var currentWealth: Double {
        viewModel.currentWealth(activeGoal: activeGoal, latestSnapshot: latestSnapshot, accounts: accounts)
    }

    private var savedYTD: Double {
        viewModel.savedYTD(definition: .incomeMinusExpense, transactions: transactions, categories: categories)
    }

    private var hasSavedData: Bool {
        abs(savedYTD) >= 1 && transactions.contains { $0.kind == .income || $0.kind == .expense || $0.kind == .refund }
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

    private var developmentSnapshots: [InvestmentSnapshot] {
        InvestmentService.filteredSnapshots(
            range: viewModel.selectedRange,
            snapshots: snapshots
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                wealthHeroModule
                developmentModule
                portfolioModule
                goalModule
                if hasSavedData {
                    savedModule
                }
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Oversikt")
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
            Text("Total formue")
                .appSecondaryStyle()

            Text(formatNOK(displayedWealth))
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
                Button(latestSnapshot == nil ? "Oppdater formue" : "Oppdater formue nå") {
                    showCheckIn = true
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .appCTAStyle()
            }
        }
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total formue")
        .accessibilityValue(formatNOK(displayedWealth))
    }

    private var developmentModule: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Utvikling")
                    .appCardTitleStyle()
                Spacer()
                Picker("Periode", selection: $viewModel.selectedRange) {
                    Text("I år").tag(GraphViewRange.yearToDate)
                    Text("1 år").tag(GraphViewRange.oneYear)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            if developmentSnapshots.count < 2 {
                Text("Legg inn én måned til for å se utvikling.")
                    .appBodyStyle()
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Chart(developmentSnapshots, id: \.periodKey) { snapshot in
                    LineMark(
                        x: .value("Dato", snapshot.capturedAt),
                        y: .value("Total", snapshot.totalValue)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(AppTheme.secondary)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 68)
                .accessibilityLabel("Utvikling")
                .accessibilityValue(developmentAccessibilitySummary())
            }

            Button {
                openInvestments(focus: .development)
            } label: {
                Text("Se mer i Investeringer")
                    .appSecondaryStyle()
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
    }

    private var portfolioModule: some View {
        Button {
            openInvestments(focus: .distribution)
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
                        .frame(height: 160)
                        .accessibilityLabel("Porteføljefordeling")
                        .accessibilityValue(portfolioAccessibilitySummary(latestSnapshot))

                        let topTwo = positiveValues.sorted { $0.amount > $1.amount }.prefix(2)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(topTwo), id: \.bucketID) { bucketValue in
                                let share = latestSnapshot.totalValue > 0 ? bucketValue.amount / latestSnapshot.totalValue : 0
                                Text("\(bucketName(for: bucketValue.bucketID)): \(formatPercent(share))")
                                    .appSecondaryStyle()
                            }
                        }
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
                            Text("Ca. \(formatNOK(summary.perMonth)) per måned")
                                .appSecondaryStyle()
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }

                        ProgressView(value: summary.progress, total: 1)
                            .tint(AppTheme.primary)

                        Text("\(formatNOK(currentWealth)) / \(formatNOK(summary.targetAmount))")
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
        let statusLine = viewModel.positiveStatusLine(savedAmount: savedYTD, period: "hittil i år", tone: .warm)
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

    private func bucketName(for id: String) -> String {
        viewModel.bucketName(for: id, buckets: buckets)
    }

    private func bucketColor(for id: String) -> Color {
        guard let bucket = buckets.first(where: { $0.id == id }) else {
            return AppTheme.secondary
        }
        return AppTheme.portfolioColor(for: bucket)
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
        return "Neste insjekk: \(formatDayMonth(next))"
    }

    private func formatDayMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "dd.MM"
        return formatter.string(from: date)
    }

    private func changeSincePreviousText() -> String {
        let sign = heroChange.kr >= 0 ? "+" : "−"
        return "Siden forrige insjekk: \(sign)\(formatNOK(abs(heroChange.kr)))"
    }

    private func developmentAccessibilitySummary() -> String {
        guard let first = developmentSnapshots.first, let last = developmentSnapshots.last else {
            return "Ingen utviklingsdata ennå."
        }
        let change = last.totalValue - first.totalValue
        return "Fra \(formatNOK(first.totalValue)) til \(formatNOK(last.totalValue)), endring \(formatNOK(change))."
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

    private func openInvestments(focus: InvestmentsSectionFocus) {
        navigationState.investmentsFocus = focus
        navigationState.selectedTab = .investments
    }
}
