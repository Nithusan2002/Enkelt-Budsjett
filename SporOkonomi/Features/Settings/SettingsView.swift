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
    @EnvironmentObject private var navigationState: AppNavigationState
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
    @State private var showExportPasswordSheet = false
    @State private var exportMessage = ""
    @State private var exportPassword = ""
    @State private var exportPasswordConfirmation = ""
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
    @State private var showImportPasswordSheet = false
    @State private var showImportSuccess = false
    @State private var showAccountSettingsHome = false
    @State private var pendingImportMode: DataImportMode = .merge
    @State private var pendingImportURL: URL?
    @State private var importPassword = ""
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
                Color.clear
                    .frame(height: 86)
                    .allowsHitTesting(false)
            }
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
            .sheet(isPresented: $showExportPasswordSheet) {
            NavigationStack {
                SecureExportSheet(
                    password: $exportPassword,
                    confirmation: $exportPasswordConfirmation,
                    onCancel: {
                        resetExportPasswordState()
                        showExportPasswordSheet = false
                    },
                    onConfirm: {
                        performExport()
                    }
                )
            }
            }
            .sheet(isPresented: $showImportPasswordSheet, onDismiss: {
                resetImportPasswordState()
            }) {
            NavigationStack {
                SecureImportSheet(
                    password: $importPassword,
                    onCancel: {
                        pendingImportURL = nil
                        showImportPasswordSheet = false
                    },
                    onConfirm: {
                        performImport()
                    }
                )
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
            .navigationDestination(isPresented: $showAccountSettingsHome) {
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
            .alert("Kunne ikke slette data", isPresented: $showDeleteAllError) {
            Button("OK", role: .cancel) { }
            } message: {
            Text("Prøv igjen litt senere.")
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
            .onAppear {
                openPendingSettingsRouteIfNeeded()
            }
            .onChange(of: navigationState.pendingSettingsRoute) { _, _ in
                openPendingSettingsRouteIfNeeded()
            }
    }

    private func openPendingSettingsRouteIfNeeded() {
        guard navigationState.selectedTab == .settings,
              navigationState.pendingSettingsRoute == .account else {
            return
        }

        navigationState.pendingSettingsRoute = nil
        showAccountSettingsHome = true
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
                settingsRow(title: "Konto og synk", value: accountOverviewText(), showsChevron: false)
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
                settingsRow(title: "Appinnstillinger", value: currentAppearanceMode.title, showsChevron: false)
            }
            .buttonStyle(.plain)

            NavigationLink {
                EconomySettingsHomeView(
                    pref: pref,
                    isReadOnlyMode: isReadOnlyMode,
                    investmentBuckets: investmentBuckets
                )
            } label: {
                settingsRow(title: "Økonomi", value: "", showsChevron: false)
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
                    onExport: {
                        resetExportPasswordState()
                        showExportPasswordSheet = true
                    },
                    onImport: { showImportModeDialog = true },
                    onConfirmDeleteAccount: {
                        Task {
                            if await sessionStore.deleteAccount(preference: pref, context: modelContext) {
                                showDeleteAccountSuccess = true
                            }
                        }
                    },
                    onConfirmDeleteAll: {
                        do {
                            try viewModel.deleteAllData(context: modelContext)
                            showDeleteAllSuccess = true
                        } catch {
                            showDeleteAllError = true
                        }
                    },
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
                    onLoadMarketingDemo: {
                        do {
                            let report = try viewModel.seedMarketingDemo(context: modelContext)
                            demoLoadMessage = "Marketing-demo lastet ✓\n\nMåneder: \(report.budgetMonths)\nTransaksjoner: \(report.transactions)\nSnapshots: \(report.snapshots)"
                            showDemoLoadSuccess = true
                            showToast("Marketing-demo lastet ✓")
                        } catch {
                            showDemoLoadError = true
                        }
                    },
                    onConfirmDemoWipe: {
                        do {
                            try viewModel.wipeAllDataForDemo(context: modelContext)
                            demoLoadMessage = "Alle lokale data er tømt."
                            showDemoLoadSuccess = true
                            showToast("Alle data tømt ✓")
                        } catch {
                            showDemoLoadError = true
                        }
                    }
                )
            } label: {
                settingsRow(title: "Data og personvern", value: storageLocationText(), showsChevron: false)
            }
            .buttonStyle(.plain)

            NavigationLink {
                AboutAppView()
            } label: {
                settingsRow(title: "Om appen", value: appVersionText(), showsChevron: false)
            }
            .buttonStyle(.plain)

            NavigationLink {
                FAQSettingsView()
            } label: {
                settingsRow(title: "Vanlige spørsmål", value: "Data, konto og tillatelser", showsChevron: false)
            }
            .buttonStyle(.plain)
        }
    }

    private var appSettingsSection: some View {
        Section {
            NavigationLink {
                AppearanceSettingsView(selection: appearanceModeBinding)
            } label: {
                settingsRow(title: "Visning", value: currentAppearanceMode.title, showsChevron: false)
            }
            .buttonStyle(.plain)

            NavigationLink {
                LanguageSettingsView()
            } label: {
                settingsRow(title: "Språk", value: "Norsk", showsChevron: false)
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

            Toggle(isOn: binding(\.faceIDLockEnabled)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Face ID-lås")
                        .appBodyStyle()
                    Text("Ber om Face ID eller kode når appen åpnes igjen på denne enheten.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
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
                settingsRow(title: "Faste poster", value: "", showsChevron: false)
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
                settingsRow(title: "Kategorier", value: "", showsChevron: false)
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
                settingsRow(title: "Lagring", value: storageLocationText(), showsChevron: false)
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
            Text("Data lagres lokalt som standard. Her kan du lese mer, eksportere eller importere en kopi av dataene dine.")
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
                settingsRow(title: "Versjon", value: appVersionText(), showsChevron: false)
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
                settingsRow(title: "Synk og diagnose", value: storeModeText(), showsChevron: false)
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
        let trimmedPassword = exportPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirmation = exportPasswordConfirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassword.isEmpty else {
            exportMessage = DataTransferError.passwordRequiredForEncryptedExport.localizedDescription
            showExportPasswordSheet = false
            showExportError = true
            return
        }
        guard trimmedPassword == trimmedConfirmation else {
            exportMessage = "Passordene må være like."
            showExportPasswordSheet = false
            showExportError = true
            return
        }

        do {
            let url = try viewModel.exportData(context: modelContext, password: trimmedPassword)
            shareItem = ShareURL(url)
            sharedExportURL = url
            exportMessage = ""
            resetExportPasswordState()
            showExportPasswordSheet = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 600) {
                if sharedExportURL == url {
                    cleanupSharedExportFile()
                }
            }
        } catch {
            exportMessage = error.localizedDescription
            showExportPasswordSheet = false
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
        importPassword = ""
        showImportPasswordSheet = true
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
                password: normalizedImportPassword()
            )
            importMessage = importSuccessText(report)
            resetImportPasswordState()
            showImportPasswordSheet = false
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
            showImportPasswordSheet = false
            showImportError = true
        }
    }

    private func resetExportPasswordState() {
        exportPassword = ""
        exportPasswordConfirmation = ""
    }

    private func resetImportPasswordState() {
        importPassword = ""
    }

    private func normalizedImportPassword() -> String? {
        let trimmed = importPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
        pref.checkInReminderEnabled ? "Varsel på den \(pref.checkInReminderDay). hver måned" : "Av"
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
            return "Lokal + iCloud"
        case .primaryWithoutCloud:
            return "Kun lokal"
        case .recovery:
            return "Recovery (lokal)"
        case .memoryOnly:
            return "Midlertidig"
        }
    }

    private func storageLocationText() -> String {
        isCloudSyncActive() ? "Lokalt + iCloud via Apple" : "Kun lagret lokalt"
    }

    private func isCloudSyncActive() -> Bool {
        SporOkonomiApp.activeStoreMode == .primary
    }

    private func storeModeDetailText() -> String? {
        switch SporOkonomiApp.activeStoreMode {
        case .primary:
            return nil
        case .primaryWithoutCloud:
            var detail = "iCloud-synk via Apple er ikke aktiv nå. Data lagres derfor bare på denne enheten."
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
        case .recovery:
            var detail = "Primær lagring kunne ikke åpnes. Appen bruker en separat recovery-lagring på denne enheten."
            if let error = SporOkonomiApp.lastCloudInitError, !error.isEmpty {
                detail += "\n\nFeildetaljer: \(error)"
            }
            return detail
        case .memoryOnly:
            return "Appen kjører midlertidig uten varig lagring. Endringer kan ikke lagres permanent."
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

private struct SecureExportSheet: View {
    @Binding var password: String
    @Binding var confirmation: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                SecureField("Passord", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Bekreft passord", text: $confirmation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("Eksportfilen lagres kryptert. Du trenger dette passordet for å importere filen senere.")
            }
        }
        .navigationTitle("Kryptert eksport")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") {
                    onCancel()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Eksporter") {
                    onConfirm()
                    dismiss()
                }
            }
        }
    }
}

private struct SecureImportSheet: View {
    @Binding var password: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                SecureField("Passord (valgfritt)", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("Skriv inn passord hvis filen er kryptert. La feltet stå tomt for eldre ukrypterte eksportfiler.")
            }
        }
        .navigationTitle("Importer data")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") {
                    onCancel()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Importer") {
                    onConfirm()
                    dismiss()
                }
            }
        }
    }
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

                    Text("Når du slår dette på, kan iOS be om tillatelse til varsler. Det brukes bare til månedlig innsjekk.")
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
                Text("Spor økonomi lagrer budsjettdata, transaksjoner, mål og innstillinger lokalt på enheten.")
                Text("Appen bruker ikke annonser, tredjepartssporing eller bankkobling.")
            }
            Section("Konto") {
                Text("Du kan bruke appen uten konto. Hvis du velger å opprette konto eller logge inn, brukes kontoopplysningene bare til innlogging, gjenoppretting og synk der det er relevant.")
            }
            Section("iCloud-synk") {
                Text("Hvis iCloud-synk er aktiv på enheten, synkes data via Apple sin CloudKit i din egen Apple-konto. Dette styres av iOS og din iCloud-innstilling.")
            }
            Section("Dine data") {
                Text("Du kan eksportere alle data som en JSON-fil fra Innstillinger → Data og personvern.")
                Text("Du kan slette alle lokale data fra Innstillinger → Data og personvern → Farlige handlinger.")
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
                Text("Lokal lagring er alltid utgangspunktet. Hvis iCloud er tilgjengelig, brukes den via Apple-kontoen din.")
                    .appSecondaryStyle()
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
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 86)
                .allowsHitTesting(false)
        }
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
                    settingsRow(title: "Visning", value: appearanceModeBinding.title, showsChevron: false)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    settingsRow(title: "Språk", value: "Norsk", showsChevron: false)
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

                Toggle(isOn: faceIDBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Face ID-lås")
                            .appBodyStyle()
                        Text("Ber om Face ID eller kode når appen åpnes igjen på denne enheten.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .disabled(isReadOnlyMode)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Appinnstillinger")
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 86)
                .allowsHitTesting(false)
        }
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
        pref.checkInReminderEnabled ? "Varsel på den \(pref.checkInReminderDay). hver måned" : "Av"
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
                    settingsRow(title: "Faste poster", value: "", showsChevron: false)
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
                    settingsRow(title: "Kategorier", value: "", showsChevron: false)
                }
                .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Økonomi")
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 86)
                .allowsHitTesting(false)
        }
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
    private enum DangerousAction: String, Identifiable {
        case wipeDemo
        case deleteAccount
        case deleteLocalData

        var id: String { rawValue }

        var initialTitle: String {
            switch self {
            case .wipeDemo:
                return "Tøm demo-data?"
            case .deleteAccount:
                return "Slett konto?"
            case .deleteLocalData:
                return "Slett lokale data?"
            }
        }

        var initialMessage: String {
            switch self {
            case .wipeDemo:
                return "Dette sletter alt lokalt på enheten."
            case .deleteAccount:
                return "Dette sletter kontoen din og rydder lokale data på denne enheten. iCloud-data fjernes når slettingen er synkronisert."
            case .deleteLocalData:
                return "Dette sletter budsjett, investeringer, mål og innstillinger lokalt på denne enheten. Dette sletter ikke kontoen din."
            }
        }

        var finalTitle: String {
            switch self {
            case .wipeDemo, .deleteLocalData:
                return "Er du helt sikker?"
            case .deleteAccount:
                return "Slette konto permanent?"
            }
        }

        var finalMessage: String {
            switch self {
            case .wipeDemo:
                return "Demo-dataene blir slettet permanent fra denne enheten."
            case .deleteAccount:
                return "Kontoen din blir slettet permanent. Denne handlingen kan ikke angres."
            case .deleteLocalData:
                return "Alle lokale data på denne enheten blir slettet. Denne handlingen kan ikke angres."
            }
        }

        var confirmTitle: String {
            switch self {
            case .wipeDemo:
                return "Ja, tøm demo-data"
            case .deleteAccount:
                return "Ja, slett konto"
            case .deleteLocalData:
                return "Ja, slett lokale data"
            }
        }
    }

    private enum DangerousConfirmation: Identifiable {
        case initial(DangerousAction)
        case final(DangerousAction)

        var id: String {
            switch self {
            case .initial(let action):
                return "initial-\(action.id)"
            case .final(let action):
                return "final-\(action.id)"
            }
        }
    }

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
    let onLoadMarketingDemo: () -> Void
    let onConfirmDemoWipe: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var dangerousConfirmation: DangerousConfirmation?
    @State private var showDemoLoadConfirm = false
    @State private var showMarketingDemoLoadConfirm = false

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
                    settingsRow(title: "Lagring", value: storageLocationText, showsChevron: false)
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
                    settingsRow(title: "Synk og diagnose", value: storeModeText, showsChevron: false)
                }
                .buttonStyle(.plain)

                if shouldShowDemoTools {
                    Button("Last inn marketing-demo") {
                        showMarketingDemoLoadConfirm = true
                    }
                    .buttonStyle(.plain)
                    .disabled(isReadOnlyMode)

                    Button("Last inn demo (3 år realistisk)") {
                        showDemoLoadConfirm = true
                    }
                    .buttonStyle(.plain)
                    .disabled(isReadOnlyMode)

                    Button(role: .destructive) {
                        dangerousConfirmation = .initial(.wipeDemo)
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
                        dangerousConfirmation = .initial(.deleteAccount)
                    } label: {
                        destructiveSettingsRow(title: "Slett konto")
                    }
                    .buttonStyle(.plain)
                }

                Button(role: .destructive) {
                    dangerousConfirmation = .initial(.deleteLocalData)
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
        .alert("Last inn demo-data?", isPresented: $showDemoLoadConfirm) {
            Button("Avbryt", role: .cancel) { }
            Button("Last inn demo", role: .destructive) {
                onLoadDemo()
            }
        } message: {
            Text("Dette erstatter lokale data på denne enheten med demo-data.")
        }
        .alert("Last inn marketing-demo?", isPresented: $showMarketingDemoLoadConfirm) {
            Button("Avbryt", role: .cancel) { }
            Button("Last inn marketing-demo", role: .destructive) {
                onLoadMarketingDemo()
            }
        } message: {
            Text("Dette erstatter lokale data på denne enheten med et kuratert demooppsett for screenshots og markedsflater.")
        }
        .alert(item: $dangerousConfirmation) { confirmation in
            switch confirmation {
            case .initial(let action):
                return Alert(
                    title: Text(action.initialTitle),
                    message: Text(action.initialMessage),
                    primaryButton: .destructive(Text(action.confirmTitle)) {
                        dangerousConfirmation = .final(action)
                    },
                    secondaryButton: .cancel(Text("Avbryt"))
                )
            case .final(let action):
                return Alert(
                    title: Text(action.finalTitle),
                    message: Text(action.finalMessage),
                    primaryButton: .destructive(Text(action.confirmTitle)) {
                        switch action {
                        case .wipeDemo:
                            onConfirmDemoWipe()
                        case .deleteAccount:
                            onConfirmDeleteAccount()
                        case .deleteLocalData:
                            onConfirmDeleteAll()
                        }
                    },
                    secondaryButton: .cancel(Text("Avbryt"))
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 86)
                .allowsHitTesting(false)
        }
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
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 86)
                .allowsHitTesting(false)
        }
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

private struct FAQSettingsView: View {
    private struct FAQItem: Identifiable {
        let id: String
        let question: String
        let answer: String
    }

    private struct FAQSection: Identifiable {
        let id: String
        let title: String
        let items: [FAQItem]
    }

    private let sections: [FAQSection] = [
        FAQSection(
            id: "privacy",
            title: "Data og personvern",
            items: [
        FAQItem(
            id: "storage",
            question: "Hvor lagres dataene mine?",
            answer: "Som standard lagres data lokalt på denne enheten. Hvis iCloud er aktiv, kan de også synkes via Apple-kontoen din."
        ),
        FAQItem(
            id: "account",
            question: "Må jeg ha konto for å bruke appen?",
            answer: "Nei. Du kan bruke appen fullt lokalt uten konto og logge inn senere hvis du vil."
        ),
        FAQItem(
            id: "with-account",
            question: "Hva skjer hvis jeg bruker konto?",
            answer: "Konto brukes til innlogging, gjenoppretting og synk der det er tilgjengelig. Lokal bruk på enheten fortsetter fortsatt som før."
        ),
        FAQItem(
            id: "tracking",
            question: "Bruker appen sporing eller annonsering?",
            answer: "Nei. Spor økonomi bruker ikke annonser, tredjepartssporing eller bankkoblinger."
        ),
        FAQItem(
            id: "export-delete",
            question: "Hvordan fungerer eksport og sletting?",
            answer: "Du kan eksportere data som en fil fra Data og personvern. Du kan også slette lokale data derfra hvis du vil rydde eller starte på nytt."
        ),
        FAQItem(
            id: "permissions",
            question: "Hvilke tillatelser kan appen be om?",
            answer: "Varsler brukes bare til månedlig innsjekk hvis du slår dem på. Face ID brukes bare til å låse opp appen på denne enheten hvis du aktiverer det."
        )
            ]
        ),
        FAQSection(
            id: "product",
            title: "Bruk av appen",
            items: [
                FAQItem(
                    id: "bank",
                    question: "Må jeg koble til banken min?",
                    answer: "Nei. Spor økonomi fungerer uten bankkobling. Du legger inn inntekter, utgifter og verdier selv."
                ),
                FAQItem(
                    id: "available",
                    question: "Hva betyr \"Tilgjengelig denne måneden\"?",
                    answer: "Det er beløpet du har igjen å bruke denne måneden basert på det du har lagt inn så langt."
                ),
                FAQItem(
                    id: "limits",
                    question: "Må jeg sette budsjettgrenser for å bruke appen?",
                    answer: "Nei. Du kan føre transaksjoner uten grenser. Grenser gir bare mer oversikt i budsjettet."
                ),
                FAQItem(
                    id: "investments",
                    question: "Hvordan fungerer investeringer i appen?",
                    answer: "Du legger inn samlet verdi når du vil oppdatere utviklingen. Appen følger verdiene over tid, men henter ikke live-data."
                )
            ]
        )
    ]

    @State private var expandedQuestionID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary.opacity(0.78))
                            .padding(.horizontal, 4)
                            .padding(.top, index == 0 ? 0 : 12)

                        VStack(spacing: 0) {
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                VStack(spacing: 0) {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            expandedQuestionID = expandedQuestionID == item.id ? nil : item.id
                                        }
                                    } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            Text(item.question)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(AppTheme.textPrimary)
                                                .multilineTextAlignment(.leading)
                                                .frame(maxWidth: .infinity, alignment: .leading)

                                            Image(systemName: expandedQuestionID == item.id ? "chevron.up" : "chevron.down")
                                                .font(.caption2.weight(.medium))
                                                .foregroundStyle(AppTheme.textSecondary.opacity(0.58))
                                                .padding(.top, 3)
                                        }
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    if expandedQuestionID == item.id {
                                        Text(item.answer)
                                            .appSecondaryStyle()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.bottom, 10)
                                    }
                                }

                                if index < section.items.count - 1 {
                                    Divider()
                                        .padding(.leading, 2)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(AppTheme.divider, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(AppTheme.background)
        .navigationTitle("Vanlige spørsmål")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AboutAppView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    private var versionText: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var heroAssetName: String {
        colorScheme == .dark ? "About-AppIcon-Dark" : "About-AppIcon-Light"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    Image(heroAssetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 152)
                        .accessibilityHidden(true)

                    VStack(spacing: 6) {
                        Text("Spor økonomi")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("Få kontroll på økonomien din uten stress")
                            .appBodyStyle()
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 2)

                aboutCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Hva appen er laget for")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Spor økonomi gir deg enkel oversikt over inntekter, utgifter, sparing og investeringer – uten bankkoblinger eller kompliserte oppsett.")
                            .appBodyStyle()
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                aboutCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Trygg og enkel økonomioversikt")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        VStack(alignment: .leading, spacing: 12) {
                            aboutTrustRow(
                                icon: "externaldrive.badge.checkmark",
                                text: "Data lagres lokalt først"
                            )
                            aboutTrustRow(
                                icon: "building.columns",
                                text: "Ingen banktilgang kreves"
                            )
                            aboutTrustRow(
                                icon: "slider.horizontal.3",
                                text: "Full kontroll på dine egne tall"
                            )
                        }
                    }
                }

                aboutCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Trenger du hjelp?")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Button {
                            if let url = URL(string: "mailto:sporokonomi.app@gmail.com") {
                                openURL(url)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("sporokonomi.app@gmail.com")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Text("Send spørsmål, forslag eller tilbakemelding.")
                                        .appSecondaryStyle()
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .padding(16)
                            .background(AppTheme.surfaceElevated.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(AppTheme.divider.opacity(0.75), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                aboutInfoCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .navigationTitle("Om appen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(17)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppTheme.divider.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: AppTheme.primary.opacity(0.05), radius: 16, x: 0, y: 6)
    }

    private func aboutTrustRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 20)

            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private var aboutInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            aboutInfoRow(title: "Versjon", value: versionText)
            aboutInfoRow(title: "Lagring", value: "Lokal først")
            aboutInfoRow(title: "Plattform", value: "iPhone")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .background(AppTheme.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.divider.opacity(0.55), lineWidth: 1)
        )
    }

    private func aboutInfoRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
