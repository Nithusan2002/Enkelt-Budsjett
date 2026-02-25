import SwiftUI
import SwiftData
import Charts
import UIKit

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
    private var rows: [BudgetCategoryRow] {
        viewModel.categoryRows(periodKey: periodKey, categories: categories, plans: plans, transactions: transactions)
    }
    private var hasPlannedBudget: Bool {
        summary.planned > 0
    }
    private var overBudgetCount: Int {
        rows.filter(\.isOverBudget).count
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
                    onNext: { viewModel.changeMonth(by: 1) }
                )

                BudgetHeroCardView(
                    hasPlannedBudget: hasPlannedBudget,
                    remaining: summary.remaining,
                    actual: summary.actual,
                    planned: summary.planned,
                    income: summary.income,
                    net: summary.net,
                    overBudgetCount: overBudgetCount,
                    fixedTotalThisMonth: fixedTotalThisMonth,
                    onShowOverBudget: {
                        viewModel.selectedFilter = .overBudget
                    }
                )

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

                if hasPlannedBudget {
                    CategoryListView(rows: rows) { row in
                        viewModel.editorTarget = BudgetEditorTarget(id: row.id, categoryName: row.title, categoryID: row.id)
                    }
                }
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
            AddTransactionSheet(categories: categories.filter(\.isActive)) { date, amount, kind, categoryID, note in
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

    private func monthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "MMM yyyy"
        let raw = formatter.string(from: date).replacingOccurrences(of: ".", with: "")
        guard let first = raw.first else { return raw }
        return String(first).uppercased() + String(raw.dropFirst())
    }
}

private struct MonthHeaderView: View {
    let monthLabel: String
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)

            Spacer()

            Text(monthLabel)
                .font(.headline.weight(.semibold))
                .accessibilityLabel("Valgt måned")
                .accessibilityValue(monthLabel)

            Spacer()

            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
    }
}

private struct BudgetHeroCardView: View {
    let hasPlannedBudget: Bool
    let remaining: Double
    let actual: Double
    let planned: Double
    let income: Double
    let net: Double
    let overBudgetCount: Int
    let fixedTotalThisMonth: Double
    let onShowOverBudget: () -> Void

    private var usedPercent: Double {
        guard planned > 0 else { return 0 }
        return min(max(actual / planned, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasPlannedBudget {
                Text("Igjen å bruke")
                    .appSecondaryStyle()
                Text(formatNOK(remaining))
                    .appBigNumberStyle()
                    .foregroundStyle(remaining < 0 ? AppTheme.negative : AppTheme.textPrimary)
                Text("Brukt \(formatNOK(actual)) av \(formatNOK(planned))")
                    .appSecondaryStyle()

                ProgressView(value: usedPercent, total: 1)
                    .tint(remaining < 0 ? AppTheme.warning : AppTheme.secondary)

                if overBudgetCount > 0 {
                    Button {
                        onShowOverBudget()
                    } label: {
                        Text("Over budsjett i \(overBudgetCount) kategorier")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.warning.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Netto hittil")
                    .appSecondaryStyle()
                Text(formatNOK(net))
                    .appBigNumberStyle()
                    .foregroundStyle(net < 0 ? AppTheme.negative : AppTheme.textPrimary)
                Text("Utgifter: \(formatNOK(actual)) • Inntekt: \(formatNOK(income))")
                    .appSecondaryStyle()

                Text("Du kan også bare spore uten grenser.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Text("Faste poster denne måneden: \(formatNOK(fixedTotalThisMonth))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasPlannedBudget ? "Igjen å bruke" : "Netto hittil")
        .accessibilityValue(hasPlannedBudget ? formatNOK(remaining) : formatNOK(net))
    }
}

private struct CategoryListView: View {
    let rows: [BudgetCategoryRow]
    let onEdit: (BudgetCategoryRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kategorier")
                .appCardTitleStyle()

            if rows.isEmpty {
                Text("Ingen kategorier å vise for denne måneden.")
                    .appSecondaryStyle()
            }

            ForEach(rows) { row in
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

                    ProgressView(value: row.spent, total: max(row.planned, 1))
                        .tint(row.isOverBudget ? AppTheme.warning : AppTheme.secondary)

                    HStack {
                        Spacer()
                        Button("Endre budsjett") {
                            onEdit(row)
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))
    }
}

private struct AddTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
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
            return categories.filter { $0.type == .expense }.sorted { $0.sortOrder < $1.sortOrder }
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
                        typeCard(title: "Utgift", systemImage: "arrow.up.circle.fill", type: .expense)
                        typeCard(title: "Inntekt", systemImage: "arrow.down.circle.fill", type: .income)
                    }
                }

                if selectedType != nil {
                    Section(selectedType == .expense ? "Ny utgift" : "Ny inntekt") {
                        if availableCategories.isEmpty {
                            Text("Ingen kategorier for valgt type.")
                                .appSecondaryStyle()
                        } else {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 155), spacing: 10)],
                                alignment: .leading,
                                spacing: 10
                            ) {
                                ForEach(availableCategories) { category in
                                    let isSelected = selectedCategoryID == category.id
                                    Button {
                                        selectedCategoryID = category.id
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: symbolForCategory(category.name))
                                                .font(.subheadline.weight(.semibold))
                                            Text(category.name)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(1)
                                            Spacer(minLength: 0)
                                            if isSelected {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.footnote.weight(.bold))
                                            }
                                        }
                                        .foregroundStyle(isSelected ? AppTheme.primary : AppTheme.textPrimary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
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
                            .padding(.vertical, 4)
                            .animation(.easeInOut(duration: 0.15), value: selectedCategoryID)
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
        case "studielan": return "graduationcap.fill"
        case "pensjon", "utbytte": return "banknote.fill"
        case "renteinntekter": return "building.columns.fill"
        case "barnetrygd": return "figure.2.and.child.holdinghands"
        case "salg av ting pa finn/tise": return "hand.raised.fill"
        case "utleie av eiendom": return "house.fill"
        case "utleie av hytte": return "mountain.2.fill"
        case "utleie av bil": return "car.fill"

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

private struct BudgetEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let categoryName: String
    let initialValue: Double
    let onSave: (Double) -> Void

    @State private var plannedText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Kategori") {
                    Text(categoryName)
                }
                Section("Planlagt beløp") {
                    TextField("Beløp", text: $plannedText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.appInput)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
            }
            .navigationTitle("Endre budsjett")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        onSave(max(parseInputAmount(plannedText) ?? 0, 0))
                        dismiss()
                    }
                }
            }
            .onAppear {
                plannedText = initialValue > 0 ? formatInputAmount(initialValue) : ""
            }
        }
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
