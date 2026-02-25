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
                        onStart: { viewModel.start() },
                        onCancel: { dismiss() }
                    )
                } else if viewModel.isSummary {
                    WizardSummaryView(
                        previousTotal: viewModel.prevTotal,
                        newTotal: viewModel.newTotal,
                        delta: viewModel.delta,
                        deltaPercent: viewModel.changePct,
                        changedCount: changedBucketsCount,
                        onBack: { viewModel.goBack() },
                        onSave: save
                    )
                } else if let bucket = viewModel.currentBucket {
                    WizardBucketStepView(
                        progressText: viewModel.progressText,
                        bucketName: bucket.name,
                        isNewType: viewModel.isNewType(bucket.id),
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
                }
            }
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

    private var changedBucketsCount: Int {
        viewModel.buckets.reduce(0) { partial, bucket in
            let mode = viewModel.stepStates[bucket.id]?.mode ?? .unchanged
            return partial + (mode == .changed ? 1 : 0)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Opprett en beholdningstype først")
                .appCardTitleStyle()
            Text("Du trenger minst én aktiv beholdning for å gjøre insjekk.")
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
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Uendret beholder forrige verdi. Første gang brukes 0.")
                .appBodyStyle()
                .foregroundStyle(AppTheme.textSecondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Denne insjekken gjelder for")
                    .appSecondaryStyle()
                DatePicker(
                    "Måned",
                    selection: $selectedMonthDate,
                    in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(periodText)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                if isEditingExistingPeriod {
                    Text("Du oppdaterer eksisterende innsjekk for denne måneden.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding()
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.divider, lineWidth: 1))

            Spacer()

            HStack(spacing: 10) {
                Button("Avbryt") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Start") {
                    onStart()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .appCTAStyle()
            }
        }
        .padding()
    }
}

private struct WizardBucketStepView: View {
    let progressText: String
    let bucketName: String
    let isNewType: Bool
    let previousValue: Double
    @Binding var mode: InvestmentWizardInputMode
    @Binding var inputText: String
    let errorMessage: String?
    let onBack: () -> Void
    let onNext: () -> Void
    let nextTitle: String
    let canGoNext: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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

            HStack(spacing: 10) {
                modeButton(title: "Uendret", modeValue: .unchanged)
                modeButton(title: "Endret", modeValue: .changed)
            }

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
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.negative)
                    }
                }
            }

            Spacer()

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
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bucketName). Forrige \(formatNOK(previousValue)). \(mode == .unchanged ? "Uendret valgt" : "Endret valgt").")
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

private struct WizardSummaryView: View {
    let previousTotal: Double
    let newTotal: Double
    let delta: Double
    let deltaPercent: Double?
    let changedCount: Int
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Oppsummering")
                .font(.title3.weight(.semibold))

            row("Forrige total", value: formatNOK(previousTotal))
            row("Ny total", value: formatNOK(newTotal))
            row("Endring siden forrige insjekk", value: deltaText)

            if changedCount == 0 {
                Text("Ingen endringer – total forblir \(formatNOK(newTotal)).")
                    .appBodyStyle()
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Tilbake") {
                    onBack()
                }
                .buttonStyle(.bordered)

                Button("Lagre") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .appCTAStyle()
            }
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Oppsummering")
        .accessibilityValue("Forrige total \(formatNOK(previousTotal)). Ny total \(formatNOK(newTotal)). Endring \(deltaText).")
    }

    private var deltaText: String {
        let sign = delta >= 0 ? "+" : "−"
        let percent = deltaPercent.map { " (\(formatPercent($0)))" } ?? ""
        return "\(sign)\(formatNOK(abs(delta)))\(percent)"
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
