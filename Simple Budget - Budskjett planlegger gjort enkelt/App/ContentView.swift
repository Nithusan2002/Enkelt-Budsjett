import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        AppRootView()
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}

private enum PreviewData {
    static let container: ModelContainer = {
        let schema = Schema([
            BudgetMonth.self,
            Category.self,
            BudgetPlan.self,
            Transaction.self,
            Account.self,
            InvestmentBucket.self,
            InvestmentSnapshot.self,
            InvestmentSnapshotValue.self,
            Goal.self,
            Challenge.self,
            UserPreference.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        context.insert(UserPreference(onboardingCompleted: true))
        context.insert(InvestmentBucket(id: "bucket_fund", name: "Fond", isDefault: true, sortOrder: 1))
        context.insert(InvestmentBucket(id: "bucket_stock", name: "Aksjer", isDefault: true, sortOrder: 2))
        context.insert(InvestmentBucket(id: "bucket_ips", name: "IPS", isDefault: true, sortOrder: 3))
        context.insert(InvestmentBucket(id: "bucket_crypto", name: "Krypto", isDefault: true, sortOrder: 4))

        let key = DateService.periodKey(from: .now)
        let values = [
            InvestmentSnapshotValue(periodKey: key, bucketID: "bucket_fund", amount: 100_000),
            InvestmentSnapshotValue(periodKey: key, bucketID: "bucket_stock", amount: 35_000),
            InvestmentSnapshotValue(periodKey: key, bucketID: "bucket_ips", amount: 20_000),
            InvestmentSnapshotValue(periodKey: key, bucketID: "bucket_crypto", amount: 8_000)
        ]
        context.insert(InvestmentSnapshot(periodKey: key, capturedAt: .now, totalValue: 163_000, bucketValues: values))
        if let targetDate = Calendar.current.date(byAdding: .year, value: 2, to: .now) {
            context.insert(Goal(targetAmount: 450_000, targetDate: targetDate, includeAccounts: true))
        }

        try? context.save()
        return container
    }()
}
