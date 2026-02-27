import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var preferences: [UserPreference]
    @Query(sort: \InvestmentBucket.sortOrder) private var investmentBuckets: [InvestmentBucket]
    @AppStorage("app_appearance_mode") private var appAppearanceModeRawValue = AppAppearancePreference.followSystem.rawValue
    @StateObject private var viewModel = SettingsViewModel()

    @State private var showReminderSheet = false
    @State private var showGoalSheet = false
    @State private var showBucketTypesSheet = false
    @State private var shareItem: ShareURL?
    @State private var showExportError = false
    @State private var showDeleteAllConfirm = false
    @State private var showDeleteAllError = false
    @State private var showDeleteAllSuccess = false
    @State private var showDemoLoadError = false
    @State private var showDemoLoadSuccess = false
    @State private var showDemoWipeConfirm = false
    @State private var showImportModeDialog = false
    @State private var showImportPicker = false
    @State private var showImportError = false
    @State private var showImportSuccess = false
    @State private var pendingImportMode: DataImportMode = .merge
    @State private var importMessage = ""
    @State private var settingsErrorMessage: String?
    @State private var demoLoadMessage = ""
    @State private var demoToastMessage: String?

    private var pref: UserPreference { viewModel.preference(from: preferences, context: modelContext) }

    var body: some View {
        configuredForm
    }

    private var baseForm: some View {
        Form {
            trustSection
            appSettingsSection
            budgetAndInvestmentsSection
            dataSection
            if viewModel.shouldShowDemoTools() {
                demoSection
            }
            destructiveSection
            aboutSection
        }
    }

    private var configuredForm: some View {
        formWithAlerts
            .safeAreaInset(edge: .bottom) {
                if let demoToastMessage {
                    Text(demoToastMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AppTheme.surfaceElevated, in: Capsule())
                        .overlay(Capsule().stroke(AppTheme.divider, lineWidth: 1))
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }

    private var formWithSheets: some View {
        baseForm
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Innstillinger")
            .sheet(isPresented: $showReminderSheet) {
            ReminderSettingsSheet(
                enabled: pref.checkInReminderEnabled,
                day: pref.checkInReminderDay,
                hour: pref.checkInReminderHour,
                minute: pref.checkInReminderMinute
            ) { enabled, day, hour, minute in
                applyReminderSettings(enabled: enabled, day: day, hour: hour, minute: minute)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
            .sheet(isPresented: $showGoalSheet) {
            GoalEditorView(goal: nil)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showBucketTypesSheet) {
            BucketTypesSettingsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
            }
    }

    private var formWithAlerts: some View {
        formWithSheets
            .alert("Kunne ikke eksportere data", isPresented: $showExportError) {
            Button("OK", role: .cancel) { }
            } message: {
            Text("Prøv igjen litt senere.")
            }
            .confirmationDialog("Importer data", isPresented: $showImportModeDialog, titleVisibility: .visible) {
            Button("Slå sammen med eksisterende data") {
                pendingImportMode = .merge
                showImportPicker = true
            }
            Button("Erstatt all data", role: .destructive) {
                pendingImportMode = .replace
                showImportPicker = true
            }
            Button("Avbryt", role: .cancel) { }
            } message: {
            Text("Velg hvordan importen skal håndtere data som allerede finnes.")
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [UTType.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert("Kunne ikke importere data", isPresented: $showImportError) {
            Button("OK", role: .cancel) { }
            } message: {
            Text(importMessage.isEmpty ? "Kontroller filen og prøv igjen." : importMessage)
            }
            .alert("Import fullført", isPresented: $showImportSuccess) {
            Button("OK", role: .cancel) { }
            } message: {
            Text(importMessage)
            }
            .alert("Slett alle data?", isPresented: $showDeleteAllConfirm) {
            Button("Avbryt", role: .cancel) { }
            Button("Slett alt", role: .destructive) {
                do {
                    try viewModel.deleteAllData(context: modelContext)
                    showDeleteAllSuccess = true
                } catch {
                    showDeleteAllError = true
                }
            }
            } message: {
            Text("Dette sletter budsjett, investeringer, mål og innstillinger lokalt på enheten.")
            }
            .alert("Kunne ikke slette data", isPresented: $showDeleteAllError) {
            Button("OK", role: .cancel) { }
            } message: {
            Text("Prøv igjen litt senere.")
            }
            .alert(
                "Kunne ikke lagre innstilling",
                isPresented: Binding(
                    get: { settingsErrorMessage != nil },
                    set: { if !$0 { settingsErrorMessage = nil } }
                )
            ) {
            Button("OK", role: .cancel) {
                settingsErrorMessage = nil
            }
            } message: {
            Text(settingsErrorMessage ?? "")
            }
            .alert("Alle data er slettet", isPresented: $showDeleteAllSuccess) {
            Button("OK", role: .cancel) { }
            } message: {
            Text("Appen er nullstilt lokalt.")
            }
            .alert("Lastet demo", isPresented: $showDemoLoadSuccess) {
            Button("OK", role: .cancel) { }
            } message: {
            Text(demoLoadMessage)
            }
            .alert("Kunne ikke laste demo", isPresented: $showDemoLoadError) {
            Button("OK", role: .cancel) { }
            } message: {
            Text("Prøv igjen litt senere.")
            }
            .alert("Tøm alle demo-data?", isPresented: $showDemoWipeConfirm) {
            Button("Avbryt", role: .cancel) { }
            Button("Tøm data", role: .destructive) {
                do {
                    try viewModel.wipeAllDataForDemo(context: modelContext)
                    demoLoadMessage = "Alle lokale data er tømt."
                    showDemoLoadSuccess = true
                    showToast("Alle data tømt ✓")
                } catch {
                    showDemoLoadError = true
                }
            }
            } message: {
            Text("Dette sletter alt lokalt på enheten.")
            }
    }

    private var trustSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Trygg lagring")
                    .appCardTitleStyle()
                Text("Data lagres kun på denne enheten. Ingen bankkobling i denne versjonen.")
                    .appSecondaryStyle()
            }
            .padding(.vertical, 6)
        }
    }

    private var appSettingsSection: some View {
        Section("Appinnstillinger") {
            HStack {
                Text("Valuta")
                    .appBodyStyle()
                Spacer()
                Text("NOK")
                    .appSecondaryStyle()
            }

            HStack {
                Text("Visning")
                    .appBodyStyle()
                Spacer()
                Picker("Visning", selection: appearanceModeBinding) {
                    ForEach(AppAppearancePreference.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(AppTheme.textPrimary)
            }

            HStack {
                Text("Språk")
                    .appBodyStyle()
                Spacer()
                Text("Norsk")
                    .appSecondaryStyle()
            }

            Button {
                showReminderSheet = true
            } label: {
                settingsRow(title: "Månedlig innsjekk", value: reminderSummaryText(), showsChevron: true)
            }
            .buttonStyle(.plain)

            Text("Få et lite dytt for å oppdatere totalsummene dine.")
                .appSecondaryStyle()

            Toggle("Face ID-lås", isOn: binding(\.faceIDLockEnabled))
                .appBodyStyle()
        }
    }

    private var budgetAndInvestmentsSection: some View {
        Section("Budsjett og investeringer") {
            NavigationLink {
                FixedItemsView()
            } label: {
                settingsRow(title: "Faste poster", value: "", showsChevron: false)
            }

            Button {
                showBucketTypesSheet = true
            } label: {
                settingsRow(title: "Beholdningstyper", value: bucketSummaryText(), showsChevron: true)
            }
            .buttonStyle(.plain)

            Button {
                showGoalSheet = true
            } label: {
                settingsRow(title: "Mål", value: "", showsChevron: true)
            }
            .buttonStyle(.plain)

            NavigationLink {
                CategoryManagementView()
            } label: {
                settingsRow(title: "Kategorier", value: "", showsChevron: false)
            }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            HStack {
                Text("Lagring")
                    .appBodyStyle()
                Spacer()
                Text("Kun lokalt")
                    .appSecondaryStyle()
            }

            HStack {
                Text("Lagringsmodus")
                    .appBodyStyle()
                Spacer()
                Text(storeModeText())
                    .appSecondaryStyle()
            }

            Button {
                do {
                    shareItem = ShareURL(try viewModel.exportData(context: modelContext))
                } catch {
                    showExportError = true
                }
            } label: {
                settingsRow(title: "Eksporter data", value: "", showsChevron: true)
            }
            .buttonStyle(.plain)

            Button {
                showImportModeDialog = true
            } label: {
                settingsRow(title: "Importer data", value: "", showsChevron: true)
            }
            .buttonStyle(.plain)

            Text("Eksport oppretter en JSON-kopi. Import kan slå sammen eller erstatte lokale data.")
                .appSecondaryStyle()

            if Simple_Budget___Budskjett_planlegger_gjort_enkeltApp.activeStoreMode != .primary {
                Text("Recovery/midlertidig modus betyr at primær lagring ikke kunne åpnes.")
                    .appSecondaryStyle()
            }
        }
    }

    private var aboutSection: some View {
        Section("Om appen") {
            Button {
                if let url = URL(string: "mailto:hei@simplebudget.app") {
                    openURL(url)
                }
            } label: {
                settingsRow(title: "Kontakt", value: "", showsChevron: true)
            }
            .buttonStyle(.plain)

            NavigationLink {
                PrivacyInfoView()
            } label: {
                settingsRow(title: "Personvern", value: "", showsChevron: false)
            }

            NavigationLink {
                TermsInfoView()
            } label: {
                settingsRow(title: "Vilkår", value: "", showsChevron: false)
            }

            NavigationLink {
                AboutAppView()
            } label: {
                settingsRow(title: "Versjon", value: appVersionText(), showsChevron: false)
            }
        }
    }

    private var demoSection: some View {
        Section("Demo-verktøy") {
            Button("Last inn demo (3 år realistisk)") {
                do {
                    let report = try viewModel.seedDemoRealisticYear(context: modelContext, year: nil)
                    demoLoadMessage = "Demo (3 år) lastet ✓\n\nMåneder: \(report.budgetMonths)\nTransaksjoner: \(report.transactions)\nSnapshots: \(report.snapshots)"
                    showDemoLoadSuccess = true
                    showToast("Demo (3 år) lastet ✓")
                } catch {
                    showDemoLoadError = true
                }
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                showDemoWipeConfirm = true
            } label: {
                Text("Tøm alle data")
            }
            .buttonStyle(.plain)
            Text("Kun for testing i debug/TestFlight.")
                .appSecondaryStyle()
        }
    }

    private var destructiveSection: some View {
        Section("Farlige handlinger") {
            Button(role: .destructive) {
                showDeleteAllConfirm = true
            } label: {
                settingsRow(title: "Slett all data", value: "", showsChevron: false)
            }
            .buttonStyle(.plain)

            Text("Dette kan ikke angres.")
                .appSecondaryStyle()
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            demoToastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.2)) {
                demoToastMessage = nil
            }
        }
    }

    private func persistSettingsChanges(syncReminder: Bool) {
        do {
            try viewModel.save(context: modelContext)
        } catch {
            settingsErrorMessage = "Kunne ikke lagre endringen."
            return
        }

        guard syncReminder else { return }
        Task { @MainActor in
            do {
                try await viewModel.syncCheckInReminder(preference: pref)
            } catch {
                settingsErrorMessage = error.localizedDescription
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            if case .failure(let error) = result {
                importMessage = error.localizedDescription
                showImportError = true
            }
            return
        }

        guard let url = urls.first else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let report = try viewModel.importData(from: url, mode: pendingImportMode, context: modelContext)
            importMessage = importSuccessText(report)
            showImportSuccess = true
            Task { @MainActor in
                do {
                    try await viewModel.syncCheckInReminder(preference: pref)
                } catch {
                    settingsErrorMessage = error.localizedDescription
                }
            }
        } catch {
            importMessage = error.localizedDescription
            showImportError = true
        }
    }

    private func importSuccessText(_ report: DataImportReport) -> String {
        "\(report.mode.title) fullført.\n\n" +
        "Måneder: \(report.budgetMonths)\n" +
        "Kategorier: \(report.categories)\n" +
        "Transaksjoner: \(report.transactions)\n" +
        "Snapshots: \(report.snapshots)"
    }

    private var appearanceModeBinding: Binding<AppAppearancePreference> {
        Binding(
            get: { AppAppearancePreference(rawValue: appAppearanceModeRawValue) ?? .followSystem },
            set: { appAppearanceModeRawValue = $0.rawValue }
        )
    }

    private func settingsRow(title: String, value: String, showsChevron: Bool) -> some View {
        HStack {
            Text(title)
                .appBodyStyle()
            Spacer()
            if !value.isEmpty {
                Text(value)
                    .appSecondaryStyle()
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func reminderTimeText() -> String {
        String(format: "%02d:%02d", pref.checkInReminderHour, pref.checkInReminderMinute)
    }

    private func reminderSummaryText() -> String {
        guard pref.checkInReminderEnabled else { return "Av" }
        return "På · \(pref.checkInReminderDay). kl \(reminderTimeText())"
    }

    private func bucketSummaryText() -> String {
        let activeCount = investmentBuckets.filter { $0.isActive }.count
        if activeCount == 1 { return "1 aktiv" }
        return "\(activeCount) aktive"
    }

    private func applyReminderSettings(enabled: Bool, day: Int, hour: Int, minute: Int) {
        pref.checkInReminderEnabled = enabled
        pref.checkInReminderDay = max(1, min(28, day))
        pref.checkInReminderHour = max(0, min(23, hour))
        pref.checkInReminderMinute = max(0, min(59, minute))
        persistSettingsChanges(syncReminder: true)
    }

    private func appVersionText() -> String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(short) (\(build))"
    }

    private func storeModeText() -> String {
        switch Simple_Budget___Budskjett_planlegger_gjort_enkeltApp.activeStoreMode {
        case .primary:
            return "Primær"
        case .recovery:
            return "Recovery"
        case .memoryOnly:
            return "Midlertidig"
        }
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<UserPreference, T>) -> Binding<T> {
        Binding(
            get: { pref[keyPath: keyPath] },
            set: {
                pref[keyPath: keyPath] = $0
                persistSettingsChanges(syncReminder: false)
            }
        )
    }
}

private struct ShareURL: Identifiable {
    let id = UUID()
    let url: URL
    init(_ url: URL) { self.url = url }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct ReminderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var enabled: Bool
    @State private var selectedDay: Int
    @State private var time: Date

    let onSave: (Bool, Int, Int, Int) -> Void

    init(
        enabled: Bool,
        day: Int,
        hour: Int,
        minute: Int,
        onSave: @escaping (Bool, Int, Int, Int) -> Void
    ) {
        self._enabled = State(initialValue: enabled)
        self._selectedDay = State(initialValue: max(1, min(28, day)))

        var components = DateComponents()
        components.hour = max(0, min(23, hour))
        components.minute = max(0, min(59, minute))
        self._time = State(initialValue: Calendar.current.date(from: components) ?? .now)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Månedlig innsjekk", isOn: $enabled)
                    .appBodyStyle()

                if enabled {
                    Stepper("Dag i måneden: \(selectedDay)", value: $selectedDay, in: 1...28)
                    DatePicker("Klokkeslett", selection: $time, displayedComponents: [.hourAndMinute])
                        .datePickerStyle(.compact)

                    Text("iOS kan be om varslingstillatelse hvis den ikke allerede er gitt.")
                        .appSecondaryStyle()
                } else {
                    Text("Påminnelser er av. Du kan fortsatt oppdatere manuelt når som helst.")
                        .appSecondaryStyle()
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Månedlig innsjekk")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        let hour = Calendar.current.component(.hour, from: time)
                        let minute = Calendar.current.component(.minute, from: time)
                        onSave(enabled, selectedDay, hour, minute)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct BucketTypesSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InvestmentBucket.sortOrder) private var buckets: [InvestmentBucket]
    @StateObject private var viewModel = InvestmentsViewModel()
    @State private var editMode: EditMode = .inactive

    private var activeBuckets: [InvestmentBucket] {
        buckets.filter(\.isActive).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var hiddenBuckets: [InvestmentBucket] {
        buckets.filter { !$0.isActive }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Aktive typer") {
                    if activeBuckets.isEmpty {
                        Text("Ingen aktive beholdningstyper.")
                            .appSecondaryStyle()
                    } else {
                        ForEach(activeBuckets) { bucket in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(AppTheme.portfolioColor(for: bucket))
                                    .frame(width: 10, height: 10)

                                Text(bucket.name)
                                    .appBodyStyle()

                                Spacer()

                                if editMode == .inactive && activeBuckets.count > 1 {
                                    Button("Skjul") {
                                        viewModel.hideBucket(bucket, context: modelContext)
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .buttonStyle(.bordered)
                                    .tint(AppTheme.textSecondary)
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

                Section("Skjulte typer") {
                    if hiddenBuckets.isEmpty {
                        Text("Ingen skjulte beholdningstyper.")
                            .appSecondaryStyle()
                    } else {
                        ForEach(hiddenBuckets) { bucket in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(AppTheme.portfolioColor(for: bucket).opacity(0.4))
                                    .frame(width: 10, height: 10)

                                Text(bucket.name)
                                    .appSecondaryStyle()

                                Spacer()

                                Button("Vis") {
                                    viewModel.restoreBucket(bucket, context: modelContext, existingBuckets: buckets)
                                }
                                .font(.footnote.weight(.semibold))
                                .buttonStyle(.bordered)
                                .tint(AppTheme.primary)
                            }
                        }
                    }
                }

                Section("Ny beholdningstype") {
                    TextField("Navn på type", text: $viewModel.newBucketName)
                        .textFieldStyle(.appInput)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(AppTheme.customBucketPalette, id: \.self) { hex in
                                let selected = viewModel.selectedBucketColorHex == hex
                                Button {
                                    viewModel.selectedBucketColorHex = hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 26, height: 26)
                                        .overlay {
                                            Circle()
                                                .stroke(selected ? AppTheme.textPrimary : AppTheme.divider, lineWidth: selected ? 2 : 1)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button("Legg til type") {
                        _ = viewModel.addBucket(context: modelContext, existingBuckets: buckets)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
                    .disabled(viewModel.newBucketName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let addError = viewModel.addBucketError {
                        Text(addError)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.negative)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Beholdningstyper")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Lukk") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if activeBuckets.count > 1 {
                        EditButton()
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .onAppear {
                viewModel.ensureDefaultBuckets(context: modelContext, existingBuckets: buckets)
            }
            .alert(
                "Kunne ikke lagre",
                isPresented: Binding(
                    get: { viewModel.persistenceErrorMessage != nil },
                    set: { if !$0 { viewModel.clearPersistenceError() } }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewModel.clearPersistenceError()
                }
            } message: {
                Text(viewModel.persistenceErrorMessage ?? "")
            }
        }
    }
}

private struct PrivacyInfoView: View {
    var body: some View {
        List {
            Text("Appen lagrer data lokalt på enheten din.")
            Text("Ingen sporing eller tredjepartsannonser brukes i MVP.")
            Text("Du kan eksportere en lokal JSON-kopi fra Innstillinger > Data.")
            Text("Du kan også slette alle lokale data fra Innstillinger > Data.")
        }
        .navigationTitle("Personvern")
    }
}

private struct TermsInfoView: View {
    var body: some View {
        List {
            Text("Enkelt Budsjett leveres uten garantier i MVP-fasen.")
            Text("Du er ansvarlig for egne data og sikker lagring av eksportfiler.")
            Text("Appen tilbyr planlegging og oversikt, ikke økonomisk rådgivning.")
        }
        .navigationTitle("Vilkår")
    }
}

private struct AboutAppView: View {
    private var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Versjon \(short) (\(build))"
    }

    var body: some View {
        List {
            Text("Enkelt Budsjett")
                .appCardTitleStyle()
            Text(versionText)
                .appSecondaryStyle()
        }
        .navigationTitle("Om appen")
    }
}
