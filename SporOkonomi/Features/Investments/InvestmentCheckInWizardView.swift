import SwiftUI
import SwiftData

struct InvestmentCheckInWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let buckets: [InvestmentBucket]
    let snapshots: [InvestmentSnapshot]
    var onRequestNewType: (() -> Void)?
    var onSaved: ((Bool, String) -> Void)?

    @StateObject private var viewModel = InvestmentCheckInWizardViewModel()
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var showAddTypeSheet = false
    @State private var showMonthPicker = false
    @State private var addTypeName = ""
    @State private var addTypeColorHex = AppTheme.customBucketPalette[0]
    @State private var addTypeErrorMessage: String?
    @State private var selectedSuggestedTypes: Set<InvestmentSuggestedBucketOption> = []
    private var isReadOnlyMode: Bool { PersistenceGate.isReadOnlyMode }

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.hasBuckets {
                    emptyState
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Oppdater verdier")
            .navigationBarTitleDisplayMode(.inline)
            .background(AppTheme.background)
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
            .appKeyboardDismissToolbar()
            .alert("Kunne ikke lagre", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                viewModel.loadInitialState(buckets: buckets, snapshots: snapshots)
            }
            .sheet(isPresented: $showMonthPicker) {
                InvestmentMonthPickerSheet(
                    selectedDate: viewModel.selectedMonthDate,
                    onSelect: { viewModel.setSelectedMonth($0) }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAddTypeSheet) {
                AddInvestmentTypeDuringCheckInSheet(
                    name: $addTypeName,
                    selectedColorHex: $addTypeColorHex,
                    errorMessage: addTypeErrorMessage
                ) {
                    do {
                        try viewModel.addBucketDuringCheckIn(
                            context: modelContext,
                            name: addTypeName,
                            colorHex: addTypeColorHex
                        )
                        addTypeErrorMessage = nil
                        showAddTypeSheet = false
                    } catch {
                        addTypeErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke lagre beholdningstype nå."
                    }
                } onCancel: {
                    addTypeErrorMessage = nil
                }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Oppdater det som har endret seg denne måneden.")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("La felt stå tomt hvis en verdi er uendret.")
                        .appBodyStyle()
                        .foregroundStyle(AppTheme.textSecondary)
                }

                monthCard

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.buckets, id: \.id) { bucket in
                        InvestmentCheckInRow(
                            bucketName: bucket.name,
                            isNewType: viewModel.isNewType(bucket.id),
                            previousValueText: previousValueText(for: bucket.id),
                            inputText: Binding(
                                get: { viewModel.displayedInput(for: bucket.id) },
                                set: { viewModel.updateDisplayedInput($0, for: bucket.id) }
                            ),
                            errorMessage: viewModel.validationMessage(for: bucket.id)
                        )
                    }
                }

                Button("Legg til ny type") {
                    addTypeName = ""
                    addTypeColorHex = AppTheme.customBucketPalette[0]
                    addTypeErrorMessage = nil
                    showAddTypeSheet = true
                }
                .buttonStyle(.bordered)
                .font(.subheadline.weight(.semibold))
                .padding(.top, 2)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if isReadOnlyMode {
                    Text("Du kan ikke lagre endringer akkurat nå.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Lagre")
                            .frame(maxWidth: .infinity)
                    }
                }
                .appProminentCTAStyle()
                .disabled(isSaving || isReadOnlyMode || !viewModel.canSave)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(AppTheme.background.opacity(0.98))
        }
    }

    private var monthCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Denne innsjekken gjelder \(formattedMonth(viewModel.selectedMonthDate))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            if viewModel.isEditingExistingPeriod {
                Text("Du oppdaterer allerede lagrede verdier for denne måneden.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Button("Bytt måned") {
                showMonthPicker = true
            }
            .buttonStyle(.bordered)
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.divider, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Velg typene du vil oppdatere")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Legg til minst én beholdning for å starte innsjekken.")
                        .appBodyStyle()
                        .foregroundStyle(AppTheme.textSecondary)
                }

                VStack(spacing: 10) {
                    ForEach(InvestmentSuggestedBucketOption.allCases) { option in
                        suggestionCard(for: option)
                    }
                }

                Button {
                    do {
                        try viewModel.addSuggestedBucketsDuringCheckIn(
                            context: modelContext,
                            selections: InvestmentSuggestedBucketOption.allCases.filter { selectedSuggestedTypes.contains($0) }
                        )
                        selectedSuggestedTypes = []
                    } catch {
                        errorMessage = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke legge til beholdningstyper nå."
                    }
                } label: {
                    Text("Legg til valgte typer")
                        .frame(maxWidth: .infinity)
                }
                .appProminentCTAStyle()
                .disabled(selectedSuggestedTypes.isEmpty || isReadOnlyMode)

                Button("Legg til egen type") {
                    addTypeName = ""
                    addTypeColorHex = AppTheme.customBucketPalette[0]
                    addTypeErrorMessage = nil
                    showAddTypeSheet = true
                }
                .buttonStyle(.bordered)
                .font(.subheadline.weight(.semibold))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func suggestionCard(for option: InvestmentSuggestedBucketOption) -> some View {
        let isSelected = selectedSuggestedTypes.contains(option)

        return Button {
            if isSelected {
                selectedSuggestedTypes.remove(option)
            } else {
                selectedSuggestedTypes.insert(option)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(Color(hex: option.colorHex))
                    .frame(width: 12, height: 12)
                    .padding(.top, 5)

                Text(option.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.primary : AppTheme.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(isSelected ? AppTheme.primary.opacity(0.08) : AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? AppTheme.primary : AppTheme.divider, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func previousValueText(for bucketID: String) -> String {
        if viewModel.previousValues[bucketID] == nil {
            return "Ingen tidligere verdi"
        }
        return "Sist registrert: \(formatNOK(viewModel.previousValue(for: bucketID)))"
    }

    private func save() {
        guard !isSaving else { return }
        guard !isReadOnlyMode else {
            errorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let wasNewSnapshot = try viewModel.saveSnapshot(context: modelContext)
            onSaved?(wasNewSnapshot, viewModel.periodKey)
            dismiss()
        } catch {
            errorMessage = "Lagring feilet. Prøv igjen."
        }
    }

    private func formattedMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).lowercased()
    }
}

private struct InvestmentCheckInRow: View {
    let bucketName: String
    let isNewType: Bool
    let previousValueText: String
    @Binding var inputText: String
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(bucketName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                if isNewType {
                    Text("Ny type")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.primary.opacity(0.12), in: Capsule())
                }
            }

            Text(previousValueText)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Ny verdi")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                HStack(spacing: 10) {
                    Text("kr")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)

                    TextField("Skriv inn ny verdi", text: $inputText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.plain)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(errorMessage == nil ? AppTheme.divider : AppTheme.negative, lineWidth: 1)
                )

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.negative)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.divider, lineWidth: 1)
        )
    }
}

private struct InvestmentMonthPickerSheet: View {
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
            .background(AppTheme.background)
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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

private struct AddInvestmentTypeDuringCheckInSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var name: String
    @Binding var selectedColorHex: String
    let errorMessage: String?
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Navn") {
                    TextField("F.eks. Eiendom", text: $name)
                        .textFieldStyle(.appInput)
                }

                Section("Farge") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                        ForEach(AppTheme.customBucketPalette, id: \.self) { hex in
                            Button {
                                selectedColorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if selectedColorHex == hex {
                                            Circle()
                                                .stroke(AppTheme.background, lineWidth: 2)
                                                .padding(2)
                                        }
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(AppTheme.divider, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Ny type vises i denne innsjekken uten at du mister det du allerede har fylt inn.")
                        .appSecondaryStyle()

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.negative)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Legg til type")
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        onSave()
                    }
                    .appCTAStyle()
                }
            }
        }
    }
}
