import SwiftUI
import SwiftData
import Charts

struct InvestmentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InvestmentBucket.sortOrder) private var buckets: [InvestmentBucket]
    @Query(sort: \InvestmentSnapshot.periodKey) private var snapshots: [InvestmentSnapshot]
    @Query private var preferences: [UserPreference]
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]
    @Query private var accounts: [Account]

    @StateObject private var viewModel = InvestmentsViewModel()

    private var latest: InvestmentSnapshot? { viewModel.latestSnapshot(snapshots) }
    private var hero: InvestmentHeroData { viewModel.heroData(snapshots: snapshots, preference: preferences.first) }
    private var bucketRows: [InvestmentBucketRowData] {
        viewModel.bucketRows(buckets: buckets, snapshots: snapshots, range: viewModel.selectedRange)
    }
    private var filteredSnapshots: [InvestmentSnapshot] {
        viewModel.filteredSnapshots(snapshots, range: viewModel.selectedRange)
    }

    private var snapshotToken: String {
        snapshots
            .map { "\($0.periodKey)-\($0.totalValue)" }
            .joined(separator: "|")
    }

    var body: some View {
        List {
            heroSection
            developmentSection
            insightSection
            holdingsSection
            distributionSection
            historySection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Investeringer")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showCheckIn = true
                } label: {
                    Label("Oppdater", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
        .refreshable {
            viewModel.refreshData(snapshots: snapshots)
        }
        .sheet(isPresented: $viewModel.showCheckIn) {
            InvestmentCheckInView(buckets: buckets, latestSnapshot: latest)
        }
        .sheet(item: $viewModel.selectedBucketForEdit) { bucket in
            BucketQuickUpdateSheet(bucket: bucket, latestSnapshot: latest)
        }
        .navigationDestination(for: String.self) { bucketID in
            if let bucket = buckets.first(where: { $0.id == bucketID }) {
                BucketDetailView(bucket: bucket, snapshots: snapshots)
            } else {
                Text("Finner ikke beholdning")
                    .appSecondaryStyle()
            }
        }
        .onAppear {
            viewModel.onAppear(preference: preferences.first, snapshots: snapshots)
        }
        .onChange(of: snapshotToken) { _, _ in
            viewModel.refreshData(snapshots: snapshots)
        }
    }

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Total beholdning")
                        .appSecondaryStyle()
                    Text(formatNOK(viewModel.displayedTotal))
                        .appBigNumberStyle()
                        .foregroundStyle(AppTheme.textPrimary)
                        .contentTransition(.numericText(value: viewModel.displayedTotal))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(2)

                    if viewModel.showTrendChip {
                        trendChip(changeKr: hero.changeKr, changePct: hero.changePct)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                sparkline(series: viewModel.totalSparkline(snapshots: snapshots, range: .last12Months), color: AppTheme.primary)
                    .frame(height: 56)

                HStack(spacing: 8) {
                    chip(text: hero.lastCheckInText, icon: "calendar")
                    chip(text: hero.nextCheckInText, icon: "clock")
                    chip(text: hero.reminderText, icon: "bell")
                    Spacer()
                }
                Text("Basert på totalsummene du legger inn.")
                    .appSecondaryStyle()

                Button {
                    viewModel.showCheckIn = true
                } label: {
                    Label("Oppdater nå", systemImage: "pencil.circle.fill")
                }
                .appCTAStyle()
                .buttonStyle(.bordered)
                .tint(AppTheme.primary.opacity(0.9))
            }
            .padding(16)
            .background(AppTheme.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppTheme.divider, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    private var developmentSection: some View {
        Section("Utvikling") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Utvikling")
                        .appCardTitleStyle()
                    Spacer()
                    Picker("Periode", selection: $viewModel.selectedRange.animation(.easeInOut(duration: 0.35))) {
                        Text("I år").tag(GraphViewRange.yearToDate)
                        Text("Siste 12 mnd").tag(GraphViewRange.last12Months)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                if filteredSnapshots.count < 2 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Legg inn én måned til for å se utvikling.")
                            .appSecondaryStyle()
                        Button("Oppdater verdier") {
                            viewModel.showCheckIn = true
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                } else {
                    Chart(filteredSnapshots, id: \.periodKey) { snapshot in
                        AreaMark(
                            x: .value("Dato", snapshot.capturedAt),
                            y: .value("Total", snapshot.totalValue)
                        )
                        .foregroundStyle(AppTheme.secondary.opacity(0.25))

                        LineMark(
                            x: .value("Dato", snapshot.capturedAt),
                            y: .value("Total", snapshot.totalValue)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(AppTheme.secondary)
                    }
                    .frame(height: 170)
                    .chartXAxis(.hidden)
                    .animation(.easeInOut(duration: 0.5), value: viewModel.selectedRange)
                }
            }
            .padding(14)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.divider, lineWidth: 1)
            )
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    private var insightSection: some View {
        let insight = viewModel.insight(
            snapshots: snapshots,
            buckets: buckets,
            goal: goals.first(where: \.isActive),
            accounts: accounts
        )

        return Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(insight.title)
                    .appCardTitleStyle()
                Text(insight.detail)
                    .appBodyStyle()
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(14)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.divider, lineWidth: 1)
            )
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    private var holdingsSection: some View {
        Section("Beholdning") {
            if bucketRows.isEmpty {
                Text("Ingen aktive beholdninger ennå.")
                    .appSecondaryStyle()
            } else {
                ForEach(bucketRows) { row in
                    NavigationLink(value: row.id) {
                        bucketRow(row)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if let bucket = buckets.first(where: { $0.id == row.id }) {
                            Button("Rediger") {
                                viewModel.selectedBucketForEdit = bucket
                            }
                            .tint(AppTheme.secondary)

                            Button("Skjul", role: .destructive) {
                                viewModel.hideBucket(bucket, context: modelContext)
                            }
                        }
                    }
                }
            }
        }
    }

    private var distributionSection: some View {
        let data = viewModel.distributionData(latestSnapshot: latest, buckets: buckets)
        return Section("Fordeling") {
            if data.isEmpty {
                Text("Fordeling vises etter første snapshot.")
                    .appSecondaryStyle()
            } else if viewModel.shouldShowDonut(distributionData: data) {
                Chart(data, id: \.bucketID) { item in
                    SectorMark(
                        angle: .value("Beløp", item.amount),
                        innerRadius: .ratio(0.58),
                        angularInset: 2
                    )
                    .foregroundStyle(AppTheme.portfolioColor(for: item.bucketName))
                }
                .frame(height: 180)

                ForEach(data, id: \.bucketID) { item in
                    HStack {
                        Circle()
                            .fill(AppTheme.portfolioColor(for: item.bucketName))
                            .frame(width: 10, height: 10)
                        Text(item.bucketName)
                            .appBodyStyle()
                        Spacer()
                        Text(formatPercent(item.percent))
                            .appSecondaryStyle()
                        Text(formatNOK(item.amount))
                            .appBodyStyle()
                            .monospacedDigit()
                    }
                }
            } else if let only = data.first {
                HStack {
                    Circle()
                        .fill(AppTheme.portfolioColor(for: only.bucketName))
                        .frame(width: 10, height: 10)
                    Text("\(only.bucketName): \(formatPercent(only.percent))")
                        .appBodyStyle()
                    Spacer()
                    Text(formatNOK(only.amount))
                        .appBodyStyle()
                        .monospacedDigit()
                }
            }
        }
    }

    private var historySection: some View {
        let history = viewModel.latestHistory(snapshots)
        return Section("Siste oppdateringer") {
            if history.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Legg inn første snapshot (tar 20 sek)")
                        .appCardTitleStyle()
                    Text("Grovt tall er nok.")
                        .appSecondaryStyle()
                    Button("Oppdater verdier") {
                        viewModel.showCheckIn = true
                    }
                    .appCTAStyle()
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
                }
                .padding(12)
            } else {
                ForEach(history, id: \.periodKey) { snapshot in
                    HStack {
                        Text(formatDate(snapshot.capturedAt))
                            .appBodyStyle()
                        Spacer()
                        Text(formatNOK(snapshot.totalValue))
                            .appBodyStyle()
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func trendChip(changeKr: Double, changePct: Double?) -> some View {
        let isPositive = changeKr >= 0
        let arrow = isPositive ? "▲" : "▼"
        let valueText = isPositive
            ? "+\(formatNOK(abs(changeKr)))"
            : "-\(formatNOK(abs(changeKr)))"
        let pctText = changePct.map { " (\(formatPercent($0)))" } ?? ""

        return Text("\(arrow) \(valueText)\(pctText) siden forrige insjekk")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isPositive ? AppTheme.positive : AppTheme.negative)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background((isPositive ? AppTheme.positive : AppTheme.negative).opacity(0.12), in: Capsule())
    }

    private func chip(text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(AppTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(AppTheme.divider, lineWidth: 1))
    }

    private func bucketRow(_ row: InvestmentBucketRowData) -> some View {
        let changeColor: Color = {
            if row.changeKr > 0 { return AppTheme.positive }
            if row.changeKr < 0 { return AppTheme.negative }
            return AppTheme.textSecondary
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(AppTheme.portfolioColor(for: row.name))
                    .frame(width: 9, height: 9)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .appCardTitleStyle()
                        .lineLimit(1)
                    Text(formatNOK(row.amount))
                        .appBodyStyle()
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                sparkline(series: row.sparkline, color: AppTheme.portfolioColor(for: row.name))
                    .frame(width: 78, height: 30)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(changeAmountText(changeKr: row.changeKr))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(changeColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    if let pct = row.changePct {
                        Text("(\(formatPercent(pct)))")
                            .font(.caption)
                            .foregroundStyle(changeColor)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .frame(width: 108, alignment: .trailing)
            }

            Text("Andel \(formatPercent(row.shareOfPortfolio)) · Sist \(formatDate(row.lastUpdated ?? .now))")
                .appSecondaryStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 4)
    }

    private func sparkline(series: [Double], color: Color) -> some View {
        let points = viewModel.bucketSparklinePoints(series)
        return Chart(points) { point in
            LineMark(
                x: .value("Index", point.index),
                y: .value("Beløp", point.value)
            )
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .foregroundStyle(color)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot.background(Color.clear)
        }
    }

    private func changeAmountText(changeKr: Double) -> String {
        changeKr >= 0 ? "+\(formatNOK(abs(changeKr)))" : "-\(formatNOK(abs(changeKr)))"
    }

}

private struct BucketDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let bucket: InvestmentBucket
    let snapshots: [InvestmentSnapshot]

    @State private var showQuickUpdate = false

    private var sorted: [InvestmentSnapshot] { InvestmentService.sortedSnapshots(snapshots) }
    private var latestValue: Double {
        sorted.last?.bucketValues.first(where: { $0.bucketID == bucket.id })?.amount ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(bucket.name)
                        .appCardTitleStyle()
                    Text(formatNOK(latestValue))
                        .appBigNumberStyle()
                        .foregroundStyle(AppTheme.textPrimary)
                    Button("Oppdater bare denne") {
                        showQuickUpdate = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
                }
                .padding()
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))

                if sorted.isEmpty {
                    Text("Ingen historikk ennå.")
                        .appSecondaryStyle()
                } else {
                    Chart(sorted, id: \.periodKey) { snapshot in
                        let amount = snapshot.bucketValues.first(where: { $0.bucketID == bucket.id })?.amount ?? 0
                        LineMark(
                            x: .value("Dato", snapshot.capturedAt),
                            y: .value("Beløp", amount)
                        )
                        .foregroundStyle(AppTheme.portfolioColor(for: bucket.name))
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    .frame(height: 220)
                    .chartXAxis(.hidden)

                    VStack(spacing: 8) {
                        ForEach(sorted.reversed(), id: \.periodKey) { snapshot in
                            let amount = snapshot.bucketValues.first(where: { $0.bucketID == bucket.id })?.amount ?? 0
                            HStack {
                                Text(formatDate(snapshot.capturedAt))
                                    .appBodyStyle()
                                Spacer()
                                Text(formatNOK(amount))
                                    .appBodyStyle()
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(bucket.name)
        .background(AppTheme.background)
        .sheet(isPresented: $showQuickUpdate) {
            BucketQuickUpdateSheet(bucket: bucket, latestSnapshot: sorted.last)
        }
        .onDisappear {
            try? modelContext.save()
        }
    }
}

private struct BucketQuickUpdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let bucket: InvestmentBucket
    let latestSnapshot: InvestmentSnapshot?

    @State private var amount: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Ny verdi") {
                    Text(bucket.name)
                        .appBodyStyle()
                    TextField(
                        "0",
                        value: $amount,
                        format: .number.precision(.fractionLength(0...2))
                    )
                    .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Oppdater beholdning")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        saveSingleBucket()
                        dismiss()
                    }
                    .appCTAStyle()
                }
            }
            .onAppear {
                amount = latestSnapshot?.bucketValues.first(where: { $0.bucketID == bucket.id })?.amount ?? 0
            }
        }
    }

    private func saveSingleBucket() {
        let periodKey = DateService.periodKey(from: .now)
        let descriptor = FetchDescriptor<InvestmentSnapshot>(predicate: #Predicate { $0.periodKey == periodKey })
        let existing = try? modelContext.fetch(descriptor).first

        if let existing {
            if let index = existing.bucketValues.firstIndex(where: { $0.bucketID == bucket.id }) {
                existing.bucketValues[index].amount = amount
            } else {
                existing.bucketValues.append(InvestmentSnapshotValue(periodKey: periodKey, bucketID: bucket.id, amount: amount))
            }
            existing.capturedAt = .now
            existing.totalValue = existing.bucketValues.reduce(0) { $0 + $1.amount }
        } else {
            let value = InvestmentSnapshotValue(periodKey: periodKey, bucketID: bucket.id, amount: amount)
            modelContext.insert(InvestmentSnapshot(periodKey: periodKey, capturedAt: .now, totalValue: amount, bucketValues: [value]))
        }
        try? modelContext.save()
    }
}

struct InvestmentCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let buckets: [InvestmentBucket]
    let latestSnapshot: InvestmentSnapshot?
    @StateObject private var viewModel = InvestmentCheckInViewModel()

    private var periodKey: String { viewModel.periodKey() }
    private var total: Double { viewModel.total() }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dato for insjekk") {
                    DatePicker(
                        "Denne innsjekken gjelder for",
                        selection: $viewModel.selectedDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)
                }

                Section("Beholdning") {
                    ForEach(buckets.filter(\.isActive)) { bucket in
                        HStack {
                            Text(bucket.name)
                                .appBodyStyle()
                            Spacer()
                            TextField(
                                "0",
                                value: binding(for: bucket.id),
                                format: .number.precision(.fractionLength(0...2))
                            )
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 120)
                        }
                    }
                }

                Section("Oppsummering") {
                    row("Valgt dato", 0, textValue: formatDate(viewModel.selectedDate))
                    row("Ny total", total)
                    row("Forrige total", latestSnapshot?.totalValue ?? 0)
                    row("Endring", total - (latestSnapshot?.totalValue ?? 0))
                }
            }
            .navigationTitle("Oppdater verdier")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        saveSnapshot()
                        dismiss()
                    }
                    .appCTAStyle()
                }
            }
            .onAppear {
                viewModel.selectedDate = latestSnapshot?.capturedAt ?? .now
                viewModel.prepareValues(buckets: buckets, latestSnapshot: latestSnapshot)
            }
        }
    }

    private func row(_ title: String, _ value: Double, textValue: String? = nil) -> some View {
        HStack {
            Text(title)
                .appBodyStyle()
            Spacer()
            if let textValue {
                Text(textValue)
                    .appBodyStyle()
                    .monospacedDigit()
            } else {
                Text(formatNOK(value))
                    .monospacedDigit()
            }
        }
    }

    private func binding(for bucketID: String) -> Binding<Double> {
        Binding(
            get: { viewModel.binding(for: bucketID) },
            set: { viewModel.setBinding($0, for: bucketID) }
        )
    }

    private func saveSnapshot() {
        viewModel.saveSnapshot(
            context: modelContext,
            periodKey: periodKey,
            total: total,
            capturedAt: viewModel.selectedDate
        )
    }
}
