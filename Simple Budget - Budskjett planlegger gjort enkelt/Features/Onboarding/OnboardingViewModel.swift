import Foundation
import Combine
import SwiftData

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var includeIncome = false
    @Published var monthlyIncome = 0.0
    @Published var bucketToggles: [String: Bool] = [
        "Fond": true,
        "Aksjer": true,
        "IPS": true,
        "Krypto": true
    ]
    @Published var customBucketName = ""

    func selectedBuckets() -> [String] {
        let selected = bucketToggles.filter(\.value).map(\.key).sorted()
        return selected.isEmpty ? ["Fond", "Aksjer", "IPS", "Krypto"] : selected
    }

    func complete(context: ModelContext, preference: UserPreference) {
        try? OnboardingService.complete(
            context: context,
            preference: preference,
            includeIncome: includeIncome,
            monthlyIncome: includeIncome ? monthlyIncome : nil,
            selectedBuckets: selectedBuckets(),
            customBucketName: customBucketName
        )
    }
}
