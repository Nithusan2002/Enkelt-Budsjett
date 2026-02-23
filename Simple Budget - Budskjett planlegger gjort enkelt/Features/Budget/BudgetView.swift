import SwiftUI
import SwiftData

struct BudgetView: View {
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var plans: [BudgetPlan]
    @Query private var transactions: [Transaction]
    @StateObject private var viewModel = BudgetViewModel()

    private var periodKey: String { viewModel.periodKey() }

    var body: some View {
        List {
            Section("Måned") {
                Text(periodKey)
            }
            Section("Oppsummering") {
                let summary = viewModel.summary(periodKey: periodKey, plans: plans, categories: categories, transactions: transactions)
                row("Planlagt", summary.planned)
                row("Faktisk", summary.actual)
                row("Avvik", summary.delta)
                row("Igjen å bruke", summary.remaining)
            }
            Section("Kategorier") {
                ForEach(viewModel.categoryRows(periodKey: periodKey, categories: categories, plans: plans, transactions: transactions)) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(row.title)
                            Spacer()
                            Text("\(formatNOK(row.spent)) / \(formatNOK(row.planned))")
                                .foregroundStyle(AppTheme.textSecondary)
                                .font(.subheadline)
                        }
                        ProgressView(value: viewModel.progressValue(for: row), total: viewModel.progressTotal(for: row))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Budsjett")
    }

    private func row(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(formatNOK(value)).monospacedDigit()
        }
    }
}
