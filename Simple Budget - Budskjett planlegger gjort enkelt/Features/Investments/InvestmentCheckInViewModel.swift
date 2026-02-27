import Foundation
import Combine
import SwiftData

enum InvestmentWizardInputMode: String {
    case unchanged
    case changed
}

struct InvestmentWizardStepState {
    var mode: InvestmentWizardInputMode = .unchanged
    var inputString: String = ""
}

struct InvestmentWizardChangeRow: Identifiable {
    let id: String
    let bucketName: String
    let previousValue: Double
    let newValue: Double

    var delta: Double { newValue - previousValue }
}

@MainActor
final class InvestmentCheckInWizardViewModel: ObservableObject {
    @Published var selectedMonthDate: Date = DateService.monthBounds(for: .now).start
    @Published var index: Int = -1 // -1 = intro, 0...N-1 = bucket steps, N = summary
    @Published var stepStates: [String: InvestmentWizardStepState] = [:]

    private(set) var buckets: [InvestmentBucket] = []
    private(set) var snapshots: [InvestmentSnapshot] = []

    var periodKey: String {
        DateService.periodKey(from: selectedMonthDate)
    }

    var isIntro: Bool { index < 0 }

    var isSummary: Bool {
        !buckets.isEmpty && index >= buckets.count
    }

    var hasBuckets: Bool {
        !buckets.isEmpty
    }

    var currentBucket: InvestmentBucket? {
        guard index >= 0, index < buckets.count else { return nil }
        return buckets[index]
    }

    var progressText: String {
        guard hasBuckets else { return "0 av 0" }
        let current = max(0, min(index, buckets.count - 1)) + 1
        return "\(current) av \(buckets.count)"
    }

    var previousValues: [String: Double] {
        valuesDictionary(from: InvestmentService.previousSnapshot(before: periodKey, snapshots: snapshots))
    }

    var existingPeriodValues: [String: Double] {
        valuesDictionary(from: InvestmentService.snapshot(for: periodKey, snapshots: snapshots))
    }

    var baselineValues: [String: Double] {
        existingPeriodValues.isEmpty ? previousValues : existingPeriodValues
    }

    var isEditingExistingPeriod: Bool {
        InvestmentService.snapshot(for: periodKey, snapshots: snapshots) != nil
    }

    var effectiveValues: [String: Double] {
        var output: [String: Double] = [:]
        for bucket in buckets {
            output[bucket.id] = effectiveValue(for: bucket.id)
        }
        return output
    }

    var prevTotal: Double {
        buckets.reduce(0) { $0 + (previousValues[$1.id] ?? 0) }
    }

    var newTotal: Double {
        buckets.reduce(0) { $0 + (effectiveValues[$1.id] ?? 0) }
    }

    var delta: Double {
        newTotal - prevTotal
    }

    var changePct: Double? {
        guard prevTotal > 0 else { return nil }
        return delta / prevTotal
    }

    var nextButtonTitle: String {
        index == buckets.count - 1 ? "Oppsummering" : "Neste"
    }

    var canMoveNext: Bool {
        guard let bucket = currentBucket else { return false }
        return validationMessage(for: bucket.id) == nil
    }

    var canSave: Bool {
        buckets.allSatisfy { validationMessage(for: $0.id) == nil }
    }

    var changedRows: [InvestmentWizardChangeRow] {
        buckets.compactMap { bucket in
            let previous = previousValue(for: bucket.id)
            let current = effectiveValue(for: bucket.id)
            guard abs(current - previous) > 0.0001 else { return nil }
            return InvestmentWizardChangeRow(
                id: bucket.id,
                bucketName: bucket.name,
                previousValue: previous,
                newValue: current
            )
        }
    }

    var changedBucketCount: Int {
        changedRows.count
    }

    func loadInitialState(
        buckets: [InvestmentBucket],
        snapshots: [InvestmentSnapshot],
        selectedMonth: Date? = nil
    ) {
        let resolvedMonth = selectedMonth ?? Date()
        self.buckets = buckets
            .filter(\.isActive)
            .sorted { $0.sortOrder < $1.sortOrder }
        self.snapshots = InvestmentService.sortedSnapshots(snapshots)
        self.selectedMonthDate = DateService.monthBounds(for: resolvedMonth).start
        self.index = -1
        prepareInitialStepStates()
    }

    func start() {
        guard hasBuckets else { return }
        index = 0
    }

    func setSelectedMonth(_ date: Date) {
        selectedMonthDate = DateService.monthBounds(for: date).start
        prepareInitialStepStates()
    }

    func goBack() {
        if isSummary {
            index = max(0, buckets.count - 1)
            return
        }
        if index > 0 {
            index -= 1
        } else {
            index = -1
        }
    }

    func goNext() {
        guard hasBuckets else { return }
        guard canMoveNext else { return }

        if index < buckets.count - 1 {
            index += 1
        } else {
            index = buckets.count
        }
    }

    func jumpToLastStep() {
        guard hasBuckets else { return }
        index = max(0, buckets.count - 1)
    }

    func setMode(_ mode: InvestmentWizardInputMode, for bucketID: String) {
        var state = stepStates[bucketID] ?? InvestmentWizardStepState()
        state.mode = mode
        if mode == .changed && state.inputString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.inputString = Self.formatInputAmount(previousValue(for: bucketID))
        }
        stepStates[bucketID] = state
    }

    func updateInput(_ text: String, for bucketID: String) {
        var state = stepStates[bucketID] ?? InvestmentWizardStepState()
        state.inputString = Self.formatAmountInputLive(text)
        stepStates[bucketID] = state
    }

    func isNewType(_ bucketID: String) -> Bool {
        previousValues[bucketID] == nil
    }

    func previousValue(for bucketID: String) -> Double {
        previousValues[bucketID] ?? 0
    }

    func copyPreviousToChanged() {
        var newStates: [String: InvestmentWizardStepState] = stepStates
        for bucket in buckets {
            newStates[bucket.id] = InvestmentWizardStepState(
                mode: .changed,
                inputString: Self.formatInputAmount(previousValues[bucket.id] ?? 0)
            )
        }
        stepStates = newStates
    }

    func effectiveValue(for bucketID: String) -> Double {
        let state = stepStates[bucketID] ?? InvestmentWizardStepState()
        switch state.mode {
        case .unchanged:
            return max(0, baselineValues[bucketID] ?? 0)
        case .changed:
            return max(0, Self.parseAmount(state.inputString) ?? 0)
        }
    }

    func validationMessage(for bucketID: String) -> String? {
        let state = stepStates[bucketID] ?? InvestmentWizardStepState()
        guard state.mode == .changed else { return nil }
        let trimmed = state.inputString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Skriv inn et beløp eller velg Uendret."
        }
        guard let amount = Self.parseAmount(trimmed), amount >= 0 else {
            return "Beløp må være 0 eller høyere."
        }
        return nil
    }

    @discardableResult
    func saveSnapshot(context: ModelContext) throws -> Bool {
        let isNewSnapshot = !isEditingExistingPeriod
        let values = buckets.map { bucket in
            InvestmentSnapshotValue(
                periodKey: periodKey,
                bucketID: bucket.id,
                amount: effectiveValue(for: bucket.id)
            )
        }
        try InvestmentService.upsertSnapshot(
            context: context,
            periodKey: periodKey,
            capturedAt: selectedMonthDate,
            values: values
        )
        return isNewSnapshot
    }

    static func parseAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "kr", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ",", with: ".")

        guard let value = Double(normalized) else { return nil }
        return value
    }

    static func formatInputAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func formatAmountInputLive(_ rawText: String) -> String {
        let cleaned = rawText
            .replacingOccurrences(of: "kr", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")

        if cleaned.isEmpty { return "" }

        let parts = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integerPart = String(parts.first ?? "")
        let decimalPart = parts.count > 1 ? String(parts[1]).prefix(2) : ""

        let integerValue = Double(integerPart) ?? 0
        let formattedInteger = formatInputAmount(integerValue)

        if parts.count > 1 {
            return "\(formattedInteger),\(decimalPart)"
        }

        return formattedInteger
    }

    private func prepareInitialStepStates() {
        var newStates: [String: InvestmentWizardStepState] = [:]
        for bucket in buckets {
            newStates[bucket.id] = InvestmentWizardStepState(
                mode: .unchanged,
                inputString: Self.formatInputAmount(previousValue(for: bucket.id))
            )
        }

        stepStates = newStates
    }

    private func valuesDictionary(from snapshot: InvestmentSnapshot?) -> [String: Double] {
        guard let snapshot else { return [:] }
        return Dictionary(uniqueKeysWithValues: snapshot.bucketValues.map { ($0.bucketID, $0.amount) })
    }
}
