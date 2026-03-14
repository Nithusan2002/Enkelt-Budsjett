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

struct InvestmentWizardBucketNavItem: Identifiable {
    let id: String
    let title: String
    let isCurrent: Bool
    let isCompleted: Bool
}

@MainActor
final class InvestmentCheckInWizardViewModel: ObservableObject {
    @Published var selectedMonthDate: Date = DateService.monthBounds(for: .now).start
    @Published var index: Int = -1 // -1 = intro, 0...N-1 = bucket steps, N = summary
    @Published var stepStates: [String: InvestmentWizardStepState] = [:]

    private(set) var buckets: [InvestmentBucket] = []
    private(set) var snapshots: [InvestmentSnapshot] = []
    private var visitedBucketIDs: Set<String> = []

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

    var existingSnapshotForSelectedPeriod: InvestmentSnapshot? {
        InvestmentService.snapshot(for: periodKey, snapshots: snapshots)
    }

    var effectiveValues: [String: Double] {
        var output: [String: Double] = [:]
        for bucket in buckets {
            output[bucket.id] = effectiveValue(for: bucket.id)
        }
        return output
    }

    var bucketNavigationItems: [InvestmentWizardBucketNavItem] {
        buckets.enumerated().map { offset, bucket in
            InvestmentWizardBucketNavItem(
                id: bucket.id,
                title: bucket.name,
                isCurrent: offset == index,
                isCompleted: visitedBucketIDs.contains(bucket.id) && isBucketCompleted(bucket.id)
            )
        }
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

    var nextButtonTitle: String { "Neste" }

    var isLastBucketStep: Bool {
        guard hasBuckets else { return false }
        return index == buckets.count - 1
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
        self.visitedBucketIDs = []
        prepareInitialStepStates()
    }

    func start() {
        guard hasBuckets else { return }
        index = 0
        if let firstID = buckets.first?.id {
            visitedBucketIDs.insert(firstID)
        }
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
            if index >= 0, index < buckets.count {
                visitedBucketIDs.insert(buckets[index].id)
            }
        } else {
            index = buckets.count
        }
    }

    func jumpToLastStep() {
        guard hasBuckets else { return }
        index = max(0, buckets.count - 1)
    }

    func jump(to bucketID: String) {
        guard let bucketIndex = buckets.firstIndex(where: { $0.id == bucketID }) else { return }
        index = bucketIndex
        visitedBucketIDs.insert(bucketID)
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

    func addToInput(_ increment: Double, for bucketID: String) {
        let current = effectiveValue(for: bucketID)
        let updated = max(0, current + increment)
        var state = stepStates[bucketID] ?? InvestmentWizardStepState()
        state.mode = .changed
        state.inputString = Self.formatInputAmount(updated)
        stepStates[bucketID] = state
    }

    func addBucketDuringCheckIn(
        context: ModelContext,
        name: String,
        colorHex: String
    ) throws {
        let existingBuckets = try context.fetch(FetchDescriptor<InvestmentBucket>())
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw InvestmentWizardAddBucketError.emptyName
        }

        let bucket: InvestmentBucket
        if let existing = existingBuckets.first(where: {
            $0.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            if existing.isActive {
                throw InvestmentWizardAddBucketError.duplicateName
            }

            existing.name = trimmedName
            existing.colorHex = colorHex
            existing.isActive = true
            existing.sortOrder = (existingBuckets.map(\.sortOrder).max() ?? 0) + 1
            try context.guardedSave(feature: "Investments", operation: "reactivate_bucket")
            bucket = existing
        } else {
            let id = uniqueBucketID(for: trimmedName, existingBuckets: existingBuckets)
            let sortOrder = (existingBuckets.map(\.sortOrder).max() ?? 0) + 1
            let created = InvestmentBucket(
                id: id,
                name: trimmedName,
                colorHex: colorHex,
                isDefault: false,
                isActive: true,
                sortOrder: sortOrder
            )
            context.insert(created)
            try context.guardedSave(feature: "Investments", operation: "add_bucket")
            bucket = created
        }

        appendBucketToWizard(bucket)
    }

    func isNewType(_ bucketID: String) -> Bool {
        previousValues[bucketID] == nil
    }

    func previousValue(for bucketID: String) -> Double {
        previousValues[bucketID] ?? 0
    }

    func hasStoredDelta(for bucketID: String) -> Bool {
        guard !existingPeriodValues.isEmpty else { return false }
        let existing = existingPeriodValues[bucketID] ?? 0
        let previous = previousValue(for: bucketID)
        return abs(existing - previous) > 0.0001
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
        AppAmountInput.parse(text)
    }

    static func formatInputAmount(_ value: Double) -> String {
        AppAmountInput.format(value)
    }

    static func formatAmountInputLive(_ rawText: String) -> String {
        AppAmountInput.formatLive(rawText)
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

    private func appendBucketToWizard(_ bucket: InvestmentBucket) {
        if let existingIndex = buckets.firstIndex(where: { $0.id == bucket.id }) {
            buckets[existingIndex] = bucket
        } else {
            buckets.append(bucket)
        }
        buckets.sort { $0.sortOrder < $1.sortOrder }
        stepStates[bucket.id] = InvestmentWizardStepState(
            mode: .unchanged,
            inputString: Self.formatInputAmount(previousValue(for: bucket.id))
        )
        if let newIndex = buckets.firstIndex(where: { $0.id == bucket.id }) {
            index = newIndex
            visitedBucketIDs.insert(bucket.id)
        }
    }

    private func isBucketCompleted(_ bucketID: String) -> Bool {
        validationMessage(for: bucketID) == nil
    }

    private func valuesDictionary(from snapshot: InvestmentSnapshot?) -> [String: Double] {
        guard let snapshot else { return [:] }
        return snapshot.bucketValues.reduce(into: [:]) { result, value in
            result[value.bucketID, default: 0] += value.amount
        }
    }

    private func uniqueBucketID(for name: String, existingBuckets: [InvestmentBucket]) -> String {
        let base = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "nb_NO"))
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        var candidate = "bucket_\(base)"
        var suffix = 2
        let existingIDs = Set(existingBuckets.map(\.id))
        while existingIDs.contains(candidate) {
            candidate = "bucket_\(base)_\(suffix)"
            suffix += 1
        }
        return candidate
    }
}

enum InvestmentWizardAddBucketError: LocalizedError {
    case emptyName
    case duplicateName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Skriv inn et navn på beholdningstypen."
        case .duplicateName:
            return "Denne beholdningstypen finnes allerede."
        }
    }
}
