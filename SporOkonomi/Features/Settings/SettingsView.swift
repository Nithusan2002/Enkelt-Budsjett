import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    private let privacyPolicyURL = URL(string: "https://nithusan2002.github.io/spor-okonomi/personvern/")
    private let termsURL = URL(string: "https://nithusan2002.github.io/spor-okonomi/vilkar/")

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var sessionStore: SessionStore
    @Query private var preferences: [UserPreference]
    @Query(sort: \InvestmentBucket.sortOrder) private var investmentBuckets: [InvestmentBucket]
    @AppStorage("app_appearance_mode") private var appAppearanceModeRawValue = AppAppearancePreference.followSystem.rawValue
    @State private var viewModel = SettingsViewModel()

    @State private var showReminderSheet = false
    @State private var showGoalSheet = false
    @State private var showBucketTypesSheet = false
    @State private var shareItem: ShareURL?
    @State private var sharedExportURL: URL?
    @State private var showExportError = false
    @State private var exportMessage = ""
    @State private var showDeleteAllConfirm = false
    @State private var showDeleteAllError = false
    @State private var showDeleteAllSuccess = false
    @State private var showDeleteAccountConfirm = false
    @State private var showDeleteAccountSuccess = false
    @State private var showDemoLoadError = false
    @State private var showDemoLoadSuccess = false
    @State private var showDemoWipeConfirm = false
    @State private var showImportModeDialog = false
    @State private var showImportPicker = false
    @State private var showImportError = false
    @State private var showImportSuccess = false
    @State private var pendingImportMode: DataImportMode = .merge
    @State private var pendingImportURL: URL?
    @State private var importMessage = ""
    @State private var settingsErrorMessage: String?
    @State private var ensuredPreference: UserPreference?
    @State private var demoLoadMessage = ""
    @State private var demoToastMessage: String?
    @State private var emailAuthMode: EmailAuthMode?

    private var pref: UserPreference {
        if let existing = preferences.first ?? ensuredPreference {
            return existing
        }
        assertionFailure("Preference should be available before settings form is rendered.")
        return UserPreference()
    }
    private var isReadOnlyMode: Bool { PersistenceGate.isReadOnlyMode }

    var body: some View {
        Group {
            if preferences.first == nil && ensuredPreference == nil {
                ProgressView("Laster inn innstillinger…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(AppTheme.background)
                    .onAppear {
                        ensurePreference()
                    }
            } else {
                configuredForm
            }
        }
    }

    private var baseForm: some View {
        Form {
            settingsHomeSection
        }
        .onAppear {
            ensurePreference()
        }
        .onChange(of: preferences.count) { _, _ in
            ensurePreference()
        }
        .task {
            await viewModel.refreshDemoToolVisibilityIfNeeded()
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
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showReminderSheet) {
            ReminderSettingsSheet(
                enabled: pref.checkInReminderEnabled,
                day: pref.checkInReminderDay
            ) { enabled, day in
                applyReminderSettings(enabled: enabled, day: day)
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
            .sheet(item: $shareItem, onDismiss: {
                cleanupSharedExportFile()
            }) { item in
            ShareSheet(activityItems: [item.url]) {
                cleanupSharedExportFile()
            }
            }
            .sheet(item: $emailAuthMode) { mode in
                EmailAuthSheetView(mode: mode) { email, password, displayName in
                    switch mode {
                    case .signUp:
                        await sessionStore.createAccountWithEmail(
                            email: email,
                            password: password,
                            displayName: displayName,
                            preference: pref,
                            context: modelContext
                        )
                    case .signIn:
                        await sessionStore.signInWithEmail(
                            email: email,
                            password: password,
                            preference: pref,
                            context: modelContext
                        )
                    }
                }
            }
    }

    private var formWithAlerts: some View {
        formWithSheets
            .alert("Kunne ikke eksportere data", isPresented: $showExportError) {
            Button("OK", role: .cancel) { }
            } message: {
            Text(exportMessage.isEmpty ? "Prøv igjen litt senere." : exportMessage)
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
                allowedContentTypes: [UTType.json, UTType.data],
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
            .alert("Slett lokale data?", isPresented: $showDeleteAllConfirm) {
            Button("Avbryt", role: .cancel) { }
            Button("Slett lokale data", role: .destructive) {
                do {
                    try viewModel.deleteAllData(context: modelContext)
                    showDeleteAllSuccess = true
                } catch {
                    showDeleteAllError = true
                }
            }
            } message: {
            Text("Dette sletter budsjett, investeringer, mål og innstillinger lokalt på denne enheten. Dette sletter ikke kontoen din.")
            }
            .alert("Kunne ikke slette data", isPresented: $showDeleteAllError) {
            Button("OK", role: .cancel) { }
            } message: {
            Text("Prøv igjen litt senere.")
            }
            .alert("Slett konto?", isPresented: $showDeleteAccountConfirm) {
            Button("Avbryt", role: .cancel) { }
            Button("Slett konto", role: .destructive) {
                Task {
                    if await sessionStore.deleteAccount(preference: pref, context: modelContext) {
                        showDeleteAccountSuccess = true
                    }
                }
            }
            } message: {
            Text("Dette sletter kontoen din og rydder lokale data på denne enheten. iCloud-data fjernes når slettingen er synkronisert.")
            }
            .alert("Konto slettet", isPresented: $showDeleteAccountSuccess) {
            Button("OK", role: .cancel) { }
            } message: {
            Text("Kontoen din er slettet, og appen er nullstilt lokalt.")
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
            .onChange(of: viewModel.preferencePersistenceErrorMessage) { _, newValue in
                guard let newValue else { return }
                settingsErrorMessage = newValue
                viewModel.clearPreferencePersistenceError()
            }
            .onChange(of: sessionStore.authErrorMessage) { _, newValue in
                guard let newValue else { return }
                settingsErrorMessage = newValue
                sessionStore.clearError()
            }
    }

    private var accountSection: some View {
        SettingsAccountSection(
            authEmail: pref.authEmail,
            isReadOnlyMode: isReadOnlyMode,
            onCreateAccount: {
                emailAuthMode = .signUp
            },
            onSignInWithEmail: {
                emailAuthMode = .signIn
            },
            onSignInWithGoogle: {
                Task {
                    await sessionStore.signInWithGoogle(preference: pref, context: modelContext)
                }
            },
            onSignOut: {
                sessionStore.signOut(preference: pref, context: modelContext)
            }
        )
    }

    private var settingsHomeSection: some View {
        Section {
            NavigationLink {
                AccountSettingsHomeView(
                    authEmail: pref.authEmail,
                    isReadOnlyMode: isReadOnlyMode,
                    onCreateAccount: {
                        emailAuthMode = .signUp
                    },
                    onSignInWithEmail: {
                        emailAuthMode = .signIn
                    },
                    onSignInWithGoogle: {
                        Task {
                            await sessionStore.signInWithGoogle(preference: pref, context: modelContext)
                        }
                    },
                    onSignOut: {
                        sessionStore.signOut(preference: pref, context: modelContext)
                    }
                )
            } label: {
                settingsRow(title: "Konto og synk", value: accountOverviewText(), showsChevron: true)
            }
            .buttonStyle(.plain)

            NavigationLink {
                AppSettingsHomeView(
                    pref: pref,
                    isReadOnlyMode: isReadOnlyMode,
                    appearanceModeBinding: appearanceModeBinding,
                    settingsErrorMessage: $settingsErrorMessage,
                    onPersistSettings: persistSettingsChanges,
                    onApplyReminderSettings: applyReminderSettings
                )
            } label: {
                settingsRow(title: "Appinnstillinger", value: currentAppearanceMode.title, showsChevron: true)
            }
            .buttonStyle(.plain)

            NavigationLink {
                EconomySettingsHomeView(
                    pref: pref,
                    isReadOnlyMode: isReadOnlyMode,
                    investmentBuckets: investmentBuckets
                )
            } label: {
                settingsRow(title: "Økonomi", value: "", showsChevron: true)
            }
            .buttonStyle(.plain)

            NavigationLink {
                DataPrivacySettingsHomeView(
                    isReadOnlyMode: isReadOnlyMode,
                    storageLocationText: storageLocationText(),
                    storeModeText: storeModeText(),
                    storeModeDetailText: storeModeDetailText(),
                    isAuthenticated: sessionStore.isAuthenticated,
                    shouldShowDemoTools: viewModel.shouldShowDemoTools(),
                    onExport: performExport,
                    onImport: { showImportModeDialog = true },
                    onConfirmDeleteAccount: { showDeleteAccountConfirm = true },
                    onConfirmDeleteAll: { showDeleteAllConfirm = true },
                    onLoadDemo: {
                        do {
                            let report = try viewModel.seedDemoRealisticYear(context: modelContext, year: nil)
                            demoLoadMessage = "Demo (3 år) lastet ✓\n\nMåneder: \(report.budgetMonths)\nTransaksjoner: \(report.transactions)\nSnapshots: \(report.snapshots)"
                            showDemoLoadSuccess = true
                            showToast("Demo (3 år) lastet ✓")
                        } catch {
                            showDemoLoadError = true
                        }
                    },
                    onConfirmDemoWipe: { showDemoWipeConfirm = true }
                )
            } label: {
                settingsRow(title: "Data og personvern", value: storageLocationText(), showsChevron: true)
            }
            .buttonStyle(.plain)

            NavigationLink {
                AboutAppView()
            } label: {
                settingsRow(title: "Om appen", value: appVersionText(), showsChevron: true)
            }
            .buttonStyle(.plain)
        }
    }

    private var appSettingsSection: some View {
        Section {
            NavigationLink {
                AppearanceSettingsView(selection: appearanceModeBinding)
            } label: {
                settingsRow(title: "Visning", value: currentAppearanceMode.title, showsChevron: true)
            }
            .buttonStyle(.plain)

            NavigationLink {
                LanguageSettingsView()
            } label: {
                settingsRow(title: "Språk", value: "Norsk", showsChevron: true)
            }
            .buttonStyle(.plain)

            Toggle(isOn: reminderEnabledBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Månedlig innsjekk")
                        .appBodyStyle()
                    Text(reminderToggleSubtitle())
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .disabled(isReadOnlyMode)

            if pref.checkInReminderEnabled {
                Button {
                    showReminderSheet = true
                } label: {
                    settingsRow(title: "Påminnelsesdag", value: "\(pref.checkInReminderDay). i måneden", showsChevron: true)
                }
                .buttonStyle(.plain)
                .disabled(isReadOnlyMode)
            }

            Toggle("Face ID-lås", isOn: binding(\.faceIDLockEnabled))
                .appBodyStyle()
                .disabled(isReadOnlyMode)
        } header: {
            sectionHeader("Appinnstillinger")
        } footer: {
            if isReadOnlyMode {
                Text("Skrivende handlinger er midlertidig deaktivert.")
            }
        }
    }

    private var budgetAndInvestmentsSection: some View {
        Section {
            NavigationLink {
                FixedItemsView()
            } label: {
                settingsRow(title: "Faste poster", value: "", showsChevron: true)
            }
            .buttonStyle(.plain)

            Button {
                showBucketTypesSheet = true
            } label: {
                settingsRow(title: "Beholdningstyper", value: bucketSummaryText(), showsChevron: true)
            }
            .buttonStyle(.plain)

            Button {
                showGoalSheet = true
            } label: {
                settingsRow(title: "Formue Mål", value: "", showsChevron: true)
            }
            .buttonStyle(.plain)

            NavigationLink {
                CategoryManagementView()
            } label: {
                settingsRow(title: "Kategorier", value: "", showsChevron: true)
            }
            .buttonStyle(.plain)
        } header: {
            sectionHeader("Økonomi")
        }
        .disabled(isReadOnlyMode)
    }

    private var dataSection: some View {
        Section {
            NavigationLink {
                StorageDiagnosticsView(
                    storageLocationText: storageLocationText(),
                    storeModeText: storeModeText(),
                    storeModeDetailText: storeModeDetailText(),
                    isReadOnlyMode: isReadOnlyMode
                )
            } label: {
                settingsRow(title: "Lagring", value: storageLocationText(), showsChevron: true)
            }
            .buttonStyle(.plain)

            Button {
                performExport()
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
            .disabled(isReadOnlyMode)

            Button {
                guard let privacyPolicyURL else { return }
                openURL(privacyPolicyURL)
            } label: {
                settingsRow(title: "Personvern", value: "", showsChevron: true)
            }
            .buttonStyle(.plain)

            Button {
                guard let termsURL else { return }
                openURL(termsURL)
            } label: {
                settingsRow(title: "Vilkår", value: "", showsChevron: true)
            }
            .buttonStyle(.plain)
        } header: {
            sectionHeader("Data og personvern")
        } footer: {
            Text("Importer eller eksporter en kopi av dataene dine.")
        }
    }

    private var aboutSection: some View {
        Section {
            Button {
                if let url = URL(string: "mailto:sporokonomi.app@gmail.com") {
                    openURL(url)
                }
            } label: {
                settingsRow(title: "Kontakt", value: "", showsChevron: true)
            }
            .buttonStyle(.plain)

            NavigationLink {
                AboutAppView()
            } label: {
                settingsRow(title: "Versjon", value: appVersionText(), showsChevron: true)
            }
            .buttonStyle(.plain)
        } header: {
            sectionHeader("Om appen")
        }
    }

    private var advancedSection: some View {
        Section {
            NavigationLink {
                StorageDiagnosticsView(
                    storageLocationText: storageLocationText(),
                    storeModeText: storeModeText(),
                    storeModeDetailText: storeModeDetailText(),
                    isReadOnlyMode: isReadOnlyMode
                )
            } label: {
                settingsRow(title: "Synk og diagnose", value: storeModeText(), showsChevron: true)
            }
            .buttonStyle(.plain)

            if viewModel.shouldShowDemoTools() {
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
                .disabled(isReadOnlyMode)

                Button(role: .destructive) {
                    showDemoWipeConfirm = true
                } label: {
                    destructiveSettingsRow(title: "Tøm demo-data")
                }
                .buttonStyle(.plain)
            }
        } header: {
            sectionHeader("Avansert")
        } footer: {
            Text("Viser teknisk lagringsstatus og demo-verktøy som bør brukes med omtanke.")
        }
    }

    private var dangerousActionsSection: some View {
        Section {
            if sessionStore.isAuthenticated {
                Button(role: .destructive) {
                    showDeleteAccountConfirm = true
                } label: {
                    destructiveSettingsRow(title: "Slett konto")
                }
                .buttonStyle(.plain)
            }

            Button(role: .destructive) {
                showDeleteAllConfirm = true
            } label: {
                destructiveSettingsRow(title: "Slett lokale data")
            }
            .buttonStyle(.plain)
        } header: {
            sectionHeader("Farlige handlinger", tone: .destructive, topPadding: 18)
        } footer: {
            Text("Disse handlingene kan ikke angres.")
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

    private func performExport() {
        do {
            let url = try viewModel.exportData(context: modelContext)
            shareItem = ShareURL(url)
            sharedExportURL = url
            exportMessage = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 600) {
                if sharedExportURL == url {
                    cleanupSharedExportFile()
                }
            }
        } catch {
            exportMessage = error.localizedDescription
            showExportError = true
        }
    }

    private func cleanupSharedExportFile() {
        guard let url = sharedExportURL else { return }
        try? FileManager.default.removeItem(at: url)
        sharedExportURL = nil
        shareItem = nil
    }

    private func ensurePreference() {
        if let existing = preferences.first {
            ensuredPreference = existing
            return
        }
        guard ensuredPreference == nil else { return }
        ensuredPreference = viewModel.preference(from: preferences, context: modelContext)
    }

    private func persistSettingsChanges(syncReminder: Bool) {
        guard !isReadOnlyMode else {
            settingsErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
            return
        }
        do {
            try viewModel.save(context: modelContext)
        } catch {
            settingsErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Kunne ikke lagre endringen."
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
        pendingImportURL = url
        performImport()
    }

    private func performImport() {
        guard !isReadOnlyMode else {
            importMessage = PersistenceWriteError.readOnlyMode.localizedDescription
            showImportError = true
            return
        }
        guard let url = pendingImportURL else { return }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
            pendingImportURL = nil
        }

        do {
            let report = try viewModel.importData(
                from: url,
                mode: pendingImportMode,
                context: modelContext,
                password: nil
            )
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
        let backupLine = report.backupFileName.map { "\nBackup: \($0)" } ?? ""
        return "\(report.mode.title) fullført.\n\n" +
        "Måneder: \(report.budgetMonths)\n" +
        "Kategorier: \(report.categories)\n" +
        "Transaksjoner: \(report.transactions)\n" +
        "Snapshots: \(report.snapshots)" +
        backupLine
    }

    private var appearanceModeBinding: Binding<AppAppearancePreference> {
        Binding(
            get: { AppAppearancePreference(rawValue: appAppearanceModeRawValue) ?? .followSystem },
            set: { appAppearanceModeRawValue = $0.rawValue }
        )
    }

    private var currentAppearanceMode: AppAppearancePreference {
        AppAppearancePreference(rawValue: appAppearanceModeRawValue) ?? .followSystem
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func destructiveSettingsRow(title: String) -> some View {
        HStack {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.negative)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func reminderToggleSubtitle() -> String {
        pref.checkInReminderEnabled ? "På den \(pref.checkInReminderDay). hver måned" : "Av"
    }

    private func accountOverviewText() -> String {
        sessionStore.isAuthenticated ? "Logget inn" : "Ikke logget inn"
    }

    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { pref.checkInReminderEnabled },
            set: { isEnabled in
                guard !isReadOnlyMode else {
                    settingsErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
                    return
                }
                applyReminderSettings(enabled: isEnabled, day: pref.checkInReminderDay)
            }
        )
    }

    private func bucketSummaryText() -> String {
        let activeCount = investmentBuckets.filter { $0.isActive }.count
        if activeCount == 1 { return "1 aktiv" }
        return "\(activeCount) aktive"
    }

    private func applyReminderSettings(enabled: Bool, day: Int) {
        guard !isReadOnlyMode else {
            settingsErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
            return
        }
        pref.checkInReminderEnabled = enabled
        pref.checkInReminderDay = max(1, min(28, day))
        pref.checkInReminderHour = 12
        pref.checkInReminderMinute = 0
        persistSettingsChanges(syncReminder: true)
    }

    private func appVersionText() -> String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (Build \(build))"
    }

    private func storeModeText() -> String {
        switch SporOkonomiApp.activeStoreMode {
        case .primary:
            return "Primær"
        case .primaryWithoutCloud:
            return "Primær (lokal)"
        case .recovery:
            return "Recovery"
        case .memoryOnly:
            return "Midlertidig"
        }
    }

    private func storageLocationText() -> String {
        isCloudSyncActive() ? "iCloud + lokalt" : "Kun lagret lokalt"
    }

    private func isCloudSyncActive() -> Bool {
        SporOkonomiApp.activeStoreMode == .primary
    }

    private func storeModeDetailText() -> String? {
        switch SporOkonomiApp.activeStoreMode {
        case .primary:
            return nil
        case .primaryWithoutCloud:
            var detail = "iCloud-synk er ikke aktiv. Data lagres kun lokalt på denne enheten."
            if let accountStatus = SporOkonomiApp.lastCloudAccountStatus, !accountStatus.isEmpty {
                detail += "\n\nKonto-status: \(accountStatus)"
            }
            if let probe = SporOkonomiApp.lastCloudProbeStatus, !probe.isEmpty {
                detail += "\n\nCloud probe: \(probe)"
            }
            if let analysis = SporOkonomiApp.lastCloudCompatibilityAnalysis, !analysis.isEmpty {
                detail += "\n\nCloud analyse: \(analysis)"
            }
            if let error = SporOkonomiApp.lastCloudInitError, !error.isEmpty {
                detail += "\n\nFeildetaljer: \(error)"
            }
            return detail
        case .recovery, .memoryOnly:
            return "Recovery/midlertidig modus betyr at primær lagring ikke kunne åpnes. Skrivende handlinger er derfor begrenset."
        }
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<UserPreference, T>) -> Binding<T> {
        Binding(
            get: { pref[keyPath: keyPath] },
            set: {
                guard !isReadOnlyMode else {
                    settingsErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
                    return
                }
                pref[keyPath: keyPath] = $0
                persistSettingsChanges(syncReminder: false)
            }
        )
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, tone: SettingsSectionHeaderTone = .default, topPadding: CGFloat = 6) -> some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(tone == .destructive ? AppTheme.negative : AppTheme.textSecondary)
            .textCase(nil)
            .padding(.top, topPadding)
    }
}

private struct ShareURL: Identifiable {
    let id = UUID()
    let url: URL
    init(_ url: URL) { self.url = url }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async {
                onComplete?()
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct ReminderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var enabled: Bool
    @State private var selectedDay: Int

    let onSave: (Bool, Int) -> Void

    init(
        enabled: Bool,
        day: Int,
        onSave: @escaping (Bool, Int) -> Void
    ) {
        self._enabled = State(initialValue: enabled)
        self._selectedDay = State(initialValue: max(1, min(28, day)))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Månedlig innsjekk", isOn: $enabled)
                    .appBodyStyle()

                if enabled {
                    Stepper("Dag i måneden: \(selectedDay)", value: $selectedDay, in: 1...28)
                    Text("Påminnelsen sendes alltid kl 12:00.")
                        .appSecondaryStyle()

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
                        onSave(enabled, selectedDay)
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
                    .appProminentCTAStyle()
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
            Section {
                Text("Spor økonomi lagrer budsjettdata, transaksjoner, mål og innstillinger lokalt på enheten via SwiftData.")
                Text("Ingen tredjepartssporing eller annonse-SDK-er brukes.")
            }
            Section("Konto") {
                Text("Hvis du velger å opprette konto eller logge inn med e-post, behandles e-postadresse, bruker-ID og eventuelt visningsnavn for autentisering.")
            }
            Section("iCloud-synk") {
                Text("Hvis iCloud-synk er aktivert på enheten, synkroniseres data via CloudKit i din Apple-konto. Du styrer dette selv i iOS-innstillinger.")
            }
            Section("Dine data") {
                Text("Du kan eksportere alle data som en JSON-fil fra Innstillinger → Data og personvern.")
                Text("Du kan slette alle lokale data fra Innstillinger → Farlige handlinger.")
            }
            Section("Kontakt") {
                Text("sporokonomi.app@gmail.com")
            }
        }
        .navigationTitle("Personvern")
    }
}

private struct StorageDiagnosticsView: View {
    let storageLocationText: String
    let storeModeText: String
    let storeModeDetailText: String?
    let isReadOnlyMode: Bool

    var body: some View {
        List {
            Section("Lagring") {
                infoRow(title: "Lagring", value: storageLocationText)
                infoRow(title: "Lagringsmodus", value: storeModeText)
            }

            if isReadOnlyMode {
                Section {
                    Text("Appen kjører i midlertidig lagring. Skrivende handlinger er derfor deaktivert til normal lagring er tilbake.")
                }
            }

            if let storeModeDetailText, !storeModeDetailText.isEmpty {
                Section("Diagnose") {
                    Text(storeModeDetailText)
                        .appSecondaryStyle()
                }
            }
        }
        .navigationTitle("Lagring og synk")
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .appBodyStyle()
            Spacer(minLength: 12)
            Text(value)
                .appSecondaryStyle()
                .multilineTextAlignment(.trailing)
        }
    }
}

private enum SettingsSectionHeaderTone {
    case `default`
    case destructive
}

private struct AccountSettingsHomeView: View {
    let authEmail: String?
    let isReadOnlyMode: Bool
    let onCreateAccount: () -> Void
    let onSignInWithEmail: () -> Void
    let onSignInWithGoogle: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        Form {
            SettingsAccountSection(
                authEmail: authEmail,
                isReadOnlyMode: isReadOnlyMode,
                onCreateAccount: onCreateAccount,
                onSignInWithEmail: onSignInWithEmail,
                onSignInWithGoogle: onSignInWithGoogle,
                onSignOut: onSignOut
            )
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Konto og synk")
    }
}

private struct AppSettingsHomeView: View {
    let pref: UserPreference
    let isReadOnlyMode: Bool
    @Binding var appearanceModeBinding: AppAppearancePreference
    @Binding var settingsErrorMessage: String?
    let onPersistSettings: (Bool) -> Void
    let onApplyReminderSettings: (Bool, Int) -> Void

    @State private var showReminderSheet = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    AppearanceSettingsView(selection: $appearanceModeBinding)
                } label: {
                    settingsRow(title: "Visning", value: appearanceModeBinding.title, showsChevron: true)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    settingsRow(title: "Språk", value: "Norsk", showsChevron: true)
                }
                .buttonStyle(.plain)

                Toggle(isOn: reminderEnabledBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Månedlig innsjekk")
                            .appBodyStyle()
                        Text(reminderToggleSubtitle)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .disabled(isReadOnlyMode)

                if pref.checkInReminderEnabled {
                    Button {
                        showReminderSheet = true
                    } label: {
                        settingsRow(title: "Påminnelsesdag", value: "\(pref.checkInReminderDay). i måneden", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(isReadOnlyMode)
                }

                Toggle("Face ID-lås", isOn: faceIDBinding)
                    .appBodyStyle()
                    .disabled(isReadOnlyMode)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Appinnstillinger")
        .sheet(isPresented: $showReminderSheet) {
            ReminderSettingsSheet(
                enabled: pref.checkInReminderEnabled,
                day: pref.checkInReminderDay
            ) { enabled, day in
                onApplyReminderSettings(enabled, day)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { pref.checkInReminderEnabled },
            set: { isEnabled in
                guard !isReadOnlyMode else {
                    settingsErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
                    return
                }
                onApplyReminderSettings(isEnabled, pref.checkInReminderDay)
            }
        )
    }

    private var faceIDBinding: Binding<Bool> {
        Binding(
            get: { pref.faceIDLockEnabled },
            set: { newValue in
                guard !isReadOnlyMode else {
                    settingsErrorMessage = PersistenceWriteError.readOnlyMode.localizedDescription
                    return
                }
                pref.faceIDLockEnabled = newValue
                onPersistSettings(false)
            }
        )
    }

    private var reminderToggleSubtitle: String {
        pref.checkInReminderEnabled ? "På den \(pref.checkInReminderDay). hver måned" : "Av"
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct EconomySettingsHomeView: View {
    let pref: UserPreference
    let isReadOnlyMode: Bool
    let investmentBuckets: [InvestmentBucket]

    @State private var showGoalSheet = false
    @State private var showBucketTypesSheet = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    FixedItemsView()
                } label: {
                    settingsRow(title: "Faste poster", value: "", showsChevron: true)
                }
                .buttonStyle(.plain)

                Button {
                    showBucketTypesSheet = true
                } label: {
                    settingsRow(title: "Beholdningstyper", value: bucketSummaryText, showsChevron: true)
                }
                .buttonStyle(.plain)

                Button {
                    showGoalSheet = true
                } label: {
                    settingsRow(title: "Formue Mål", value: "", showsChevron: true)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    CategoryManagementView()
                } label: {
                    settingsRow(title: "Kategorier", value: "", showsChevron: true)
                }
                .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Økonomi")
        .disabled(isReadOnlyMode)
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
    }

    private var bucketSummaryText: String {
        let activeCount = investmentBuckets.filter(\.isActive).count
        return activeCount == 1 ? "1 aktiv" : "\(activeCount) aktive"
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct DataPrivacySettingsHomeView: View {
    let isReadOnlyMode: Bool
    let storageLocationText: String
    let storeModeText: String
    let storeModeDetailText: String?
    let isAuthenticated: Bool
    let shouldShowDemoTools: Bool
    let onExport: () -> Void
    let onImport: () -> Void
    let onConfirmDeleteAccount: () -> Void
    let onConfirmDeleteAll: () -> Void
    let onLoadDemo: () -> Void
    let onConfirmDemoWipe: () -> Void
    @Environment(\.openURL) private var openURL

    private let privacyPolicyURL = URL(string: "https://nithusan2002.github.io/spor-okonomi/personvern/")
    private let termsURL = URL(string: "https://nithusan2002.github.io/spor-okonomi/vilkar/")

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    StorageDiagnosticsView(
                        storageLocationText: storageLocationText,
                        storeModeText: storeModeText,
                        storeModeDetailText: storeModeDetailText,
                        isReadOnlyMode: isReadOnlyMode
                    )
                } label: {
                    settingsRow(title: "Lagring", value: storageLocationText, showsChevron: true)
                }
                .buttonStyle(.plain)

                Button {
                    onExport()
                } label: {
                    settingsRow(title: "Eksporter data", value: "", showsChevron: true)
                }
                .buttonStyle(.plain)

                Button {
                    onImport()
                } label: {
                    settingsRow(title: "Importer data", value: "", showsChevron: true)
                }
                .buttonStyle(.plain)
                .disabled(isReadOnlyMode)

                Button {
                    guard let privacyPolicyURL else { return }
                    openURL(privacyPolicyURL)
                } label: {
                    settingsRow(title: "Personvern", value: "", showsChevron: true)
                }
                .buttonStyle(.plain)

                Button {
                    guard let termsURL else { return }
                    openURL(termsURL)
                } label: {
                    settingsRow(title: "Vilkår", value: "", showsChevron: true)
                }
                .buttonStyle(.plain)
            }

            Section {
                NavigationLink {
                    StorageDiagnosticsView(
                        storageLocationText: storageLocationText,
                        storeModeText: storeModeText,
                        storeModeDetailText: storeModeDetailText,
                        isReadOnlyMode: isReadOnlyMode
                    )
                } label: {
                    settingsRow(title: "Synk og diagnose", value: storeModeText, showsChevron: true)
                }
                .buttonStyle(.plain)

                if shouldShowDemoTools {
                    Button("Last inn demo (3 år realistisk)") {
                        onLoadDemo()
                    }
                    .buttonStyle(.plain)
                    .disabled(isReadOnlyMode)

                    Button(role: .destructive) {
                        onConfirmDemoWipe()
                    } label: {
                        destructiveSettingsRow(title: "Tøm demo-data")
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Avansert")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(nil)
                    .padding(.top, 6)
            }

            Section {
                if isAuthenticated {
                    Button(role: .destructive) {
                        onConfirmDeleteAccount()
                    } label: {
                        destructiveSettingsRow(title: "Slett konto")
                    }
                    .buttonStyle(.plain)
                }

                Button(role: .destructive) {
                    onConfirmDeleteAll()
                } label: {
                    destructiveSettingsRow(title: "Slett lokale data")
                }
                .buttonStyle(.plain)
            } header: {
                Text("Farlige handlinger")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.negative)
                    .textCase(nil)
                    .padding(.top, 6)
            } footer: {
                Text("Disse handlingene kan ikke angres.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Data og personvern")
    }

    private func settingsRow(title: String, value: String, showsChevron: Bool) -> some View {
        HStack {
            Text(title)
                .appBodyStyle()
            Spacer()
            if !value.isEmpty {
                Text(value)
                    .appSecondaryStyle()
                    .truncationMode(.tail)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func destructiveSettingsRow(title: String) -> some View {
        HStack {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.negative)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct AppearanceSettingsView: View {
    @Binding var selection: AppAppearancePreference

    var body: some View {
        List {
            Section {
                ForEach(AppAppearancePreference.allCases, id: \.rawValue) { mode in
                    Button {
                        selection = mode
                    } label: {
                        HStack {
                            Text(mode.title)
                                .appBodyStyle()
                            Spacer()
                            if selection == mode {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppTheme.primary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Visning")
    }
}

private struct LanguageSettingsView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Norsk")
                        .appBodyStyle()
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                }
            } footer: {
                Text("Norsk er appens aktive språk.")
            }
        }
        .navigationTitle("Språk")
    }
}

private struct TermsInfoView: View {
    var body: some View {
        List {
            Section {
                Text("Spor økonomi gir ikke økonomisk rådgivning. Appen er et planleggings- og oversiktsverktøy.")
                Text("Du er ansvarlig for egne økonomiske beslutninger.")
            }
            Section("Data og sikkerhet") {
                Text("Du er ansvarlig for sikker oppbevaring av eksportfiler, kontoopplysninger og eventuelle passord.")
                Text("Appen leveres uten garantier.")
            }
            Section("Kontakt") {
                Text("sporokonomi.app@gmail.com")
            }
        }
        .navigationTitle("Vilkår")
    }
}

private struct AboutAppView: View {
    @Environment(\.openURL) private var openURL

    private var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Versjon \(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image("Spor-økonomi-applogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 140)
                        .accessibilityHidden(true)

                    VStack(spacing: 4) {
                        Text("Spor økonomi")
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .multilineTextAlignment(.center)
                        Text("En rolig måte å følge budsjett, sparing og investeringer på.")
                            .appBodyStyle()
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)

                aboutCard {
                    VStack(alignment: .leading, spacing: 12) {
                        aboutRow(title: "Versjon", value: versionText)
                        aboutRow(title: "Plattform", value: "iPhone")
                        aboutRow(title: "Lagring", value: "Lokal først med SwiftData")
                    }
                }

                aboutCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Hva appen er laget for")
                            .font(.headline.weight(.semibold))
                        Text("Spor økonomi hjelper deg å få oversikt over hverdagsøkonomi og investeringer uten bankkoblinger, støy eller unødvendig kompleksitet.")
                            .appBodyStyle()
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                aboutCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Kontakt")
                            .font(.headline.weight(.semibold))

                        Button {
                            if let url = URL(string: "mailto:sporokonomi.app@gmail.com") {
                                openURL(url)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("sporokonomi.app@gmail.com")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Text("Send spørsmål, feil eller forslag")
                                        .appSecondaryStyle()
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(AppTheme.primary)
                            }
                            .padding(14)
                            .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(AppTheme.divider, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(AppTheme.background)
        .navigationTitle("Om appen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppTheme.divider, lineWidth: 1)
            )
    }

    private func aboutRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .appSecondaryStyle()
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}
