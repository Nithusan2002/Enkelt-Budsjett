# CLAUDE.md — Enkelt Budsjett

Practical guide for AI assistants working on this codebase. Read this before making any changes.

---

## Project Overview

**Enkelt Budsjett** (Simple Budget) is a Norwegian personal-finance iOS app built entirely with SwiftUI and SwiftData. It is offline-first with optional iCloud sync via CloudKit. There is no backend server, no third-party SDKs, and no analytics. The UI language is Norwegian throughout.

- **Bundle ID:** `com.nithusan.Enkelt-Budsjett`
- **Minimum iOS:** 18.0
- **CloudKit container:** `iCloud.com.nithusan.Enkelt-Budsjett`
- **App Store URLs:** https://simplebudget.app

---

## Repository Layout

```
Enkelt Budsjett/
├── App/                        # Entry point, root navigation, app state
│   ├── *App.swift              # SwiftData container setup, CloudKit fallback logic
│   ├── AppRootView.swift       # Tab/nav shell
│   ├── AppRootViewModel.swift
│   ├── ContentView.swift
│   └── AppNavigationState.swift
├── Domain/
│   ├── Models/
│   │   └── DomainModels.swift  # All 13 SwiftData @Model classes + enums
│   └── Services/
│       ├── FinanceServices.swift       # Core financial calculations (~43 KB)
│       ├── DemoDataSeeder.swift        # Generates 3 years of demo data
│       ├── PersistenceGate.swift       # Safe save / read-only detection
│       ├── CheckInReminderService.swift # Monthly notification scheduling
│       └── OnboardingEventLogger.swift
├── Features/                   # One folder per feature, each with View + ViewModel
│   ├── Budget/
│   ├── Investments/
│   ├── Overview/
│   ├── Onboarding/
│   ├── Settings/
│   ├── Goals/
│   ├── Challenges/
│   └── Tips/
├── Shared/
│   └── Utils/
│       ├── AppTheme.swift      # Colors, light/dark mode, portfolio color map
│       └── UIFormatting.swift  # NOK currency, Norwegian date formatters, View modifiers
├── DemoData/                   # JSON demo dataset
└── Assets.xcassets/

Enkelt BudsjettTests/           # Swift Testing unit tests
Enkelt BudsjettUITests/         # XCUITest UI tests
docs/legal/                     # Norwegian privacy policy & terms
```

---

## Architecture

**Pattern:** MVVM, one ViewModel per feature screen.

- **Views** are pure SwiftUI; keep logic out of them.
- **ViewModels** hold `@Observable` state and call Domain services.
- **Domain/Services** contain business logic that has no UI dependency.
- **SwiftData models** are passed through the environment via `@Query` or fetched inside ViewModels.

### Key Principle

> Do the minimum complete change to solve the task. Don't refactor unrelated code.

---

## Data Layer

### SwiftData Models (13 entities in `DomainModels.swift`)

| Model | Purpose |
|---|---|
| `BudgetMonth` | Monthly period (YYYY-MM key) |
| `Category` | Expense/income/savings categories |
| `BudgetPlan` | Per-category monthly budget amounts |
| `BudgetGroupPlan` | Per-group monthly budget limits |
| `Transaction` | Individual income/expense/transfer records |
| `Account` | Bank/savings/cash accounts |
| `FixedItem` | Recurring auto-created transactions |
| `FixedItemSkip` | Skip records for recurring items |
| `InvestmentBucket` | Portfolio categories (Funds, Stocks, BSU…) |
| `InvestmentSnapshot` | Monthly portfolio value snapshots |
| `Goal` | Wealth goals |
| `Challenge` | Financial challenges |
| `UserPreference` | Singleton: app-wide preferences |

### Persistence Strategy

The app uses a fallback chain to handle CloudKit/store failures:

1. **Primary** — Local SQLite + CloudKit iCloud sync
2. **PrimaryWithoutCloud** — Local only (CloudKit unavailable)
3. **Recovery** — Separate `.recovery.store` (primary corrupt)
4. **MemoryOnly** — In-memory last resort

All writes go through `PersistenceGate.safeSave()`. Never call `modelContext.save()` directly.

---

## SwiftUI Conventions

- Use `Button` / `NavigationLink` for interactive elements — not `onTapGesture`.
- Always use `AppTheme` colors and `UIFormatting` helpers; never hard-code hex colors or format currency/dates manually.
- Support both light mode and dark mode. Test both before committing.
- Handle empty states and zero-data explicitly — never leave a screen blank without guidance copy.
- Accessibility: every meaningful interactive element needs a VoiceOver label.
- Dynamic Type: use system fonts and relative sizing.

---

## Formatting & Localization

All user-facing text is in **Norwegian Bokmål**. Copy must be:
- Simple and warm
- Non-moralizing (never shame the user about spending)
- Concise — one primary action per screen

**Currency:** Norwegian Krone (NOK). Use `UIFormatting` formatters — never `NumberFormatter` directly.

**Dates:** Norwegian locale (`nb_NO`). Use the date formatters in `UIFormatting.swift`.

---

## Testing

Framework: **Swift Testing** (native, not XCTest where possible).

Location: `Enkelt BudsjettTests/FeatureLogicTests.swift`

For unit tests, create an in-memory SwiftData container:

```swift
let config = ModelConfiguration(isStoredInMemoryOnly: true)
let container = try ModelContainer(for: UserPreference.self, configurations: config)
```

UI tests use the launch argument `UITEST_IN_MEMORY_STORE` to get a clean store.

Run tests via Xcode or:
```bash
xcodebuild test \
  -scheme "Enkelt Budsjett" \
  -destination "platform=iOS Simulator,name=iPhone 16"
```

**Definition of Done (every change):**
- [ ] Feature works as specified
- [ ] No new build errors or warnings
- [ ] No regressions in adjacent screens
- [ ] Empty state and zero-data handled
- [ ] Dark mode and light mode both look correct
- [ ] Change committed with a clear message

---

## Build & Run

Requires Xcode 16+ on macOS with an Apple ID that has iCloud/CloudKit access.

```bash
# Build for simulator
xcodebuild \
  -scheme "Enkelt Budsjett" \
  -destination "platform=iOS Simulator,name=iPhone 16"

# Archive for distribution
xcodebuild archive -scheme "Enkelt Budsjett"
```

**Demo data** (Debug / TestFlight only): Settings → Demo → "Load demo (3 år realistisk)"
This seeds 36 months of realistic Norwegian student-budget data via `DemoDataSeeder`.

---

## Commit Convention

```
<type>(<scope>): <short description in Norwegian or English>
```

Types: `feat` · `fix` · `refactor` · `test` · `docs` · `chore`

Examples:
```
feat(budget): innfør gruppegrenser med enkel setup-sheet
fix(investments): hindre duplikat snapshot ved samme periodKey
refactor(overview): flytt beregninger til viewmodel
chore(assets): oppdater appikon
```

One logical change per commit. Keep commits small and focused.

---

## Agent Workflow

This project uses named agent profiles (defined in `AGENTS.md`):

| Agent | When to use |
|---|---|
| **Designer-agent** | UX, information architecture, copy, empty states, visual consistency |
| **iOS-agent** | SwiftUI / SwiftData implementation |
| **QA-agent** | Quality review, regression checks, accessibility |
| **Release-agent** | TestFlight / App Store preparation |

Request format:
```
Agent: iOS-agent
Mål: <what to achieve>
Krav: <must/shall rules>
Akseptansekriterier: <how we know it is done>
Leveranse: implementer + test + commit
```

---

## Privacy & Compliance

- **No third-party analytics or tracking SDKs.**
- Data stays on device; iCloud sync is the only network path.
- Privacy manifest: `Enkelt Budsjett/PrivacyInfo.xcprivacy` — update if new API categories are used.
- Debug-only features (demo seeder UI) must be hidden in App Store builds.
- GDPR-friendly by design — no personal data leaves the device without user consent (iCloud sync).

---

## Key Files Quick Reference

| File | Purpose |
|---|---|
| `Domain/Models/DomainModels.swift` | All data models — start here for schema questions |
| `Domain/Services/FinanceServices.swift` | All financial calculations |
| `Domain/Services/PersistenceGate.swift` | Use `safeSave()` for all writes |
| `Shared/Utils/AppTheme.swift` | Colors and theming |
| `Shared/Utils/UIFormatting.swift` | Currency, date, percentage formatters |
| `App/*App.swift` | CloudKit fallback and container bootstrap |
| `AGENTS.md` | Norwegian-language agent workflow details |
