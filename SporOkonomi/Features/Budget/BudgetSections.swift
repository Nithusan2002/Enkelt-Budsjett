import SwiftUI
import SwiftData
import UIKit

struct BudgetBottomAddTransactionButton: View {
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
            .foregroundStyle(AppTheme.onPrimary)
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

struct BudgetIncomeRow: Identifiable {
    let id: String
    let title: String
    let amount: Double
}

struct BudgetSavingsRow: Identifiable {
    let id: String
    let title: String
    let amount: Double
}

struct IncomeListView: View {
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

struct SavingsListView: View {
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

struct MonthHeaderView: View {
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

struct BudgetHeroCardView: View {
    let hasPlannedBudget: Bool
    let remaining: Double
    let trackedActual: Double
    let expenseTotal: Double
    let planned: Double
    let overBudgetCount: Int
    let groupsWithoutLimitWithSpendCount: Int
    let hasTransactions: Bool
    let isOverBudgetFilterActive: Bool
    let onToggleOverBudget: () -> Void
    let onSetLimits: () -> Void

    private var spentSoFar: Double {
        hasPlannedBudget ? trackedActual : expenseTotal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Denne måneden")
                .appCardTitleStyle()

            HStack(spacing: 12) {
                budgetMetric(
                    title: "Igjen denne måneden",
                    valueText: hasPlannedBudget ? formatNOK(remaining) : "Ikke satt",
                    tone: hasPlannedBudget
                        ? (remaining < 0 ? AppTheme.warning : AppTheme.textPrimary)
                        : AppTheme.textSecondary
                )

                budgetMetric(
                    title: "Brukt så langt",
                    valueText: formatNOK(spentSoFar),
                    tone: AppTheme.textPrimary
                )
            }

            if hasPlannedBudget {
                Text("\(formatNOK(spentSoFar)) brukt av \(formatNOK(planned)) denne måneden.")
                    .appSecondaryStyle()
            } else if hasTransactions {
                Text("Sett grenser for å se hva som er igjen denne måneden.")
                    .appSecondaryStyle()
            } else {
                Text("Når du har satt grenser, ser du hva som er brukt og hva som er igjen her.")
                    .appSecondaryStyle()
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

    private func budgetMetric(title: String, valueText: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appSecondaryStyle()
            Text(valueText)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.divider, lineWidth: 1))
    }

}

struct BudgetPrimaryActionCard: View {
    let hasPlannedBudget: Bool
    let hasTransactions: Bool
    let isReadOnlyMode: Bool
    let onSetLimits: () -> Void

    private var title: String {
        hasPlannedBudget ? "Juster grenser" : "Sett grenser"
    }

    private var subtitle: String {
        if hasPlannedBudget {
            return "Juster grensene når planen for måneden trenger en enkel oppdatering."
        }
        return "Sett grenser for å se hva som er brukt og hva som er igjen denne måneden."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .appCardTitleStyle()

            Text(subtitle)
                .appSecondaryStyle()

            Button(title) {
                onSetLimits()
            }
            .appProminentCTAStyle()
            .controlSize(.large)
            .disabled(isReadOnlyMode)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
    }
}

struct GroupListView: View {
    let rows: [BudgetGroupRow]
    let hasPlannedBudget: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kategorier")
                .appCardTitleStyle()

            if rows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(hasPlannedBudget ? "Ingen kategorier å vise ennå" : "Ingen grenser satt ennå")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(
                        hasPlannedBudget
                            ? "Kategorier med aktivitet dukker opp her etter hvert som måneden fylles."
                            : "Sett grenser for måneden for å få en enkel oversikt over brukt og igjen."
                    )
                    .appSecondaryStyle()
                }
            }

            ForEach(rows) { row in
                NavigationLink(value: row.group) {
                    GroupRowView(row: row)
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

struct BudgetDetailsView: View {
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

struct BudgetMonthPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var selectedDate: Date
    @State private var optionsAnchor: Date = .now
    let onSelect: (Date) -> Void

    private var monthOptions: [Date] {
        let calendar = Calendar.current
        let base = DateService.monthBounds(for: optionsAnchor).start
        return (-120...120).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: base).map { DateService.monthBounds(for: $0).start }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Velg måned")
                    .appSecondaryStyle()

                Picker("Måned", selection: $selectedDate) {
                    ForEach(monthOptions, id: \.self) { month in
                        Text(monthPickerLabel(month))
                            .tag(month)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
            }
            .navigationTitle("Velg måned")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") {
                        onSelect(DateService.monthBounds(for: selectedDate).start)
                        dismiss()
                    }
                }
            }
            .onAppear {
                selectedDate = DateService.monthBounds(for: selectedDate).start
                optionsAnchor = selectedDate
            }
        }
    }

    private func monthPickerLabel(_ date: Date) -> String {
        let raw = formatMonthYearShort(date).replacingOccurrences(of: ".", with: "")
        guard let first = raw.first else { return raw }
        return String(first).uppercased() + String(raw.dropFirst())
    }
}

struct AddTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    let initialType: TransactionKind?
    let initialTransaction: Transaction?
    let onSave: (Date, Double, TransactionKind, String?, String) -> Void

    @State private var date: Date = .now
    @State private var amountText: String = ""
    @State private var selectedType: TransactionKind?
    @State private var expenseMode: ExpenseEntryMode = .spending
    @State private var selectedCategoryID: String?
    @State private var note: String = ""
    @State private var attemptedSave = false
    @State private var showSavedBanner = false
    @State private var showPostSaveActions = false
    @State private var showCategoryPicker = false
    @FocusState private var amountFocused: Bool

    @AppStorage("budget.last_category.expense") private var lastExpenseCategoryID: String = ""
    @AppStorage("budget.last_category.savings") private var lastSavingsCategoryID: String = ""
    @AppStorage("budget.last_category.income") private var lastIncomeCategoryID: String = ""

    private var transactionKindForSave: TransactionKind {
        guard selectedType == .expense else { return .income }
        return expenseMode == .saving ? .manualSaving : .expense
    }

    private var availableCategories: [Category] {
        guard let selectedType else { return [] }
        switch selectedType {
        case .expense:
            return categories
                .filter {
                    if expenseMode == .saving {
                        return $0.type == .savings && $0.isActive
                    }
                    return $0.type == .expense && $0.isActive
                }
                .sorted { $0.sortOrder < $1.sortOrder }
        case .income:
            return categories
                .filter { $0.type == .income && $0.isActive }
                .sorted { $0.sortOrder < $1.sortOrder }
        default:
            return []
        }
    }

    private var isValid: Bool {
        selectedType != nil && parsedAmount > 0 && selectedCategoryID != nil
    }

    private var isEditing: Bool {
        initialTransaction != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transaksjon")
                            .appCardTitleStyle()

                        VStack(alignment: .leading, spacing: 14) {
                            Text("Type")
                                .appSecondaryStyle()

                            HStack(spacing: 10) {
                                typeCard(title: "Inntekt", systemImage: "arrow.down.circle.fill", type: .income)
                                typeCard(title: "Utgift", systemImage: "arrow.up.circle.fill", type: .expense)
                            }

                            if selectedType != nil {
                                Divider()
                                    .overlay(AppTheme.divider)

                                Text(entryHeading)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)

                                if selectedType == .expense {
                                    Picker("Utgiftstype", selection: $expenseMode) {
                                        ForEach(ExpenseEntryMode.allCases) { mode in
                                            Text(mode.title).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }

                                Text(categoryModeHelpText)
                                    .appSecondaryStyle()

                                if availableCategories.isEmpty {
                                    Text(categoryEmptyStateText)
                                        .appSecondaryStyle()
                                } else {
                                    Button {
                                        showCategoryPicker = true
                                    } label: {
                                        HStack(spacing: 10) {
                                            if let selected = selectedCategory {
                                                Image(systemName: symbolForCategory(selected.name))
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(AppTheme.primary)
                                                Text(selected.name)
                                                    .appBodyStyle()
                                            } else {
                                                Text("Velg kategori")
                                                    .appBodyStyle()
                                                    .foregroundStyle(AppTheme.textSecondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(AppTheme.textSecondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(AppTheme.divider, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }

                                Divider()
                                    .overlay(AppTheme.divider)

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

                                Divider()
                                    .overlay(AppTheme.divider)

                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Dato")
                                        .appSecondaryStyle()
                                    DatePicker(
                                        "Dato",
                                        selection: $date,
                                        displayedComponents: .date
                                    )
                                    .labelsHidden()
                                }

                                if initialTransaction?.fixedItemID != nil {
                                    Text("Denne endringen gjelder bare denne måneden, ikke malen for faste poster.")
                                        .appSecondaryStyle()
                                }

                                if attemptedSave && selectedCategoryID == nil {
                                    Text("Velg kategori for å lagre.")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(AppTheme.negative)
                                }
                            }
                        }
                        .padding()
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
                    }

                    Text("Notat")
                        .appCardTitleStyle()
                    TextField("Hva var dette?", text: $note)
                        .textFieldStyle(.appInput)
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle(isEditing ? "Rediger transaksjon" : "Legg til transaksjon")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Lagre endring" : "Lagre") {
                        attemptedSave = true
                        guard isValid else { return }
                        onSave(date, parsedAmount, transactionKindForSave, selectedCategoryID, note)
                        persistLastCategoryIfNeeded()
                        amountFocused = false
                        if isEditing {
                            dismiss()
                        } else {
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSavedBanner = true
                                showPostSaveActions = true
                            }
                            resetForNextEntry()
                        }
                    }
                    .disabled(!isValid)
                }
            }
            .appKeyboardDismissToolbar()
            .safeAreaInset(edge: .bottom) {
                if !isEditing && (showSavedBanner || showPostSaveActions) {
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
                                .appProminentCTAStyle()
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
                if let initialTransaction {
                    configureForTransaction(initialTransaction)
                } else if selectedType == nil, let initialType {
                    configureForType(initialType)
                }
                preselectCategoryForCurrentType()
            }
            .onChange(of: expenseMode) { _, _ in
                guard selectedType == .expense else { return }
                clearSelectionIfInvalidForType()
                preselectCategoryForCurrentType()
            }
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerSheet(
                    categories: availableCategories,
                    selectedCategoryID: $selectedCategoryID,
                    symbolForCategory: symbolForCategory
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: amountText) { _, newValue in
                let formatted = AppAmountInput.formatLive(newValue)
                if formatted != newValue {
                    amountText = formatted
                }
            }
        }
    }

    private var parsedAmount: Double {
        AppAmountInput.parse(amountText) ?? 0
    }

    private var selectedCategory: Category? {
        guard let selectedCategoryID else { return nil }
        return availableCategories.first(where: { $0.id == selectedCategoryID })
    }

    private var categoryModeHelpText: String {
        guard let selectedType else { return "" }
        switch selectedType {
        case .expense:
            if expenseMode == .saving {
                return "Sparing trekkes fra det som er tilgjengelig denne måneden og vises også i sparingsoversikten."
            }
            return "Forbruk føres på utgiftskategorier og påvirker gruppen det tilhører."
        case .income:
            return "Inntekter påvirker ikke brukt-beløpet, men vises i månedsdetaljene."
        default:
            return ""
        }
    }

    private var categoryEmptyStateText: String {
        guard let selectedType else { return "Velg type først." }
        switch selectedType {
        case .income:
            return "Ingen inntektskategorier er tilgjengelige ennå."
        case .expense:
            return expenseMode == .saving
                ? "Ingen sparekategorier er tilgjengelige ennå."
                : "Ingen utgiftskategorier er tilgjengelige ennå."
        default:
            return "Ingen kategorier er tilgjengelige ennå."
        }
    }

    private var entryHeading: String {
        if isEditing {
            return transactionKindForSave == .manualSaving ? "Rediger sparing" : (transactionKindForSave == .income ? "Rediger inntekt" : "Rediger utgift")
        }
        guard let selectedType else { return "Ny transaksjon" }
        switch selectedType {
        case .expense:
            return expenseMode == .saving ? "Ny sparing" : "Ny utgift"
        case .income:
            return "Ny inntekt"
        default:
            return "Ny transaksjon"
        }
    }

    private func preselectCategoryForCurrentType() {
        if availableCategories.isEmpty {
            selectedCategoryID = nil
            return
        }
        if let selectedCategoryID,
           availableCategories.contains(where: { $0.id == selectedCategoryID }) {
            return
        }
        switch selectedType ?? .expense {
        case .expense:
            let lastCategoryID = expenseMode == .saving ? lastSavingsCategoryID : lastExpenseCategoryID
            if availableCategories.contains(where: { $0.id == lastCategoryID }) {
                selectedCategoryID = lastCategoryID
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
        if selectedType == .expense {
            if expenseMode == .saving {
                lastSavingsCategoryID = selectedCategoryID
            } else {
                lastExpenseCategoryID = selectedCategoryID
            }
        } else if selectedType == .income {
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

    private func configureForType(_ type: TransactionKind) {
        switch type {
        case .income:
            selectedType = .income
            expenseMode = .spending
        case .manualSaving:
            selectedType = .expense
            expenseMode = .saving
        case .expense, .refund, .transfer:
            selectedType = .expense
            expenseMode = .spending
        }
    }

    private func configureForTransaction(_ transaction: Transaction) {
        date = transaction.date
        amountText = AppAmountInput.format(abs(transaction.amount))
        note = transaction.note
        selectedCategoryID = transaction.categoryID
        configureForType(transaction.kind)
    }

    private func typeCard(title: String, systemImage: String, type: TransactionKind) -> some View {
        let isSelected = selectedType == type
        return Button {
            selectedType = type
            if type == .income {
                expenseMode = .spending
            }
            attemptedSave = false
            clearSelectionIfInvalidForType()
            preselectCategoryForCurrentType()
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

enum ExpenseEntryMode: String, CaseIterable, Identifiable {
    case spending
    case saving

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spending: return "Forbruk"
        case .saving: return "Sparing"
        }
    }
}

struct CategoryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    @Binding var selectedCategoryID: String?
    let symbolForCategory: (String) -> String

    private let columns = [
        GridItem(.flexible(), spacing: 10, alignment: .top),
        GridItem(.flexible(), spacing: 10, alignment: .top)
    ]
    @State private var searchText: String = ""

    private var filteredCategories: [Category] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        guard !query.isEmpty else { return categories }
        return categories.filter { category in
            category.name
                .folding(options: .diacriticInsensitive, locale: .current)
                .lowercased()
                .contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                TextField("Søk kategori", text: $searchText)
                    .textFieldStyle(.appInput)
                    .padding(.horizontal)
                    .padding(.top, 8)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(filteredCategories) { category in
                        let isSelected = selectedCategoryID == category.id
                        Button {
                            selectedCategoryID = category.id
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: symbolForCategory(category.name))
                                        .font(.subheadline.weight(.semibold))
                                    Spacer(minLength: 0)
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.footnote.weight(.bold))
                                    }
                                }

                                Text(category.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, minHeight: 88, maxHeight: 88, alignment: .topLeading)
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
                }
                .padding()

                if filteredCategories.isEmpty {
                    Text("Ingen kategorier matcher søket.")
                        .appSecondaryStyle()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Velg kategori")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Lukk") { dismiss() }
                }
            }
        }
    }
}

struct GroupRowView: View {
    let row: BudgetGroupRow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(row.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            HStack(spacing: 12) {
                valueBlock(title: "Brukt", value: row.spent, tone: AppTheme.textPrimary)
                valueBlock(
                    title: "Igjen",
                    value: row.remaining ?? 0,
                    tone: remainingTone
                )
            }

            if !row.hasLimit {
                Text("Ingen grense satt ennå.")
                    .appSecondaryStyle()
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if let remaining = row.remaining, let planned = row.planned {
            return "Brukt \(formatNOK(row.spent)) av \(formatNOK(planned)), \(formatNOK(remaining)) igjen"
        }
        return "Brukt \(formatNOK(row.spent)), ingen grense"
    }

    private var remainingTone: Color {
        guard let remaining = row.remaining else { return AppTheme.textSecondary }
        return remaining < 0 ? AppTheme.warning : AppTheme.positive
    }

    private func valueBlock(title: String, value: Double, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appSecondaryStyle()
            Text(formatNOK(value))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.divider, lineWidth: 1))
    }
}

struct SetGroupLimitsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    let periodKey: String
    let groupPlans: [BudgetGroupPlan]
    let groupRows: [BudgetGroupRow]
    let fixedByGroup: [String: Double]
    @ObservedObject var viewModel: BudgetViewModel

    @State private var values: [BudgetGroup: String] = Dictionary(
        uniqueKeysWithValues: BudgetGroup.allCases.map { ($0, "") }
    )

    private var hasAnyInput: Bool {
        BudgetGroup.allCases.contains { group in
            let text = values[group, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return false }
            return (AppAmountInput.parse(text) ?? 0) > 0
        }
    }

    private var hasExistingForMonth: Bool {
        groupPlans.contains { $0.monthPeriodKey == periodKey }
    }

    private var previousValues: [BudgetGroup: Double?] {
        viewModel.copyPreviousMonthGroupPlans(periodKey: periodKey, groupPlans: groupPlans)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Sett bare grensene du trenger. Tomt betyr at gruppen spores uten å telle i månedsmålet.")
                        .appSecondaryStyle()
                }

                Section("Månedsgrenser") {
                    ForEach(BudgetGroup.allCases) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Månedsgrense for \(group.title)")
                                Spacer()
                                HStack(spacing: 6) {
                                    Text("kr")
                                        .foregroundStyle(AppTheme.textSecondary)
                                    TextField("Ingen grense satt", text: binding(for: group))
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .monospacedDigit()
                                        .frame(maxWidth: 140)
                                }
                            }

                            Text(previousMonthText(for: group))
                                .appSecondaryStyle()

                            Text("Brukt hittil: \(formatNOK(viewModel.currentSpent(for: group, groupRows: groupRows)))")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.textSecondary)
                                .monospacedDigit()

                            let fixedTotal = fixedByGroup[group.rawValue] ?? 0
                            if fixedTotal > 0 {
                                Text("Faste poster: \(formatNOK(fixedTotal))")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .monospacedDigit()
                            }

                            if let suggestionText = suggestionText(for: group) {
                                Text(suggestionText)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textSecondary)
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
                    Button("Kopier fra forrige måned") {
                        let previous = previousValues
                        for group in BudgetGroup.allCases {
                            if let value = previous[group] ?? nil, value > 0 {
                                values[group] = AppAmountInput.format(value)
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
            .navigationTitle("Månedsgrenser")
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
                                let value = AppAmountInput.parse(raw) ?? 0
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
            .appKeyboardDismissToolbar()
            .onAppear {
                let current = groupPlans.filter { $0.monthPeriodKey == periodKey }
                for group in BudgetGroup.allCases {
                    if let existing = current.first(where: { $0.groupKey == group.rawValue }), existing.plannedAmount > 0 {
                        values[group] = AppAmountInput.format(existing.plannedAmount)
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
                values[group] = AppAmountInput.formatLive(newValue)
            }
        )
    }

    private func parsedValue(for group: BudgetGroup) -> Double? {
        let raw = values[group, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return AppAmountInput.parse(raw)
    }

    private func previousMonthText(for group: BudgetGroup) -> String {
        if let previous = previousValues[group] ?? nil, previous > 0 {
            return "Forrige måned: \(formatNOK(previous))"
        }
        return "Forrige måned: Ingen grense satt"
    }

    private func suggestionText(for group: BudgetGroup) -> String? {
        guard values[group, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let previous = previousValues[group] ?? nil, previous > 0 else { return nil }
        return "Forslag: Start med \(formatNOK(previous)) og juster ved behov."
    }

}

struct BudgetGroupDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var editingTransaction: Transaction?
    @State private var transactionFilter: BudgetDetailTransactionFilter = .all

    let group: BudgetGroup
    let periodKey: String
    let categories: [Category]
    let groupPlans: [BudgetGroupPlan]
    let transactions: [Transaction]
    @Binding var showAddTransaction: Bool
    @ObservedObject var viewModel: BudgetViewModel

    private var isReadOnlyMode: Bool {
        PersistenceGate.isReadOnlyMode
    }

    private var planned: Double? {
        groupPlans.first { $0.monthPeriodKey == periodKey && $0.groupKey == group.rawValue }?.plannedAmount
    }

    private var spent: Double {
        rows.reduce(0) { $0 + BudgetService.trackedBudgetImpact($1) }
    }

    private var groupCategories: [Category] {
        viewModel.categoriesForGroup(group, categories: categories)
    }

    private var rows: [Transaction] {
        viewModel.transactionsForGroup(group, periodKey: periodKey, categories: categories, transactions: transactions)
    }

    private var filteredRows: [Transaction] {
        rows.filter { transaction in
            switch transactionFilter {
            case .all:
                return true
            case .spending:
                return transaction.kind == .expense
            case .saving:
                return transaction.kind == .manualSaving
            case .fixed:
                return transaction.recurringKey != nil
            }
        }
    }

    private var groupedTransactions: [(title: String, rows: [Transaction])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredRows) { transaction in
            calendar.startOfDay(for: transaction.date)
        }

        return grouped
            .map { day, rows in
                (
                    title: transactionSectionTitle(for: day),
                    rows: rows.sorted { $0.date > $1.date }
                )
            }
            .sorted { lhs, rhs in
                guard let lhsDate = lhs.rows.first?.date, let rhsDate = rhs.rows.first?.date else { return false }
                return lhsDate > rhsDate
            }
    }

    private var spentByCategory: [(name: String, spent: Double)] {
        let groupedByName = Dictionary(grouping: groupCategories) { category in
            category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return groupedByName
            .map { name, categories in
                let ids = Set(categories.map(\.id))
                let spent = rows
                    .filter { transaction in
                        guard let categoryID = transaction.categoryID else { return false }
                        return ids.contains(categoryID)
                    }
                    .reduce(0) { $0 + BudgetService.trackedBudgetImpact($1) }
                return (name: name, spent: max(spent, 0))
            }
            .sorted { lhs, rhs in
                if lhs.spent != rhs.spent { return lhs.spent > rhs.spent }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
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
                        ForEach(spentByCategory, id: \.name) { row in
                            HStack {
                                Text(row.name)
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
                    HStack {
                        Text("Transaksjoner")
                            .appCardTitleStyle()
                        Spacer()
                        Text("\(filteredRows.count)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(BudgetDetailTransactionFilter.allCases) { filter in
                                Button {
                                    transactionFilter = filter
                                } label: {
                                    Text(filter.title)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(transactionFilter == filter ? AppTheme.onPrimary : AppTheme.textPrimary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            transactionFilter == filter ? AppTheme.primary : AppTheme.surfaceElevated,
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if filteredRows.isEmpty {
                        Text(emptyTransactionsText)
                            .appSecondaryStyle()
                    }

                    ForEach(groupedTransactions, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)

                            ForEach(section.rows, id: \.persistentModelID) { transaction in
                                Button {
                                    editingTransaction = transaction
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(categoryTitle(for: transaction))
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(AppTheme.textPrimary)

                                            if !transaction.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                Text(transaction.note)
                                                    .font(.footnote)
                                                    .foregroundStyle(AppTheme.textSecondary)
                                                    .lineLimit(2)
                                            }

                                            HStack(spacing: 6) {
                                                transactionMetaPill(
                                                    text: transactionKindLabel(for: transaction),
                                                    color: transaction.kind == .manualSaving ? AppTheme.secondary : AppTheme.textSecondary
                                                )

                                                if transaction.recurringKey != nil {
                                                    transactionMetaPill(text: "Fast post", color: AppTheme.primary)
                                                }

                                                Text(transactionTimeLabel(transaction.date))
                                                    .font(.caption2)
                                                    .foregroundStyle(AppTheme.textSecondary)
                                            }
                                        }

                                        Spacer()

                                        VStack(alignment: .trailing, spacing: 4) {
                                            Text(formatNOK(BudgetService.trackedBudgetImpact(transaction)))
                                                .foregroundStyle(transactionAmountColor(for: transaction))
                                                .monospacedDigit()
                                            Text("Hold inne for valg")
                                                .font(.caption2)
                                                .foregroundStyle(AppTheme.textSecondary)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        guard !isReadOnlyMode else {
                                            viewModel.persistenceErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
                                            return
                                        }
                                        editingTransaction = transaction
                                    } label: {
                                        Label("Rediger", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        guard !isReadOnlyMode else {
                                            viewModel.persistenceErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
                                            return
                                        }
                                        viewModel.deleteTransaction(context: modelContext, transaction: transaction)
                                    } label: {
                                        Label("Slett", systemImage: "trash")
                                    }
                                }
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
        .sheet(
            isPresented: Binding(
                get: { editingTransaction != nil },
                set: { if !$0 { editingTransaction = nil } }
            )
        ) {
            if let transaction = editingTransaction {
                AddTransactionSheet(
                    categories: categories.filter(\.isActive),
                    initialType: transaction.kind,
                    initialTransaction: transaction
                ) { date, amount, kind, categoryID, note in
                    viewModel.updateTransaction(
                        context: modelContext,
                        transaction: transaction,
                        date: date,
                        amount: amount,
                        kind: kind,
                        categoryID: categoryID,
                        note: note
                    )
                }
            }
        }
    }

    private var emptyTransactionsText: String {
        switch transactionFilter {
        case .all:
            return "Ingen transaksjoner i \(group.title.lowercased()) ennå."
        case .spending:
            return "Ingen forbrukstransaksjoner i denne gruppen ennå."
        case .saving:
            return "Ingen sparing registrert i denne gruppen ennå."
        case .fixed:
            return "Ingen faste poster i denne gruppen denne måneden."
        }
    }

    private func categoryTitle(for transaction: Transaction) -> String {
        guard let categoryID = transaction.categoryID,
              let category = categories.first(where: { $0.id == categoryID }) else {
            return group.title
        }
        return category.name
    }

    private func transactionKindLabel(for transaction: Transaction) -> String {
        switch transaction.kind {
        case .manualSaving:
            return "Sparing"
        case .income:
            return "Inntekt"
        case .refund:
            return "Refusjon"
        case .transfer:
            return "Overføring"
        case .expense:
            return "Forbruk"
        }
    }

    private func transactionAmountColor(for transaction: Transaction) -> Color {
        switch transaction.kind {
        case .manualSaving:
            return AppTheme.secondary
        case .income, .refund:
            return AppTheme.positive
        case .transfer, .expense:
            return AppTheme.textPrimary
        }
    }

    private func transactionSectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "I dag"
        }
        if calendar.isDateInYesterday(date) {
            return "I går"
        }
        return formatDate(date)
    }

    private func transactionTimeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func transactionMetaPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private enum BudgetDetailTransactionFilter: String, CaseIterable, Identifiable {
    case all
    case spending
    case saving
    case fixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "Alle"
        case .spending:
            return "Forbruk"
        case .saving:
            return "Sparing"
        case .fixed:
            return "Faste"
        }
    }
}
