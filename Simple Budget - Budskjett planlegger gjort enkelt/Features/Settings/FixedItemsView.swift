import SwiftUI
import SwiftData

struct FixedItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FixedItem.title) private var fixedItems: [FixedItem]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var editorItem: FixedItem?
    @State private var showAddSheet = false

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
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primary)
                    }
                    .padding(.vertical, 8)
                }
            } else {
                Section("Faste poster") {
                    ForEach(fixedItems) { item in
                        Button {
                            editorItem = item
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .appBodyStyle()
                                    Text("\(formatNOK(item.amount)) • \(item.dayOfMonth). hver måned")
                                        .appSecondaryStyle()
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { item.isActive },
                                    set: { value in
                                        item.isActive = value
                                        try? modelContext.save()
                                    }
                                ))
                                .labelsHidden()
                            }
                        }
                        .buttonStyle(.plain)
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
            }
        }
        .sheet(isPresented: $showAddSheet) {
            FixedItemEditorSheet(categories: categories) { draft, createCurrentMonth in
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
                try? modelContext.save()

                if createCurrentMonth {
                    try? FixedItemsService.generateForCurrentMonthForItem(
                        context: modelContext,
                        fixedItemID: item.id
                    )
                }
            }
        }
        .sheet(item: $editorItem) { item in
            FixedItemEditorSheet(
                categories: categories,
                existing: item
            ) { draft, createCurrentMonth in
                item.title = draft.title
                item.amount = draft.amount
                item.categoryID = draft.categoryID
                item.kind = draft.kind
                item.dayOfMonth = draft.dayOfMonth
                item.startDate = draft.startDate
                item.endDate = draft.endDate
                item.isActive = draft.isActive
                item.autoCreate = draft.autoCreate
                try? modelContext.save()
            }
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(fixedItems[index])
        }
        try? modelContext.save()
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

    var amount: Double { max(parseFixedItemAmount(amountText) ?? 0, 0) }
}

private struct FixedItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    let existing: FixedItem?
    let onSave: (FixedItemDraft, Bool) -> Void

    @State private var draft = FixedItemDraft()
    @State private var createCurrentMonth = true
    @State private var useEndDate = false

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

    private var isValid: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        draft.amount > 0 &&
        !draft.categoryID.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fast post") {
                    TextField("Navn", text: $draft.title)
                        .textFieldStyle(.appInput)
                    TextField("Beløp", text: $draft.amountText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.appInput)
                        .onChange(of: draft.amountText) { _, value in
                            let formatted = formatFixedItemAmountInputLive(value)
                            if formatted != value {
                                draft.amountText = formatted
                            }
                        }

                    Picker("Type", selection: $draft.kind) {
                        Text("Utgift").tag(TransactionKind.expense)
                        Text("Inntekt").tag(TransactionKind.income)
                    }
                    .pickerStyle(.segmented)

                    Picker("Kategori", selection: $draft.categoryID) {
                        Text("Velg kategori").tag("")
                        ForEach(filteredCategories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }

                    Picker("Dag i måneden", selection: $draft.dayOfMonth) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }

                    DatePicker("Startdato", selection: $draft.startDate, displayedComponents: [.date])
                    Toggle("Sluttdato", isOn: $useEndDate)
                    if useEndDate {
                        DatePicker(
                            "Sluttdato",
                            selection: Binding(
                                get: { draft.endDate ?? draft.startDate },
                                set: { draft.endDate = $0 }
                            ),
                            in: draft.startDate...,
                            displayedComponents: [.date]
                        )
                    }

                    Toggle("Aktiv", isOn: $draft.isActive)
                    Toggle("Opprett automatisk", isOn: $draft.autoCreate)
                }

                Section("Nåværende måned") {
                    Toggle("Opprett også for denne måneden", isOn: $createCurrentMonth)
                        .disabled(existing != nil)
                    if existing != nil {
                        Text("Gjelder kun ved opprettelse av ny fast post.")
                            .appSecondaryStyle()
                    }
                }
            }
            .navigationTitle(existing == nil ? "Legg til fast post" : "Rediger fast post")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        onSave(draft, createCurrentMonth)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let existing {
                    draft.title = existing.title
                    draft.amountText = formatFixedItemInputAmount(existing.amount)
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
                }
            }
            .onChange(of: draft.kind) { _, _ in
                if !filteredCategories.contains(where: { $0.id == draft.categoryID }) {
                    draft.categoryID = filteredCategories.first?.id ?? ""
                }
            }
            .onChange(of: useEndDate) { _, enabled in
                if !enabled {
                    draft.endDate = nil
                } else if draft.endDate == nil {
                    draft.endDate = draft.startDate
                }
            }
        }
    }
}

private func parseFixedItemAmount(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let normalized = trimmed
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "\u{00A0}", with: "")
        .replacingOccurrences(of: "\u{202F}", with: "")
        .replacingOccurrences(of: ",", with: ".")
    return Double(normalized)
}

private func formatFixedItemInputAmount(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "nb_NO")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: value)) ?? ""
}

private func formatFixedItemAmountInputLive(_ rawText: String) -> String {
    let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    let filtered = trimmed.filter { $0.isNumber || $0 == "," || $0 == "." }
    guard !filtered.isEmpty else { return "" }
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
    let formattedInteger = formatFixedItemInputAmount(integerValue)

    if hasSeparator {
        let fraction = String(fractionRaw.prefix(2))
        if endsWithSeparator || !fraction.isEmpty {
            return "\(formattedInteger),\(fraction)"
        }
    }
    return formattedInteger
}
