import SwiftUI
import SwiftData
import UIKit

enum AppTab {
    case overview
    case budget
    case investments
    case tips
    case settings
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
    @StateObject private var sessionStore = SessionStore()
    @State private var bootstrapAttempted = false

    private var preference: UserPreference? { preferences.first }
    private var activeStoreMode: AppStoreMode { SporOkonomiApp.activeStoreMode }
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
                    if sessionStore.requiresAuthChoice {
                        WelcomeAuthView(preference: preference)
                    } else if !preference.onboardingCompleted {
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
        .environmentObject(sessionStore)
        .task {
            guard !bootstrapAttempted else { return }
            applyBarAppearance()
            bootstrapAttempted = true
            viewModel.bootstrap(context: modelContext)
        }
        .onAppear {
            applyBarAppearance()
            viewModel.configureLock(enabled: shouldUseFaceIDLock)
            Task {
                await sessionStore.restore(from: preference, context: modelContext)
            }
        }
        .onChange(of: preference?.authSessionModeRaw) { _, _ in
            Task {
                await sessionStore.restore(from: preference, context: modelContext)
            }
        }
        .onChange(of: preference?.authUserID) { _, _ in
            Task {
                await sessionStore.restore(from: preference, context: modelContext)
            }
        }
        .onChange(of: shouldUseFaceIDLock) { _, newValue in
            viewModel.configureLock(enabled: newValue)
        }
        .onChange(of: scenePhase) { _, newValue in
            viewModel.handleScenePhaseChange(newValue)
            if newValue == .active {
                viewModel.refreshDemoProtection(context: modelContext)
            }
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
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: selectedColor,
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]
        tabAppearance.inlineLayoutAppearance.normal.iconColor = normalColor
        tabAppearance.inlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        tabAppearance.inlineLayoutAppearance.selected.iconColor = selectedColor
        tabAppearance.inlineLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: selectedColor,
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]
        tabAppearance.compactInlineLayoutAppearance.normal.iconColor = normalColor
        tabAppearance.compactInlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        tabAppearance.compactInlineLayoutAppearance.selected.iconColor = selectedColor
        tabAppearance.compactInlineLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: selectedColor,
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().selectionIndicatorImage = tabSelectionIndicatorImage()

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(AppTheme.textPrimary)]
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(AppTheme.textPrimary)]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(AppTheme.primary)
    }

    private func tabSelectionIndicatorImage() -> UIImage? {
        let size = CGSize(width: 76, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 16)
            UIColor(AppTheme.primary).withAlphaComponent(0.12).setFill()
            context.cgContext.addPath(path.cgPath)
            context.cgContext.fillPath()
        }
        .resizableImage(withCapInsets: UIEdgeInsets(top: 16, left: 28, bottom: 16, right: 28))
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
                .appProminentCTAStyle()
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
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 0) {
            Image("Spor-økonomi-applogo")
                .resizable()
                .scaledToFit()
                .frame(height: 88)
                .accessibilityHidden(true)

            Image(systemName: "gearshape.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
                .padding(.top, -6)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: isAnimating)
                .accessibilityHidden(true)

            if let errorMessage {
                Text(errorMessage)
                    .appSecondaryStyle()
                    .multilineTextAlignment(.center)
            }

            if showRetry, errorMessage != nil {
                Button("Prøv igjen") {
                    onRetry()
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.primary)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isAnimating = true
        }
    }
}
