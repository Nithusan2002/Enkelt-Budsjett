import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var preferences: [UserPreference]
    @StateObject private var viewModel = SettingsViewModel()

    @State private var showDayPicker = false
    @State private var showTimePicker = false
    @State private var shareItem: ShareURL?
    @State private var showExportError = false
    @State private var showDeleteAllConfirm = false
    @State private var showDeleteAllError = false
    @State private var showDeleteAllSuccess = false
    @State private var showDemoLoadError = false
    @State private var showDemoLoadSuccess = false
    @State private var showDemoWipeConfirm = false
    @State private var demoLoadMessage = ""
    @State private var demoToastMessage: String?

    private var pref: UserPreference { viewModel.preference(from: preferences, context: modelContext) }

    var body: some View {
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
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Innstillinger")
        .sheet(isPresented: $showDayPicker) {
            ReminderDayPickerSheet(selectedDay: pref.checkInReminderDay) { day in
                pref.checkInReminderDay = day
                viewModel.save(context: modelContext)
            }
        }
        .sheet(isPresented: $showTimePicker) {
            ReminderTimePickerSheet(
                selectedHour: pref.checkInReminderHour,
                selectedMinute: pref.checkInReminderMinute
            ) { hour, minute in
                pref.checkInReminderHour = hour
                pref.checkInReminderMinute = minute
                viewModel.save(context: modelContext)
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .alert("Kunne ikke eksportere data", isPresented: $showExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Prøv igjen litt senere.")
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
                Text("Følg systemet")
                    .appSecondaryStyle()
            }

            HStack {
                Text("Språk")
                    .appBodyStyle()
                Spacer()
                Text("Norsk")
                    .appSecondaryStyle()
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Månedlig insjekk", isOn: binding(\.checkInReminderEnabled))
                    .appBodyStyle()
                Text("Få et lite dytt for å oppdatere totalsummene dine.")
                    .appSecondaryStyle()
            }

            if pref.checkInReminderEnabled {
                Button {
                    showDayPicker = true
                } label: {
                    settingsRow(title: "Dag i måneden", value: "\(pref.checkInReminderDay).", showsChevron: true)
                }
                .buttonStyle(.plain)

                Button {
                    showTimePicker = true
                } label: {
                    settingsRow(title: "Klokkeslett", value: reminderTimeText(), showsChevron: true)
                }
                .buttonStyle(.plain)
            }

            Toggle("Face ID-lås", isOn: binding(\.faceIDLockEnabled))
                .appBodyStyle()
        }
    }

    private var budgetAndInvestmentsSection: some View {
        Section("Budsjett og investeringer") {
            NavigationLink {
                FixedItemsView()
            } label: {
                settingsRow(title: "Faste poster", value: "", showsChevron: true)
            }

            NavigationLink {
                InvestmentsView()
            } label: {
                settingsRow(title: "Investeringsbøtter", value: "", showsChevron: true)
            }

            NavigationLink {
                GoalEditorView(goal: nil)
            } label: {
                settingsRow(title: "Mål", value: "", showsChevron: true)
            }

            HStack {
                Text("Kategorier")
                    .appBodyStyle()
                Spacer()
                Text("Kommer snart")
                    .appSecondaryStyle()
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

            HStack {
                Text("Importer data")
                    .appBodyStyle()
                Spacer()
                Text("Kommer snart")
                    .appSecondaryStyle()
            }
            // TODO(settings): Implementer importflyt (filvalg + validering + merge/replace) etter MVP.

            Text("Eksport oppretter en JSON-kopi av alle lokale data.")
                .appSecondaryStyle()
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
                settingsRow(title: "Personvern", value: "", showsChevron: true)
            }

            NavigationLink {
                TermsInfoView()
            } label: {
                settingsRow(title: "Vilkår", value: "", showsChevron: true)
            }

            NavigationLink {
                AboutAppView()
            } label: {
                settingsRow(title: "Versjon", value: appVersionText(), showsChevron: true)
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

    private func appVersionText() -> String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(short) (\(build))"
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<UserPreference, T>) -> Binding<T> {
        Binding(
            get: { pref[keyPath: keyPath] },
            set: {
                pref[keyPath: keyPath] = $0
                viewModel.save(context: modelContext)
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

private struct ReminderDayPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State var selectedDay: Int
    let onSave: (Int) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Picker("Dag i måneden", selection: $selectedDay) {
                    ForEach(1...28, id: \.self) { day in
                        Text("\(day).")
                            .tag(day)
                    }
                }
                .pickerStyle(.wheel)
            }
            .navigationTitle("Dag i måneden")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        onSave(selectedDay)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ReminderTimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var time: Date
    let onSave: (Int, Int) -> Void

    init(selectedHour: Int, selectedMinute: Int, onSave: @escaping (Int, Int) -> Void) {
        var components = DateComponents()
        components.hour = selectedHour
        components.minute = selectedMinute
        self._time = State(initialValue: Calendar.current.date(from: components) ?? .now)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Klokkeslett", selection: $time, displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.wheel)
            }
            .navigationTitle("Klokkeslett")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        let hour = Calendar.current.component(.hour, from: time)
                        let minute = Calendar.current.component(.minute, from: time)
                        onSave(hour, minute)
                        dismiss()
                    }
                }
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
