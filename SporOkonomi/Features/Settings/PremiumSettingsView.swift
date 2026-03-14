import SwiftUI
import StoreKit

private struct PremiumFeatureItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
}

struct PremiumSettingsView: View {
    let privacyPolicyURL: URL?
    let termsURL: URL?

    @Environment(\.openURL) private var openURL
    @State private var isRestoringPurchases = false
    @State private var restoreResultMessage: String?
    @State private var showPremiumComingSoon = false

    private let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")

    private let featureItems: [PremiumFeatureItem] = [
        .init(
            id: "history",
            icon: "clock.arrow.circlepath",
            title: "Mer historikk",
            detail: "Se utviklingen over lengre tid."
        ),
        .init(
            id: "goals",
            icon: "target",
            title: "Flere mål",
            detail: "Folg malene dine med tydeligere progresjon."
        ),
        .init(
            id: "insights",
            icon: "text.alignleft",
            title: "Dypere innsikt",
            detail: "Fa mer kontekst rundt okonomien din uten unodvendig stoy."
        ),
        .init(
            id: "investments",
            icon: "chart.line.uptrend.xyaxis",
            title: "Utvidet investeringsoversikt",
            detail: "Se mer av utviklingen over tid."
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard
                featuresCard
                whyPremiumCard
                planCard
                ctaCard
                footerLinks
            }
            .padding(16)
        }
        .background(AppTheme.background)
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Premium kommer snart", isPresented: $showPremiumComingSoon) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Premium-skjermen er klar, men abonnement er ikke koblet til App Store ennå.")
        }
        .alert(
            "Gjenopprett kjøp",
            isPresented: Binding(
                get: { restoreResultMessage != nil },
                set: { if !$0 { restoreResultMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                restoreResultMessage = nil
            }
        } message: {
            Text(restoreResultMessage ?? "")
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spor økonomi Premium")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Mer historikk, flere verktøy og en enda bedre oversikt.")
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(22)
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
        .shadow(color: AppTheme.primary.opacity(0.08), radius: 18, y: 10)
    }

    private var featuresCard: some View {
        premiumCard(title: "Dette får du") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(featureItems) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 18, height: 18)
                            .padding(8)
                            .background(AppTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(item.detail)
                                .appSecondaryStyle()
                        }
                    }
                }
            }
        }
    }

    private var whyPremiumCard: some View {
        premiumCard(title: "Hvorfor Premium") {
            Text("Premium gjør det mulig å utvikle appen videre uten reklame og uten å gå på kompromiss med enkelheten.")
                .appSecondaryStyle()
        }
    }

    private var planCard: some View {
        premiumCard(title: "Plan") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Enkelt abonnement")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text("Kommer snart")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                }

                Text("Pris og prøveperiode vises her når abonnementet er koblet til App Store.")
                    .appSecondaryStyle()

                Text("Kjøp, administrasjon og oppsigelse håndteres i App Store.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var ctaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showPremiumComingSoon = true
            } label: {
                Text("Prøv Premium")
                    .frame(maxWidth: .infinity)
            }
            .appProminentCTAStyle()

            Button {
                restorePurchases()
            } label: {
                HStack(spacing: 8) {
                    if isRestoringPurchases {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Gjenopprett kjøp")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(AppTheme.textPrimary)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.divider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isRestoringPurchases)
        }
    }

    private var footerLinks: some View {
        VStack(alignment: .leading, spacing: 10) {
            footerLink("Vilkår", url: termsURL)
            footerLink("Personvern", url: privacyPolicyURL)
            footerLink("Administrer abonnement", url: manageSubscriptionsURL)
        }
        .padding(.top, 2)
    }

    private func premiumCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .appCardTitleStyle()
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.divider.opacity(0.8), lineWidth: 1)
        )
    }

    private func footerLink(_ title: String, url: URL?) -> some View {
        Button {
            guard let url else { return }
            openURL(url)
        } label: {
            HStack {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }

    private func restorePurchases() {
        guard !isRestoringPurchases else { return }
        isRestoringPurchases = true

        Task {
            do {
                try await AppStore.sync()
                restoreResultMessage = "Kjøpene dine er oppdatert via App Store."
            } catch {
                restoreResultMessage = "Kunne ikke gjenopprette kjøp akkurat nå."
            }
            isRestoringPurchases = false
        }
    }
}
