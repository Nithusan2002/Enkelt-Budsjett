import SwiftUI
import SwiftData
import UIKit

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
    @State private var addTypeName = ""
    @State private var addTypeColorHex = AppTheme.customBucketPalette[0]
    @State private var addTypeErrorMessage: String?
    private var isReadOnlyMode: Bool { PersistenceGate.isReadOnlyMode }

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.hasBuckets {
                    emptyState
                } else if viewModel.isIntro {
                    WizardIntroView(
                        selectedMonthDate: Binding(
                            get: { viewModel.selectedMonthDate },
                            set: { viewModel.setSelectedMonth($0) }
                        ),
                        periodText: formattedMonth(viewModel.selectedMonthDate),
                        hasPreviousData: !viewModel.previousValues.isEmpty,
                        onPrefill: { viewModel.copyPreviousToChanged() },
                        onStart: { viewModel.start() }
                    )
                } else if viewModel.isSummary {
                    WizardSummaryView(
                        periodText: formattedMonth(viewModel.selectedMonthDate),
                        lastSavedAt: viewModel.existingSnapshotForSelectedPeriod?.capturedAt,
                        newTotal: viewModel.newTotal,
                        changedCount: viewModel.changedBucketCount,
                        isSaving: isSaving,
                        onBack: { viewModel.goBack() },
                        onSave: save,
                        saveDisabled: isReadOnlyMode || isSaving
                    )
                } else if let bucket = viewModel.currentBucket {
                    WizardBucketStepView(
                        progressText: viewModel.progressText,
                        bucketName: bucket.name,
                        previousValue: viewModel.previousValue(for: bucket.id),
                        mode: Binding(
                            get: { viewModel.stepStates[bucket.id]?.mode ?? .unchanged },
                            set: { viewModel.setMode($0, for: bucket.id) }
                        ),
                        inputText: Binding(
                            get: { viewModel.stepStates[bucket.id]?.inputString ?? "" },
                            set: { viewModel.updateInput($0, for: bucket.id) }
                        ),
                        errorMessage: viewModel.validationMessage(for: bucket.id),
                        onAddPreset: { viewModel.addToInput($0, for: bucket.id) },
                        onBack: { viewModel.goBack() },
                        onNext: { viewModel.goNext() },
                        showAddNewType: viewModel.isLastBucketStep,
                        onAddNewType: {
                            addTypeName = ""
                            addTypeColorHex = AppTheme.customBucketPalette[0]
                            addTypeErrorMessage = nil
                            showAddTypeSheet = true
                        },
                        nextTitle: viewModel.nextButtonTitle,
                        canGoNext: viewModel.canMoveNext
                    )
                }
            }
            .navigationTitle("Oppdater verdier")
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

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Opprett en beholdningstype først")
                .appCardTitleStyle()
            Text("Du trenger minst én aktiv beholdning for å gjøre innsjekk.")
                .appBodyStyle()
                .foregroundStyle(AppTheme.textSecondary)
            Button("Ny type") {
                dismiss()
                onRequestNewType?()
            }
            .appProminentCTAStyle()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
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
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date).capitalized
    }
}

private struct WizardIntroView: View {
    @Binding var selectedMonthDate: Date
    let periodText: String
    let hasPreviousData: Bool
    let onPrefill: () -> Void
    let onStart: () -> Void
    @State private var showMonthPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gå gjennom beholdningene dine og oppdater det som har endret seg.")
                .appBodyStyle()
                .foregroundStyle(AppTheme.textSecondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Denne innsjekken gjelder \(periodText.lowercased()).")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Button("Bytt måned") {
                    showMonthPicker = true
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.primary)
                .sheet(isPresented: $showMonthPicker) {
                    InvestmentMonthPickerSheet(
                        selectedDate: selectedMonthDate,
                        onSelect: { selectedMonthDate = $0 }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }

            if !hasPreviousData {
                Text("Første innsjekk starter på 0 for typer uten tidligere verdi.")
                    .appSecondaryStyle()
            }

            Spacer()
        }
        .padding()
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                if hasPreviousData {
                    Button("Kopier forrige måned") {
                        onPrefill()
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                }

                Button("Start") {
                    onStart()
                }
                .appProminentCTAStyle()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
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
        return (-12...6).compactMap { offset in
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

private struct WizardBucketStepView: View {
    let progressText: String
    let bucketName: String
    let previousValue: Double
    @Binding var mode: InvestmentWizardInputMode
    @Binding var inputText: String
    let errorMessage: String?
    let onAddPreset: (Double) -> Void
    let onBack: () -> Void
    let onNext: () -> Void
    let showAddNewType: Bool
    let onAddNewType: () -> Void
    let nextTitle: String
    let canGoNext: Bool
    @FocusState private var amountFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(progressText)
                .appSecondaryStyle()

            Text(bucketName)
                .font(.title2.weight(.semibold))

            Text(previousValue > 0 ? "Sist registrert: \(formatNOK(previousValue))" : "Ingen tidligere verdi")
                .appBodyStyle()
                .foregroundStyle(AppTheme.textSecondary)

            HStack(spacing: 10) {
                modeButton(title: "Uendret", modeValue: .unchanged)
                modeButton(title: "Oppdater verdi", modeValue: .changed)
            }

            if mode == .changed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ny verdi")
                        .appSecondaryStyle()

                    HStack(spacing: 8) {
                        Text("kr")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                        TextField("0", text: $inputText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.appInput)
                            .monospacedDigit()
                            .focused($amountFieldFocused)
                    }

                    HStack(spacing: 8) {
                        presetButton("+1 000", increment: 1_000)
                        presetButton("+10 000", increment: 10_000)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.negative)
                    }
                }
            }

            if showAddNewType {
                Button("Legg til ny type") {
                    onAddNewType()
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()
        }
        .padding()
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button("Tilbake") {
                    onBack()
                }
                .buttonStyle(.bordered)

                Button(nextTitle) {
                    onNext()
                }
                .appProminentCTAStyle()
                .disabled(!canGoNext)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .onChange(of: mode) { _, newValue in
            guard newValue == .changed else { return }
            amountFieldFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
            }
        }
        .onAppear {
            if mode == .changed {
                amountFieldFocused = true
            }
        }
    }

    @ViewBuilder
    private func presetButton(_ title: String, increment: Double) -> some View {
        Button(title) {
            onAddPreset(increment)
            amountFieldFocused = true
        }
        .buttonStyle(.bordered)
        .font(.footnote.weight(.semibold))
    }

    @ViewBuilder
    private func modeButton(title: String, modeValue: InvestmentWizardInputMode) -> some View {
        let selected = mode == modeValue
        Button {
            mode = modeValue
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? AppTheme.primary.opacity(0.14) : AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selected ? AppTheme.primary : AppTheme.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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
                    Text("Ny type vises i denne innsjekken før oppsummering.")
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

private struct WizardSummaryView: View {
    let periodText: String
    let lastSavedAt: Date?
    let newTotal: Double
    let changedCount: Int
    let isSaving: Bool
    let onBack: () -> Void
    let onSave: () -> Void
    let saveDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Klar til å lagre")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                summaryRow("Måned", value: periodText.lowercased())
                summaryRow(
                    "Oppdatert",
                    value: changedCount == 1 ? "1 beholdning" : "\(changedCount) beholdninger"
                )
                summaryRow("Ny total", value: formatNOK(newTotal))

                if let lastSavedAt {
                    Text("Sist lagret: \(formatDateTime(lastSavedAt))")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(12)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.divider, lineWidth: 1))
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button("Tilbake") {
                    onBack()
                }
                .buttonStyle(.bordered)
                .disabled(saveDisabled)

                Button {
                    onSave()
                } label: {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Text("Lagre")
                    }
                }
                .appProminentCTAStyle()
                .disabled(saveDisabled)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Oppsummering")
        .accessibilityValue("Måned \(periodText). Oppdatert \(changedCount) beholdninger. Ny total \(formatNOK(newTotal)).")
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter.string(from: date)
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .appBodyStyle()
            Spacer()
            Text(value)
                .appBodyStyle()
                .monospacedDigit()
        }
    }
}
