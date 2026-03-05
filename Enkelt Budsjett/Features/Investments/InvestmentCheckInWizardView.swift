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
                        isEditingExistingPeriod: viewModel.isEditingExistingPeriod,
                        hasPreviousData: !viewModel.previousValues.isEmpty,
                        onPrefill: { viewModel.copyPreviousToChanged() },
                        onStart: { viewModel.start() },
                        onCancel: { dismiss() }
                    )
                } else if viewModel.isSummary {
                    WizardSummaryView(
                        periodText: formattedMonth(viewModel.selectedMonthDate),
                        lastSavedAt: viewModel.existingSnapshotForSelectedPeriod?.capturedAt,
                        previousTotal: viewModel.prevTotal,
                        newTotal: viewModel.newTotal,
                        delta: viewModel.delta,
                        deltaPercent: viewModel.changePct,
                        changedCount: viewModel.changedBucketCount,
                        changedRows: viewModel.changedRows,
                        isSaving: isSaving,
                        onBack: { viewModel.goBack() },
                        onSave: save,
                        saveDisabled: isReadOnlyMode || isSaving
                    )
                } else if let bucket = viewModel.currentBucket {
                    WizardBucketStepView(
                        progressText: viewModel.progressText,
                        navigationItems: viewModel.bucketNavigationItems,
                        onSelectBucket: { viewModel.jump(to: $0) },
                        bucketName: bucket.name,
                        isNewType: viewModel.isNewType(bucket.id),
                        previousValue: viewModel.previousValue(for: bucket.id),
                        currentValue: viewModel.effectiveValue(for: bucket.id),
                        hasStoredDelta: viewModel.hasStoredDelta(for: bucket.id),
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
                        nextTitle: viewModel.nextButtonTitle,
                        canGoNext: viewModel.canMoveNext
                    )
                }
            }
            .navigationTitle("Oppdater verdier")
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
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primary)
            .appCTAStyle()
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
    let isEditingExistingPeriod: Bool
    let hasPreviousData: Bool
    let onPrefill: () -> Void
    let onStart: () -> Void
    let onCancel: () -> Void
    @State private var showMonthPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Uendret bruker forrige måneds verdi. Første gang brukes 0.")
                .appBodyStyle()
                .foregroundStyle(AppTheme.textSecondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Denne innsjekken gjelder for")
                    .appSecondaryStyle()
                Button {
                    showMonthPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .foregroundStyle(AppTheme.primary)
                        Text(periodText)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.divider, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showMonthPicker) {
                    InvestmentMonthPickerSheet(
                        selectedDate: selectedMonthDate,
                        onSelect: { selectedMonthDate = $0 }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }

                if isEditingExistingPeriod {
                    Text("Du oppdaterer eksisterende innsjekk for denne måneden.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding()
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))

            if !hasPreviousData {
                Text("Første innsjekk: start med grove tall, du kan justere senere.")
                    .appSecondaryStyle()
                    .padding(.horizontal, 4)
            }

            Spacer()
        }
        .padding()
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button("Avbryt") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                if hasPreviousData {
                    Button("Kopier forrige måned") {
                        onPrefill()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Start") {
                    onStart()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .appCTAStyle()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(.ultraThinMaterial)
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

private struct WizardBucketStepView: View {
    let progressText: String
    let navigationItems: [InvestmentWizardBucketNavItem]
    let onSelectBucket: (String) -> Void
    let bucketName: String
    let isNewType: Bool
    let previousValue: Double
    let currentValue: Double
    let hasStoredDelta: Bool
    @Binding var mode: InvestmentWizardInputMode
    @Binding var inputText: String
    let errorMessage: String?
    let onAddPreset: (Double) -> Void
    let onBack: () -> Void
    let onNext: () -> Void
    let nextTitle: String
    let canGoNext: Bool
    @FocusState private var amountFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WizardBucketNavigationStrip(
                items: navigationItems,
                onSelect: onSelectBucket
            )

            Text(progressText)
                .appSecondaryStyle()

            HStack(spacing: 8) {
                Text(bucketName)
                    .font(.title2.weight(.semibold))
                if isNewType {
                    Text("Ny type")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.primary.opacity(0.12), in: Capsule())
                }
            }

            Text("Forrige: \(formatNOK(previousValue))")
                .appBodyStyle()
                .foregroundStyle(AppTheme.textSecondary)

            if shouldShowDeltaChip {
                HStack(spacing: 6) {
                    Image(systemName: currentValue >= previousValue ? "arrow.up.right" : "arrow.down.right")
                    Text("\(currentValue >= previousValue ? "+" : "-")\(formatNOK(abs(currentValue - previousValue))) fra forrige")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(currentValue >= previousValue ? AppTheme.positive : AppTheme.negative)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background((currentValue >= previousValue ? AppTheme.positive : AppTheme.negative).opacity(0.12), in: Capsule())
            }

            HStack(spacing: 10) {
                modeButton(title: "Uendret", modeValue: .unchanged)
                modeButton(title: "Endret", modeValue: .changed)
            }

            statusLine

            if mode == .changed {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("kr")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                        TextField("Beløp", text: $inputText)
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
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .appCTAStyle()
                .disabled(!canGoNext)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(.ultraThinMaterial)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bucketName). Forrige \(formatNOK(previousValue)). Status: \(statusTextForAccessibility).")
    }

    private var shouldShowDeltaChip: Bool {
        abs(currentValue - previousValue) > 0.0001 && (mode == .changed || hasStoredDelta)
    }

    private var statusTextForAccessibility: String {
        if mode == .changed {
            if errorMessage != nil { return "Mangler beløp" }
            return "Endret"
        }
        return "Uendret"
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIconName)
            Text(statusTextForAccessibility)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(statusColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var statusIconName: String {
        if mode == .changed {
            return errorMessage == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        }
        return "arrow.triangle.2.circlepath.circle.fill"
    }

    private var statusColor: Color {
        if mode == .changed {
            return errorMessage == nil ? AppTheme.positive : AppTheme.warning
        }
        return AppTheme.textSecondary
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

private struct WizardBucketNavigationStrip: View {
    let items: [InvestmentWizardBucketNavItem]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    Button {
                        onSelect(item.id)
                    } label: {
                        HStack(spacing: 6) {
                            if item.isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                            }
                            Text(item.title)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(item.isCurrent ? AppTheme.primary.opacity(0.14) : AppTheme.surface, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(item.isCurrent ? AppTheme.primary : AppTheme.divider, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Hopp mellom beholdningstyper")
    }
}

private struct WizardSummaryView: View {
    let periodText: String
    let lastSavedAt: Date?
    let previousTotal: Double
    let newTotal: Double
    let delta: Double
    let deltaPercent: Double?
    let changedCount: Int
    let changedRows: [InvestmentWizardChangeRow]
    let isSaving: Bool
    let onBack: () -> Void
    let onSave: () -> Void
    let saveDisabled: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Oppsummering")
                    .font(.title3.weight(.semibold))

                Text("Gjelder: \(periodText)")
                    .appSecondaryStyle()
                if let lastSavedAt {
                    Text("Sist lagret: \(formatDateTime(lastSavedAt))")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                row("Forrige total", value: formatNOK(previousTotal))
                row("Ny total", value: formatNOK(newTotal))
                row("Total endring fra forrige måned", value: deltaText)

                if changedCount == 0 {
                    Text("Ingen endringer – total forblir \(formatNOK(newTotal)).")
                        .appBodyStyle()
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Endret i \(changedCount) typer")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                        ForEach(changedRows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.bucketName)
                                    .font(.footnote.weight(.semibold))
                                HStack {
                                    Text("Ny verdi")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                    Spacer()
                                    Text(formatNOK(row.newValue))
                                        .font(.footnote)
                                        .monospacedDigit()
                                }
                                HStack {
                                    Text("Endring")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                    Spacer()
                                    Text(signedAmountText(row.delta))
                                        .font(.footnote.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(row.delta >= 0 ? AppTheme.positive : AppTheme.negative)
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(row.bucketName). Ny verdi \(formatNOK(row.newValue)). Endring \(signedAmountText(row.delta)).")
                        }
                    }
                    .padding(10)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.divider, lineWidth: 1))
                }
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
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .appCTAStyle()
                .disabled(saveDisabled)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(.ultraThinMaterial)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Oppsummering")
        .accessibilityValue("Gjelder \(periodText). Forrige total \(formatNOK(previousTotal)). Ny total \(formatNOK(newTotal)). Endring \(deltaText). Endret i \(changedCount) typer.")
    }

    private var deltaText: String {
        let sign = delta >= 0 ? "+" : "−"
        let percent = deltaPercent.map { " (\(formatPercent($0)))" } ?? ""
        return "\(sign)\(formatNOK(abs(delta)))\(percent)"
    }

    private func signedAmountText(_ amount: Double) -> String {
        let sign = amount >= 0 ? "+" : "−"
        return "\(sign)\(formatNOK(abs(amount)))"
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter.string(from: date)
    }

    private func row(_ title: String, value: String) -> some View {
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
