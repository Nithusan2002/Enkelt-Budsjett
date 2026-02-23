import SwiftUI
import SwiftData
import Charts

struct OverviewView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]
    @Query(sort: \InvestmentSnapshot.periodKey) private var snapshots: [InvestmentSnapshot]
    @Query(sort: \InvestmentBucket.sortOrder) private var buckets: [InvestmentBucket]
    @Query private var accounts: [Account]
    @Query private var preferences: [UserPreference]
    @Query private var transactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @StateObject private var viewModel = OverviewViewModel()
    @State private var showCheckIn = false

    private var activeGoal: Goal? { viewModel.activeGoal(from: goals) }
    private var latestSnapshot: InvestmentSnapshot? { viewModel.latestSnapshot(from: snapshots) }

    private var savingsDefinition: SavingsDefinition {
        preferences.first?.savingsDefinition ?? .incomeMinusExpense
    }

    private var toneStyle: AppToneStyle {
        preferences.first?.toneStyle ?? .warm
    }

    private var currentWealth: Double {
        viewModel.currentWealth(activeGoal: activeGoal, latestSnapshot: latestSnapshot, accounts: accounts)
    }

    private var savedYTD: Double {
        viewModel.savedYTD(definition: savingsDefinition, transactions: transactions, categories: categories)
    }

    private var chartData: [ChartPoint] {
        viewModel.chartData(snapshots: snapshots, buckets: buckets)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                firstRunModule
                goalModule
                statusModule
                portfolioModule
                developmentModule
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
            viewModel.onAppear(preference: preferences.first)
        }
    }

    @ViewBuilder
    private var firstRunModule: some View {
        if latestSnapshot != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Total formue")
                    .appSecondaryStyle()
                Text(formatNOK(currentWealth))
                    .appBigNumberStyle()
                    .foregroundStyle(AppTheme.textPrimary)
                HStack {
                    Label(nextCheckInText(), systemImage: "calendar")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.secondary.opacity(0.12), in: Capsule())
                    Spacer()
                }
                if shouldShowPrimaryCheckInAction {
                    Button("Oppdater formue") {
                        showCheckIn = true
                    }
                    .appCTAStyle()
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
                }
            }
            .padding()
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Klar for første oppdatering")
                    .appCardTitleStyle()
                Text("Legg inn grove tall nå. Det tar rundt 30 sekunder.")
                    .appBodyStyle()
                Button("Oppdater formue (30 sek)") {
                    showCheckIn = true
                }
                .appCTAStyle()
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
            }
            .padding()
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        }
    }

    private var goalModule: some View {
        let summary = viewModel.goalSummary(activeGoal: activeGoal, currentWealth: currentWealth)

        return Button {
            viewModel.showGoalEditor = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                if activeGoal == nil {
                    Text("Mål")
                        .appCardTitleStyle()
                    Text("Sett et formuemål for å få tydelig fremdrift på oversikten.")
                        .appBodyStyle()
                        .foregroundStyle(AppTheme.textSecondary)
                    HStack {
                        Spacer()
                        Text("Trykk for å opprette")
                            .appSecondaryStyle()
                    }
                } else {
                    HStack {
                        Text("Mål")
                            .appCardTitleStyle()
                        Spacer()
                        Text("Trykk for å redigere")
                            .appSecondaryStyle()
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

                    Text("Mål: \(formatNOK(summary.targetAmount)) innen \(formatDate(summary.targetDate))")
                        .appSecondaryStyle()

                    HStack(spacing: 10) {
                        goalStatChip(title: "Igjen", value: "\(summary.monthsRemaining) mnd")
                        goalStatChip(title: "Behov / mnd", value: formatNOK(summary.perMonth))
                    }

                    HStack {
                        Spacer()
                        Text("Se mer")
                            .appSecondaryStyle()
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(activeGoal == nil ? "Målkort" : "Målkort med fremdrift")
        .accessibilityHint(activeGoal == nil ? "Åpner opprett mål" : "Åpner redigering av mål")
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private func goalStatChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusModule: some View {
        let statusLine = viewModel.positiveStatusLine(savedAmount: savedYTD, period: "hittil i år", tone: toneStyle)
        return Button {
            navigationState.selectedTab = .budget
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(statusLine)
                    .appCoachStyle()
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Trykk for detaljer i Budsjett.")
                    .appSecondaryStyle()
                HStack {
                    Spacer()
                    Text("Se mer")
                        .appSecondaryStyle()
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sparing hittil i år")
        .accessibilityValue(statusLine)
        .accessibilityHint("Åpner budsjettdetaljer")
        .padding()
        .background(AppTheme.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
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
                    Chart(latestSnapshot.bucketValues, id: \.bucketID) { value in
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
                    ForEach(latestSnapshot.bucketValues, id: \.bucketID) { value in
                        HStack {
                            Text(bucketName(for: value.bucketID))
                            Spacer()
                            Text(formatNOK(value.amount))
                        }
                        .appBodyStyle()
                    }
                } else {
                    Text("Legg inn første tall for å se fordeling.")
                        .appBodyStyle()
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Porteføljekort")
        .accessibilityHint("Åpner investeringer")
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private var developmentModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Utvikling")
                    .appCardTitleStyle()
                Spacer()
                Picker("Periode", selection: $viewModel.selectedRange) {
                    Text("I år").tag(GraphViewRange.yearToDate)
                    Text("Siste 12 mnd").tag(GraphViewRange.last12Months)
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }

            if chartData.isEmpty {
                Text(latestSnapshot == nil ? "Utvikling: kommer etter 2 insjekker." : "Legg inn én måned til for å se utvikling.")
                    .appBodyStyle()
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                Chart(chartData) { point in
                    AreaMark(
                        x: .value("Periode", point.periodKey),
                        y: .value("Beløp", point.amount),
                        stacking: .standard
                    )
                    .foregroundStyle(bucketColor(for: point.bucketID))
                }
                .frame(height: 240)
                .chartXAxis(.hidden)
                .accessibilityLabel("Utviklingsgraf")
                .accessibilityValue(developmentAccessibilitySummary(chartData))
            }
            HStack {
                Spacer()
                Button("Se mer") {
                    navigationState.selectedTab = .investments
                }
                .appSecondaryStyle()
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
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
        let day = preferences.first?.checkInReminderDay ?? 5
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month], from: now)
        comps.day = day
        let candidate = cal.date(from: comps) ?? now
        let next = candidate >= now ? candidate : cal.date(byAdding: .month, value: 1, to: candidate) ?? candidate
        return "Neste insjekk: \(formatDate(next))"
    }

    private var shouldShowPrimaryCheckInAction: Bool {
        guard let latestSnapshot else { return true }
        return latestSnapshot.periodKey != DateService.periodKey(from: .now)
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

    private func developmentAccessibilitySummary(_ points: [ChartPoint]) -> String {
        let grouped = Dictionary(grouping: points, by: \.periodKey)
            .mapValues { rows in rows.reduce(0) { $0 + $1.amount } }
        let keys = grouped.keys.sorted()
        guard let firstKey = keys.first, let lastKey = keys.last,
              let first = grouped[firstKey], let last = grouped[lastKey] else {
            return "Ingen utviklingsdata."
        }
        let change = last - first
        return "Fra \(formatNOK(first)) til \(formatNOK(last)), endring \(formatNOK(change))."
    }
}
