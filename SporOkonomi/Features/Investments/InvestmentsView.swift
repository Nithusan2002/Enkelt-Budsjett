import SwiftUI
import SwiftData
import Charts
import UIKit

struct InvestmentsView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @Environment(\.modelContext) private var modelContext
    @AppStorage("overview_amounts_hidden") private var areAmountsHidden = false
    @Query(sort: \InvestmentBucket.sortOrder) private var buckets: [InvestmentBucket]
    @Query(sort: \InvestmentSnapshot.periodKey) private var snapshots: [InvestmentSnapshot]
    @Query private var preferences: [UserPreference]

    @StateObject private var viewModel = InvestmentsViewModel()
    @State private var showFullHistory = false
    @State private var isHistoryExpanded = false
    @State private var checkInToastMessage: String?
    @State private var selectedBucketID: String?
    private var isReadOnlyMode: Bool { PersistenceGate.isReadOnlyMode }

    private enum SectionAnchor: String {
        case development
        case distribution
    }

    private var latest: InvestmentSnapshot? { viewModel.latestSnapshot(snapshots) }
    private var hero: InvestmentHeroData { viewModel.heroData(snapshots: snapshots, preference: preferences.first) }
    private var bucketRows: [InvestmentBucketRowData] {
        viewModel.bucketRows(buckets: buckets, snapshots: snapshots, range: viewModel.selectedRange)
    }
    private var hasSnapshots: Bool { !snapshots.isEmpty }
    private var activeBuckets: [InvestmentBucket] {
        buckets.filter(\.isActive)
    }
    private var distributionRows: [InvestmentDistributionRowData] {
        viewModel.distributionRows(latestSnapshot: latest, buckets: buckets)
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
                    .id(SectionAnchor.development.rawValue)
                chartSection
                distributionSection
                    .id(SectionAnchor.distribution.rawValue)
                holdingsSection
                historySection
                administrationSection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(14)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Investeringer")
            .refreshable {
                viewModel.refreshData(snapshots: snapshots)
            }
            .sheet(isPresented: $viewModel.showCheckIn) {
                InvestmentCheckInWizardView(
                    buckets: buckets,
                    snapshots: snapshots,
                    onRequestNewType: {
                        viewModel.resetAddBucketState()
                        viewModel.showAddBucketSheet = true
                    },
                    onSaved: { _, periodKey in
                        showCheckInToast(checkInToastMessage(for: periodKey))
                    }
                )
            }
            .sheet(isPresented: $viewModel.showAddBucketSheet) {
                AddInvestmentBucketSheet(
                    name: $viewModel.newBucketName,
                    selectedColorHex: $viewModel.selectedBucketColorHex,
                    existingBucketNames: Set(buckets.map { $0.name.lowercased() }),
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
            .navigationDestination(
                isPresented: Binding(
                    get: { selectedBucketID != nil },
                    set: { if !$0 { selectedBucketID = nil } }
                )
            ) {
                if let selectedBucketID,
                   let bucket = buckets.first(where: { $0.id == selectedBucketID }) {
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
            .onChange(of: viewModel.developmentPeriod) { _, period in
                switch period {
                case .oneMonth:
                    viewModel.selectedRange = .yearToDate
                case .sixMonths, .last12Months:
                    viewModel.selectedRange = .oneYear
                case .total:
                    viewModel.selectedRange = .max
                }
            }
            .onChange(of: navigationState.investmentsFocus) { _, focus in
                guard let focus else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(focus.rawValue, anchor: .top)
                }
                navigationState.investmentsFocus = nil
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    InvestmentsBottomCTAButton {
                        openCheckIn()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .disabled(isReadOnlyMode)
                }
                .padding(.bottom, 8)
            }
            .overlay(alignment: .bottom) {
                if let checkInToastMessage {
                    Text(checkInToastMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AppTheme.surfaceElevated, in: Capsule())
                        .overlay(Capsule().stroke(AppTheme.divider, lineWidth: 1))
                        .padding(.bottom, 76)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .alert(
                "Kunne ikke lagre endringer",
                isPresented: Binding(
                    get: { viewModel.persistenceErrorMessage != nil },
                    set: { if !$0 { viewModel.clearPersistenceError() } }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewModel.clearPersistenceError()
                }
            } message: {
                Text(viewModel.persistenceErrorMessage ?? "Prøv igjen litt senere.")
            }
        }
    }

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Text("Min formue")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                Text(displayedAmount(viewModel.displayedTotal))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .contentTransition(.numericText(value: viewModel.displayedTotal))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text(changeSummaryText(changeKr: hero.changeKr, changePct: hero.changePct))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(hero.changeKr >= 0 ? AppTheme.positive : AppTheme.negative)
                    Text(hero.lastCheckInText)
                        .appSecondaryStyle()
                }

                if latest == nil {
                    Text("Legg inn første verdi for å følge utviklingen over tid.")
                        .appBodyStyle()
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        AppTheme.surface,
                        AppTheme.primary.opacity(0.08),
                        AppTheme.surfaceElevated
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.divider.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: AppTheme.primary.opacity(0.08), radius: 24, y: 14)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 1, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var chartSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Utvikling")
                        .appCardTitleStyle()
                    Text("Total formue over tid")
                        .appSecondaryStyle()
                }

                InvestmentsDevelopmentChartView(
                    points: viewModel.developmentChartPoints(snapshots: snapshots, buckets: buckets),
                    period: $viewModel.developmentPeriod,
                    onUpdateValues: openCheckIn,
                    embedded: true,
                    showStatusRow: false
                )
            }
            .padding(18)
            .cardContainer()
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 1, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var holdingsSection: some View {
        Section {
            if bucketRows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ingen beholdning registrert ennå")
                        .appCardTitleStyle()
                    Text("Legg til en beholdningstype og registrer verdi for å se utviklingen over tid.")
                        .appSecondaryStyle()
                }
                .padding(18)
                .cardContainer()
                .listRowSeparator(.hidden)
            } else {
                ForEach(bucketRows) { row in
                    holdingRow(row, isFirst: row.id == bucketRows.first?.id)
                }
            }
        } header: {
            holdingsHeader
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }

    private var administrationSection: some View {
        let hiddenBuckets = buckets.filter { !$0.isActive }
        guard !hiddenBuckets.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(Section {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Skjulte beholdninger")
                        .appSecondaryStyle()
                    ForEach(hiddenBuckets) { bucket in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(AppTheme.portfolioColor(for: bucket))
                                .frame(width: 10, height: 10)
                            Text(bucket.name)
                                .appBodyStyle()
                            Spacer()
                            Button("Vis igjen") {
                                guard !isReadOnlyMode else {
                                    viewModel.persistenceErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
                                    return
                                }
                                viewModel.restoreBucket(bucket, context: modelContext, existingBuckets: buckets)
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.primary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .cardContainer()
            .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)))
    }

    private var distributionSection: some View {
        return Section {
            VStack(alignment: .leading, spacing: 16) {
                Text("Fordeling")
                    .appCardTitleStyle()

                if distributionRows.isEmpty {
                    Text("Fordelingen vises når du har lagret din første innsjekk.")
                        .appSecondaryStyle()
                } else {
                    ForEach(Array(distributionRows.enumerated()), id: \.element.id) { index, row in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(portfolioColor(bucketID: row.bucketID, fallbackName: row.bucketName))
                                        .frame(width: 10, height: 10)
                                    Text(row.bucketName)
                                        .appBodyStyle()
                                }
                                Spacer()
                                Text(formatPercent(row.percent))
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text(displayedAmount(row.amount))
                                    .appSecondaryStyle()
                                    .monospacedDigit()
                            }

                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(AppTheme.surfaceElevated)
                                    Capsule()
                                        .fill(portfolioColor(bucketID: row.bucketID, fallbackName: row.bucketName))
                                        .frame(width: max(18, geometry.size.width * row.percent))
                                }
                            }
                            .frame(height: 10)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(row.bucketName), \(formatPercent(row.percent)), \(displayedAmount(row.amount))")

                        if index < distributionRows.count - 1 {
                            Divider()
                                .overlay(AppTheme.divider.opacity(0.7))
                        }
                    }
                }
            }
            .padding(18)
            .cardContainer()
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 1, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var historySection: some View {
        let allHistory = viewModel.history(snapshots)
        let history = showFullHistory ? allHistory : Array(allHistory.prefix(6))
        return Section {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHistoryExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text("Tidligere innsjekker")
                            .appCardTitleStyle()
                        Spacer()
                        Image(systemName: isHistoryExpanded ? "chevron.up" : "chevron.down")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isHistoryExpanded {
                    if allHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Ingen innsjekker ennå")
                                .appCardTitleStyle()
                            Text("Oppdater verdien når du vil følge utviklingen over tid.")
                                .appSecondaryStyle()
                            Button("Oppdater verdi") {
                                openCheckIn()
                            }
                            .appProminentCTAStyle()
                            .disabled(isReadOnlyMode)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(history, id: \.periodKey) { snapshot in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(formatPeriodKeyAsDate(snapshot.periodKey))
                                            .appBodyStyle()
                                        Text(formatShortDate(snapshot.capturedAt))
                                            .appSecondaryStyle()
                                    }
                                    Spacer()
                                    Text(displayedAmount(snapshot.totalValue))
                                        .appBodyStyle()
                                        .monospacedDigit()
                                }
                            }
                            if allHistory.count > 6 {
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
            }
            .padding(18)
            .cardContainer()
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 1, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func showCheckInToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            checkInToastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                checkInToastMessage = nil
            }
        }
    }

    private func checkInToastMessage(for periodKey: String) -> String {
        guard let monthDate = DateService.monthStart(from: periodKey) else {
            return "Verdier lagret"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "LLLL"
        return "Verdier lagret for \(formatter.string(from: monthDate).lowercased())"
    }

    private func changeSummaryText(changeKr: Double, changePct: Double?) -> String {
        if areAmountsHidden {
            guard changeKr != 0 || changePct != nil else {
                return "Siden sist oppdatert: ingen endring ennå"
            }
            return changeKr >= 0
                ? "Siden sist oppdatert: opp"
                : "Siden sist oppdatert: ned"
        }
        guard changeKr != 0 || changePct != nil else {
            return "Siden sist oppdatert: ingen endring ennå"
        }
        let sign = changeKr >= 0 ? "+" : "−"
        let pctText = changePct.map { " (\(formatPercent($0)))" } ?? ""
        return "Siden sist oppdatert: \(sign)\(formatNOK(abs(changeKr)))\(pctText)"
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
                    Text(displayedAmount(row.amount))
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

            Text("Sist oppdatert \(formatShortDate(row.lastUpdated ?? .now))")
                .appSecondaryStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(16)
        .cardContainer()
    }

    private var holdingsHeader: some View {
        HStack {
            Text("Beholdning")
                .appCardTitleStyle()
            Spacer()
            Button {
                viewModel.resetAddBucketState()
                viewModel.showAddBucketSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.background, in: Circle())
                    .overlay(
                        Circle()
                            .stroke(AppTheme.divider, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isReadOnlyMode)
            .accessibilityLabel("Legg til beholdningstype")
        }
        .textCase(nil)
    }

    private func holdingRow(_ row: InvestmentBucketRowData, isFirst: Bool) -> some View {
        let bucket = buckets.first(where: { $0.id == row.id })

        return Button {
            selectedBucketID = row.id
        } label: {
            bucketRow(row)
        }
        .buttonStyle(.plain)
        .moveDisabled(isReadOnlyMode)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let bucket {
                Button("Rediger") {
                    guard !isReadOnlyMode else {
                        viewModel.persistenceErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
                        return
                    }
                    viewModel.selectedBucketForEdit = bucket
                }
                .tint(AppTheme.secondary)

                Button("Skjul", role: .destructive) {
                    guard !isReadOnlyMode else {
                        viewModel.persistenceErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
                        return
                    }
                    viewModel.hideBucket(bucket, context: modelContext)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: isFirst ? 6 : 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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
        if areAmountsHidden {
            if changeKr == 0 { return "Uendret" }
            return changeKr > 0 ? "Opp siden sist" : "Ned siden sist"
        }
        return changeKr >= 0 ? "+\(formatNOK(abs(changeKr)))" : "-\(formatNOK(abs(changeKr)))"
    }

    private func displayedAmount(_ amount: Double) -> String {
        areAmountsHidden ? "•••• kr" : formatNOK(amount)
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date).lowercased()
    }

    private func portfolioColor(bucketID: String, fallbackName: String) -> Color {
        if let bucket = buckets.first(where: { $0.id == bucketID }) {
            return AppTheme.portfolioColor(for: bucket)
        }
        return AppTheme.portfolioColor(for: fallbackName)
    }

    private func openCheckIn() {
        guard !isReadOnlyMode else {
            viewModel.persistenceErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
            return
        }
        viewModel.showCheckIn = true
    }

}

private struct InvestmentsBottomCTAButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.title3.weight(.bold))
                Text("Oppdater formue")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(AppTheme.onPrimary)
            .background(AppTheme.primary, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(AppTheme.primary.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Oppdater formue")
    }
}

private extension View {
    func cardContainer() -> some View {
        self
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppTheme.divider.opacity(0.8), lineWidth: 1)
            )
    }
}

private struct AddInvestmentBucketSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var name: String
    @Binding var selectedColorHex: String
    let existingBucketNames: Set<String>
    let errorMessage: String?
    let onSave: () -> Bool
    let onCancel: () -> Void

    private let suggestedTypes = ["Fond", "Aksjer", "Krypto", "Kontanter", "BSU"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Ny beholdningstype") {
                    TextField("F.eks. Eiendom", text: $name)
                        .textFieldStyle(.appInput)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Forslag")
                            .appBodyStyle()

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                            ForEach(suggestedTypes, id: \.self) { suggestion in
                                Button {
                                    name = suggestion
                                } label: {
                                    HStack {
                                        Text(suggestion)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(isSuggestionUnavailable(suggestion) ? AppTheme.textSecondary : AppTheme.textPrimary)
                                        Spacer(minLength: 8)
                                        if normalizedName == suggestion.lowercased() {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(AppTheme.primary)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(normalizedName == suggestion.lowercased() ? AppTheme.primary.opacity(0.12) : AppTheme.surface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(normalizedName == suggestion.lowercased() ? AppTheme.primary.opacity(0.35) : AppTheme.divider, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(isSuggestionUnavailable(suggestion))
                                .opacity(isSuggestionUnavailable(suggestion) ? 0.45 : 1)
                                .accessibilityLabel(isSuggestionUnavailable(suggestion) ? "\(suggestion), finnes allerede" : suggestion)
                            }
                        }
                    }

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
                    }
                    Text("Ny type vises i Beholdning, graf og neste innsjekk.")
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

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isSuggestionUnavailable(_ suggestion: String) -> Bool {
        let normalizedSuggestion = suggestion.lowercased()
        return existingBucketNames.contains(normalizedSuggestion) && normalizedName != normalizedSuggestion
    }
}

private struct BucketDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let bucket: InvestmentBucket
    let snapshots: [InvestmentSnapshot]

    @State private var showQuickUpdate = false
    @State private var selectedRange: GraphViewRange = .threeYears
    @State private var showAllHistory = false
    @State private var selectedPointDate: Date?
    @State private var selectedPointPeriodKey: String?

    private var sorted: [InvestmentSnapshot] { InvestmentService.sortedSnapshots(snapshots) }
    private var isReadOnlyMode: Bool { PersistenceGate.isReadOnlyMode }
    private var sortedUpToNow: [InvestmentSnapshot] {
        InvestmentService.filteredSnapshots(range: .max, snapshots: sorted)
    }
    private var bucketColor: Color { AppTheme.portfolioColor(for: bucket) }

    private func bucketAmount(in snapshot: InvestmentSnapshot) -> Double {
        snapshot.bucketValues.first(where: { $0.bucketID == bucket.id })?.amount ?? 0
    }

    private var latestSnapshot: InvestmentSnapshot? { sortedUpToNow.last }
    private var previousSnapshot: InvestmentSnapshot? {
        guard sortedUpToNow.count > 1 else { return nil }
        return sortedUpToNow[sortedUpToNow.count - 2]
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
        InvestmentService.filteredSnapshots(
            range: InvestmentsBucketChartHelper.normalizedRange(selectedRange),
            snapshots: sorted
        )
    }

    private var visibleHistory: [InvestmentSnapshot] {
        let reversed = sortedUpToNow.reversed()
        return showAllHistory ? Array(reversed) : Array(reversed.prefix(6))
    }

    private var selectedSnapshot: InvestmentSnapshot? {
        guard let selectedPointDate else { return nil }
        return InvestmentsBucketChartHelper.nearestSnapshot(to: selectedPointDate, in: filtered)
    }

    private var changeText: String {
        if abs(changeSinceLast) < 0.01 { return "Ingen endring siden forrige innsjekk" }
        let sign = changeSinceLast >= 0 ? "+" : "-"
        if let pct = changePctSinceLast {
            return "\(sign)\(formatNOK(abs(changeSinceLast))) (\(formatPercent(pct))) siden forrige innsjekk"
        }
        return "\(sign)\(formatNOK(abs(changeSinceLast))) siden forrige innsjekk"
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date).lowercased()
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
                    Text("Sist oppdatert \(latestSnapshot.map { formatShortDate($0.capturedAt) } ?? "Ikke satt")")
                        .appSecondaryStyle()
                    Text("Andel: \(formatPercent(shareOfPortfolio)) av porteføljen")
                        .appSecondaryStyle()
                    let progress = clampedProgress(value: shareOfPortfolio, total: 1)
                    ProgressView(value: progress.value, total: progress.total)
                        .tint(bucketColor)
                    Button {
                        showQuickUpdate = true
                    } label: {
                        Label("Oppdater denne", systemImage: "pencil.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.primary.opacity(0.9))
                    .disabled(isReadOnlyMode)
                }
                .padding()
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Utvikling")
                            .appCardTitleStyle()
                        Spacer()
                        Menu {
                            ForEach(rangeOptions, id: \.rawValue) { range in
                                Button {
                                    selectedRange = range
                                } label: {
                                    if InvestmentsBucketChartHelper.normalizedRange(selectedRange) == range {
                                        Label(InvestmentsBucketChartHelper.rangeTitle(range), systemImage: "checkmark")
                                    } else {
                                        Text(InvestmentsBucketChartHelper.rangeTitle(range))
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(InvestmentsBucketChartHelper.rangeTitle(InvestmentsBucketChartHelper.normalizedRange(selectedRange)))
                                    .font(.subheadline.weight(.semibold))
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(AppTheme.surfaceElevated, in: Capsule())
                            .overlay(Capsule().stroke(AppTheme.divider, lineWidth: 1))
                        }
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
                            .disabled(isReadOnlyMode)
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

                            if snapshot.periodKey == filtered.last?.periodKey {
                                PointMark(
                                    x: .value("Siste dato", snapshot.capturedAt),
                                    y: .value("Siste beløp", amount)
                                )
                                .symbolSize(64)
                                .foregroundStyle(AppTheme.primary)
                                .annotation(position: .topTrailing) {
                                    Text("Nå")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(AppTheme.primary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(AppTheme.primary.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                        .frame(height: 210)
                        .chartXScale(domain: InvestmentsBucketChartHelper.chartDateDomain(for: filtered))
                        .chartXAxis {
                            AxisMarks(values: InvestmentsBucketChartHelper.xAxisDates(for: filtered, range: selectedRange)) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(AppTheme.divider.opacity(0.35))
                                AxisValueLabel {
                                    if let date = value.as(Date.self) {
                                        Text(InvestmentsBucketChartHelper.monthLabel(date))
                                    }
                                }
                                .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                                    .foregroundStyle(AppTheme.divider.opacity(0.45))
                                AxisValueLabel {
                                    if let amount = value.as(Double.self) {
                                        Text(InvestmentsBucketChartHelper.compactNOK(amount))
                                    }
                                }
                                .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                        .chartOverlay { proxy in
                            GeometryReader { geometry in
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                guard let plotFrame = proxy.plotFrame else { return }
                                                let origin = geometry[plotFrame].origin
                                                let relativeX = value.location.x - origin.x
                                                if let date: Date = proxy.value(atX: relativeX),
                                                   let nearest = InvestmentsBucketChartHelper.nearestSnapshot(to: date, in: filtered) {
                                                    if selectedPointPeriodKey != nearest.periodKey {
                                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                    }
                                                    selectedPointPeriodKey = nearest.periodKey
                                                    selectedPointDate = nearest.capturedAt
                                                }
                                            }
                                            .onEnded { _ in
                                                selectedPointDate = nil
                                                selectedPointPeriodKey = nil
                                            }
                                    )
                            }
                        }
                        .animation(.easeInOut(duration: 0.35), value: selectedRange)

                        if let selectedSnapshot {
                            Text("\(formatShortDate(selectedSnapshot.capturedAt)): \(formatNOK(bucketAmount(in: selectedSnapshot)))")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                    }

                    Text("Basert på totalsummen du legger inn ved innsjekk.")
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

                    if sortedUpToNow.isEmpty {
                        Text("Ingen historikk ennå.")
                            .appSecondaryStyle()
                    } else {
                        VStack(spacing: 8) {
                            ForEach(visibleHistory, id: \.periodKey) { snapshot in
                                HStack {
                                    Text(formatShortDate(snapshot.capturedAt))
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
                .disabled(isReadOnlyMode)
            }
        }
        .background(AppTheme.background)
        .sheet(isPresented: $showQuickUpdate) {
            BucketQuickUpdateSheet(bucket: bucket, latestSnapshot: sortedUpToNow.last)
        }
    }

    private var rangeOptions: [GraphViewRange] {
        [.yearToDate, .oneYear, .twoYears, .threeYears, .fiveYears, .max]
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
    private var isReadOnlyMode: Bool { PersistenceGate.isReadOnlyMode }

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
                    .disabled(isReadOnlyMode)
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
                        guard !isReadOnlyMode else {
                            errorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
                            return
                        }
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
                    guard !isReadOnlyMode else {
                        errorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
                        return
                    }
                    do {
                        let snapshots = try modelContext.fetch(FetchDescriptor<InvestmentSnapshot>())
                        viewModel.deleteBucket(bucket, context: modelContext, snapshots: snapshots)
                        if let persistenceErrorMessage = viewModel.persistenceErrorMessage {
                            errorMessage = persistenceErrorMessage
                            viewModel.clearPersistenceError()
                            return
                        }
                        dismiss()
                    } catch {
                        errorMessage = "Kunne ikke hente historikk for sletting."
                    }
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
}

private struct BucketQuickUpdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let bucket: InvestmentBucket
    let latestSnapshot: InvestmentSnapshot?

    @State private var amountText: String = ""
    @State private var saveErrorMessage: String?
    private var isReadOnlyMode: Bool { PersistenceGate.isReadOnlyMode }

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
                    .onChange(of: amountText) { _, newValue in
                        let formatted = AppAmountInput.formatLive(newValue)
                        if formatted != newValue {
                            amountText = formatted
                        }
                    }
                }
            }
            .navigationTitle("Oppdater beholdning")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        do {
                            try saveSingleBucket()
                            dismiss()
                        } catch let error as LocalizedError {
                            saveErrorMessage = error.errorDescription ?? "Lagring feilet. Prøv igjen."
                        } catch {
                            saveErrorMessage = "Lagring feilet. Prøv igjen."
                        }
                    }
                    .appCTAStyle()
                    .disabled(isReadOnlyMode)
                }
            }
            .appKeyboardDismissToolbar()
            .alert(
                "Kunne ikke lagre",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "")
            }
            .onAppear {
                amountText = latestSnapshot
                    .flatMap { snapshot in
                        snapshot.bucketValues.first(where: { $0.bucketID == bucket.id })?.amount
                    }
                    .map { AppAmountInput.format($0) } ?? ""
            }
        }
    }

    private func saveSingleBucket() throws {
        if isReadOnlyMode {
            throw PersistenceWriteError.readOnlyMode
        }
        guard let amount = AppAmountInput.parse(amountText) else {
            throw BucketQuickUpdateError.invalidAmount
        }
        let periodKey = DateService.periodKey(from: .now)
        let descriptor = FetchDescriptor<InvestmentSnapshot>(predicate: #Predicate { $0.periodKey == periodKey })
        let existing = try modelContext.fetch(descriptor).first
        var amountsByBucket = existing?.bucketValues.reduce(into: [String: Double]()) { result, value in
            result[value.bucketID] = value.amount
        } ?? [:]
        amountsByBucket[bucket.id] = amount
        let values = amountsByBucket.map { bucketID, value in
            InvestmentSnapshotValue(periodKey: periodKey, bucketID: bucketID, amount: value)
        }
        do {
            try InvestmentService.upsertSnapshot(
                context: modelContext,
                periodKey: periodKey,
                capturedAt: .now,
                values: values
            )
        } catch {
            throw BucketQuickUpdateError.saveFailed
        }
    }
}

private enum BucketQuickUpdateError: LocalizedError {
    case invalidAmount
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "Skriv inn et gyldig beløp."
        case .saveFailed:
            return "Kunne ikke lagre oppdateringen."
        }
    }
}
