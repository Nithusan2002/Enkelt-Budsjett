import SwiftUI
import SwiftData
import Charts

struct InvestmentsView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InvestmentBucket.sortOrder) private var buckets: [InvestmentBucket]
    @Query(sort: \InvestmentSnapshot.periodKey) private var snapshots: [InvestmentSnapshot]
    @Query private var preferences: [UserPreference]

    @StateObject private var viewModel = InvestmentsViewModel()
    @State private var showFullHistory = false
    @State private var selectedDevelopmentDate: Date?

    private enum SectionAnchor: String {
        case development
        case distribution
    }

    private var latest: InvestmentSnapshot? { viewModel.latestSnapshot(snapshots) }
    private var hero: InvestmentHeroData { viewModel.heroData(snapshots: snapshots, preference: preferences.first) }
    private var bucketRows: [InvestmentBucketRowData] {
        viewModel.bucketRows(buckets: buckets, snapshots: snapshots, range: viewModel.selectedRange)
    }
    private var filteredSnapshots: [InvestmentSnapshot] {
        viewModel.filteredSnapshots(snapshots, range: viewModel.selectedRange)
    }
    private var activeBuckets: [InvestmentBucket] {
        buckets.filter(\.isActive)
    }

    private var snapshotToken: String {
        snapshots
            .map { "\($0.periodKey)-\($0.totalValue)" }
            .joined(separator: "|")
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                heroSection
                developmentSection
                    .id(SectionAnchor.development.rawValue)
                distributionSection
                    .id(SectionAnchor.distribution.rawValue)
                holdingsSection
                historySection
                administrationSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Investeringer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openCheckIn()
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
            .sheet(isPresented: $viewModel.showAddBucketSheet) {
                AddInvestmentBucketSheet(
                    name: $viewModel.newBucketName,
                    selectedColorHex: $viewModel.selectedBucketColorHex,
                    errorMessage: viewModel.addBucketError
                ) {
                    viewModel.addBucket(context: modelContext, existingBuckets: buckets)
                } onCancel: {
                    viewModel.resetAddBucketState()
                }
            }
            .sheet(item: $viewModel.selectedBucketForEdit) { bucket in
                EditInvestmentBucketSheet(
                    bucket: bucket,
                    existingBuckets: buckets
                )
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
                viewModel.ensureDefaultBuckets(context: modelContext, existingBuckets: buckets)
                viewModel.onAppear(preference: preferences.first, snapshots: snapshots)
            }
            .onChange(of: snapshotToken) { _, _ in
                viewModel.refreshData(snapshots: snapshots)
            }
            .onChange(of: navigationState.investmentsFocus) { _, focus in
                guard let focus else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(focus.rawValue, anchor: .top)
                }
                navigationState.investmentsFocus = nil
            }
        }
    }

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total beholdning")
                            .appSecondaryStyle()
                        Text("Basert på totalsummene du legger inn.")
                            .appSecondaryStyle()
                    }
                    Spacer()
                    Button {
                        openCheckIn()
                    } label: {
                        Label("Oppdater", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(AppTheme.primary)
                }

                Text(formatNOK(viewModel.displayedTotal))
                    .appBigNumberStyle()
                    .foregroundStyle(AppTheme.textPrimary)
                    .contentTransition(.numericText(value: viewModel.displayedTotal))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(2)

                if latest == nil {
                    Text("Legg inn første snapshot. Grovt tall holder.")
                        .appSecondaryStyle()
                } else if viewModel.showTrendChip {
                    trendChip(changeKr: hero.changeKr, changePct: hero.changePct)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !snapshots.isEmpty {
                    sparkline(series: viewModel.totalSparkline(snapshots: snapshots, range: .last12Months), color: AppTheme.primary)
                        .frame(height: 56)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 6)
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    heroMetaRow(icon: "calendar", text: hero.lastCheckInText)
                    heroMetaRow(icon: "clock", text: hero.nextCheckInText)
                    heroMetaRow(icon: "bell", text: hero.reminderText)
                }
            }
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppTheme.divider, lineWidth: 1)
            )
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
                            openCheckIn()
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

                        if let selectedDevelopmentDate,
                           let selectedSnapshot = nearestSnapshot(to: selectedDevelopmentDate, in: filteredSnapshots),
                           selectedSnapshot.periodKey == snapshot.periodKey {
                            RuleMark(x: .value("Valgt dato", selectedSnapshot.capturedAt))
                                .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .annotation(position: .topLeading) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(formatDate(selectedSnapshot.capturedAt))
                                            .font(.caption2.weight(.semibold))
                                        Text(formatNOK(selectedSnapshot.totalValue))
                                            .font(.caption.weight(.semibold))
                                    }
                                    .padding(8)
                                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(AppTheme.divider, lineWidth: 1)
                                    )
                                }
                        }
                    }
                    .frame(height: 170)
                    .chartXAxis(.hidden)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let origin = geometry[proxy.plotAreaFrame].origin
                                            let relativeX = value.location.x - origin.x
                                            if let date: Date = proxy.value(atX: relativeX) {
                                                selectedDevelopmentDate = date
                                            }
                                        }
                                        .onEnded { _ in
                                            selectedDevelopmentDate = nil
                                        }
                                )
                        }
                    }
                    .animation(.easeInOut(duration: 0.5), value: viewModel.selectedRange)
                    .accessibilityLabel("Utviklingsgraf for investeringer")
                    .accessibilityValue(developmentChartAccessibilitySummary(filteredSnapshots))
                }

                Text("Basert på totalsummene du legger inn.")
                    .appSecondaryStyle()
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ingen aktive beholdninger ennå.")
                        .appSecondaryStyle()
                    Button("Legg til type") {
                        viewModel.resetAddBucketState()
                        viewModel.showAddBucketSheet = true
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.primary)
                }
            } else {
                ForEach(bucketRows) { row in
                    NavigationLink(value: row.id) {
                        bucketRow(row)
                    }
                    .moveDisabled(false)
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
                .onMove { source, destination in
                    viewModel.moveActiveBuckets(
                        from: source,
                        to: destination,
                        allBuckets: buckets,
                        context: modelContext
                    )
                }
            }
        }
    }

    private var administrationSection: some View {
        let hiddenBuckets = buckets.filter { !$0.isActive }
        return Section("Administrasjon") {
            Button {
                viewModel.resetAddBucketState()
                viewModel.showAddBucketSheet = true
            } label: {
                Label("Ny type", systemImage: "plus.circle")
            }
            .foregroundStyle(AppTheme.primary)

            if hiddenBuckets.isEmpty {
                Text("Ingen skjulte beholdningstyper.")
                    .appSecondaryStyle()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Skjulte beholdninger")
                        .appSecondaryStyle()
                    ForEach(hiddenBuckets) { bucket in
                        HStack {
                            Circle()
                                .fill(AppTheme.portfolioColor(for: bucket))
                                .frame(width: 10, height: 10)
                            Text(bucket.name)
                                .appBodyStyle()
                            Spacer()
                            Button("Vis igjen") {
                                viewModel.restoreBucket(bucket, context: modelContext, existingBuckets: buckets)
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.primary)
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
                    .foregroundStyle(portfolioColor(bucketID: item.bucketID, fallbackName: item.bucketName))
                }
                .frame(height: 180)
                .accessibilityLabel("Fordeling av beholdning")
                .accessibilityValue(distributionAccessibilitySummary(data))

                ForEach(data, id: \.bucketID) { item in
                    HStack {
                        Circle()
                            .fill(portfolioColor(bucketID: item.bucketID, fallbackName: item.bucketName))
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
                        .fill(portfolioColor(bucketID: only.bucketID, fallbackName: only.bucketName))
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
        let history = showFullHistory ? viewModel.history(snapshots) : viewModel.latestHistory(snapshots)
        return Section("Siste oppdateringer") {
            if history.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Legg inn første snapshot (tar 20 sek)")
                        .appCardTitleStyle()
                    Text("Grovt tall er nok.")
                        .appSecondaryStyle()
                    Button("Oppdater verdier") {
                        openCheckIn()
                    }
                    .appCTAStyle()
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
                }
                .padding(12)
            } else {
                ForEach(history, id: \.periodKey) { snapshot in
                    HStack {
                        Text(formatPeriodKeyAsDate(snapshot.periodKey))
                            .appBodyStyle()
                        Spacer()
                        Text(formatNOK(snapshot.totalValue))
                            .appBodyStyle()
                            .monospacedDigit()
                    }
                }
                if snapshots.count > 6 {
                    Button(showFullHistory ? "Vis færre" : "Se alle") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showFullHistory.toggle()
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
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

    private func heroMetaRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 16)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
        }
    }

    private func bucketRow(_ row: InvestmentBucketRowData) -> some View {
        let bucketColor = portfolioColor(bucketID: row.id, fallbackName: row.name)
        let changeColor: Color = {
            if row.changeKr > 0 { return AppTheme.positive }
            if row.changeKr < 0 { return AppTheme.negative }
            return AppTheme.textSecondary
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(bucketColor)
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

                sparkline(series: row.sparkline, color: bucketColor)
                    .frame(width: 78, height: 30)
                    .accessibilityHidden(true)

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

    private func portfolioColor(bucketID: String, fallbackName: String) -> Color {
        if let bucket = buckets.first(where: { $0.id == bucketID }) {
            return AppTheme.portfolioColor(for: bucket)
        }
        return AppTheme.portfolioColor(for: fallbackName)
    }

    private func developmentChartAccessibilitySummary(_ snapshots: [InvestmentSnapshot]) -> String {
        guard let first = snapshots.first, let last = snapshots.last else {
            return "Ingen utviklingsdata ennå."
        }
        let change = last.totalValue - first.totalValue
        return "Fra \(formatNOK(first.totalValue)) til \(formatNOK(last.totalValue)), endring \(formatNOK(change))."
    }

    private func distributionAccessibilitySummary(_ data: [(bucketID: String, bucketName: String, amount: Double, percent: Double)]) -> String {
        guard !data.isEmpty else { return "Ingen fordeling ennå." }
        return data
            .sorted { $0.percent > $1.percent }
            .prefix(3)
            .map { "\($0.bucketName) \(formatPercent($0.percent))" }
            .joined(separator: ", ")
    }

    private func nearestSnapshot(to date: Date, in snapshots: [InvestmentSnapshot]) -> InvestmentSnapshot? {
        snapshots.min(by: {
            abs($0.capturedAt.timeIntervalSince(date)) < abs($1.capturedAt.timeIntervalSince(date))
        })
    }

    private func openCheckIn() {
        if activeBuckets.isEmpty {
            viewModel.ensureDefaultBuckets(context: modelContext, existingBuckets: buckets)
            DispatchQueue.main.async {
                viewModel.showCheckIn = true
            }
            return
        }
        viewModel.showCheckIn = true
    }

}

private struct AddInvestmentBucketSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var name: String
    @Binding var selectedColorHex: String
    let errorMessage: String?
    let onSave: () -> Bool
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Ny beholdningstype") {
                    TextField("F.eks. Eiendom", text: $name)
                        .textFieldStyle(.appInput)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Velg farge")
                            .appBodyStyle()
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
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
                                                    .stroke(Color.white, lineWidth: 2)
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
                    }
                    Text("Ny type vises i Beholdning, graf og neste insjekk.")
                        .appSecondaryStyle()
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.negative)
                    }
                }
            }
            .navigationTitle("Legg til type")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        if onSave() {
                            dismiss()
                        }
                    }
                    .appCTAStyle()
                }
            }
        }
    }
}

private struct BucketDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let bucket: InvestmentBucket
    let snapshots: [InvestmentSnapshot]

    @State private var showQuickUpdate = false
    @State private var selectedRange: GraphViewRange = .yearToDate
    @State private var showAllHistory = false
    @State private var selectedPointDate: Date?

    private var sorted: [InvestmentSnapshot] { InvestmentService.sortedSnapshots(snapshots) }
    private var bucketColor: Color { AppTheme.portfolioColor(for: bucket) }

    private func bucketAmount(in snapshot: InvestmentSnapshot) -> Double {
        snapshot.bucketValues.first(where: { $0.bucketID == bucket.id })?.amount ?? 0
    }

    private var latestSnapshot: InvestmentSnapshot? { sorted.last }
    private var previousSnapshot: InvestmentSnapshot? {
        guard sorted.count > 1 else { return nil }
        return sorted[sorted.count - 2]
    }

    private var latestValue: Double {
        latestSnapshot.map { bucketAmount(in: $0) } ?? 0
    }

    private var changeSinceLast: Double {
        latestValue - (previousSnapshot.map(bucketAmount(in:)) ?? 0)
    }

    private var changePctSinceLast: Double? {
        guard let previousSnapshot else { return nil }
        let previous = bucketAmount(in: previousSnapshot)
        guard previous != 0 else { return nil }
        return changeSinceLast / previous
    }

    private var shareOfPortfolio: Double {
        guard let latestSnapshot, latestSnapshot.totalValue > 0 else { return 0 }
        return latestValue / latestSnapshot.totalValue
    }

    private var filtered: [InvestmentSnapshot] {
        switch selectedRange {
        case .yearToDate:
            let year = Calendar.current.component(.year, from: .now)
            return sorted.filter { Calendar.current.component(.year, from: $0.capturedAt) == year }
        case .last12Months:
            return Array(sorted.suffix(12))
        }
    }

    private var visibleHistory: [InvestmentSnapshot] {
        let reversed = sorted.reversed()
        return showAllHistory ? Array(reversed) : Array(reversed.prefix(6))
    }

    private var selectedSnapshot: InvestmentSnapshot? {
        guard let selectedPointDate else { return nil }
        return filtered.min(by: {
            abs($0.capturedAt.timeIntervalSince(selectedPointDate)) < abs($1.capturedAt.timeIntervalSince(selectedPointDate))
        })
    }

    private var changeText: String {
        if abs(changeSinceLast) < 0.01 { return "Ingen endring siden forrige insjekk" }
        let sign = changeSinceLast >= 0 ? "+" : "-"
        if let pct = changePctSinceLast {
            return "\(sign)\(formatNOK(abs(changeSinceLast))) (\(formatPercent(pct))) siden forrige insjekk"
        }
        return "\(sign)\(formatNOK(abs(changeSinceLast))) siden forrige insjekk"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(bucketColor)
                            .frame(width: 10, height: 10)
                        Text(bucket.name)
                            .appCardTitleStyle()
                    }
                    Text(formatNOK(latestValue))
                        .appBigNumberStyle()
                        .foregroundStyle(AppTheme.textPrimary)
                        .contentTransition(.numericText(value: latestValue))
                    Text(changeText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(abs(changeSinceLast) < 0.01 ? AppTheme.textSecondary : (changeSinceLast >= 0 ? AppTheme.positive : AppTheme.negative))
                    Text("Sist oppdatert: \(latestSnapshot.map { formatDate($0.capturedAt) } ?? "Ikke satt")")
                        .appSecondaryStyle()
                    Text("Andel: \(formatPercent(shareOfPortfolio)) av porteføljen")
                        .appSecondaryStyle()
                    ProgressView(value: shareOfPortfolio, total: 1)
                        .tint(bucketColor)
                    Button {
                        showQuickUpdate = true
                    } label: {
                        Label("Oppdater denne", systemImage: "pencil.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.primary.opacity(0.9))
                }
                .padding()
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Utvikling")
                            .appCardTitleStyle()
                        Spacer()
                        Picker("Periode", selection: $selectedRange) {
                            Text("I år").tag(GraphViewRange.yearToDate)
                            Text("Siste 12 mnd").tag(GraphViewRange.last12Months)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }

                    if filtered.count < 2 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Legg inn én måned til for å se utvikling.")
                                .appBodyStyle()
                            Button("Oppdater verdier") {
                                showQuickUpdate = true
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.primary)
                        }
                    } else {
                        Chart(filtered, id: \.periodKey) { snapshot in
                            let amount = bucketAmount(in: snapshot)
                            LineMark(
                                x: .value("Dato", snapshot.capturedAt),
                                y: .value("Beløp", amount)
                            )
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(bucketColor)

                            PointMark(
                                x: .value("Dato", snapshot.capturedAt),
                                y: .value("Beløp", amount)
                            )
                            .symbolSize(35)
                            .foregroundStyle(bucketColor)
                        }
                        .frame(height: 210)
                        .chartXAxis(.hidden)
                        .chartXSelection(value: $selectedPointDate)
                        .animation(.easeInOut(duration: 0.35), value: selectedRange)

                        if let selectedSnapshot {
                            Text("\(formatDate(selectedSnapshot.capturedAt)): \(formatNOK(bucketAmount(in: selectedSnapshot)))")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                    }

                    Text("Basert på totalsummen du legger inn ved insjekk.")
                        .appSecondaryStyle()
                }
                .padding()
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Historikk")
                            .appCardTitleStyle()
                        Spacer()
                        if sorted.count > 6 {
                            Button(showAllHistory ? "Vis færre" : "Se alle") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showAllHistory.toggle()
                                }
                            }
                            .font(.footnote.weight(.semibold))
                        }
                    }

                    if sorted.isEmpty {
                        Text("Ingen historikk ennå.")
                            .appSecondaryStyle()
                    } else {
                        VStack(spacing: 8) {
                            ForEach(visibleHistory, id: \.periodKey) { snapshot in
                                HStack {
                                    Text(formatDate(snapshot.capturedAt))
                                        .appBodyStyle()
                                    Spacer()
                                    Text(formatNOK(bucketAmount(in: snapshot)))
                                        .appBodyStyle()
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
            }
            .padding()
        }
        .navigationTitle(bucket.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Oppdater") {
                    showQuickUpdate = true
                }
            }
        }
        .background(AppTheme.background)
        .sheet(isPresented: $showQuickUpdate) {
            BucketQuickUpdateSheet(bucket: bucket, latestSnapshot: sorted.last)
        }
        .onDisappear {
            try? modelContext.save()
        }
    }
}

private struct EditInvestmentBucketSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let bucket: InvestmentBucket
    let existingBuckets: [InvestmentBucket]

    @StateObject private var viewModel = InvestmentsViewModel()
    @State private var name: String = ""
    @State private var selectedColorHex: String = AppTheme.customBucketPalette[0]
    @State private var showDeleteAlert = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Beholdningstype") {
                    TextField("Navn", text: $name)
                        .textFieldStyle(.appInput)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Farge")
                            .appBodyStyle()
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
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
                                                    .stroke(Color.white, lineWidth: 2)
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
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.negative)
                    }
                }

                Section {
                    Button("Slett beholdningstype", role: .destructive) {
                        showDeleteAlert = true
                    }
                } footer: {
                    Text("Sletter typen helt og fjerner den fra historikk/snapshots.")
                        .appSecondaryStyle()
                }
            }
            .navigationTitle("Rediger type")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        errorMessage = viewModel.updateBucket(
                            bucket,
                            name: name,
                            colorHex: selectedColorHex,
                            context: modelContext,
                            existingBuckets: existingBuckets
                        )
                        if errorMessage == nil {
                            dismiss()
                        }
                    }
                    .appCTAStyle()
                }
            }
            .alert("Slette beholdningstype?", isPresented: $showDeleteAlert) {
                Button("Avbryt", role: .cancel) { }
                Button("Slett", role: .destructive) {
                    viewModel.deleteBucket(bucket, context: modelContext, snapshots: snapshotsFromContext())
                    dismiss()
                }
            } message: {
                Text("Dette kan ikke angres.")
            }
            .onAppear {
                name = bucket.name
                selectedColorHex = bucket.colorHex ?? AppTheme.customBucketPalette[0]
            }
        }
    }

    private func snapshotsFromContext() -> [InvestmentSnapshot] {
        (try? modelContext.fetch(FetchDescriptor<InvestmentSnapshot>())) ?? []
    }
}

private struct BucketQuickUpdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let bucket: InvestmentBucket
    let latestSnapshot: InvestmentSnapshot?

    @State private var amountText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Ny verdi") {
                    Text(bucket.name)
                        .appBodyStyle()
                    TextField(
                        "Beløp",
                        text: $amountText
                    )
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.appInput)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
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
                amountText = ""
            }
        }
    }

    private func saveSingleBucket() {
        let amount = parseInputAmount(amountText) ?? 0
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

    private func parseInputAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
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
                                "Beløp",
                                text: binding(for: bucket.id)
                            )
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.appInput)
                            .monospacedDigit()
                            .frame(width: 130)
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

    private func binding(for bucketID: String) -> Binding<String> {
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
