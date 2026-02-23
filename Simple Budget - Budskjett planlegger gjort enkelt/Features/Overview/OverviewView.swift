import SwiftUI
import SwiftData
import Charts

struct OverviewView: View {
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]
    @Query(sort: \InvestmentSnapshot.periodKey) private var snapshots: [InvestmentSnapshot]
    @Query(sort: \InvestmentBucket.sortOrder) private var buckets: [InvestmentBucket]
    @Query private var accounts: [Account]
    @Query private var preferences: [UserPreference]
    @Query private var transactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @StateObject private var viewModel = OverviewViewModel()

    private var activeGoal: Goal? { viewModel.activeGoal(from: goals) }
    private var latestSnapshot: InvestmentSnapshot? { viewModel.latestSnapshot(from: snapshots) }

    private var savingsDefinition: SavingsDefinition {
        preferences.first?.savingsDefinition ?? .incomeMinusExpense
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rediger mål") { viewModel.showGoalEditor = true }
            }
        }
        .sheet(isPresented: $viewModel.showGoalEditor) {
            GoalEditorView(goal: activeGoal)
        }
        .onAppear {
            viewModel.onAppear(preference: preferences.first)
        }
    }

    private var goalModule: some View {
        let summary = viewModel.goalSummary(activeGoal: activeGoal, currentWealth: currentWealth)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Jeg vil ha en formue på \(formatNOK(summary.targetAmount)) innen \(summary.targetDate.formatted(date: .numeric, time: .omitted))")
                .appBodyStyle()
                .foregroundStyle(AppTheme.textSecondary)
            HStack(spacing: 16) {
                Gauge(value: summary.progress) {
                    Text("Fremdrift")
                } currentValueLabel: {
                    Text("\(Int((summary.progress * 100).rounded())) %")
                        .font(.caption)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(AppTheme.primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(formatNOK(summary.targetAmount))")
                        .appBigNumberStyle()
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("\(summary.monthsRemaining) måneder igjen")
                        .appBodyStyle()
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Ca. \(formatNOK(summary.perMonth)) per måned")
                        .appBodyStyle()
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
            }
        }
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
    }

    private var statusModule: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Du har spart \(formatNOK(savedYTD)) hittil i år.")
                .appCoachStyle()
                .foregroundStyle(AppTheme.textPrimary)
            Text(savingsDefinition == .incomeMinusExpense
                 ? "Definisjon: Inntekt minus utgifter (YTD)"
                 : "Definisjon: Kun sparingskategori (YTD)")
                .appSecondaryStyle()
        }
        .padding()
        .background(AppTheme.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
    }

    private var portfolioModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Porteføljefordeling")
                .appCardTitleStyle()
            if let latestSnapshot {
                Chart(latestSnapshot.bucketValues, id: \.bucketID) { value in
                    SectorMark(
                        angle: .value("Beløp", value.amount),
                        innerRadius: .ratio(0.55),
                        angularInset: 2
                    )
                    .foregroundStyle(AppTheme.portfolioColor(for: bucketName(for: value.bucketID)))
                }
                .frame(height: 220)
                ForEach(latestSnapshot.bucketValues, id: \.bucketID) { value in
                    HStack {
                        Text(bucketName(for: value.bucketID))
                        Spacer()
                        Text(formatNOK(value.amount))
                    }
                    .appBodyStyle()
                }
            } else {
                Text("Ingen insjekk ennå.")
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
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
                .frame(width: 220)
            }

            if chartData.isEmpty {
                Text("Ingen trenddata å vise ennå.")
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                Chart(chartData) { point in
                    AreaMark(
                        x: .value("Periode", point.periodKey),
                        y: .value("Beløp", point.amount),
                        stacking: .standard
                    )
                    .foregroundStyle(AppTheme.portfolioColor(for: point.bucketName))
                }
                .frame(height: 240)
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
}
