import SwiftUI
import SwiftData
import UIKit

struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \BudgetMonth.startDate) private var months: [BudgetMonth]
    @Query private var groupPlans: [BudgetGroupPlan]
    @Query private var transactions: [Transaction]

    @StateObject private var viewModel = BudgetViewModel()
    @State private var showMonthPicker = false
    @State private var addTransactionInitialType: TransactionKind?

    private var periodKey: String { viewModel.periodKey() }
    private var monthTransactions: [Transaction] {
        viewModel.monthTransactions(periodKey: periodKey, transactions: transactions)
    }
    private var groupRows: [BudgetGroupRow] {
        viewModel.groupRows(
            periodKey: periodKey,
            categories: categories,
            groupPlans: groupPlans,
            periodTransactions: monthTransactions
        )
    }
    private var fixedByGroup: [String: Double] {
        viewModel.fixedSpentByGroup(
            categories: categories,
            periodTransactions: monthTransactions
        )
    }
    private var incomeRows: [BudgetIncomeRow] {
        let incomeByCategory = Dictionary(grouping: monthTransactions.filter { $0.kind == .income }) { $0.categoryID ?? "" }
            .mapValues { tx in tx.reduce(0) { $0 + abs($1.amount) } }
        return categories
            .filter { $0.type == .income && $0.isActive }
            .map { category in
                let amount = incomeByCategory[category.id] ?? 0
                return BudgetIncomeRow(id: category.id, title: category.name, amount: amount)
            }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
    }
    private var savingsRows: [BudgetSavingsRow] {
        let savingsCategoryIDs = Set(
            categories
                .filter { $0.type == .savings && $0.isActive }
                .map(\.id)
        )

        let grouped = Dictionary(grouping: monthTransactions) { tx in
            tx.categoryID ?? ""
        }

        return categories
            .filter { $0.type == .savings && $0.isActive }
            .map { category in
                let amount = (grouped[category.id] ?? [])
                    .filter { tx in
                        (tx.kind == .manualSaving || (tx.categoryID != nil && savingsCategoryIDs.contains(tx.categoryID!)))
                    }
                    .reduce(0) { $0 + abs($1.amount) }
                return BudgetSavingsRow(id: category.id, title: category.name, amount: amount)
            }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
    }
    private var summary: BudgetSummaryData {
        viewModel.summary(groupRows: groupRows, periodTransactions: monthTransactions)
    }
    private var hasPlannedBudget: Bool {
        summary.planned > 0
    }
    private var overBudgetCount: Int {
        groupRows.filter(\.isOverBudget).count
    }
    private var fixedTotalThisMonth: Double {
        FixedItemsService.fixedTotalForMonth(periodKey: periodKey, transactions: transactions)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                MonthHeaderView(
                    monthLabel: monthLabel(viewModel.selectedMonthDate),
                    onPrevious: { viewModel.changeMonth(by: -1) },
                    onNext: { viewModel.changeMonth(by: 1) },
                    onPickMonth: { showMonthPicker = true }
                )

                BudgetHeroCardView(
                    hasPlannedBudget: hasPlannedBudget,
                    remaining: summary.remaining,
                    trackedActual: summary.trackedActual,
                    expenseTotal: summary.expenseTotal,
                    planned: summary.planned,
                    monthDate: viewModel.selectedMonthDate,
                    overBudgetCount: overBudgetCount,
                    isOverBudgetFilterActive: viewModel.selectedFilter == .overLimit,
                    onToggleOverBudget: {
                        viewModel.selectedFilter = viewModel.selectedFilter == .overLimit ? .all : .overLimit
                    },
                    onAddExpense: {
                        addTransactionInitialType = .expense
                        viewModel.showAddTransaction = true
                    },
                    onAddIncome: {
                        addTransactionInitialType = .income
                        viewModel.showAddTransaction = true
                    }
                )

                NavigationLink {
                    BudgetDetailsView(
                        fixedTotalThisMonth: fixedTotalThisMonth,
                        incomeRows: incomeRows,
                        savingsRows: savingsRows
                    )
                } label: {
                    HStack {
                        Text("Se detaljer")
                            .appBodyStyle()
                        Spacer()
                        Text("Historikk og ekstra innsikt")
                            .appSecondaryStyle()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding()
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
                }
                .buttonStyle(.plain)

                GroupListView(
                    rows: groupRows,
                    fixedByGroup: fixedByGroup,
                    onSetLimits: { viewModel.showGroupLimitsSheet = true }
                )
            }
            .padding()
        }
        .refreshable {
            viewModel.ensureMonthExists(context: modelContext, months: months)
        }
        .background(AppTheme.background)
        .navigationTitle("Budsjett")
        .safeAreaInset(edge: .bottom) {
            if !viewModel.showAddTransaction {
                BudgetBottomAddTransactionButton {
                    addTransactionInitialType = .expense
                    viewModel.showAddTransaction = true
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showMonthPicker) {
            BudgetMonthPickerSheet(
                selectedDate: viewModel.selectedMonthDate,
                onSelect: { date in
                    viewModel.selectedMonthDate = DateService.monthBounds(for: date).start
                }
            )
        }
        .sheet(isPresented: $viewModel.showAddTransaction) {
            AddTransactionSheet(
                categories: categories.filter(\.isActive),
                initialType: addTransactionInitialType
            ) { date, amount, kind, categoryID, note in
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
        .sheet(isPresented: $viewModel.showGroupLimitsSheet) {
            SetGroupLimitsSheet(
                periodKey: periodKey,
                groupPlans: groupPlans,
                fixedByGroup: fixedByGroup,
                viewModel: viewModel
            )
        }
        .navigationDestination(for: BudgetGroup.self) { group in
            BudgetGroupDetailView(
                group: group,
                periodKey: periodKey,
                categories: categories,
                groupPlans: groupPlans,
                transactions: transactions,
                showAddTransaction: $viewModel.showAddTransaction,
                viewModel: viewModel
            )
        }
        .onAppear {
            viewModel.ensureMonthExists(context: modelContext, months: months)
        }
        .onChange(of: viewModel.selectedMonthDate) { _, _ in
            viewModel.ensureMonthExists(context: modelContext, months: months)
        }
        .alert(
            "Kunne ikke lagre",
            isPresented: Binding(
                get: { viewModel.persistenceErrorMessage != nil },
                set: { if !$0 { viewModel.clearPersistenceError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.clearPersistenceError()
            }
        } message: {
            Text(viewModel.persistenceErrorMessage ?? "")
        }
    }

    private func monthLabel(_ date: Date) -> String {
        let raw = formatMonthYearShort(date).replacingOccurrences(of: ".", with: "")
        guard let first = raw.first else { return raw }
        return String(first).uppercased() + String(raw.dropFirst())
    }
}

private struct BudgetBottomAddTransactionButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.title3.weight(.bold))
                Text("Legg til transaksjon")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(AppTheme.primary, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(AppTheme.primary.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Legg til transaksjon")
    }
}

private struct BudgetIncomeRow: Identifiable {
    let id: String
    let title: String
    let amount: Double
}

private struct BudgetSavingsRow: Identifiable {
    let id: String
    let title: String
    let amount: Double
}

private struct IncomeListView: View {
    let rows: [BudgetIncomeRow]

    private var total: Double {
        rows.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Inntekter")
                    .appCardTitleStyle()
                Spacer()
                Text(formatNOK(total))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.positive)
                    .monospacedDigit()
            }

            ForEach(rows) { row in
                HStack {
                    Text(row.title)
                        .appBodyStyle()
                    Spacer()
                    Text(formatNOK(row.amount))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.positive)
                        .monospacedDigit()
                }
                .padding(.vertical, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
    }
}

private struct SavingsListView: View {
    let rows: [BudgetSavingsRow]

    private var total: Double {
        rows.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sparing")
                    .appCardTitleStyle()
                Spacer()
                Text(formatNOK(total))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondary)
                    .monospacedDigit()
            }

            ForEach(rows) { row in
                HStack {
                    Text(row.title)
                        .appBodyStyle()
                    Spacer()
                    Text(formatNOK(row.amount))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
    }
}

private struct MonthHeaderView: View {
    let monthLabel: String
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onPickMonth: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            Spacer()

            Button(action: onPickMonth) {
                HStack(spacing: 6) {
                    Text(monthLabel)
                        .font(.headline.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Valgt måned")
            .accessibilityValue(monthLabel)

            Spacer()

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
    }
}

private struct BudgetHeroCardView: View {
    let hasPlannedBudget: Bool
    let remaining: Double
    let trackedActual: Double
    let expenseTotal: Double
    let planned: Double
    let monthDate: Date
    let overBudgetCount: Int
    let isOverBudgetFilterActive: Bool
    let onToggleOverBudget: () -> Void
    let onAddExpense: () -> Void
    let onAddIncome: () -> Void

    private var spentSoFar: Double {
        hasPlannedBudget ? trackedActual : expenseTotal
    }

    private var usedPercent: Double {
        guard planned > 0 else { return 0 }
        return min(max(trackedActual / planned, 0), 1)
    }

    private var projectedMonthEnd: Double {
        let calendar = Calendar.current
        let now = Date()
        guard calendar.isDate(now, equalTo: monthDate, toGranularity: .month) else {
            return spentSoFar
        }
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let dayOfMonth = max(calendar.component(.day, from: now), 1)
        let pace = spentSoFar / Double(dayOfMonth)
        return max(0, pace * Double(daysInMonth))
    }

    private var statusText: String {
        guard hasPlannedBudget else {
            return "Ingen grense satt ennå. Du kan fortsatt spore forbruket."
        }
        if remaining >= 0 {
            return "Du ligger innenfor med \(formatNOK(remaining)) igjen."
        }
        return "Du ligger \(formatNOK(abs(remaining))) over plan."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasPlannedBudget {
                Text("Igjen denne måneden")
                    .appSecondaryStyle()
                Text(formatNOK(remaining))
                    .appBigNumberStyle()
                    .foregroundStyle(remaining < 0 ? AppTheme.negative : AppTheme.textPrimary)
                Text(statusText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(remaining < 0 ? AppTheme.warning : AppTheme.positive)

                let progress = clampedProgress(value: usedPercent, total: 1)
                ProgressView(value: progress.value, total: progress.total)
                    .tint(remaining < 0 ? AppTheme.warning : AppTheme.secondary)
            } else {
                Text("Brukt denne måneden")
                    .appSecondaryStyle()
                Text(formatNOK(expenseTotal))
                    .appBigNumberStyle()
                    .foregroundStyle(AppTheme.textPrimary)
                Text(statusText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            HStack(spacing: 10) {
                BudgetQuickMetricView(
                    title: "Brukt hittil",
                    value: formatNOK(spentSoFar)
                )
                BudgetQuickMetricView(
                    title: "Forventet ved månedsslutt",
                    value: formatNOK(projectedMonthEnd)
                )
            }

            HStack(spacing: 8) {
                Button {
                    onAddExpense()
                } label: {
                    Label("Legg til utgift", systemImage: "minus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .appCTAStyle()

                Button("Legg til inntekt") {
                    onAddIncome()
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.primary)
            }

            if overBudgetCount > 0 {
                Button {
                    onToggleOverBudget()
                } label: {
                    Text(
                        isOverBudgetFilterActive
                            ? "Vis alle kategorier"
                            : "Over budsjett i \(overBudgetCount) kategorier"
                    )
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            (isOverBudgetFilterActive ? AppTheme.secondary : AppTheme.warning).opacity(0.12),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasPlannedBudget ? "Igjen å bruke" : "Forbruk hittil")
        .accessibilityValue(hasPlannedBudget ? formatNOK(remaining) : formatNOK(expenseTotal))
    }

}

private struct BudgetQuickMetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.divider, lineWidth: 1))
    }
}

private struct GroupListView: View {
    let rows: [BudgetGroupRow]
    let fixedByGroup: [String: Double]
    let onSetLimits: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kategorier")
                    .appCardTitleStyle()
                Spacer()
                Button("Sett grenser") {
                    onSetLimits()
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.primary)
            }

            if rows.isEmpty {
                Text("Legg til en transaksjon for å starte sporing.")
                    .appSecondaryStyle()
            }

            ForEach(rows) { row in
                NavigationLink(value: row.group) {
                    GroupRowView(
                        row: row,
                        fixedSpent: fixedByGroup[row.group.rawValue] ?? 0
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
    }
}

private struct BudgetDetailsView: View {
    let fixedTotalThisMonth: Double
    let incomeRows: [BudgetIncomeRow]
    let savingsRows: [BudgetSavingsRow]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                NavigationLink {
                    FixedItemsView()
                } label: {
                    HStack {
                        Text("Faste poster denne måneden")
                            .appBodyStyle()
                        Spacer()
                        Text(formatNOK(fixedTotalThisMonth))
                            .font(.headline.weight(.semibold))
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding()
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
                }
                .buttonStyle(.plain)

                if !incomeRows.isEmpty {
                    IncomeListView(rows: incomeRows)
                }

                if !savingsRows.isEmpty {
                    SavingsListView(rows: savingsRows)
                }

                if incomeRows.isEmpty && savingsRows.isEmpty && fixedTotalThisMonth <= 0 {
                    Text("Ingen ekstra detaljer ennå.")
                        .appSecondaryStyle()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
                }
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle("Detaljer")
    }
}

private struct BudgetMonthPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var selectedDate: Date
    let onSelect: (Date) -> Void

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Måned",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
            }
            .navigationTitle("Velg måned")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") {
                        onSelect(selectedDate)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AddTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    let initialType: TransactionKind?
    let onSave: (Date, Double, TransactionKind, String?, String) -> Void

    @State private var date: Date = .now
    @State private var amountText: String = ""
    @State private var selectedType: TransactionKind?
    @State private var selectedCategoryID: String?
    @State private var note: String = ""
    @State private var attemptedSave = false
    @State private var showSavedBanner = false
    @State private var showPostSaveActions = false
    @FocusState private var amountFocused: Bool

    @AppStorage("budget.last_category.expense") private var lastExpenseCategoryID: String = ""
    @AppStorage("budget.last_category.income") private var lastIncomeCategoryID: String = ""

    private var kind: TransactionKind {
        selectedType ?? .expense
    }

    private var availableCategories: [Category] {
        guard let selectedType else { return [] }
        switch selectedType {
        case .expense:
            return categories
                .filter { ($0.type == .expense || $0.type == .savings) && $0.isActive }
                .sorted { $0.sortOrder < $1.sortOrder }
        case .income:
            return categories.filter { $0.type == .income }.sorted { $0.sortOrder < $1.sortOrder }
        default:
            return []
        }
    }

    private var isValid: Bool {
        selectedType != nil && parsedAmount > 0 && selectedCategoryID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    HStack(spacing: 10) {
                        typeCard(title: "Inntekt", systemImage: "arrow.down.circle.fill", type: .income)
                        typeCard(title: "Utgift", systemImage: "arrow.up.circle.fill", type: .expense)
                    }
                }

                if selectedType != nil {
                    Section(selectedType == .expense ? "Ny utgift" : "Ny inntekt") {
                        if availableCategories.isEmpty {
                            Text("Ingen kategorier for valgt type.")
                                .appSecondaryStyle()
                        } else {
                            Picker("Kategori", selection: $selectedCategoryID) {
                                Text("Velg kategori").tag(Optional<String>.none)
                                ForEach(availableCategories) { category in
                                    Label(category.name, systemImage: symbolForCategory(category.name))
                                        .tag(Optional(category.id))
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Beløp")
                                .appSecondaryStyle()
                            HStack(spacing: 8) {
                                Text("kr")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                                TextField("f.eks. 450", text: $amountText)
                                    .keyboardType(.decimalPad)
                                    .font(.title2.weight(.semibold))
                                    .monospacedDigit()
                                    .focused($amountFocused)
                            }
                            Text("Grovt tall holder.")
                                .appSecondaryStyle()
                        }

                        if attemptedSave && selectedCategoryID == nil {
                            Text("Velg kategori for å lagre.")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.negative)
                        }
                    }
                }

                Section("Notat") {
                    TextField("Hva var dette?", text: $note)
                        .textFieldStyle(.appInput)
                }
            }
            .navigationTitle("Legg til transaksjon")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        attemptedSave = true
                        guard isValid else { return }
                        onSave(date, parsedAmount, kind, selectedCategoryID, note)
                        persistLastCategoryIfNeeded()
                        amountFocused = false
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSavedBanner = true
                            showPostSaveActions = true
                        }
                        resetForNextEntry()
                    }
                    .disabled(!isValid)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if showSavedBanner || showPostSaveActions {
                    VStack(spacing: 8) {
                        if showSavedBanner {
                            Text("Lagret ✓")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.positive)
                                .transition(.opacity)
                        }
                        if showPostSaveActions {
                            HStack(spacing: 10) {
                                Button("Legg til en til") {
                                    amountFocused = true
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showSavedBanner = false
                                        showPostSaveActions = false
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .frame(maxWidth: .infinity)

                                Button("Ferdig") {
                                    dismiss()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.primary)
                                .controlSize(.large)
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(AppTheme.divider)
                            .frame(height: 1)
                    }
                }
            }
            .onAppear {
                if selectedType == nil, let initialType {
                    selectedType = initialType
                }
                preselectCategoryForCurrentType()
            }
            .onChange(of: amountText) { _, newValue in
                let formatted = formatAmountInputLive(newValue)
                if formatted != newValue {
                    amountText = formatted
                }
            }
        }
    }

    private var parsedAmount: Double {
        parseInputAmount(amountText) ?? 0
    }

    private func preselectCategoryForCurrentType() {
        if availableCategories.isEmpty {
            selectedCategoryID = nil
            return
        }
        switch kind {
        case .expense:
            if availableCategories.contains(where: { $0.id == lastExpenseCategoryID }) {
                selectedCategoryID = lastExpenseCategoryID
            } else if let first = availableCategories.first {
                selectedCategoryID = first.id
            }
        case .income:
            if availableCategories.contains(where: { $0.id == lastIncomeCategoryID }) {
                selectedCategoryID = lastIncomeCategoryID
            } else if let firstIncomeCategory = availableCategories.first {
                selectedCategoryID = firstIncomeCategory.id
            }
        case .transfer, .manualSaving:
            break
        case .refund:
            break
        }
    }

    private func clearSelectionIfInvalidForType() {
        guard let selectedCategoryID else { return }
        if !availableCategories.contains(where: { $0.id == selectedCategoryID }) {
            self.selectedCategoryID = nil
        }
    }

    private func persistLastCategoryIfNeeded() {
        guard let selectedCategoryID else { return }
        if kind == .expense {
            lastExpenseCategoryID = selectedCategoryID
        } else if kind == .income {
            lastIncomeCategoryID = selectedCategoryID
        }
    }

    private func resetForNextEntry() {
        amountText = ""
        note = ""
        date = .now
        selectedCategoryID = nil
        selectedType = nil
        attemptedSave = false
    }

    private func typeCard(title: String, systemImage: String, type: TransactionKind) -> some View {
        let isSelected = selectedType == type
        return Button {
            selectedType = type
            attemptedSave = false
            clearSelectionIfInvalidForType()
            preselectCategoryForCurrentType()
            amountFocused = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(isSelected ? AppTheme.primary : AppTheme.textPrimary)
            .background(
                isSelected ? AppTheme.primary.opacity(0.14) : AppTheme.surface,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? AppTheme.primary : AppTheme.divider, lineWidth: isSelected ? 1.4 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func symbolForCategory(_ name: String) -> String {
        let key = name
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        switch key {
        case "bilvask": return "car.fill"
        case "spotify", "apple music": return "music.note"
        case "icloud", "netflix", "prime video", "disney+": return "arrow.triangle.2.circlepath"
        case "playstation plus", "xbox live": return "gamecontroller.fill"
        case "legebesok": return "heart"
        case "medisiner": return "pills.fill"
        case "frisor": return "scissors"
        case "kommunale avgifter": return "building.columns.fill"
        case "vann og avlop": return "water.waves"
        case "feiing": return "house.fill"
        case "reise": return "airplane"
        case "klaer": return "tshirt.fill"
        case "mobler": return "sofa.fill"
        case "blomster": return "leaf"
        case "barnehage": return "figure.2.and.child.holdinghands"
        case "hyttelan": return "mountain.2.fill"
        case "nedbetaling av lan": return "banknote.fill"
        case "kjaeledyr": return "pawprint.fill"
        case "matkasse": return "takeoutbag.and.cup.and.straw.fill"
        case "kollektivtransport": return "tram.fill"
        case "trening": return "figure.strengthtraining.traditional"
        case "investering i aksjer": return "chart.bar.fill"
        case "investering i fond": return "chart.pie.fill"
        case "forsikring", "reiseforsikring", "innboforsikring": return "umbrella.fill"
        case "bilforsikring", "bompenger", "drivstoff", "lading av elbil": return "car.fill"
        case "parkering": return "parkingsign.circle"
        case "lunsj pa jobb": return "fork.knife"
        case "uteliv": return "party.popper.fill"
        case "internett": return "globe"
        case "mobilabonnement": return "phone"

        case "lonn": return "party.popper.fill"
        case "lanekassen (stipend/lan)": return "graduationcap.fill"
        case "ekstrajobb / sideinntekt": return "briefcase.fill"
        case "salg (finn.no / brukt)": return "hand.raised.fill"
        case "gaver / penger mottatt": return "gift.fill"

        case "bolig": return "house.fill"
        case "mat": return "fork.knife"
        case "transport": return "tram.fill"
        case "fritid": return "sparkles"
        case "sparingskonto": return "banknote.fill"
        default:
            break
        }

        if key.contains("mat") || key.contains("daglig") { return "fork.knife" }
        if key.contains("transport") || key.contains("buss") || key.contains("tog") { return "tram.fill" }
        if key.contains("bolig") || key.contains("husleie") { return "house.fill" }
        if key.contains("spar") { return "banknote.fill" }
        if key.contains("inntekt") || key.contains("lonn") { return "arrow.down.circle.fill" }
        return "tag.fill"
    }
}

private func parseInputAmount(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let withoutWhitespace = trimmed.components(separatedBy: .whitespacesAndNewlines).joined()
    let normalized = withoutWhitespace
        .replacingOccurrences(of: "\u{00A0}", with: "")
        .replacingOccurrences(of: "\u{202F}", with: "")
        .replacingOccurrences(of: ",", with: ".")
    return Double(normalized)
}

private func formatInputAmount(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "nb_NO")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: value)) ?? ""
}

private func formatAmountInputLive(_ rawText: String) -> String {
    let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    let filtered = trimmed.filter { $0.isNumber || $0 == "," || $0 == "." }
    let separatorIndex = filtered.firstIndex(where: { $0 == "," || $0 == "." })

    let integerPartRaw: String
    let fractionRaw: String
    let hasSeparator: Bool
    let endsWithSeparator: Bool

    if let separatorIndex {
        integerPartRaw = String(filtered[..<separatorIndex])
        let after = filtered.index(after: separatorIndex)
        if after < filtered.endIndex {
            fractionRaw = String(filtered[after...]).filter(\.isNumber)
        } else {
            fractionRaw = ""
        }
        hasSeparator = true
        endsWithSeparator = separatorIndex == filtered.index(before: filtered.endIndex)
    } else {
        integerPartRaw = filtered.filter(\.isNumber)
        fractionRaw = ""
        hasSeparator = false
        endsWithSeparator = false
    }

    let integerDigits = integerPartRaw.filter(\.isNumber)
    let integerValue = Double(integerDigits) ?? 0
    let formattedInteger = formatInputAmount(integerValue)

    if hasSeparator {
        let fraction = String(fractionRaw.prefix(2))
        if endsWithSeparator || !fraction.isEmpty {
            return "\(formattedInteger),\(fraction)"
        }
    }
    return formattedInteger
}

private struct GroupRowView: View {
    let row: BudgetGroupRow
    let fixedSpent: Double

    private var planned: Double? {
        guard let value = row.planned, value > 0 else { return nil }
        return value
    }

    private var progressValue: Double {
        guard let planned else { return 0 }
        return min(max(row.spent, 0), max(planned, 1))
    }

    private var progressTotal: Double {
        clampedProgress(value: row.spent, total: planned ?? 1).total
    }

    private var variableSpent: Double {
        max(row.spent - fixedSpent, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if let planned {
                    Text("\(formatNOK(row.spent)) / \(formatNOK(planned))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textPrimary)
                } else {
                    Text("\(formatNOK(row.spent)) brukt hittil")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }

            if planned != nil {
                let progress = clampedProgress(value: progressValue, total: progressTotal)
                ProgressView(value: progress.value, total: progress.total)
                    .tint(row.isOverBudget ? AppTheme.warning : AppTheme.secondary)
            }

            if fixedSpent > 0 {
                Text("Fast: \(formatNOK(fixedSpent)) • Variabel: \(formatNOK(variableSpent))")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .monospacedDigit()
            }

            HStack {
                if row.isOverBudget {
                    statusPill(text: "Over", color: AppTheme.warning)
                } else if row.isNearLimit {
                    statusPill(text: "Nær grensen", color: AppTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if let planned {
            let status: String
            if row.isOverBudget {
                status = "over budsjett"
            } else if row.isNearLimit {
                status = "nær grensen"
            } else {
                status = "innenfor"
            }
            return "Brukt \(formatNOK(row.spent)) av \(formatNOK(planned)), \(status)"
        }
        return "Brukt \(formatNOK(row.spent)), ingen grense"
    }

    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct SetGroupLimitsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    let periodKey: String
    let groupPlans: [BudgetGroupPlan]
    let fixedByGroup: [String: Double]
    @ObservedObject var viewModel: BudgetViewModel

    @State private var values: [BudgetGroup: String] = Dictionary(
        uniqueKeysWithValues: BudgetGroup.allCases.map { ($0, "") }
    )

    private var hasAnyInput: Bool {
        BudgetGroup.allCases.contains { group in
            let text = values[group, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return false }
            return (parseInputAmount(text) ?? 0) > 0
        }
    }

    private var hasExistingForMonth: Bool {
        groupPlans.contains { $0.monthPeriodKey == periodKey }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Du trenger bare å sette de du vil. Tomt = kun sporing.")
                        .appSecondaryStyle()
                }

                Section("Grupper") {
                    ForEach(BudgetGroup.allCases) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(group.title)
                                Spacer()
                                HStack(spacing: 6) {
                                    Text("kr")
                                        .foregroundStyle(AppTheme.textSecondary)
                                    TextField("Tomt", text: binding(for: group))
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .monospacedDigit()
                                        .frame(maxWidth: 140)
                                }
                            }

                            let fixedTotal = fixedByGroup[group.rawValue] ?? 0
                            if fixedTotal > 0 {
                                Text("Faste poster: \(formatNOK(fixedTotal))")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .monospacedDigit()
                            }

                            if let entered = parsedValue(for: group),
                               let fixedTotal = fixedByGroup[group.rawValue],
                               fixedTotal > 0,
                               entered > 0,
                               entered < fixedTotal {
                                Text("Lavere enn faste poster i gruppen.")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.warning)
                            }
                        }
                    }
                }

                Section {
                    Button("Kopier forrige måned") {
                        let previous = viewModel.copyPreviousMonthGroupPlans(periodKey: periodKey, groupPlans: groupPlans)
                        for group in BudgetGroup.allCases {
                            if let value = previous[group] ?? nil, value > 0 {
                                values[group] = formatInputAmount(value)
                            } else {
                                values[group] = ""
                            }
                        }
                    }

                    Button("Beregn med SIFO (OsloMet)") {
                        guard let url = URL(string: "https://www.oslomet.no/om/sifo/referansebudsjettet") else { return }
                        openURL(url)
                    }
                }
            }
            .navigationTitle("Grenser")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        var parsed: [BudgetGroup: Double?] = [:]
                        for group in BudgetGroup.allCases {
                            let raw = values[group, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                            if raw.isEmpty {
                                parsed[group] = nil
                            } else {
                                let value = parseInputAmount(raw) ?? 0
                                parsed[group] = value > 0 ? value : nil
                            }
                        }
                        viewModel.upsertGroupPlans(
                            context: modelContext,
                            periodKey: periodKey,
                            values: parsed,
                            existingPlans: groupPlans
                        )
                        dismiss()
                    }
                    .disabled(!hasAnyInput && !hasExistingForMonth)
                }
            }
            .onAppear {
                let current = groupPlans.filter { $0.monthPeriodKey == periodKey }
                for group in BudgetGroup.allCases {
                    if let existing = current.first(where: { $0.groupKey == group.rawValue }), existing.plannedAmount > 0 {
                        values[group] = formatInputAmount(existing.plannedAmount)
                    } else {
                        values[group] = ""
                    }
                }
            }
        }
    }

    private func binding(for group: BudgetGroup) -> Binding<String> {
        Binding(
            get: { values[group, default: ""] },
            set: { newValue in
                values[group] = formatAmountInputLive(newValue)
            }
        )
    }

    private func parsedValue(for group: BudgetGroup) -> Double? {
        let raw = values[group, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return parseInputAmount(raw)
    }

}

private struct BudgetGroupDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let group: BudgetGroup
    let periodKey: String
    let categories: [Category]
    let groupPlans: [BudgetGroupPlan]
    let transactions: [Transaction]
    @Binding var showAddTransaction: Bool
    @ObservedObject var viewModel: BudgetViewModel

    private var planned: Double? {
        groupPlans.first { $0.monthPeriodKey == periodKey && $0.groupKey == group.rawValue }?.plannedAmount
    }

    private var spent: Double {
        rows.reduce(0) { $0 + BudgetService.budgetImpact($1) }
    }

    private var groupCategories: [Category] {
        viewModel.categoriesForGroup(group, categories: categories)
    }

    private var rows: [Transaction] {
        viewModel.transactionsForGroup(group, periodKey: periodKey, categories: categories, transactions: transactions)
    }

    private var spentByCategory: [(category: Category, spent: Double)] {
        groupCategories
            .map { category in
                let spent = rows
                    .filter { $0.categoryID == category.id }
                    .reduce(0) { $0 + BudgetService.budgetImpact($1) }
                return (category, max(spent, 0))
            }
            .sorted { lhs, rhs in
                if lhs.spent != rhs.spent { return lhs.spent > rhs.spent }
                return lhs.category.name.localizedCaseInsensitiveCompare(rhs.category.name) == .orderedAscending
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title)
                        .appCardTitleStyle()
                    if let planned, planned > 0 {
                        Text("\(formatNOK(spent)) / \(formatNOK(planned))")
                            .appBodyStyle()
                        Text("Avvik: \(formatNOK(spent - planned))")
                            .appSecondaryStyle()
                    } else {
                        Text("\(formatNOK(spent)) brukt hittil")
                            .appBodyStyle()
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Brukt per kategori")
                        .appCardTitleStyle()
                    if spentByCategory.isEmpty {
                        Text("Ingen kategorier i denne gruppen.")
                            .appSecondaryStyle()
                    } else {
                        ForEach(spentByCategory, id: \.category.id) { row in
                            HStack {
                                Text(row.category.name)
                                    .appBodyStyle()
                                Spacer()
                                Text(formatNOK(row.spent))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(AppTheme.textPrimary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Transaksjoner")
                        .appCardTitleStyle()
                    if rows.isEmpty {
                        Text("Ingen transaksjoner i \(group.title.lowercased()) ennå.")
                            .appSecondaryStyle()
                    }
                    ForEach(rows, id: \.date) { transaction in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatDate(transaction.date))
                                    .appSecondaryStyle()
                                if transaction.recurringKey != nil {
                                    Text("Fast post")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.primary.opacity(0.12), in: Capsule())
                                }
                            }
                            Spacer()
                            Text(formatNOK(BudgetService.budgetImpact(transaction)))
                                .foregroundStyle(BudgetService.budgetImpact(transaction) >= 0 ? AppTheme.textPrimary : AppTheme.positive)
                                .monospacedDigit()
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.deleteTransaction(context: modelContext, transaction: transaction)
                            } label: {
                                Label("Slett", systemImage: "trash")
                            }
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
        .navigationTitle(group.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Legg til") {
                    showAddTransaction = true
                }
            }
        }
    }
}
