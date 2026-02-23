import SwiftUI
import SwiftData
import Charts

struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \BudgetMonth.startDate) private var months: [BudgetMonth]
    @Query private var plans: [BudgetPlan]
    @Query private var transactions: [Transaction]

    @StateObject private var viewModel = BudgetViewModel()

    private var periodKey: String { viewModel.periodKey() }
    private var summary: BudgetSummaryData {
        viewModel.summary(periodKey: periodKey, plans: plans, categories: categories, transactions: transactions)
    }
    private var previousActual: Double {
        viewModel.previousMonthActual(periodKey: periodKey, transactions: transactions)
    }
    private var rows: [BudgetCategoryRow] {
        viewModel.categoryRows(periodKey: periodKey, categories: categories, plans: plans, transactions: transactions)
    }
    private var monthTransactions: [Transaction] {
        viewModel.transactionsForMonth(periodKey: periodKey, transactions: transactions)
    }
    private var hasPlansForMonth: Bool {
        plans.contains { $0.monthPeriodKey == periodKey }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                monthHeader
                actionRow
                summaryCard
                insightCard
                contentState
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Budsjett")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showAddTransaction = true
                } label: {
                    Label("Legg til", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $viewModel.showAddTransaction) {
            AddTransactionSheet(categories: categories.filter { $0.type == .expense && $0.isActive }) { date, amount, kind, categoryID, note in
                viewModel.addTransaction(
                    context: modelContext,
                    date: date,
                    amount: amount,
                    kind: kind,
                    categoryID: categoryID,
                    note: note
                )
            }
        }
        .sheet(item: $viewModel.editorTarget) { target in
            BudgetEditSheet(
                categoryName: target.categoryName,
                initialValue: plans.first { $0.monthPeriodKey == periodKey && $0.categoryID == target.categoryID }?.plannedAmount ?? 0
            ) { newValue in
                viewModel.upsertBudgetPlan(
                    context: modelContext,
                    periodKey: periodKey,
                    categoryID: target.categoryID,
                    plannedAmount: newValue,
                    plans: plans
                )
            }
        }
        .navigationDestination(for: String.self) { categoryID in
            if let category = categories.first(where: { $0.id == categoryID }) {
                BudgetCategoryDetailView(
                    category: category,
                    periodKey: periodKey,
                    plans: plans,
                    transactions: transactions,
                    viewModel: viewModel
                )
            } else {
                Text("Finner ikke kategori")
                    .appSecondaryStyle()
            }
        }
        .onAppear {
            viewModel.ensureMonthExists(context: modelContext, months: months, plans: plans)
        }
        .onChange(of: viewModel.selectedMonthDate) { _, _ in
            viewModel.ensureMonthExists(context: modelContext, months: months, plans: plans)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                viewModel.changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)

            Spacer()

            VStack(spacing: 2) {
                Text("Måned")
                    .appSecondaryStyle()
                Text(viewModel.monthDateText())
                    .font(.headline.weight(.semibold))
            }

            Spacer()

            Button {
                viewModel.changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button("Legg til transaksjon") {
                viewModel.showAddTransaction = true
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primary)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Denne måneden")
                .appCardTitleStyle()

            HStack {
                summaryCell("Planlagt", summary.planned)
                summaryCell("Faktisk", summary.actual)
            }

            HStack {
                summaryCell("Avvik", summary.deviation, color: summary.deviation > 0 ? AppTheme.warning : AppTheme.positive)
                summaryCell("Igjen å bruke", summary.remaining, color: summary.remaining < 0 ? AppTheme.negative : AppTheme.textPrimary)
            }

            let delta = summary.actual - previousActual
            Text(previousActual > 0
                 ? "Endring fra forrige måned: \(formatNOK(delta))"
                 : "Ingen sammenligningsmåned ennå")
                .appSecondaryStyle()
        }
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
    }

    private var insightCard: some View {
        let insight = viewModel.insight(summary: summary, rows: rows)
        return VStack(alignment: .leading, spacing: 5) {
            Text(insight.title)
                .appCardTitleStyle()
            Text(insight.detail)
                .appBodyStyle()
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
    }

    @ViewBuilder
    private var contentState: some View {
        if !hasPlansForMonth && monthTransactions.isEmpty {
            setupEmptyState
        } else if hasPlansForMonth && monthTransactions.isEmpty {
            zeroTransactionsState
        } else if !hasPlansForMonth {
            trackingOnlyState
        } else {
            categoriesSection(rows: rows)
        }
    }

    private var setupEmptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Klar for første budsjett?")
                .appCardTitleStyle()
            Text("Start med å registrere første utgift. Du kan sette budsjett per kategori etterpå.")
                .appBodyStyle()
                .foregroundStyle(AppTheme.textSecondary)
            Button("Legg til første utgift") {
                viewModel.showAddTransaction = true
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
    }

    private var zeroTransactionsState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ingen utgifter registrert ennå")
                .appCardTitleStyle()
            Text("Legg til første utgift for å se status og avvik.")
                .appBodyStyle()
                .foregroundStyle(AppTheme.textSecondary)
            Button("Legg til første utgift") {
                viewModel.showAddTransaction = true
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primary)
            categoriesSection(rows: rows)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
    }

    private var trackingOnlyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sporing er aktiv")
                .appCardTitleStyle()
            Text("Du kan sette budsjett når som helst. Nå ser du faktisk forbruk og toppkategorier.")
                .appBodyStyle()
                .foregroundStyle(AppTheme.textSecondary)
            ForEach(viewModel.topCategoryRows(periodKey: periodKey, categories: categories, plans: plans, transactions: transactions)) { row in
                categoryRow(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
    }

    private func categoriesSection(rows: [BudgetCategoryRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kategorier")
                .appCardTitleStyle()
            if rows.isEmpty {
                Text("Ingen kategorier å vise for valgt filter.")
                    .appSecondaryStyle()
            }
            ForEach(rows) { row in
                categoryRow(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
    }

    private func categoryRow(_ row: BudgetCategoryRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: row.id) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .appCardTitleStyle()
                        Text("\(formatNOK(row.spent)) / \(formatNOK(row.planned))")
                            .appSecondaryStyle()
                    }
                    Spacer()
                    Text(row.isOverBudget ? "Over" : "OK")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(row.isOverBudget ? AppTheme.warning : AppTheme.positive)
                }
            }
            .buttonStyle(.plain)

            ProgressView(value: viewModel.progressValue(for: row), total: viewModel.progressTotal(for: row))
                .tint(row.isOverBudget ? AppTheme.warning : AppTheme.secondary)

            HStack {
                Spacer()
                Button("Endre budsjett") {
                    viewModel.editorTarget = BudgetEditorTarget(id: row.id, categoryName: row.title, categoryID: row.id)
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .padding(.vertical, 6)
    }

    private func summaryCell(_ title: String, _ value: Double, color: Color = AppTheme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appSecondaryStyle()
            Text(formatNOK(value))
                .font(.headline.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct AddTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    let onSave: (Date, Double, TransactionKind, String?, String) -> Void

    @State private var date: Date = .now
    @State private var amount: Double = 0
    @State private var kind: TransactionKind = .expense
    @State private var selectedCategoryID: String?
    @State private var note: String = ""

    private var needsCategory: Bool {
        kind == .expense || kind == .refund
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Transaksjonstype", selection: $kind) {
                        Text("Utgift").tag(TransactionKind.expense)
                        Text("Inntekt").tag(TransactionKind.income)
                        Text("Refusjon").tag(TransactionKind.refund)
                        Text("Overføring").tag(TransactionKind.transfer)
                    }
                }

                Section("Detaljer") {
                    DatePicker("Dato", selection: $date, displayedComponents: [.date])
                    TextField("Beløp", value: $amount, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)

                    if needsCategory {
                        Picker("Kategori", selection: $selectedCategoryID) {
                            Text("Velg kategori").tag(String?.none)
                            ForEach(categories) { category in
                                Text(category.name).tag(Optional(category.id))
                            }
                        }
                    }

                    TextField("Notat (valgfritt)", text: $note)
                }
            }
            .navigationTitle("Legg til transaksjon")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        onSave(date, amount, kind, selectedCategoryID, note)
                        dismiss()
                    }
                    .disabled(amount <= 0 || (needsCategory && selectedCategoryID == nil))
                }
            }
        }
    }
}

private struct BudgetEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let categoryName: String
    let initialValue: Double
    let onSave: (Double) -> Void

    @State private var planned: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Kategori") {
                    Text(categoryName)
                }
                Section("Planlagt beløp") {
                    TextField("0", value: $planned, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Endre budsjett")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        onSave(max(planned, 0))
                        dismiss()
                    }
                }
            }
            .onAppear {
                planned = initialValue
            }
        }
    }
}

private struct BudgetCategoryDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let category: Category
    let periodKey: String
    let plans: [BudgetPlan]
    let transactions: [Transaction]

    @ObservedObject var viewModel: BudgetViewModel

    @State private var showEditor = false

    private var planned: Double {
        plans.first { $0.monthPeriodKey == periodKey && $0.categoryID == category.id }?.plannedAmount ?? 0
    }

    private var spent: Double {
        BudgetService.spentByCategory(for: periodKey, categoryID: category.id, transactions: transactions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(category.name)
                        .appCardTitleStyle()
                    Text("\(formatNOK(spent)) / \(formatNOK(planned))")
                        .appBodyStyle()
                    Text("Avvik: \(formatNOK(spent - planned))")
                        .appSecondaryStyle()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))

                let trend = viewModel.trendPoints(categoryID: category.id, periodKey: periodKey, transactions: transactions)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trend i måneden")
                        .appCardTitleStyle()
                    if trend.isEmpty {
                        Text("Ingen registreringer ennå.")
                            .appSecondaryStyle()
                    } else {
                        Chart(trend) { point in
                            LineMark(
                                x: .value("Dag", point.day),
                                y: .value("Kumulativ", point.cumulative)
                            )
                            .foregroundStyle(AppTheme.secondary)
                        }
                        .frame(height: 160)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Transaksjoner")
                        .appCardTitleStyle()
                    ForEach(viewModel.transactionsForCategory(categoryID: category.id, periodKey: periodKey, transactions: transactions), id: \.date) { transaction in
                        HStack {
                            Text(formatDate(transaction.date))
                                .appSecondaryStyle()
                            Spacer()
                            Text(formatNOK(BudgetService.budgetImpact(transaction)))
                                .foregroundStyle(BudgetService.budgetImpact(transaction) >= 0 ? AppTheme.textPrimary : AppTheme.positive)
                                .monospacedDigit()
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle(category.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rediger budsjett") {
                    showEditor = true
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            BudgetEditSheet(categoryName: category.name, initialValue: planned) { newValue in
                viewModel.upsertBudgetPlan(
                    context: modelContext,
                    periodKey: periodKey,
                    categoryID: category.id,
                    plannedAmount: newValue,
                    plans: plans
                )
            }
        }
    }
}
