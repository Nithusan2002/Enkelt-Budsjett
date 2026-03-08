import Foundation
import Combine

struct GoalSummary {
    let targetAmount: Double
    let targetDate: Date
    let progress: Double
    let monthsRemaining: Int
    let perMonth: Double
}

struct OverviewBudgetStatus {
    let hasPlan: Bool
    let remaining: Double
    let net: Double
    let spent: Double
}

@MainActor
final class OverviewViewModel: ObservableObject {
    @Published var showGoalEditor = false

    func onAppear(preference: UserPreference?) {}

    func overviewTitle(firstName: String?) -> String {
        "Oversikt"
    }

    func activeGoal(from goals: [Goal]) -> Goal? {
        goals.first(where: \.isActive)
    }

    func latestSnapshot(from snapshots: [InvestmentSnapshot]) -> InvestmentSnapshot? {
        InvestmentService.latestSnapshot(snapshots)
    }

    func currentWealth(activeGoal: Goal?, latestSnapshot: InvestmentSnapshot?, accounts: [Account]) -> Double {
        GoalService.currentWealth(
            latestInvestmentTotal: latestSnapshot?.totalValue ?? 0,
            accounts: accounts,
            includeAccounts: activeGoal?.includeAccounts ?? true
        )
    }

    func savedYTD(definition: SavingsDefinition, transactions: [Transaction], categories: [Category]) -> Double {
        SavingsService.savedYearToDate(definition: definition, transactions: transactions, categories: categories)
    }

    func shouldShowEmptyState(
        transactions: [Transaction],
        snapshots: [InvestmentSnapshot],
        plans: [BudgetPlan],
        accounts: [Account]
    ) -> Bool {
        transactions.isEmpty && snapshots.isEmpty && plans.isEmpty && accounts.isEmpty
    }

    func goalSummary(activeGoal: Goal?, currentWealth: Double) -> GoalSummary {
        let targetAmount = activeGoal?.targetAmount ?? 0
        let targetDate = activeGoal?.targetDate ?? .now
        let progress = targetAmount > 0 ? min(1, currentWealth / targetAmount) : 0
        let monthsRemaining = DateService.monthsRemaining(from: .now, to: targetDate)
        let perMonth = GoalService.requiredMonthlySaving(
            nowWealth: currentWealth,
            targetAmount: targetAmount,
            targetDate: targetDate
        )
        return GoalSummary(
            targetAmount: targetAmount,
            targetDate: targetDate,
            progress: progress,
            monthsRemaining: monthsRemaining,
            perMonth: perMonth
        )
    }

    func budgetStatus(
        plans: [BudgetPlan],
        transactions: [Transaction],
        now: Date = .now
    ) -> OverviewBudgetStatus {
        let monthKey = DateService.periodKey(from: now)
        let hasPlan = plans.contains { $0.monthPeriodKey == monthKey && $0.plannedAmount > 0 }
        let planned = plans
            .filter { $0.monthPeriodKey == monthKey }
            .reduce(0) { $0 + $1.plannedAmount }
        let actual = BudgetService.actualExpenseTotal(for: monthKey, transactions: transactions)
        let income = BudgetService.actualIncomeTotal(for: monthKey, transactions: transactions)
        let net = income - actual
        let remaining = planned - actual
        return OverviewBudgetStatus(
            hasPlan: hasPlan,
            remaining: remaining,
            net: net,
            spent: actual
        )
    }

    func scopeText(activeGoal: Goal?) -> String {
        (activeGoal?.includeAccounts ?? true)
            ? "Formue = investeringer + konti markert for formue. Gjeld er ikke med i v1.0."
            : "Formue = kun investeringer. Gjeld er ikke med i v1.0."
    }

    func positiveStatusLine(savedAmount: Double, period: String, tone: AppToneStyle) -> String {
        switch tone {
        case .calm:
            return "Du har spart \(formatNOK(savedAmount)) i \(period)."
        case .nudges:
            return "Bra flyt: \(formatNOK(savedAmount)) i \(period)."
        case .warm:
            let lines = [
                "Du har spart {x} i {p}.",
                "Sterk start: {x} så langt i {p}.",
                "Fin flyt nå: {x} spart i {p}.",
                "Du ligger på pluss med {x} i {p}.",
                    "Bra jobbet, {x} er på plass i {p}.",
                "Små steg teller: {x} i {p}.",
                "Du har allerede nådd {x} i {p}.",
                "Stabil progresjon: {x} i {p}.",
                "Økonomien din vokser: {x} i {p}.",
                "Dette ser lovende ut: {x} i {p}.",
                "Du holder rytmen: {x} i {p}.",
                "{x} spart i {p} - fin utvikling."
            ]
            let idx = Calendar.current.component(.month, from: .now) % lines.count
            return lines[idx]
                .replacingOccurrences(of: "{x}", with: formatNOK(savedAmount))
                .replacingOccurrences(of: "{p}", with: period)
        }
    }
}
