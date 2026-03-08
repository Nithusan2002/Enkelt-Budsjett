import SwiftUI
import SwiftData

struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \BudgetMonth.startDate) private var months: [BudgetMonth]
    @Query private var groupPlans: [BudgetGroupPlan]
    @Query private var transactions: [Transaction]

    @StateObject private var viewModel = BudgetViewModel()
    @State private var showMonthPicker = false
    @State private var addTransactionInitialType: TransactionKind?
    private var isReadOnlyMode: Bool { PersistenceGate.isReadOnlyMode }

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
        viewModel.incomeRows(categories: categories, periodTransactions: monthTransactions)
    }
    private var savingsRows: [BudgetSavingsRow] {
        viewModel.savingsRows(categories: categories, periodTransactions: monthTransactions)
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
    private var groupsWithoutLimitWithSpendCount: Int {
        viewModel.groupsWithoutLimitWithSpendCount(groupRows: groupRows)
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
                    overBudgetCount: overBudgetCount,
                    groupsWithoutLimitWithSpendCount: groupsWithoutLimitWithSpendCount,
                    hasTransactions: !monthTransactions.isEmpty,
                    isOverBudgetFilterActive: viewModel.selectedFilter == .overLimit,
                    onToggleOverBudget: {
                        viewModel.selectedFilter = viewModel.selectedFilter == .overLimit ? .all : .overLimit
                    },
                    onSetLimits: {
                        if isReadOnlyMode {
                            viewModel.persistenceErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
                        } else {
                            viewModel.showGroupLimitsSheet = true
                        }
                    }
                )

                BudgetPrimaryActionCard(
                    hasPlannedBudget: hasPlannedBudget,
                    hasTransactions: !monthTransactions.isEmpty,
                    isReadOnlyMode: isReadOnlyMode,
                    onSetLimits: {
                        if isReadOnlyMode {
                            viewModel.persistenceErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
                        } else {
                            viewModel.showGroupLimitsSheet = true
                        }
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
                        Text("Faste poster, inntekter og sparing")
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
                    hasPlannedBudget: hasPlannedBudget,
                    hasTransactions: !monthTransactions.isEmpty,
                    onAddTransaction: {
                        addTransactionInitialType = .expense
                        viewModel.showAddTransaction = true
                    }
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
                .disabled(isReadOnlyMode)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if isReadOnlyMode {
                Text("Skrivende handlinger er låst fordi appen kjører uten varig lagring.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showMonthPicker) {
            BudgetMonthPickerSheet(
                selectedDate: viewModel.selectedMonthDate,
                onSelect: { date in
                    viewModel.selectedMonthDate = DateService.monthBounds(for: date).start
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
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
                groupRows: groupRows,
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
