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

enum OverviewToneRole {
    case positive
    case warning
    case neutral
}

struct OverviewBudgetStatus {
    let hasPlan: Bool
    let planned: Double
    let remaining: Double
    let net: Double
    let income: Double
    let spent: Double
}

struct AIInsightCategorySummary: Codable, Equatable {
    let title: String
    let amount: Double
}

struct AIInsightGoalSummary: Codable, Equatable {
    let progress: Double
    let monthlyNeed: Double
}

struct AIInsightRequestSummary: Codable, Equatable {
    let income: Double
    let spent: Double
    let remaining: Double
    let fixedItemsTotal: Double
    let topCategories: [AIInsightCategorySummary]
    let goal: AIInsightGoalSummary?
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

    func savedYTD(transactions: [Transaction], categories: [Category]) -> Double {
        SavingsService.savedYearToDate(
            definition: .incomeMinusExpense,
            transactions: transactions,
            categories: categories
        )
    }

    func shouldShowEmptyState(
        transactions: [Transaction],
        snapshots: [InvestmentSnapshot],
        groupPlans: [BudgetGroupPlan],
        accounts: [Account],
        activeGoal: Goal?
    ) -> Bool {
        transactions.isEmpty && snapshots.isEmpty && groupPlans.isEmpty && accounts.isEmpty && activeGoal == nil
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
        groupPlans: [BudgetGroupPlan],
        transactions: [Transaction],
        now: Date = .now
    ) -> OverviewBudgetStatus {
        let monthKey = DateService.periodKey(from: now)
        let hasPlan = groupPlans.contains { $0.monthPeriodKey == monthKey && $0.plannedAmount > 0 }
        let planned = BudgetService.plannedGroupTotal(for: monthKey, groupPlans: groupPlans)
        let actual = transactions
            .filter { DateService.periodKey(from: $0.date) == monthKey }
            .reduce(0) { $0 + BudgetService.trackedBudgetImpact($1) }
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

    func aiInsightSummary(
        status: OverviewBudgetStatus,
        transactions: [Transaction],
        categories: [Category],
        goalSummary: GoalSummary?,
        fixedItemsTotal: Double,
        now: Date = .now
    ) -> AIInsightRequestSummary {
        let monthKey = DateService.periodKey(from: now)
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        let topCategories = Dictionary(grouping: transactions.filter {
            DateService.periodKey(from: $0.date) == monthKey && BudgetService.trackedBudgetImpact($0) > 0
        }) { transaction in
            guard let categoryID = transaction.categoryID,
                  let category = categoriesByID[categoryID] else {
                return "Annet"
            }
            return category.name
        }
        .map { title, rows in
            AIInsightCategorySummary(
                title: title,
                amount: rows.reduce(0) { $0 + BudgetService.trackedBudgetImpact($1) }
            )
        }
        .sorted { lhs, rhs in
            if lhs.amount == rhs.amount {
                return lhs.title < rhs.title
            }
            return lhs.amount > rhs.amount
        }
        .prefix(3)

        return AIInsightRequestSummary(
            income: status.income,
            spent: status.spent,
            remaining: status.hasPlan ? status.remaining : status.net,
            fixedItemsTotal: fixedItemsTotal,
            topCategories: Array(topCategories),
            goal: goalSummary.map {
                AIInsightGoalSummary(progress: $0.progress, monthlyNeed: $0.perMonth)
            }
        )
    }

    func heroTitle() -> String {
        "Tilgjengelig denne måneden"
    }

    func screenStatusText(status: OverviewBudgetStatus, goalSummary: GoalSummary?, hasTransactions: Bool) -> String {
        if status.hasPlan && status.remaining < 0 {
            return "Over budsjett"
        }
        if status.hasPlan && status.planned > 0 {
            let ratio = status.remaining / status.planned
            if ratio <= 0.15 {
                return "Nær budsjettgrensen"
            }
            return "På budsjett denne måneden"
        }
        if let goalSummary {
            switch goalPlanState(summary: goalSummary) {
            case .behind:
                return "Litt bak spareplan"
            case .ahead, .onTrack, .complete:
                return "På vei mot målet"
            case .expired:
                return "Målfristen er passert"
            }
        }
        return hasTransactions ? "På budsjett denne måneden" : "I gang med denne måneden"
    }

    func screenStatusTone(status: OverviewBudgetStatus, goalSummary: GoalSummary?) -> OverviewToneRole {
        if status.hasPlan && status.remaining < 0 {
            return .warning
        }
        if status.hasPlan && status.planned > 0 {
            let ratio = status.remaining / status.planned
            if ratio <= 0.15 {
                return .warning
            }
            return .positive
        }
        if let goalSummary, goalPlanState(summary: goalSummary) == .behind {
            return .warning
        }
        return .neutral
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

    func dailyBudgetText(status: OverviewBudgetStatus, now: Date = .now, areAmountsHidden: Bool) -> String? {
        let baseAmount = status.hasPlan ? status.remaining : status.net
        guard abs(baseAmount) >= 1 else { return nil }

        let daysRemaining = remainingDaysInMonth(from: now)
        guard daysRemaining > 0 else { return nil }

        if areAmountsHidden {
            return baseAmount >= 0 ? "≈ •••• kr per dag resten av måneden" : "Du bruker ca. •••• kr for mye per dag"
        }

        let perDay = abs(baseAmount) / Double(daysRemaining)
        let rounded = roundedKr(perDay)
        if baseAmount < 0 {
            return "Du bruker ca. \(rounded) for mye per dag"
        }
        return "≈ \(rounded) per dag resten av måneden"
    }

    func spentPlannedText(status: OverviewBudgetStatus, areAmountsHidden: Bool) -> String? {
        guard status.hasPlan, status.planned > 0 else { return nil }
        if areAmountsHidden {
            return "•••• kr / •••• kr"
        }
        return "\(roundedKr(status.spent)) / \(roundedKr(status.planned))"
    }

    func monthlyProgressTone(status: OverviewBudgetStatus) -> OverviewToneRole {
        guard status.hasPlan, status.planned > 0 else { return .neutral }
        if status.remaining < 0 {
            return .warning
        }
        let ratio = status.remaining / status.planned
        if ratio <= 0.15 {
            return .warning
        }
        return .positive
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
        "Registrert sparing"
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
        if summary.targetDate < now {
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
            return "Foran planen"
        case .onTrack:
            return "På vei mot målet"
        case .behind:
            return "Litt bak spareplan"
        case .complete:
            return "Målet er nådd"
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

    func investmentLastUpdatedText(snapshot: InvestmentSnapshot?) -> String? {
        guard let snapshot else { return nil }
        return "Oppdatert \(formatDayMonth(snapshot.capturedAt))"
    }

    func investmentChangeText(change: Double, previousSnapshot: InvestmentSnapshot?, areAmountsHidden: Bool) -> String {
        guard previousSnapshot != nil else {
            return "Siden sist: ikke tilgjengelig ennå"
        }
        if areAmountsHidden {
            return "Siden sist: beløp skjult"
        }
        let sign = change >= 0 ? "+" : "−"
        return "Siden sist: \(sign)\(roundedKr(abs(change)))"
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

    private func formatDayMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date).lowercased()
    }

    private func remainingDaysInMonth(from date: Date) -> Int {
        let calendar = Calendar.current
        guard
            let dayRange = calendar.range(of: .day, in: .month, for: date)
        else { return 0 }
        let currentDay = calendar.component(.day, from: date)
        return max(dayRange.count - currentDay + 1, 0)
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
