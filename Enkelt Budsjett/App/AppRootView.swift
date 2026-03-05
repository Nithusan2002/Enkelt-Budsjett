import SwiftUI
import SwiftData
import UIKit

enum AppTab {
    case overview
    case budget
    case investments
    case tips
    case settings
    #if DEBUG
    case debug
    #endif
}

enum AppAppearancePreference: String, CaseIterable {
    case followSystem
    case light
    case dark

    var title: String {
        switch self {
        case .followSystem:
            return "Følg system"
        case .light:
            return "Lys"
        case .dark:
            return "Mørk"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .followSystem:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

struct AppRootView: View {
    // Midlertidig skjult i navigasjonen, beholdt i kodebasen for senere aktivering.
    private let showTipsTab = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var preferences: [UserPreference]
    @AppStorage("app_appearance_mode") private var appAppearanceModeRawValue = AppAppearancePreference.followSystem.rawValue
    @StateObject private var viewModel = AppRootViewModel()
    @StateObject private var navigationState = AppNavigationState()
    @State private var bootstrapAttempted = false

    private var preference: UserPreference? { preferences.first }
    private var activeStoreMode: AppStoreMode { Simple_Budget___Budskjett_planlegger_gjort_enkeltApp.activeStoreMode }
    private var preferredColorScheme: ColorScheme? {
        (AppAppearancePreference(rawValue: appAppearanceModeRawValue) ?? .followSystem).colorScheme
    }
    private var shouldShowStoreModeBanner: Bool {
        if activeStoreMode == .memoryOnly {
            return true
        }
        guard preference?.onboardingCompleted ?? false else { return false }
        return activeStoreMode != .primary
    }
    private var shouldUseFaceIDLock: Bool {
        if ProcessInfo.processInfo.arguments.contains("UITEST_DISABLE_FACEID") {
            return false
        }
        guard preference?.onboardingCompleted ?? false else {
            return false
        }
        return preference?.faceIDLockEnabled ?? false
    }

    var body: some View {
        ZStack {
            Group {
                if let preference {
                    if !preference.onboardingCompleted {
                        OnboardingView(preference: preference)
                    } else {
                        TabView(selection: $navigationState.selectedTab) {
                            NavigationStack { OverviewView() }
                                .tabItem { Label("Oversikt", systemImage: "chart.pie.fill") }
                                .tag(AppTab.overview)

                            NavigationStack { InvestmentsView() }
                                .tabItem { Label("Investeringer", systemImage: "chart.line.uptrend.xyaxis") }
                                .tag(AppTab.investments)

                            NavigationStack { BudgetView() }
                                .tabItem { Label("Budsjett", systemImage: "list.bullet.rectangle") }
                                .tag(AppTab.budget)

                            if showTipsTab {
                                NavigationStack { TipsTriksView() }
                                    .tabItem { Label("Tips & Triks", systemImage: "lightbulb") }
                                    .tag(AppTab.tips)
                            }

                            NavigationStack { SettingsView() }
                                .tabItem { Label("Innstillinger", systemImage: "gear") }
                                .tag(AppTab.settings)

                            #if DEBUG
                            NavigationStack { DebugMenuView() }
                                .tabItem { Label("Debug", systemImage: "hammer") }
                                .tag(AppTab.debug)
                            #endif
                        }
                        .environmentObject(navigationState)
                    }
                } else {
                    BootstrapLoadingView(
                        phase: viewModel.bootstrapPhase,
                        errorMessage: viewModel.bootstrapErrorMessage,
                        showRetry: bootstrapAttempted
                    ) {
                        viewModel.bootstrap(context: modelContext)
                    }
                }
            }

            if shouldUseFaceIDLock && viewModel.isLocked {
                lockOverlay
                    .transition(.opacity)
                    .zIndex(5)
            }

            if shouldShowStoreModeBanner {
                VStack {
                    storeModeBanner
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .zIndex(4)
            }
        }
        .tint(AppTheme.primary)
        .background(AppTheme.background.ignoresSafeArea())
        .foregroundStyle(AppTheme.textPrimary)
        .preferredColorScheme(preferredColorScheme)
        .task {
            guard !bootstrapAttempted else { return }
            applyBarAppearance()
            bootstrapAttempted = true
            viewModel.bootstrap(context: modelContext)
        }
        .onAppear {
            applyBarAppearance()
            viewModel.configureLock(enabled: shouldUseFaceIDLock)
        }
        .onChange(of: shouldUseFaceIDLock) { _, newValue in
            viewModel.configureLock(enabled: newValue)
        }
        .onChange(of: scenePhase) { _, newValue in
            viewModel.handleScenePhaseChange(newValue)
        }
        .onChange(of: preferredColorScheme) { _, _ in
            applyBarAppearance()
        }
    }

    private func applyBarAppearance() {
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(AppTheme.surface)
        tabAppearance.shadowColor = UIColor(AppTheme.divider)

        let normalColor = UIColor(AppTheme.textSecondary)
        let selectedColor = UIColor(AppTheme.primary)
        tabAppearance.stackedLayoutAppearance.normal.iconColor = normalColor
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        tabAppearance.stackedLayoutAppearance.selected.iconColor = selectedColor
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(AppTheme.textPrimary)]
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(AppTheme.textPrimary)]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(AppTheme.primary)
    }

    private var lockOverlay: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "faceid")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                Text("Face ID-lås")
                    .font(.title3.weight(.semibold))
                Text("Lås opp for å fortsette")
                    .appSecondaryStyle()
                if viewModel.isAuthenticating {
                    ProgressView()
                }
                if let lockError = viewModel.lockErrorMessage {
                    Text(lockError)
                        .appSecondaryStyle()
                        .multilineTextAlignment(.center)
                }
                Button("Prøv igjen") {
                    viewModel.retryUnlock()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
            }
            .padding(24)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.divider, lineWidth: 1))
            .padding(24)
        }
    }

    private var storeModeBanner: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.primary)
            Text(storeModeMessage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Spacer(minLength: 8)
            Button("Innstillinger") {
                navigationState.selectedTab = .settings
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(AppTheme.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.divider, lineWidth: 1)
        )
        .accessibilityLabel(storeModeMessage)
    }

    private var storeModeMessage: String {
        switch activeStoreMode {
        case .primary:
            return ""
        case .primaryWithoutCloud:
            return "Appen kjører lokalt uten iCloud-synk. Sjekk iCloud-innstillinger på enheten."
        case .recovery:
            return "Appen kjører i recovery-lagring. Primær lagring kunne ikke åpnes."
        case .memoryOnly:
            return "Appen kjører midlertidig uten varig lagring. Skrivende handlinger er låst til normal lagring er tilbake."
        }
    }
}

private struct BootstrapLoadingView: View {
    let phase: BootstrapPhase
    let errorMessage: String?
    let showRetry: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Klargjør appen")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Text(phase.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                ProgressView(value: phase.progress, total: 1)
                    .tint(AppTheme.primary)

                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.surfaceElevated)
                        .frame(height: 14)
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.surfaceElevated)
                        .frame(height: 14)
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.surfaceElevated)
                        .frame(height: 14)
                }
            }
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.divider, lineWidth: 1)
            )

            if let errorMessage {
                Text(errorMessage)
                    .appSecondaryStyle()
                    .multilineTextAlignment(.center)
            }

            if showRetry {
                Button("Prøv igjen") {
                    onRetry()
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.primary)
            }
        }
        .padding(24)
    }
}
