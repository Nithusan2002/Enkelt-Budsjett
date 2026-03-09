import Foundation
import Combine

struct GoalSummary {
    let targetAmount: Double
    let targetDate: Date
    let createdAt: Date
    let progress: Double
    let monthsRemaining: Int
    let perMonth: Double
}

enum GoalPlanState {
    case ahead
    case onTrack
    case behind
    case complete
    case expired
}

struct OverviewBudgetStatus {
    let hasPlan: Bool
    let planned: Double
    let remaining: Double
    let net: Double
    let income: Double
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

    func registeredSavingYTD(transactions: [Transaction], categories: [Category]) -> Double {
        SavingsService.savedYearToDate(
            definition: .savingsCategoryOnly,
            transactions: transactions,
            categories: categories
        )
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
        let createdAt = activeGoal?.createdAt ?? .now
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
            createdAt: createdAt,
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
            planned: planned,
            remaining: remaining,
            net: net,
            income: income,
            spent: actual
        )
    }

    func heroTitle() -> String {
        "Tilgjengelig denne måneden"
    }

    func heroAmountText(status: OverviewBudgetStatus) -> String {
        let focusAmount = status.hasPlan ? status.remaining : status.net
        let rounded = roundedKr(abs(focusAmount))
        if focusAmount < 0 {
            return "\(rounded) over"
        }
        return rounded
    }

    func heroStatusLine(
        status: OverviewBudgetStatus,
        hasTransactions: Bool,
        areAmountsHidden: Bool = false
    ) -> String {
        if status.hasPlan && status.remaining < 0 {
            if areAmountsHidden {
                return "Over budsjett"
            }
            return "Over budsjett med \(roundedKr(abs(status.remaining)))"
        }
        if status.hasPlan {
            return "Innenfor budsjettet så langt."
        }
        if !hasTransactions {
            return "Basert på det du har lagt inn så langt."
        }
        if status.income > 0 && status.spent <= 0 {
            return "Legg til flere transaksjoner for en mer presis oversikt."
        }
        if status.net >= 0 {
            return "Basert på det du har lagt inn så langt."
        }
        return "Registrer flere transaksjoner for en mer presis oversikt."
    }

    func heroMetricValue(amount: Double) -> String {
        return roundedKr(amount)
    }

    func heroPrimaryCTATitle() -> String {
        "Legg til transaksjon"
    }

    func shouldShowMonthlyProgress(status: OverviewBudgetStatus) -> Bool {
        status.hasPlan && status.planned > 0
    }

    func monthlyProgress(status: OverviewBudgetStatus) -> (value: Double, total: Double)? {
        guard shouldShowMonthlyProgress(status: status) else { return nil }
        return clampedProgress(value: status.spent, total: status.planned)
    }

    func registeredSavingsHeadline() -> String {
        "Satt til side"
    }

    func registeredSavingsSupportText() -> String {
        "Penger du har registrert til sparing."
    }

    func goalEmptySupportText() -> String {
        "Et enkelt mål gjør fremgangen lettere å følge."
    }

    func goalProgressTitle() -> String {
        "På vei mot målet ditt"
    }

    func goalPercentText(summary: GoalSummary) -> String {
        "\(Int((summary.progress * 100).rounded())) %"
    }

    func goalAmountsText(currentWealth: Double, summary: GoalSummary, areAmountsHidden: Bool) -> String {
        if areAmountsHidden {
            return "•••• kr / •••• kr"
        }
        return "\(roundedKr(currentWealth)) / \(roundedKr(summary.targetAmount))"
    }

    func goalMonthlyNeedText(summary: GoalSummary, areAmountsHidden: Bool) -> String {
        if areAmountsHidden {
            return "•••• kr / måned"
        }
        return "\(roundedKr(summary.perMonth)) / måned"
    }

    func goalContextText(summary: GoalSummary, areAmountsHidden: Bool) -> String {
        let targetText = areAmountsHidden ? "•••• kr" : roundedKr(summary.targetAmount)
        return "Mål: \(targetText) innen \(formatMonthYearShort(summary.targetDate))"
    }

    func goalPlanState(summary: GoalSummary, now: Date = .now) -> GoalPlanState {
        if summary.progress >= 1 {
            return .complete
        }
        if summary.monthsRemaining <= 0 {
            return .expired
        }

        let totalDuration = max(summary.targetDate.timeIntervalSince(summary.createdAt), 1)
        let elapsed = min(max(now.timeIntervalSince(summary.createdAt), 0), totalDuration)
        let expectedProgress = elapsed / totalDuration
        let delta = summary.progress - expectedProgress

        if delta > 0.07 {
            return .ahead
        }
        if delta < -0.07 {
            return .behind
        }
        return .onTrack
    }

    func goalPlanStatusText(summary: GoalSummary) -> String {
        switch goalPlanState(summary: summary) {
        case .ahead:
            return "Du ligger foran planen"
        case .onTrack:
            return "Du ligger i rute"
        case .behind:
            return "Du ligger litt bak planen"
        case .complete:
            return "Du er i mål"
        case .expired:
            return "Målfristen er passert"
        }
    }

    func investmentsEmptyTitle() -> String {
        "Ingen registreringer ennå"
    }

    func investmentsEmptySupportText() -> String {
        "Legg inn verdien når du vil følge utviklingen over tid."
    }

    private func roundedKr(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        let number = NSNumber(value: value.rounded())
        let formatted = formatter.string(from: number) ?? String(Int(value.rounded()))
        return "\(formatted) kr"
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
