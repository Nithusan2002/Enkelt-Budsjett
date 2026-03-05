import Foundation
import SwiftData
import Testing
@testable import Simple_Budget___Budskjett_planlegger_gjort_enkelt

struct InvestmentsFeatureTests {

    @Test
    @MainActor
    func investmentWizardEffectiveValuesAndTotalsFollowRules() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        let previousPeriodDate = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? .now
        let currentPeriodDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? .now
        let previousPeriodKey = DateService.periodKey(from: previousPeriodDate)

        let buckets = [
            InvestmentBucket(id: "bucket_fond", name: "Fond", isDefault: true, sortOrder: 1),
            InvestmentBucket(id: "bucket_aksjer", name: "Aksjer", isDefault: true, sortOrder: 2),
            InvestmentBucket(id: "bucket_ny", name: "Ny type", isDefault: false, sortOrder: 3)
        ]
        buckets.forEach { context.insert($0) }
        let previousValues = [
            InvestmentSnapshotValue(periodKey: previousPeriodKey, bucketID: "bucket_fond", amount: 100_000),
            InvestmentSnapshotValue(periodKey: previousPeriodKey, bucketID: "bucket_aksjer", amount: 25_000)
        ]
        context.insert(
            InvestmentSnapshot(
                periodKey: previousPeriodKey,
                capturedAt: previousPeriodDate,
                totalValue: 125_000,
                bucketValues: previousValues
            )
        )
        try context.save()

        let viewModel = InvestmentCheckInWizardViewModel()
        viewModel.loadInitialState(buckets: buckets, snapshots: try context.fetch(FetchDescriptor<InvestmentSnapshot>()), selectedMonth: currentPeriodDate)
        viewModel.start()

        viewModel.setMode(.unchanged, for: "bucket_fond")
        viewModel.setMode(.changed, for: "bucket_aksjer")
        viewModel.updateInput("26 500", for: "bucket_aksjer")
        viewModel.setMode(.unchanged, for: "bucket_ny")

        #expect(viewModel.effectiveValue(for: "bucket_fond") == 100_000)
        #expect(viewModel.effectiveValue(for: "bucket_aksjer") == 26_500)
        #expect(viewModel.effectiveValue(for: "bucket_ny") == 0)
        #expect(viewModel.prevTotal == 125_000)
        #expect(viewModel.newTotal == 126_500)
        #expect(viewModel.delta == 1_500)
    }

    @Test
    @MainActor
    func investmentWizardSortOrderAndNewBucketInclusion() {
        let buckets = [
            InvestmentBucket(id: "b3", name: "Tre", isDefault: false, sortOrder: 3),
            InvestmentBucket(id: "b1", name: "En", isDefault: false, sortOrder: 1),
            InvestmentBucket(id: "b2", name: "To", isDefault: false, sortOrder: 2),
            InvestmentBucket(id: "inactive", name: "Skjult", isDefault: false, isActive: false, sortOrder: 0)
        ]
        let viewModel = InvestmentCheckInWizardViewModel()
        viewModel.loadInitialState(buckets: buckets, snapshots: [], selectedMonth: .now)

        #expect(viewModel.buckets.map(\.id) == ["b1", "b2", "b3"])
        #expect(viewModel.isNewType("b1"))
        #expect(viewModel.isNewType("b2"))
        #expect(viewModel.isNewType("b3"))
    }

    @Test
    @MainActor
    func investmentWizardUpsertsSnapshotPerPeriodKey() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let currentPeriodDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? .now
        let currentPeriodKey = DateService.periodKey(from: currentPeriodDate)

        let bucket = InvestmentBucket(id: "bucket_fond", name: "Fond", isDefault: true, sortOrder: 1)
        context.insert(bucket)
        let existing = InvestmentSnapshot(
            periodKey: currentPeriodKey,
            capturedAt: currentPeriodDate,
            totalValue: 1000,
            bucketValues: [
                InvestmentSnapshotValue(periodKey: currentPeriodKey, bucketID: bucket.id, amount: 1000)
            ]
        )
        context.insert(existing)
        try context.save()

        let viewModel = InvestmentCheckInWizardViewModel()
        viewModel.loadInitialState(
            buckets: [bucket],
            snapshots: try context.fetch(FetchDescriptor<InvestmentSnapshot>()),
            selectedMonth: currentPeriodDate
        )
        viewModel.start()
        viewModel.setMode(.changed, for: bucket.id)
        viewModel.updateInput("2 500", for: bucket.id)
        viewModel.goNext()
        try viewModel.saveSnapshot(context: context)

        let snapshots = try context.fetch(FetchDescriptor<InvestmentSnapshot>())
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.totalValue == 2500)

        let values = snapshots.first?.bucketValues ?? []
        #expect(values.count == 1)
        #expect(values.contains(where: { $0.bucketID == bucket.id && $0.amount == 2500 }))
    }

    @Test
    @MainActor
    func investmentWizardUsesExistingPeriodAsBaselineWhenEditing() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        let bucket = InvestmentBucket(id: "bucket_fond", name: "Fond", isDefault: true, sortOrder: 1)
        context.insert(bucket)

        let previousDate = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? .now
        let currentDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? .now
        let previousKey = DateService.periodKey(from: previousDate)
        let currentKey = DateService.periodKey(from: currentDate)

        context.insert(
            InvestmentSnapshot(
                periodKey: previousKey,
                capturedAt: previousDate,
                totalValue: 100_000,
                bucketValues: [
                    InvestmentSnapshotValue(periodKey: previousKey, bucketID: bucket.id, amount: 100_000)
                ]
            )
        )
        context.insert(
            InvestmentSnapshot(
                periodKey: currentKey,
                capturedAt: currentDate,
                totalValue: 120_000,
                bucketValues: [
                    InvestmentSnapshotValue(periodKey: currentKey, bucketID: bucket.id, amount: 120_000)
                ]
            )
        )
        try context.save()

        let viewModel = InvestmentCheckInWizardViewModel()
        viewModel.loadInitialState(
            buckets: [bucket],
            snapshots: try context.fetch(FetchDescriptor<InvestmentSnapshot>()),
            selectedMonth: currentDate
        )

        #expect(viewModel.isEditingExistingPeriod)
        #expect(viewModel.previousValues[bucket.id] == 100_000)
        #expect(viewModel.existingPeriodValues[bucket.id] == 120_000)
        #expect(viewModel.previousValue(for: bucket.id) == 120_000)
        #expect(viewModel.effectiveValue(for: bucket.id) == 120_000)
    }

    @Test
    @MainActor
    func investmentWizardCopyPreviousUsesPreviousMonthValues() throws {
        let container = try TestModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        let bucket = InvestmentBucket(id: "bucket_fond", name: "Fond", isDefault: true, sortOrder: 1)
        context.insert(bucket)

        let previousDate = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? .now
        let currentDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? .now
        let previousKey = DateService.periodKey(from: previousDate)
        let currentKey = DateService.periodKey(from: currentDate)

        context.insert(
            InvestmentSnapshot(
                periodKey: previousKey,
                capturedAt: previousDate,
                totalValue: 100_000,
                bucketValues: [
                    InvestmentSnapshotValue(periodKey: previousKey, bucketID: bucket.id, amount: 100_000)
                ]
            )
        )
        context.insert(
            InvestmentSnapshot(
                periodKey: currentKey,
                capturedAt: currentDate,
                totalValue: 120_000,
                bucketValues: [
                    InvestmentSnapshotValue(periodKey: currentKey, bucketID: bucket.id, amount: 120_000)
                ]
            )
        )
        try context.save()

        let viewModel = InvestmentCheckInWizardViewModel()
        viewModel.loadInitialState(
            buckets: [bucket],
            snapshots: try context.fetch(FetchDescriptor<InvestmentSnapshot>()),
            selectedMonth: currentDate
        )
        viewModel.copyPreviousToChanged()

        #expect(viewModel.stepStates[bucket.id]?.mode == .changed)
        #expect(viewModel.effectiveValue(for: bucket.id) == 100_000)
    }

    @Test
    @MainActor
    func developmentChartBuilderFiltersYearToDateAndLast12() {
        let bucket = InvestmentBucket(id: "funds", name: "Fond", isDefault: true, sortOrder: 1)
        let now = Date()
        let snapshots: [InvestmentSnapshot] = (0..<16).compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .month, value: -offset, to: now) else { return nil }
            let key = DateService.periodKey(from: date)
            let value = 10_000 + Double((15 - offset) * 1_000)
            let row = InvestmentSnapshotValue(periodKey: key, bucketID: bucket.id, amount: value)
            return InvestmentSnapshot(periodKey: key, capturedAt: date, totalValue: value, bucketValues: [row])
        }
        .sorted { $0.periodKey < $1.periodKey }

        let ytd = InvestmentsDevelopmentChartDataBuilder.points(
            snapshots: snapshots,
            buckets: [bucket],
            period: .sixMonths,
            now: now
        )
        #expect(ytd.count <= 6)

        let last12 = InvestmentsDevelopmentChartDataBuilder.points(
            snapshots: snapshots,
            buckets: [bucket],
            period: .last12Months,
            now: now
        )
        #expect(last12.count <= 12)
        #expect(last12.count > 1)
    }

    @Test
    @MainActor
    func developmentChartBuilderFillsMissingBucketValuesWithZero() {
        let fund = InvestmentBucket(id: "funds", name: "Fond", isDefault: true, sortOrder: 1)
        let stock = InvestmentBucket(id: "stocks", name: "Aksjer", isDefault: true, sortOrder: 2)
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? .now
        let key = DateService.periodKey(from: date)
        let snapshot = InvestmentSnapshot(
            periodKey: key,
            capturedAt: date,
            totalValue: 50_000,
            bucketValues: [
                InvestmentSnapshotValue(periodKey: key, bucketID: fund.id, amount: 50_000)
            ]
        )

        let points = InvestmentsDevelopmentChartDataBuilder.points(
            snapshots: [snapshot],
            buckets: [fund, stock],
            period: .sixMonths,
            now: date
        )

        #expect(points.count == 1)
        #expect(points[0].buckets.count == 2)
        #expect(points[0].buckets.first(where: { $0.bucketID == stock.id })?.amount == 0)
    }

    @Test
    @MainActor
    func developmentChartDeltaSincePreviousIsCorrect() {
        let date1 = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .now
        let date2 = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? .now
        let date3 = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? .now
        let points = [
            InvestmentsDevelopmentChartPoint(id: "2026-01", date: date1, periodKey: "2026-01", total: 100_000, buckets: []),
            InvestmentsDevelopmentChartPoint(id: "2026-02", date: date2, periodKey: "2026-02", total: 103_500, buckets: []),
            InvestmentsDevelopmentChartPoint(id: "2026-03", date: date3, periodKey: "2026-03", total: 102_000, buckets: [])
        ]

        let secondDelta = InvestmentsDevelopmentChartDataBuilder.deltaSincePrevious(for: points[1], in: points)
        let thirdDelta = InvestmentsDevelopmentChartDataBuilder.deltaSincePrevious(for: points[2], in: points)

        #expect(secondDelta == 3_500)
        #expect(thirdDelta == -1_500)
    }

    @Test
    @MainActor
    func investmentsHeroUsesReminderClockTimeForSameDayCheckInText() {
        let viewModel = InvestmentsViewModel()
        let preference = UserPreference(
            checkInReminderEnabled: true,
            checkInReminderDay: 5,
            checkInReminderHour: 19,
            checkInReminderMinute: 0
        )
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 13, minute: 0)) ?? .now

        let hero = viewModel.heroData(
            snapshots: [],
            preference: preference,
            now: now
        )

        #expect(hero.nextCheckInText == "Neste: i dag")
    }

    @Test
    @MainActor
    func investmentsHeroMovesToNextMonthAfterReminderTimeHasPassedSameDay() {
        let viewModel = InvestmentsViewModel()
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 20, minute: 30)) ?? .now
        let preference = UserPreference(
            checkInReminderEnabled: true,
            checkInReminderDay: 5,
            checkInReminderHour: 8,
            checkInReminderMinute: 0
        )

        let hero = viewModel.heroData(
            snapshots: [],
            preference: preference,
            now: now
        )

        #expect(hero.nextCheckInText == "Neste: om 31 dager")
    }
}
