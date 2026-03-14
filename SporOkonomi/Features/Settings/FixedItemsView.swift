import SwiftUI
import SwiftData

struct FixedItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FixedItem.title) private var fixedItems: [FixedItem]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var transactions: [Transaction]
    @Query private var fixedItemSkips: [FixedItemSkip]

    @State private var editorItem: FixedItem?
    @State private var showAddSheet = false
    @State private var saveErrorMessage: String?
    private var isReadOnlyMode: Bool { PersistenceGate.isReadOnlyMode }

    var body: some View {
        List {
            if fixedItems.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ingen faste poster ennå")
                            .appCardTitleStyle()
                        Text("Legg til faste utgifter eller inntekter én gang, så opprettes de automatisk hver måned.")
                            .appSecondaryStyle()
                        Button("Legg til fast post") {
                            showAddSheet = true
                        }
                        .appProminentCTAStyle()
                        .disabled(isReadOnlyMode)
                    }
                    .padding(.vertical, 8)
                }
            } else {
                Section("Faste poster") {
                    ForEach(fixedItems) { item in
                        HStack(spacing: 12) {
                            Button {
                                editorItem = item
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .appBodyStyle()
                                    Text("\(formatNOK(item.amount)) • \(item.dayOfMonth). hver måned")
                                        .appSecondaryStyle()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Rediger \(item.title)")

                            Toggle(
                                "Aktiv",
                                isOn: Binding(
                                    get: { item.isActive },
                                    set: { value in
                                        guard !isReadOnlyMode else {
                                            saveErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
                                            return
                                        }
                                        let previousValue = item.isActive
                                        item.isActive = value
                                        do {
                                            try modelContext.guardedSave(feature: "FixedItems", operation: "toggle_fixed_item")
                                        } catch {
                                            item.isActive = previousValue
                                            saveErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke oppdatere fast post."
                                        }
                                    }
                                )
                            )
                            .labelsHidden()
                            .accessibilityLabel("\(item.title), aktiv")
                        }
                    }
                    .onDelete(perform: deleteItems)
                }
            }
        }
        .navigationTitle("Faste poster")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Legg til", systemImage: "plus")
                }
                .disabled(isReadOnlyMode)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            FixedItemEditorSheet(categories: categories) { draft, createCurrentMonth in
                guard !isReadOnlyMode else {
                    saveErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
                    return
                }
                let item = FixedItem(
                    title: draft.title,
                    amount: draft.amount,
                    categoryID: draft.categoryID,
                    kind: draft.kind,
                    dayOfMonth: draft.dayOfMonth,
                    startDate: draft.startDate,
                    endDate: draft.endDate,
                    isActive: draft.isActive,
                    autoCreate: draft.autoCreate
                )
                modelContext.insert(item)
                do {
                    try modelContext.guardedSave(feature: "FixedItems", operation: "create_fixed_item")
                } catch {
                    saveErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke opprette fast post."
                    return
                }

                if createCurrentMonth {
                    do {
                        try FixedItemsService.generateForCurrentMonthForItem(
                            context: modelContext,
                            fixedItemID: item.id
                        )
                    } catch {
                        saveErrorMessage = "Fast post ble lagret, men månedens transaksjon kunne ikke opprettes."
                    }
                }
            }
        }
        .sheet(item: $editorItem) { item in
            FixedItemEditorSheet(
                categories: categories,
                existing: item
            ) { draft, createCurrentMonth in
                guard !isReadOnlyMode else {
                    saveErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
                    return
                }
                item.title = draft.title
                item.amount = draft.amount
                item.categoryID = draft.categoryID
                item.kind = draft.kind
                item.dayOfMonth = draft.dayOfMonth
                item.startDate = draft.startDate
                item.endDate = draft.endDate
                item.isActive = draft.isActive
                item.autoCreate = draft.autoCreate
                do {
                    try modelContext.guardedSave(feature: "FixedItems", operation: "update_fixed_item")
                } catch {
                    saveErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke lagre endringer i fast post."
                }
            }
        }
        .alert(
            "Kunne ikke lagre faste poster",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "Prøv igjen litt senere.")
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        guard !isReadOnlyMode else {
            saveErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
            return
        }
        for index in offsets {
            let item = fixedItems[index]

            for transaction in transactions where transaction.fixedItemID == item.id {
                modelContext.delete(transaction)
            }

            for skip in fixedItemSkips where skip.fixedItemID == item.id {
                modelContext.delete(skip)
            }

            modelContext.delete(item)
        }
        do {
            try modelContext.guardedSave(feature: "FixedItems", operation: "delete_fixed_items")
        } catch {
            saveErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke slette fast post."
        }
    }
}

private struct FixedItemDraft {
    var title: String = ""
    var amountText: String = ""
    var categoryID: String = ""
    var kind: TransactionKind = .expense
    var dayOfMonth: Int = 1
    var startDate: Date = .now
    var endDate: Date? = nil
    var isActive: Bool = true
    var autoCreate: Bool = true

    var amount: Double { max(AppAmountInput.parse(amountText) ?? 0, 0) }
}

private struct FixedItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    let existing: FixedItem?
    let onSave: (FixedItemDraft, Bool) -> Void

    @State private var draft = FixedItemDraft()
    @State private var createCurrentMonth = false
    @State private var hasCustomizedCreateCurrentMonth = false
    @State private var useEndDate = false
    @State private var showDayPicker = false
    @State private var showCategoryPicker = false
    @State private var showAmountError = false
    @State private var showCategoryError = false
    @State private var showAdvanced = false
    @FocusState private var titleFocused: Bool

    init(
        categories: [Category],
        existing: FixedItem? = nil,
        onSave: @escaping (FixedItemDraft, Bool) -> Void
    ) {
        self.categories = categories
        self.existing = existing
        self.onSave = onSave
    }

    private var filteredCategories: [Category] {
        switch draft.kind {
        case .expense:
            return categories.filter { $0.type == .expense && $0.isActive }
        case .income:
            return categories.filter { $0.type == .income && $0.isActive }
        case .refund, .transfer, .manualSaving:
            return categories.filter(\.isActive)
        }
    }

    private var selectedCategoryName: String {
        filteredCategories.first(where: { $0.id == draft.categoryID })?.name ?? "Velg kategori"
    }

    private var isValid: Bool {
        draft.amount > 0 && !draft.categoryID.isEmpty
    }

    private var resolvedTitleForSave: String {
        let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return selectedCategoryName == "Velg kategori" ? "Fast post" : selectedCategoryName
    }

    private var automaticMonthDescription: String {
        "Legges inn på valgt dag hver måned."
    }

    private var shouldShowCreateForCurrentMonth: Bool {
        guard existing == nil else { return false }
        let calendar = Calendar.current
        let monthStartToday = calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
        let monthStartForStartDate = calendar.date(from: calendar.dateComponents([.year, .month], from: draft.startDate)) ?? draft.startDate
        guard monthStartToday == monthStartForStartDate else { return false }
        return draft.dayOfMonth >= 1 && draft.dayOfMonth <= 31
    }

    private var currentMonthContextText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: draft.startDate).capitalized
    }

    private var suggestedCreateCurrentMonthDefault: Bool {
        let todayDay = Calendar.current.component(.day, from: .now)
        return todayDay < draft.dayOfMonth
    }

    private var createCurrentMonthBinding: Binding<Bool> {
        Binding(
            get: { createCurrentMonth },
            set: { newValue in
                hasCustomizedCreateCurrentMonth = true
                createCurrentMonth = newValue
            }
        )
    }

    private var nameRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Navn")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            TextField("F.eks. Husleie", text: $draft.title)
                .focused($titleFocused)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.next)
        }
    }

    private var typeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type")
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
            Picker("Type", selection: $draft.kind) {
                Text("Utgift").tag(TransactionKind.expense)
                Text("Inntekt").tag(TransactionKind.income)
            }
            .pickerStyle(.segmented)
        }
    }

    private var amountRow: some View {
        HStack(spacing: 10) {
            Text("kr")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .accessibilityHidden(true)
            TextField("Beløp", text: $draft.amountText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("Beløp i kroner")
                .onChange(of: draft.amountText) { _, value in
                    let formatted = AppAmountInput.formatLive(value)
                    if formatted != value {
                        draft.amountText = formatted
                    }
                }
        }
    }

    @ViewBuilder
    private var amountErrorRow: some View {
        if showAmountError && draft.amount <= 0 {
            Text("Skriv inn et beløp for å lagre.")
                .font(.footnote)
                .foregroundStyle(AppTheme.negative)
        }
    }

    private var categoryRow: some View {
        Button {
            showCategoryPicker = true
        } label: {
            HStack {
                Text("Kategori")
                Spacer()
                Text(selectedCategoryName)
                    .foregroundStyle(draft.categoryID.isEmpty ? AppTheme.textSecondary : AppTheme.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Kategori, \(selectedCategoryName)")
    }

    @ViewBuilder
    private var categoryErrorRow: some View {
        if showCategoryError && draft.categoryID.isEmpty {
            Text("Velg kategori for å lagre.")
                .font(.footnote)
                .foregroundStyle(AppTheme.negative)
        }
    }

    private var dayRow: some View {
        Button {
            showDayPicker = true
        } label: {
            HStack {
                Text("Dag i måneden")
                Spacer()
                Text("\(draft.dayOfMonth).")
                    .foregroundStyle(AppTheme.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dag i måneden, valgt \(draft.dayOfMonth)")
    }

    private var basicsSection: some View {
        Section {
            nameRow
            typeRow
            amountRow
            amountErrorRow
            categoryRow
            categoryErrorRow
            dayRow
        }
    }

    private var automationSection: some View {
        Section("Automatikk") {
            Toggle("Opprett automatisk hver måned", isOn: $draft.autoCreate)
                .accessibilityLabel("Opprett automatisk hver måned")
            Text(automaticMonthDescription)
                .appSecondaryStyle()
        }
    }

    @ViewBuilder
    private var currentMonthSection: some View {
        if shouldShowCreateForCurrentMonth {
            Section("Nåværende måned") {
                Toggle("Opprett også denne måneden", isOn: createCurrentMonthBinding)
                Text(currentMonthContextText)
                    .appSecondaryStyle()
            }
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showAdvanced) {
                DatePicker("Startdato", selection: $draft.startDate, displayedComponents: [.date])
                Toggle("Sluttdato", isOn: $useEndDate)
                if useEndDate {
                    DatePicker(
                        "Velg sluttdato",
                        selection: Binding(
                            get: { draft.endDate ?? draft.startDate },
                            set: { draft.endDate = $0 }
                        ),
                        in: draft.startDate...,
                        displayedComponents: [.date]
                    )
                }

                if existing != nil {
                    Toggle("Aktiv", isOn: $draft.isActive)
                }
            } label: {
                Text("Avansert")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                basicsSection
                automationSection
                currentMonthSection
                advancedSection
            }
            .navigationTitle(existing == nil ? "Ny fast post" : "Fast post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        showAmountError = draft.amount <= 0
                        showCategoryError = draft.categoryID.isEmpty
                        guard isValid else { return }
                        var normalizedDraft = draft
                        normalizedDraft.title = resolvedTitleForSave
                        onSave(normalizedDraft, shouldShowCreateForCurrentMonth ? createCurrentMonth : false)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .appKeyboardDismissToolbar()
            .onAppear {
                if let existing {
                    draft.title = existing.title
                    draft.amountText = AppAmountInput.format(existing.amount)
                    draft.categoryID = existing.categoryID
                    draft.kind = existing.kind
                    draft.dayOfMonth = existing.dayOfMonth
                    draft.startDate = existing.startDate
                    draft.endDate = existing.endDate
                    useEndDate = existing.endDate != nil
                    draft.isActive = existing.isActive
                    draft.autoCreate = existing.autoCreate
                    createCurrentMonth = false
                } else if let first = filteredCategories.first {
                    draft.categoryID = first.id
                    useEndDate = false
                    draft.endDate = nil
                    createCurrentMonth = suggestedCreateCurrentMonthDefault
                }
                titleFocused = existing == nil
            }
            .onChange(of: draft.kind) { _, _ in
                if !filteredCategories.contains(where: { $0.id == draft.categoryID }) {
                    draft.categoryID = filteredCategories.first?.id ?? ""
                }
            }
            .onChange(of: draft.dayOfMonth) { _, _ in
                guard existing == nil, !hasCustomizedCreateCurrentMonth else { return }
                createCurrentMonth = suggestedCreateCurrentMonthDefault
            }
            .onChange(of: draft.startDate) { _, _ in
                guard existing == nil, !hasCustomizedCreateCurrentMonth else { return }
                createCurrentMonth = suggestedCreateCurrentMonthDefault
            }
            .onChange(of: useEndDate) { _, enabled in
                if !enabled {
                    draft.endDate = nil
                } else if draft.endDate == nil {
                    draft.endDate = draft.startDate
                }
            }
            .sheet(isPresented: $showDayPicker) {
                FixedItemDayPickerSheet(dayOfMonth: $draft.dayOfMonth)
            }
            .sheet(isPresented: $showCategoryPicker) {
                FixedItemCategoryPickerSheet(
                    categories: filteredCategories,
                    selectedCategoryID: $draft.categoryID
                )
            }
        }
    }
}

private struct FixedItemDayPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var dayOfMonth: Int

    var body: some View {
        NavigationStack {
            Form {
                Picker("Dag i måneden", selection: $dayOfMonth) {
                    ForEach(1...31, id: \.self) { day in
                        Text("\(day).")
                            .tag(day)
                    }
                }
                .pickerStyle(.wheel)
            }
            .navigationTitle("Dag i måneden")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") { dismiss() }
                }
            }
        }
    }
}

private struct FixedItemCategoryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [Category]
    @Binding var selectedCategoryID: String
    @State private var searchText: String = ""

    private var filteredCategories: [Category] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return categories }
        return categories.filter { category in
            category.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredCategories.isEmpty {
                    ContentUnavailableView {
                        Label("Ingen treff", systemImage: "magnifyingglass")
                    } description: {
                        Text("Ingen kategorier matcher søket ditt.")
                    }
                } else {
                    List(filteredCategories) { category in
                        Button {
                            selectedCategoryID = category.id
                            dismiss()
                        } label: {
                            HStack {
                                Text(category.name)
                                Spacer()
                                if category.id == selectedCategoryID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppTheme.primary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Velg kategori")
            .searchable(text: $searchText, prompt: "Søk kategori")
        }
    }
}
