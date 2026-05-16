# CashLens — Codebase Documentation

> **Version:** 1.0.5 (Build 5) — Current App Store release  
> **Platform:** iOS 18.0+ (iPhone & iPad)  
> **Language:** Swift 5.0 / SwiftUI  
> **Bundle ID:** `com.rushi.CashLens`  
> **Created by:** Rushiraj Jadeja (October 2025)  
> **Last updated:** April 2026

---

## Table of Contents

1. [App Overview](#1-app-overview)
2. [Architecture](#2-architecture)
3. [Project Structure](#3-project-structure)
4. [Data Layer](#4-data-layer)
5. [Models](#5-models)
6. [ViewModels](#6-viewmodels)
7. [Views](#7-views)
8. [Components](#8-components)
9. [Utilities](#9-utilities)
10. [Extensions](#10-extensions)
11. [Design System](#11-design-system)
12. [Monetization](#12-monetization)
13. [Notifications](#13-notifications)
14. [Import / Export](#14-import--export)
15. [Navigation Flow](#15-navigation-flow)
16. [Key Patterns & Conventions](#16-key-patterns--conventions)
17. [Dependencies](#17-dependencies)
18. [Build & Run](#18-build--run)
19. [Widgets (Pro)](#19-widgets-pro)

---

## 1. App Overview

CashLens is a **local-first, privacy-focused personal expense tracker** for iOS. All data is stored on-device using Core Data — no accounts, no cloud sync, no server.

### Core Features

| Feature | Description |
|---------|-------------|
| **Expense Tracking** | Add, edit, delete expenses with amount, title, category, date, notes |
| **Recurring Bills** | Track subscriptions with frequency, due dates, reminders, pause/resume |
| **Statistics** | Donut chart, trend line, spending heatmap, category breakdown, insights |
| **Custom Categories** | User-defined categories with SF Symbol icons and named colors |
| **Import/Export** | Full backup/restore via `.cashlens.json`; expense-only `.csv` for spreadsheets; **Pro:** import Mint / YNAB / bank CSV with auto column detection |
| **Notifications** | Weekly/monthly spending digests, backup reminders, subscription due alerts |
| **Multi-Currency** | 170+ currencies with locale-based auto-detection (single global currency) |
| **Dark Mode** | System/Light/Dark appearance toggle |
| **Draft Recovery** | Unfinished expense forms are auto-saved and restorable |
| **Feedback System** | Smart in-app review prompts after successful actions |

---

## 2. Architecture

The app uses a **MVVM (Model-View-ViewModel)** architecture with Core Data as the persistence layer.

```
┌─────────────────────────────────────────────────────┐
│                    SwiftUI Views                     │
│  (HomeView, StatisticsView, SubscriptionsView, ...) │
└────────────────────┬────────────────────────────────┘
                     │ @EnvironmentObject / @StateObject
┌────────────────────▼────────────────────────────────┐
│                   ViewModels                         │
│  ExpenseViewModel (+ extensions)                     │
│  SubscriptionViewModel                               │
│  CategoryViewModel                                   │
│  BudgetViewModel (Pro)                               │
└────────────────────┬────────────────────────────────┘
                     │ Core Data Fetch/Save
┌────────────────────▼────────────────────────────────┐
│              Core Data Entities                      │
│  ExpenseEntity, SubscriptionEntity,                  │
│  CustomCategoryEntity, BudgetEntity                  │
│         ↕ (Bridge via +Extensions.swift)             │
│  Expense (struct), Subscription (struct),            │
│  CustomCategory (struct)                             │
└─────────────────────────────────────────────────────┘

Preferences: UserDefaults (via UserDefaultsKeys enum)
IAP: StoreKit 2 (DonationManager — tip jar only)
```

### Data Flow

1. **Core Data entities** are the durable store
2. **Bridge extensions** (`*Entity+Extensions.swift`) convert entities ↔ value-type structs
3. **ViewModels** hold `@Published` arrays of structs; views bind to these
4. **Combine pipelines** debounce filter/sort changes for smooth UI
5. **UserDefaults** stores lightweight preferences (currency, appearance, onboarding flags, notification schedules)

---

## 3. Project Structure

```
CashLens/
├── CashLensApp.swift              # App entry point, scene setup, onboarding gate
├── Persistence.swift              # Core Data stack (PersistenceController)
│
├── Models/
│   ├── Expense.swift              # Expense struct + Currency enum + Category enum
│   ├── Subscription.swift         # Subscription struct + Frequency enum
│   ├── CustomCategory.swift       # CustomCategory struct + available icons/colors
│   ├── CurrencyData.swift         # Static currency code → symbol/name mapping
│   ├── CurrencyRegion.swift       # Currency grouped by world region for picker
│   ├── DonationManager.swift      # StoreKit 2 tip jar (3 consumable products)
│   ├── ProManager.swift           # StoreKit 2 Pro subscription/lifetime entitlements
│   ├── AppTheme.swift             # Pro: 6 accent themes (light/dark hex pairs per theme)
│   ├── AppIconOption.swift        # Pro: 8 alternate-icon options (primary + 7 alternates)
│   ├── ExpenseEntity+Extensions.swift      # Core Data ↔ Expense bridge
│   ├── SubscriptionEntity+Extensions.swift # Core Data ↔ Subscription bridge
│   └── CustomCategoryEntity+Extensions.swift # Core Data ↔ CustomCategory bridge
│
├── Backup/                                 # Backup / restore pipeline (see §14)
│   ├── BackupBundle.swift                  # Canonical Codable schema (v2) — entities + preferences
│   ├── BackupExporter.swift                # Snapshots store + UserDefaults, writes JSON / CSV
│   ├── BackupImporter.swift                # Format detection, parsing, merge/replace apply
│   └── GenericCSVAdapter.swift             # Auto-maps Mint / YNAB / bank CSV columns (Pro)
│
├── ViewModels/
│   ├── ExpenseViewModel.swift              # Main VM: state, filtering, preferences
│   ├── ExpenseViewModel+CoreData.swift     # Load/save expenses from Core Data
│   ├── ExpenseViewModel+CRUD.swift         # Add/update/delete + amount formatting
│   ├── ExpenseViewModel+Categories.swift   # Custom categories, deleted defaults
│   ├── ExpenseViewModel+Currency.swift     # Global currency sync across all data
│   ├── ExpenseViewModel+ImportExport.swift # Compatibility shim → delegates to Backup/
│   ├── ExpenseViewModel+Maintenance.swift  # Refresh, health check, clear all data
│   ├── ExpenseViewModel+Preferences.swift  # Summary card customization tokens
│   ├── ExpenseViewModel+Preview.swift      # SwiftUI preview helper
│   ├── SubscriptionViewModel.swift         # Subscription CRUD, due processing, notifications
│   └── CategoryViewModel.swift             # Custom category CRUD via NSFetchedResultsController
│
├── Views/
│   ├── MainTabView.swift           # Root tab bar (Home, Subscriptions, Statistics)
│   ├── HomeView.swift              # Dashboard: hero spending card, pinned categories, recent expenses
│   ├── SubscriptionsView.swift     # Subscription list with filters and monthly total
│   ├── StatisticsView.swift        # Analytics: hero overview, insights, where-it-goes (donut+rows), heatmap, trend
│   ├── AddExpenseView.swift        # Expense create/edit form
│   ├── AddSubscriptionView.swift   # Subscription create/edit form
│   ├── AllExpensesView.swift       # Library: full list with sort, date range, category/tag filters, pagination — toolbar magnifying glass routes to QuickSearchView
│   ├── QuickSearchView.swift       # Modal search with custom header, persisted recents, quick tips, category/tag browse, grouped results with match highlighting
│   ├── ProfileView.swift           # Settings hub: header, pro, backup banner, preferences, reminders, data, about
│   ├── CurrencyPickerView.swift    # Currency selection with region chips + search
│   ├── ManageCategoriesView.swift  # Default + custom category management
│   ├── CustomCategoryForm.swift    # Create/edit custom category (+ icon/color pickers)
│   ├── SummaryCustomizationView.swift # Choose 3 summary card categories for Home
│   ├── ExportDataView.swift        # Picks Complete Backup vs Spreadsheet, calls BackupExporter
│   ├── ImportDataView.swift        # File picker → preview sheet (counts, mode, errors) → apply via BackupImporter
│   ├── DonationView.swift          # StoreKit tip jar UI
│   ├── AboutView.swift             # App info, features, contact, privacy
│   ├── OnboardingView.swift        # 6-page first-launch carousel
│   ├── PaywallView.swift           # CashLens Pro upgrade screen with pricing
│   ├── ThemePickerView.swift       # Pro: 6-theme accent picker w/ live preview + paywall on Pro tap
│   ├── AppIconPickerView.swift     # Pro: 8-option alternate-icon picker w/ hero preview + paywall on Pro tap
│   ├── ProInsightsSection.swift    # Pro Insights section (Daily Pace / Velocity / YoY) + free teaser
│   ├── ForecastSection.swift       # Forecast section (horizon switcher, projection card, sub-cards) + free teaser
│   ├── SplashScreenView.swift      # Branded splash (~2s auto-dismiss)
│   ├── FeedbackRequestView.swift   # In-app rate/share overlay
│   └── DiagnosticsView.swift       # Debug-only data health tools
│
├── Components/
│   ├── ColorExtension.swift        # Design system colors (pastel palette, category mapping)
│   ├── PinnedCategoryCard.swift    # Rich pinned-category tile on Home (amount + trend + count + budget bar + selected state)
│   ├── ForecastChart.swift         # SwiftUI Charts renderer for ForecastEngine.Forecast (history line + dashed projection + ±1σ band + subscription dots)
│   ├── ExpenseCard.swift           # Optimized expense row (Equatable)
│   ├── ExpenseRow.swift            # Simple expense row (environment-based)
│   ├── CategoryItem.swift          # Horizontal category chip (default categories)
│   ├── CustomCategoryItem.swift    # Horizontal category chip (custom categories)
│   ├── CategoryDonutChart.swift    # Interactive donut chart + legend
│   ├── ExpenseTrendChart.swift     # Custom Path line/area chart
│   ├── SpendingHeatmap.swift       # GitHub-style calendar heatmap
│   ├── SubscriptionRow.swift       # Subscription cell with mark-as-paid
│   ├── FloatingAddButton.swift     # FAB on Home tab
│   └── AddButton.swift             # Gradient add button variant
│
├── Design/                         # Cross-cutting design system (tokens + shared UI)
│   ├── Theme.swift                 # Spacing, Radius, Stroke, Typography, Shadow, Motion, Icon, LinearGradient extensions
│   ├── ViewModifiers.swift         # .cardSurface(), .sectionContainer(), .softShadow(), .primaryGlow()
│   └── Components/
│       ├── SectionHeader.swift         # SectionHeader + SectionHeaderLink (trailing "See All")
│       ├── PillChip.swift              # Canonical filter / selection chip (capsule or rounded)
│       ├── PrimaryGradientButton.swift # Gradient CTA + SecondaryOutlineButton
│       ├── EmptyStatePanel.swift       # Full empty state + InlineEmptyState
│       └── SettingsRow.swift           # SettingsRow + SettingsRowValue + SettingsRowDestructive
│
├── Extensions/
│   ├── ButtonStyles.swift          # ScaleButtonStyle, OpacityButtonStyle, CustomAddButtonStyle
│   ├── NotificationExtension.swift # Notification.Name constants
│   └── ViewExtensions.swift        # Conditional modifier, per-corner rounding
│
├── Utilities/
│   ├── HapticManager.swift         # Centralized haptic feedback (cached generators)
│   ├── DeepLinkRouter.swift        # Notification → route parsing for sheets
│   ├── ExpenseFilter.swift         # Pure function: filter/sort by category, time, date range
│   ├── NotificationScheduler.swift # Weekly/monthly digest + backup reminder scheduling
│   ├── StatisticsCalculator.swift  # Previous-period, insights, category breakdown
│   ├── AdvancedStatsCalculator.swift # Pro: daily pace, velocity, year-over-year aggregation
│   ├── ForecastEngine.swift        # Pro: pure forecast compute (weekday seasonality, recency weighting, outlier capping, subscription overlay, ±1σ confidence band)
│   ├── ImportUtilities.swift       # CSV/JSON parse pipeline, ImportResult, ImportError
│   ├── UserDefaultsKeys.swift      # Centralized preference key registry
│   ├── ThemeStore.swift            # Pro: @MainActor singleton for active accent theme; nonisolated read for dynamic Color.appPrimary
│   ├── AppIconStore.swift          # Pro: @MainActor singleton wrapping UIApplication.setAlternateIconName
│   └── ExpenseDraft.swift          # Codable snapshot of in-progress expense form
│
├── Assets.xcassets/                # App icon, accent color, logo
├── CashLens.xcdatamodeld/         # Core Data model (3 entities)
├── Donations.storekit             # StoreKit configuration file
└── Preview Content/               # Preview assets
```

---

## 4. Data Layer

### Core Data Schema

**3 Entities** defined in `CashLens.xcdatamodeld`:

#### ExpenseEntity
| Attribute | Type | Optional | Default | Notes |
|-----------|------|----------|---------|-------|
| `id` | UUID | No | — | Primary identifier |
| `title` | String | No | — | Expense name |
| `amount` | Double | No | 0.0 | Monetary value |
| `currency` | String | No | — | Currency code (e.g., "USD") |
| `date` | Date | No | — | When expense occurred |
| `category` | String | No | — | Category rawValue (e.g., "Food") |
| `customCategoryId` | UUID | Yes | — | Links to CustomCategoryEntity when category is "Custom" |
| `notes` | String | Yes | — | User notes |
| `isFromSubscription` | Boolean | Yes | NO | Whether auto-generated from subscription |
| `subscriptionId` | UUID | Yes | — | Links back to originating subscription |
| `tags` | Transformable (`NSArray`) | Yes | — | Smart Tags — `NSSecureUnarchiveFromDataTransformerName` |
| `isRefund` | Boolean | Yes | NO | Marks the entry as money returned; `signedAmount` returns `-amount`. Lightweight migration. |
| `paymentMethod` | String | Yes | — | Raw value of `PaymentMethod` enum (`cash` / `credit` / `debit` / `upi` / `bank` / `wallet` / `other`). Captured free for everyone; powers the **Pro** Payment Methods donut on Statistics. Lightweight migration. |

#### SubscriptionEntity
| Attribute | Type | Optional | Default | Notes |
|-----------|------|----------|---------|-------|
| `id` | UUID | No | — | Primary identifier |
| `name` | String | No | — | Subscription name |
| `amount` | Double | No | 0.0 | Payment amount |
| `currency` | String | No | — | Currency code |
| `startDate` | Date | No | — | When subscription started |
| `frequency` | String | No | — | Frequency rawValue (Daily/Weekly/Monthly/Quarterly/Yearly) |
| `nextDueDate` | Date | No | — | Next payment date |
| `category` | String | No | — | Category rawValue |
| `customCategoryId` | UUID | Yes | — | Links to CustomCategoryEntity |
| `notes` | String | Yes | — | User notes |
| `isActive` | Boolean | No | YES | Active vs paused |
| `reminderEnabled` | Boolean | No | YES | Push notification reminder |
| `reminderDaysBefore` | Int16 | No | 1 | Days before due date to remind |

#### CustomCategoryEntity
| Attribute | Type | Optional | Default | Notes |
|-----------|------|----------|---------|-------|
| `id` | UUID | No | — | Primary identifier |
| `name` | String | No | — | Category display name |
| `icon` | String | No | — | SF Symbol name |
| `colorName` | String | No | — | Named color from palette |

### Persistence Controller (`Persistence.swift`)

- **Singleton**: `PersistenceController.shared`
- **SQLite optimizations**: WAL journal mode, NORMAL synchronous
- **Merge policy**: `NSMergeByPropertyObjectTrumpMergePolicy`
- **Performance**: Undo manager disabled, auto-merges from parent context
- **Preview support**: In-memory store for SwiftUI previews

### UserDefaults Keys (`UserDefaultsKeys.swift`)

All preference keys are centralized in a caseless enum:

| Group | Keys |
|-------|------|
| **Onboarding** | `hasCompletedOnboarding`, `hasLaunchedBefore`, `hasShownCurrencyPicker` |
| **Preferences** | `selectedCurrency`, `selectedTimeFrame`, `defaultHomeTimeFrame`, `appearanceMode`, `userName` |
| **Summary** | `preferredSummaryCategories` |
| **Categories** | `deletedDefaultCategories` |
| **Drafts** | `expenseDraft` |
| **Feedback** | `hasRequestedFeedback`, `successfulActionsCount`, `lastFeedbackAttempt` |
| **Notifications** | Weekly/monthly/backup: `*Enabled`, `*Weekday`/`*DayOfMonth`, `*Hour`, `*Minute` |
| **Smart Insights (Pro)** | `smartInsightsEnabled`, `smartInsightsHistory`, `smartInsightsLastFireDate` |
| **Backup** | `lastBackupDate`, `lastBackupFormat`, `totalBackupCount` |
| **Personalization (Pro)** | `activeThemeId` (`AppTheme.id` — defaults to `mauve` so existing users see no change), `activeAppIconId` (matches `AppIconOption.id`; `nil` ⇒ primary icon) |

---

## 5. Models

### Expense (`Models/Expense.swift`)

Core domain struct for a single expense.

```swift
struct Expense: Identifiable, Codable {
    var id: UUID
    var title: String
    var amount: Double
    var currency: Currency
    var date: Date
    var category: Category
    var notes: String?
    var customCategoryId: UUID?
    var isFromSubscription: Bool
    var subscriptionId: UUID?
    var tags: [String]?
    var isRefund: Bool          // false for normal expenses, true for money returned
    var paymentMethod: PaymentMethod?  // optional; powers Pro donut on Statistics

    var signedAmount: Double { isRefund ? -amount : amount }
}

extension Sequence where Element == Expense {
    func netTotal() -> Double { reduce(0) { $0 + $1.signedAmount } }
}
```

**Nested Types:**

- **`Currency`** — 170+ ISO 4217 codes as enum cases. `symbol` and `name` resolved via `CurrencyData`. `allCases` derived from `CurrencyData.allCurrencies`.
- **`Category`** — 11 built-in categories: Groceries, Food, Transportation, Entertainment, Shopping, Utilities, Health, Education, Travel, Custom, Other. Each has an `icon` (SF Symbol), `color` (named color key), and `displayName`.

**Import Support:** `init(from json:)` for JSON, `init(fromCSV:)` for CSV with multi-format date parsing. Custom `init(from decoder:)` uses `decodeIfPresent` for `isRefund` and `paymentMethod` so older backups (pre-refund / pre-payment-method) decode unchanged with `isRefund = false` and `paymentMethod = nil`. CSV imports also accept a "Payment Method" column with tolerant parsing via `PaymentMethod.tolerant(from:)`.

**Refund-aware aggregation:** All totals across the app go through `signedAmount` / `netTotal()` so refunds subtract from spending while sorting/displaying continues to use absolute `amount`. Touched aggregators include `ExpenseViewModel.computeTotals`, `StatisticsCalculator`, `AdvancedStatsCalculator`, `ForecastEngine`, `BudgetViewModel`, `NotificationScheduler.DigestStatsCalculator`, `ExpenseTrendChart`, `SpendingHeatmap`, `AllExpensesView` day headers, `QuickSearchView`, and `HomeView`.

### Subscription (`Models/Subscription.swift`)

Recurring bill/payment model.

```swift
struct Subscription: Identifiable, Codable {
    var id: UUID
    var name: String
    var amount: Double
    var currency: Expense.Currency
    var startDate: Date
    var frequency: Frequency
    var nextDueDate: Date
    var category: Expense.Category
    var customCategoryId: UUID?
    var notes: String?
    var isActive: Bool
    var reminderEnabled: Bool
    var reminderDaysBefore: Int
}
```

**Nested Type:**

- **`Frequency`** — Daily, Weekly, Monthly, Quarterly, Yearly. Each has `icon`, `description`, `daysInterval`.

**Key Methods:**
- `calculateNextDueDate(from:frequency:)` — Calendar-based date advancement
- `updateNextDueDate()` — Advances to next period
- `isDue` — True if `Date() >= nextDueDate && isActive`
- `toExpense()` — Converts to `Expense` when marking as paid
- `daysUntilNext` — Can be negative for overdue

### CustomCategory (`Models/CustomCategory.swift`)

User-defined expense category.

```swift
struct CustomCategory: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var icon: String       // SF Symbol name
    var colorName: String  // Named color from palette
}
```

**Static catalogs:** `availableIcons` (80+ SF Symbols), `availableColors` (10 pastel colors).

### ExpenseTemplate (`Models/ExpenseTemplate.swift`)

Lightweight `Codable` value type representing a saved preset for the Add Expense form (e.g. "Morning coffee · $4 · Food").

```swift
struct ExpenseTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String              // user-visible label, falls back to title
    var title: String             // applied to the form's title
    var amount: Double
    var category: Expense.Category
    var customCategoryId: UUID?
    var notes: String?
    var tags: [String]?
    var isRefund: Bool
    var lastUsedAt: Date?         // bumps on apply for LRU sorting
    let createdAt: Date
}
```

**Backward-compatible decode:** custom `init(from:)` uses `decodeIfPresent` for `tags`, `isRefund`, `lastUsedAt`, `paymentMethod`, and `createdAt` so older serialized blobs keep loading. Persisted via `ExpenseTemplateStore` to `UserDefaults` (key `expense_templates_v1`); never written to JSON/CSV backups.

### PaymentMethod (`Models/PaymentMethod.swift`) — Phase 11

Enum capturing how an expense was paid. Free for everyone to enter; the cross-method donut on Statistics is the Pro feature.

```swift
enum PaymentMethod: String, CaseIterable, Codable, Identifiable, Hashable {
    case cash, creditCard = "credit", debitCard = "debit", upi,
         bankTransfer = "bank", wallet, other

    var displayName: String  // "Cash" / "Credit Card" / …
    var shortLabel: String   // "Cash" / "Credit" / …
    var icon: String         // SF Symbol per method
    var color: Color         // tinted color for chips/donut slices

    static func tolerant(from raw: String?) -> PaymentMethod?
}
```

`tolerant(from:)` accepts common aliases ("credit card", "visa", "venmo", "gpay", "paytm", "neft", …) so foreign-CSV imports map cleanly without surfacing a manual mapping UI. `Sequence`-style aggregations live in `StatisticsCalculator.paymentMethodBreakdown(...)`.

### PaymentMethodBreakdown (`Models/PaymentMethodBreakdown.swift`) — Phase 11

Aggregated result for the Pro Payment Methods donut. Computed once per Statistics recompute pass; refund-aware via `signedAmount`.

```swift
struct PaymentMethodSlice: Identifiable, Hashable {
    let method: PaymentMethod
    let amount: Double            // net (refund-adjusted)
    let percentage: Double        // share of positive-net spend in view
    let count: Int
}

struct PaymentMethodBreakdown {
    let slices: [PaymentMethodSlice]   // sorted biggest-first; positive-net only
    let unspecifiedAmount: Double      // tracked separately, never a wedge
    let unspecifiedCount: Int          // drives "tag x more" footer
    let total: Double                  // percentage denominator
    var hasData: Bool
    var taggedCoverage: Double          // 0…1 share of *tagged* positive-net spend
}
```

The donut deliberately excludes the unspecified bucket — instead, a footer surfaces "N without a method" so the user understands what's *missing* without inflating slices.

### AppTheme (`Models/AppTheme.swift`) — Phase 4 (Pro)

User-selectable accent theme. Six options ship: Mauve (default — preserves the historical CashLens brand), Ocean, Forest, Sunset, Berry, Graphite. Each carries hand-tuned light + dark hex pairs for both `primary` and `secondary` so contrast stays AA-safe in either appearance mode.

```swift
struct AppTheme: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let primaryLightHex, primaryDarkHex: String
    let secondaryLightHex, secondaryDarkHex: String

    var primaryColor: Color    // Color(UIColor { trait in ... }) — light/dark adaptive
    var secondaryColor: Color

    static let mauve, ocean, forest, sunset, berry, graphite: AppTheme
    static let all: [AppTheme]
    static let `default`: AppTheme = .mauve
    static func resolve(id: String?) -> AppTheme
}
```

Lives behind `ThemeStore` (see [Utilities](#9-utilities)) which is the single read/write surface. **Never instantiate ad-hoc** — always pull from `AppTheme.all` or `AppTheme.resolve(id:)` so the picker, persistence, and color resolution stay in lock-step.

### AppIconOption (`Models/AppIconOption.swift`) — Phase 4 (Pro)

User-selectable alternate app icon. Eight options ship: `primary` (Mauve, the default `AppIcon`) plus seven alternates that match each colored theme — Ocean / Forest / Sunset / Berry / Graphite — and two monochromes (Mono Light, Mono Dark).

```swift
struct AppIconOption: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let alternateName: String?       // nil ⇒ primary; pass to setAlternateIconName(_:)
    let previewAssetName: String     // also addressable via UIImage(named:) for in-app preview

    var isPrimary: Bool { alternateName == nil }

    static let primary, ocean, forest, sunset, berry, graphite, monoLight, monoDark: AppIconOption
    static let all: [AppIconOption]
    static func resolve(id: String?) -> AppIconOption
}
```

The actual PNG art lives in `Assets.xcassets/AppIcon-*.appiconset/` folders (one per alternate, single 1024×1024 universal entry each). The build is configured with `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES` and `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` listing all seven alternates, so Xcode auto-generates the `CFBundleIcons.CFBundleAlternateIcons` Info.plist entries. The PNGs themselves are produced by `Scripts/generate_app_icons.swift` — a re-runnable CoreGraphics renderer that draws the existing CashLens coin/$/glint geometry in each theme color, so the family stays pixel-cohesive.

### CurrencyData (`Models/CurrencyData.swift`)

Static lookup table: currency code → `(symbol, name)`. Backs `Expense.Currency.symbol` and `.name`.

### CurrencyRegion (`Models/CurrencyRegion.swift`)

Groups currencies by world region for the currency picker: Americas, Europe, Asia Pacific, Middle East, Africa, Caribbean, etc.

### DonationManager (`Models/DonationManager.swift`)

StoreKit 2 wrapper for tip jar. See [Monetization](#12-monetization).

### Entity Bridge Extensions

- **`ExpenseEntity+Extensions.swift`** — `fromExpense(_:context:)` and `toExpense()` conversions
- **`SubscriptionEntity+Extensions.swift`** — Same pattern + `updateFromSubscription(_:)` for in-place updates
- **`CustomCategoryEntity+Extensions.swift`** — Same pattern with defaults for missing icon/color

---

## 6. ViewModels

### ExpenseViewModel (`ViewModels/ExpenseViewModel.swift`)

**Central ViewModel** — injected as `@StateObject` in `CashLensApp` and passed via `@EnvironmentObject`.

**Published State:**
- `expenses: [Expense]` — Full expense list from Core Data
- `filteredExpenses: [Expense]` — After category/time frame filters
- `selectedCategory`, `selectedCustomCategoryId`, `selectedTimeFrame` — Active filters
- `cachedTotalAmount`, `cachedTotalsByCategory`, `cachedTotalsByCustomId` — O(1) totals
- `cachedCountsByCategory`, `cachedCountsByCustomId` — O(1) counts
- `selectedCurrency`, `userName`, `appearanceMode`, `defaultHomeTimeFrame` — User preferences
- `preferredSummaryCategoryTokens: [String]` — Home summary card selections

**Key Types:**
- `TimeFrame` — day/week/month/year/all with `dateRange(referenceDate:)` returning half-open `[start, end)`
- `AppearanceMode` — light/dark/system with `colorScheme` mapping

**Filtering Pipeline (Combine):**
1. `CombineLatest4(expenses, selectedCategory, selectedCustomCategoryId, selectedTimeFrame)`
2. Debounced 50ms to batch rapid changes
3. `scheduleFilterRecompute` cancels previous task, runs `ExpenseFilter.apply` on background thread
4. Updates `filteredExpenses` on main thread
5. `updateCachedTotals` aggregates amounts/counts asynchronously

#### Extension Files

| File | Responsibility |
|------|---------------|
| `+CoreData.swift` | `loadExpenses()` (sync fetch, batch 100), `loadExpensesAsync()`, `saveContext()` |
| `+CRUD.swift` | `addExpense`, `updateExpense` (persists `isRefund`), `deleteExpense(at:)`, `deleteExpenseById`, **`deleteExpenses(ids:)`**, **`bulkChangeCategory(ids:to:customCategoryId:)`**, **`bulkAddTag(ids:tag:)`** (single-save batch ops powering `AllExpensesView` selection mode), `formattedAmount`, `parseAmount` |
| `+Categories.swift` | `getCustomCategories()`, `getAvailableDefaultCategories()`, `getDeletedDefaultCategories()`, `moveExpensesFromDeletedCategory`, display helpers |
| `+Currency.swift` | `syncCurrencyAcrossStoredData()`, bulk-updates all expenses and subscriptions to `selectedCurrency` |
| `+ImportExport.swift` | `exportToCSV()`, `exportToJSON()`, `importData(_:completion:)` with phased import + deduplication |
| `+Maintenance.swift` | `refreshData()`, `checkDataExists()`, `checkCurrencyConsistency()`, `clearAllData()` |
| `+Preferences.swift` | `loadSummaryPreferences`, `saveSummaryPreferences`, `updateSummaryCategoryTokens` |
| `+Preview.swift` | `ExpenseViewModel.preview` with sample data |

### SubscriptionViewModel (`ViewModels/SubscriptionViewModel.swift`)

**Manages recurring bills** — not App Store subscriptions.

**Published State:**
- `subscriptions`, `filteredSubscriptions`
- `activeFilter: SubscriptionFilter` (`all` / `dueSoon` / `active`)

**Key Features:**
- **NSFetchedResultsController** for auto-sync with Core Data
- **Mark as Paid** (user-driven): `markSubscriptionAsPaid(_:)` creates an expense via `expenseViewModel.addExpense` and advances `nextDueDate`. **This is the only path that converts a subscription into an expense** — silent auto-processing was intentionally removed because it could mis-record historical amounts the user never confirmed.
- **Local notifications**: Per-subscription calendar-based reminders (`subscription_<UUID>`). `syncNotification(for:)` cancels any stale request and schedules a fresh one on every save/toggle; on load, `resyncAllSubscriptionNotifications()` purges orphans for subs that no longer exist.
- **Currency sync**: Listens for `.subscriptionCurrencyUpdated` notification
- **Combine filtering**: Reactive filter pipeline on `$subscriptions` + `$activeFilter`
- **Legacy data repair**: Fixes entities with nil UUIDs on load

### CategoryViewModel (`ViewModels/CategoryViewModel.swift`)

**Custom category CRUD** via `NSFetchedResultsController<CustomCategoryEntity>`.

- Seeds 3 defaults (Pets, Gifts, Tech) on first use if empty
- Methods: `addCustomCategory`, `updateCustomCategory`, `deleteCustomCategory`, `categoryNameExists`
- Auto-syncs `customCategories: [CustomCategory]` on Core Data changes

### BudgetViewModel (`ViewModels/BudgetViewModel.swift`) — **CashLens Pro**

**Manages spending budgets** persisted in Core Data (`BudgetEntity`). **Gated in UI** via `ProManager.isPro` (Home teaser, Profile “Manage Budgets”, `BudgetSetupView` / `BudgetListView`).

**Published State:**
- `budgets`, `budgetProgress: [UUID: BudgetProgress]` — spent, limit, percentage, days remaining, status (safe / warning ≥80% / exceeded), pace helpers

**Data flow:**
- `NSFetchedResultsController<BudgetEntity>` keeps `budgets` in sync
- `setExpenseViewModel(_:)` subscribes to `expenses` with **120ms debounce**, then recomputes progress on a **background task** (50ms debounce before compute) so the main thread stays responsive
- Progress sums expenses in the budget’s **current period** `[start, end)` (weekly or monthly calendar ranges), optionally filtered to a default category, custom category, or all spending
- **Threshold alerts (80% / 100%):** `BudgetAlertState` stores last known utilization and “fired” flags **per budget per period**; when utilization **crosses** a threshold upward, a local notification is scheduled (with haptic). Notifications include `userInfo` to open **All Expenses** for the budget period and category. No spam on launch if already over limit (first sample for a period only seeds state)

**Utilities:** `Utilities/BudgetAlertState.swift` — UserDefaults keys for `lastPct` and fired flags keyed by period start

**Views:** `BudgetSetupView`, `BudgetListView`, `Components/BudgetProgressCard` + `BudgetMiniCard`; Home shows budgets below the header; Profile includes “Manage Budgets”

### Smart Tags (Phase 3 Pro) — `ExpenseViewModel.tagStats` + `Utilities/Tag*.swift`

**Tags are a property of `Expense`** (`tags: [String]?`) persisted to `ExpenseEntity.tags` (Transformable `NSArray`, `NSSecureUnarchiveFromDataTransformerName`). The feature is split across three small, composable units:

- **`Utilities/Tag.swift`** — pure helpers. `Tag.normalize(_:)` canonicalizes user input (trim, strip `#`, whitespace-to-`-`, lowercase, 30-char cap). `Tag.displayForm(_:)` always renders with a `#` prefix. Constants: `maxLength = 30`, `maxPerExpense = 10`.
- **`Utilities/TagSuggestionProvider.swift`** — aggregator. `computeStats(from:)` walks expenses (sorted by date desc) once and returns a `Stats` struct: `usageCounts`, `recentTags`, `popularTags`. `suggestions(for:allTags:excluding:limit:)` produces autocomplete (prefix matches rank above substring, usage count breaks ties).
- **`ExpenseViewModel.tagStats: TagSuggestionProvider.Stats`** — `@Published`, recomputed off-main via a 200ms-debounced `$expenses` Combine sink. This is the single source of truth for autocomplete and filter-strip ordering.

**Gating:** adding tags is **free** (keeps the dopamine loop frictionless); **filtering by tag is Pro**. Free users see a subtle "Filter by tag with Pro" nudge in `AllExpensesView` whenever any expense has tags, which opens `PaywallView`. Tags always render on `ExpenseCard` regardless of Pro status — this also implicitly grandfathers downgraded users.

**UI:**
- `Components/TagChip.swift` — 4 styles: `.inline` (tiny chip on `ExpenseCard`, up to 3 + `+N` overflow), `.standard` (filter strip / popular chips), `.selected` (active filter), `.editable` (input-field chip with remove `xmark`).
- `Components/TagInputField.swift` — chip flow layout + text field. Commits on space, comma, return, or tapping a suggestion. Shows live `Matches` while typing; `Recent` + `Popular` when idle/focused. Light haptic on commit, warning haptic on duplicate / 10-tag cap hit.
- `AddExpenseView.tagsField` — section between date and notes; tag count badge on the section header; draft persistence covers tags.
- `AllExpensesView.tagsFilterRow` — Pro-only horizontal strip below category chips; "all" chip clears the filter; selecting a chip filters via `recomputeResults(resetPagination: true)`. To search by tag text, users tap the toolbar magnifying glass and use `QuickSearchView`'s `#tag` mode.

**Import/Export round-trip:**
- **JSON:** adds `"tags": [String]` per expense; absent on legacy payloads is treated as nil.
- **CSV:** adds 9th `"Tags"` column (semicolon-separated); `Expense.init(fromCSV:)` tolerates 8-column legacy files.

### Advanced Statistics & PDF Reports (Phase 5 Pro)

Pro tier layers four additions onto the existing Statistics screen — deliberately *inside* the same scrolling flow so upgrading feels like the view lights up rather than moves.

- **`Utilities/AdvancedStatsCalculator.swift`** — three pure functions, all Sendable-safe and called from the existing detached-task pipeline in `StatisticsView.recomputeStatsNow`:
  - `dailyPace(currentTotal:previousTotal:rangeStart:rangeEnd:)` — `DailyPace` with current daily avg, prior daily avg (same-length window), and % change. Elapsed days are capped at "today" so a 31-day month doesn't dilute the average on day 5.
  - `velocity(currentTotal:previousTotal:rangeStart:rangeEnd:)` — `Velocity` with `state` (`.projecting` or `.completed`), current total, linearly-projected end-of-period total, prior total, and % change. When the range has already ended, projection equals actual.
  - `yearOverYear(allExpenses:count:)` — `[YearOverYearPoint]` for the trailing `count` months (default 6). Buckets all expenses by `(year, month)` in a single O(n) walk so the window length is free. **Intentionally ignores the current date-range filter** — YoY is a year-wide insight.
- **`Components/YearOverYearChart.swift`** — SwiftUI Charts grouped `BarMark`s (this-year bold, last-year muted). Shows totals + a signed % delta pill (red for increase, green for decrease).
- **`Views/ProInsightsSection.swift`** — the only view the Statistics screen knows about. Pro users see two metric cards (Daily Pace + Velocity) side-by-side plus the YoY card below; free users see a single premium-styled teaser (gradient icon, three preview pills, "Try Pro" capsule, lock-badge) that opens `PaywallView` on tap. Identical vertical footprint either way so layout never jumps between states.
- **`Components/InsightInfoButton.swift`** — small `info.circle` button + `InsightExplanationSheet` bottom sheet used by **every** section on the Statistics screen (Pro and free). Copy lives in a single file as `InsightInfo` values (`.dailyPace`, `.velocity`, `.yearOverYear`, `.heroOverview`, `.highlights`, `.whereItGoes`, `.paymentMethods`, `.spendingPattern`, `.trend`). Three-section sheet: "What it means" / "How it's calculated" / "Why it matters" — keeps explanations scannable.
- **`Components/TrendChartPager.swift`** — three-page swipeable pager that replaced the old single-chart Trend section. Pages: **Over time** (`ExpenseTrendChart`), **By weekday** (SwiftUI Charts `BarMark` over Sun–Sat averages, highest bar emphasised with a star + annotation), **Top days** (horizontal bars with rank badges + gradient fills). Top row is a segmented tab bar with `matchedGeometryEffect` selection pill; bottom row is animated page dots + a "Swipe to compare" hint. Heavy aggregation is precomputed by `StatisticsCalculator.weekdayAverages(...)` / `topSpendingDays(...)` on the background recompute task so swipes stay at 60 fps regardless of dataset size.

**PDF Report Generator — `Utilities/PDFReportGenerator.swift`:**
- Public API: `PDFReportGenerator.generate(data: ReportData) throws -> URL`. Writes to `FileManager.default.temporaryDirectory` so the returned URL can be handed straight to `ShareSheet` (reusing the existing `UIActivityViewController` wrapper from `ExportDataView`).
- `ReportData` is a fully self-contained snapshot (primitives + arrays of value types), so the generator can run from `Task.detached(priority: .userInitiated)` without capturing the view.
- Layout is US-Letter (612×792 pts), 48-pt margins, hand-drawn with `UIBezierPath`/`NSAttributedString` for consistent output: brand header + rule on every page, large title + date range, total banner (mauve tint, % vs previous), stat grid (Transactions / Avg / Daily Pace / Projected Total), category breakdown with progress bars, zebra-striped "Top Expenses" table, footer with page number. Page-break logic in `DrawState.ensureSpace(for:)` reserves space for the footer before every row.
- `StatisticsView.buildReportData()` assembles the payload from already-cached aggregates (no extra aggregation on export) and includes the top 40 expenses by amount from `cachedTopExpenses`.

**Gating strategy (follows the "give all the value to Pro" principle):**
- Every pre-existing statistic stays free — nothing was taken away.
- Pro unlocks *forward-looking* metrics (projection, pace, YoY) plus the shareable PDF artifact.
- The export button in `StatisticsView.headerSection` is visible to everyone, with a tiny lock badge for free users; tapping it from free opens the paywall directly so upgrade friction is effectively one tap.

### Forecasting (Phase 7 Pro)

Forecasting is a Pro-only section that sits directly under **Pro Insights** on the Statistics screen. It answers a forward-looking question — *"if I keep going, where will I land?"* — using only on-device math. No network, no cloud, no model downloads.

- **`Utilities/ForecastEngine.swift`** — pure, Sendable-safe compute. The single entry point is:
  ```swift
  ForecastEngine.compute(
      history: [Expense],
      upcomingSubscriptions: [Subscription],
      horizonDays: Int = 30
  ) -> Forecast
  ```
  The algorithm is intentionally simple and explainable so the confidence band remains honest:
  1. **Discretionary baseline.** History is filtered to the last 90 days, and any `Expense.isFromSubscription == true` is excluded from the daily-pattern model so recurring bills aren't double-counted when added back as known cashflows.
  2. **Weekday seasonality.** Daily totals (including zero-spend days) are bucketed by `Calendar.weekday`. Each day in the horizon is projected from its own weekday's mean — Saturdays don't look like Tuesdays.
  3. **Recency weighting.** Each historical day's contribution is multiplied by `0.5 ^ (daysAgo / 30)` so a habit change shows up quickly instead of being averaged out by ancient data.
  4. **Outlier resilience.** A provisional weekday mean+stddev is computed first; values above `mean + 3σ` are capped before the final mean is computed, so a single $1,200 flight doesn't poison Tuesday.
  5. **Subscription overlay.** Active subscriptions are walked forward from `nextDueDate` using `Subscription.calculateNextDueDate(...)` and added on the actual day each charge falls. Each loop has a 400-iteration safety cap so a malformed cadence can never spin forever.
  6. **Confidence band.** ±1σ of daily residuals from the weekday mean, clamped to ≥0 on the low end and floored at 8% of the average daily spend so the band never collapses to a deceptive zero on flat data.
  7. **Data quality gate.** `< 14 days` of history with `< 5 active days` returns `dataQuality == .insufficient` and an empty projection — the section then renders the "keep logging" empty state instead of an unreliable number.
  8. **Top driver.** Recency-weighted category share over the discretionary history, returned as a `(category, customCategoryId, projectedShare)` triple.
  
  Output is a `Forecast` value — per-day points (`actual` for history, `projected`+`confidenceLow`+`confidenceHigh`+`subscriptionAmount` for the horizon) plus headline sums and diagnostics. Both the chart and headline cards consume the same struct so they always agree.

- **`Components/ForecastChart.swift`** — SwiftUI Charts renderer. Solid `LineMark` for actual history, dashed `LineMark` for projection (a "bridge point" connects them so there's no gap at "today"), faint `AreaMark` for the confidence band, a `RuleMark` for the "Today" label, and yellow `PointMark` dots on days where a subscription cashflow lands. Render-only; no compute.

- **`Views/ForecastSection.swift`** — section composer. Pro users see a horizon switcher (`30d` / `60d` / `90d`, gradient-pill capsule style matching the rest of the app), the headline card (projected total, confidence range, "through May 25" label, the chart, and a small legend), plus two side-by-side metric cards (Subscriptions $ and % of forecast / Top Driver category and recent share). Free users see a single teaser matching the Pro Insights teaser style — same vertical footprint either way so layout never jumps when upgrading. The header has an `InsightInfoButton` (`.forecast`) that opens a plain-English explanation sheet describing the algorithm without jargon.

- **Compute integration with `StatisticsView`:** the forecast is built on the **same `Task.detached` pipeline** as the rest of the stats. The detached task fetches active subscriptions directly from a `newBackgroundContext()` (so we don't have to inject a `SubscriptionViewModel` into Statistics) and feeds the full expense set (not the date-filtered slice — the forecast is about overall trajectory) into `ForecastEngine.compute`. Switching the horizon calls `scheduleRecomputeStats(immediate: true)` so the new projection appears in one frame.

- **History scope:** the forecast deliberately uses **all** expenses, not the currently-filtered period. The Statistics filter bar is a "look at the past" control; the forecast is a "look at the future" control. Decoupling them means the forecast is stable while the user pages backward through historical months.

- **Concurrency safety:** every input crossing the actor boundary (expenses snapshot, subscriptions snapshot, horizon int) is a value type. The engine itself is a free `enum` with only static functions and zero stored state.

---

## 7. Views

### App Shell

| View | File | Description |
|------|------|-------------|
| `CashLensApp` | `CashLensApp.swift` | `@main` entry. Core Data injection, ViewModel creation, onboarding/splash gates, deep link sheets, scene phase refresh. |
| `MainTabView` | `MainTabView.swift` | Custom 3-tab bar (Home, Subscriptions, Statistics). Hidden `UITabBar`, FloatingAddButton on Home. Sheets: add expense, currency picker, feedback overlay. |
| `SplashScreenView` | `SplashScreenView.swift` | ~2s branded splash with logo, gradient, spring animation. |
| `OnboardingView` | `OnboardingView.swift` | 6-page marketing carousel with Skip/Next/Get Started. Sets `hasCompletedOnboarding`. |

### Primary Tabs

| View | File | Description |
|------|------|-------------|
| `HomeView` | `HomeView.swift` | Redesigned landing dashboard. **Top-to-bottom order:** compact header (time-of-day greeting + emoji + page title with the user's name + subtitle showing the active period's date range; circular Search and Profile gradient-icon buttons), **period selector pills moved above content** (TimeFrame filter now precedes everything it filters), **Hero Spending Card** (uppercase caption, **optional no-spend streak leaf chip** rendered to the right of the period caption when `StreakCalculator.summary(...).isMeaningful` — current streak ≥ 2 or month progress ≥ 3 no-spend days, huge total with `.numericText()` content transition, color-tinted delta pill comparing this period vs the previous comparable period with matched-elapsed cutoff so partial months compare apples-to-apples, divider, three inline mini-stats: Expense count / Per-day average / Top category — whole card is a button that opens All Expenses), **budget strip** (Pro budgets or upgrade teaser), **Pinned Categories** grid (rich `PinnedCategoryCard` tiles — amount + trend pill vs previous period + expense count + optional budget progress bar + strong selected state when acting as the Recent Expenses filter), **Recent Expenses** with a **matched-geometry segmented filter pill** (All / Subscriptions). The old "Filter by Category" horizontal strip has been removed: its behaviour is now owned by Pinned Categories (tap-to-filter with obvious selected state) and `QuickSearchView`'s Browse-by-Category strip handles non-pinned categories, so Home has exactly one category-filter control. All sections share one `SectionEntrance` cascading spring entrance (0.06s stagger) matching Statistics and Subscriptions. Previous-period totals — both app-wide (for the hero pill) and per-category (for each pinned tile's trend) — are computed off-main in debounced `Task.detached` runs (80 ms debounce, `nonisolated` static pure compute) so large datasets never block the UI. iPhone and iPad layouts share the same structure. Sheets: profile, all expenses, add expense, summary customization, quick search, budgets, paywall. |
| `SubscriptionsView` | `SubscriptionsView.swift` | Redesigned subscriptions tab. One **hero card** owns the summary: small "Per month" label, huge total, a **"Next up"** row previewing the earliest upcoming active sub (category chip + "Netflix · tomorrow · $15.99"), divider, then three inline mini-stats (Yearly / Due 7d / Average). Below: **segmented filter pills** (`All` / `Active` / `Due Soon`) with `matchedGeometryEffect` on the selection. List is grouped into Due Soon / Later / Paused subsections when "All" is active. Empty-filter state is a single compact card with a "Show All" pill. Entrance motion mirrors Statistics via `SubEntrance`. Sheets: add/edit subscription, monthly breakdown. |
| `StatisticsView` | `StatisticsView.swift` | Redesigned premium statistics dashboard. Filter bar (time-frame pills → **Apple-Fitness-style period chevrons** `< December 2024 >` with smart labels for Today / Yesterday / This week / Last week / named months / years + forward chevron disabled when at current period → optional category row). Hero Overview card: huge total + delta pill + three inline mini-stats (Expenses / Average / Highest) replacing the old three-card grid. Pro Insights (daily pace / velocity / YoY). **Forecast** (horizon switcher `30d / 60d / 90d`, projected total + confidence range, line-chart with dashed projection + ±1σ band + subscription dots, Subscriptions and Top Driver mini-cards). Highlights (auto insights). **Where It Goes** merges the donut chart + category rows into one card with tap-linked selection — tap a slice or a row and the other half highlights via shared `donutSelectedId`. **Payment Methods** (Pro): same donut + breakdown shape, but slices are payment methods; selection state is `paymentDonutSelectedId`. Untagged expenses surface as a "tag x more (N% covered)" footer instead of as a wedge. Free users see a focused upgrade teaser instead of a live donut so the Pro reveal feels meaningful. Section is hidden entirely when no expense in view has any payment method *and* the user is free. Spending Pattern (heatmap). **Trend is a three-page swipeable pager** (Over time / By weekday / Top days) with a segmented tab bar, page dots, and matched-geometry selection. Every section header (plus the hero label) has an `InsightInfoButton` that opens a plain-English explanation sheet. Unified `SectionEntrance` modifier gives every section a spring-based cascade that settles in ~0.4 s. Debounced background recomputation computes weekday averages + top-day aggregates + the forecast + the payment-method breakdown alongside the existing totals so swipes stay at 60 fps. Free users see teasers for Pro Insights, Forecast, and Payment Methods + lock-badged PDF export; all of them route to `PaywallView`. |

### Forms

| View | File | Description |
|------|------|-------------|
| `AddExpenseView` | `AddExpenseView.swift` | Expense create/edit. **Templates chip strip** at the top of the form when the user has saved presets — taps fill the form with safe-merge semantics (never overwrites typed title/amount; tags/notes/refund flag are *additive*); long-press / context-menu offers Use or Delete. **"Save as template"** bookmark in the header (right of close, only when the form is valid and not editing) opens a quick rename alert. Amount, **refund toggle row** (above title; flips the entry to subtract from totals), title, **smart "Suggested" category pill** (driven by `CategorySuggester`, surfaces once title ≥ 2 chars and confidence ≥ 0.45 — single tap sets the category with a haptic), category picker (horizontal), date, **tags (chip field with live autocomplete / recent / popular suggestions, Pro-free for adding)**, notes. Draft save/restore (includes tags + `isRefund`), duplicate detection, quick date chips, title suggestions. |
| `AddSubscriptionView` | `AddSubscriptionView.swift` | Subscription create/edit — **structural twin of `AddExpenseView` / `BudgetSetupView`** (same custom header with X + optional trash, `@FocusState`-driven `.fieldCard(isFocused:)` inputs, fixed bottom save button with gradient fade). Fields: amount (hero), service name, billing frequency (horizontal pill row), start date (compact row → `.graphical` date picker sheet) with live "Next: Mar 20, 2026 · Every month" preview, category picker (circle style identical to Budget), reminder card (toggle + 1d/2d/3d/7d pill chips replacing the old stepper), notes. Delete section shown when editing. |
| `CustomCategoryForm` | `CustomCategoryForm.swift` | Category name, icon picker (grid sheet), color picker (grid sheet). Validation. |

### Lists & Search

| View | File | Description |
|------|------|-------------|
| `AllExpensesView` | `AllExpensesView.swift` | Full list — the **Library** half of the search/browse pair. Sort (date/amount/title/category), date range, subscription filter, default + custom category chips, **Pro-gated tag filter strip** (`tagsFilterRow`), pagination (250 chunks). Swipe delete, context menu, date-grouped sections with refund-aware daily totals (`netTotal()`). The inline search field has been removed: tapping the toolbar magnifying glass opens `QuickSearchView` as a sheet so the app has exactly **one** search surface. The toolbar **calendar icon** opens `ExpenseCalendarView` for month-grid browsing (iPhone + iPad). **Selection mode:** a "Select"/"Done" toolbar toggle reveals checkboxes per row and a sticky bottom action bar with **Category**, **Tag**, and **Delete** actions plus a live count; bulk operations route through the batch APIs in `ExpenseViewModel+CRUD.swift` (`deleteExpenses`, `bulkChangeCategory`, `bulkAddTag`) so all changes commit in a single Core Data save. Tap-to-toggle when selecting, tap-to-edit otherwise. The empty state is filter-aware — when narrowing filters return zero results it shows a "Clear Filters" button + a "Search instead" link straight into Quick Search; otherwise it shows the standard "No expenses found" panel. |
| `ExpenseCalendarView` | `ExpenseCalendarView.swift` | Modal **month-grid browse** surface — the calendar complement to the chronological `AllExpensesView` list and the intensity-based `SpendingHeatmap`. Reachable from `AllExpensesView`'s toolbar (`calendar` icon, iPhone + iPad). Each day cell shows the day number, up to three colored category dots (top categories that day by absolute amount), and a compact net total. Today is highlighted with an `appPrimary` tint; future days are visually muted and non-tappable. Tapping a day expands a detail section beneath the grid showing the day's expenses sorted newest-first; rows route to the same `AddExpenseView` editor used elsewhere — never a separate code path. A summary strip surfaces month net total, transaction count, and active-day count. Per-day aggregation runs in `Task.detached`, keyed off `visibleMonth` and `viewModel.$expenses`, so swiping months never blocks the main thread. **Read-only** — never mutates Core Data directly. |
| `QuickSearchView` | `QuickSearchView.swift` | Modal search — the **Spotlight** half of the search/browse pair. Opened from the Home header magnifying glass **and** from the toolbar magnifying glass on `AllExpensesView`, so search is the same experience everywhere in the app. Custom header (X close + centered "Search" title) replaces the default `NavigationView` chrome to match the Add screens. Hero search field uses `.fieldCard(isFocused:)` so the focus glow is consistent app-wide. Empty-query state surfaces useful affordances: **persisted Recent Searches** (last 5, dismissible chips, `UserDefaultsKeys.quickSearchRecents`), one-tap **Quick Tips** chips ("This month", a real `$X` example anchored to the user's median spend, top tag/category), **Browse by Category** strip with circular icon medallions, **Browse by Tag** strip (top 5 tags with usage counts via `tagStats`, only shown when tags exist), and a Recent Activity preview. Results state shows a count + total summary chip and groups results into Today / Yesterday / This Week / Earlier. Result rows highlight the matched substring of the title in `appPrimary` semibold and show category · date · first tag. **Smarter ranking** (off-main, 150 ms debounce, `Task.detached`): title-prefix > title-contains > tag > category > notes > exact-amount. Numeric amount parsing (`$50` ≈ `50.00`), `#tagname` tag-only mode, and natural date keywords (`today`, `yesterday`, `this week`, `this month`, `this year`) act as hard filters. Sections animate in with a `SearchEntrance` cascade matching Statistics / Subscriptions / Home. |

### Settings & Data

| View | File | Description |
|------|------|-------------|
| `ProfileView` | `ProfileView.swift` | Settings hub, restructured for clean information architecture. **Top → bottom:** compact profile header (72 pt avatar, tap-to-edit name with pencil chip + `@FocusState`), Pro card (active or upgrade), **contextual Backup Warning Banner** (only visible when backup health is not `.good`, tap → opens export sheet directly so the most critical signal can't be buried), **Preferences** (currency, appearance, default time frame, manage budgets — Appearance and Default Time Frame use SwiftUI `Menu` instead of inline accordion pickers), **Personalization** (Pro — Color Theme + App Icon, both rows route into their dedicated picker sheet for everyone; trailing slots show the active theme name + swatch dot or active icon name + tiny rounded preview tile for Pro users, or a shared `proLockChip` for free users — picker tap is the same UX in both states so users discover the upsell *inside* the picker, not at the row), **Reminders** (weekly digest, monthly digest, backup reminder, plus the **Pro Smart Insights** toggle — single toggle, no schedule sub-row, fires Sunday 10 AM only when something interesting happened; free users see the row with a "Pro" lock pill that opens the paywall on tap), **Data** (Backup Health card + export / import / clear-all + footnote — backup-related settings now live together in one place), **About** (Support the App — moved out of Settings since it's an action not a preference, About CashLens, compact 3-up community icon row replacing the prior full-width social tiles), and a tiny **version footer**. Fully built on the design system — every row is `SettingsRow`/`SettingsRowValue`/`SettingsRowDestructive`, every section wrapped in `.sectionContainer()`, every section title a `SectionHeader`. |
| `ThemePickerView` | `ThemePickerView.swift` | Pro-gated accent theme picker. **Live preview card** at the top (mock pills + tinted progress bar + FAB that all recolor instantly when the user taps a swatch — the marketing moment), **3-column swatch grid** (6 themes, circular wells filled with each theme's primary color, checkmark on the saved selection, accent ring on the previewed selection, lock badge on Pro options for free users), and a **conditional Pro CTA** that only appears when a free user is previewing a Pro theme. `previewTheme` updates instantly on every tap; `themeStore.applyTheme(_:)` only commits for the default or for Pro users. Uses `Theme.Motion.tap` springs for tile scale + `Theme.Motion.snappy` for content transitions; `HapticManager.shared.success()` on a real apply, `.warning()` on a paywall hit. |
| `AppIconPickerView` | `AppIconPickerView.swift` | Pro-gated alternate-app-icon picker. Same UX shape as `ThemePickerView` so users build muscle memory: **132 pt rounded-square hero preview** at the top (with shadow + soft scale animation on apply), **4-column grid** of 60 pt rounded icon tiles (8 options — Mauve primary + 7 alternates), and a **conditional Pro CTA** for previewed-but-locked picks. Active selection gets a `checkmark.circle.fill` badge; Pro-locked picks get a tiny lock badge. Wraps `appIconStore.apply(_:)` in a `Task`, surfacing `ApplyError` via an in-picker alert and reverting the preview on failure so the UI never lies. Hides itself entirely on devices where `UIApplication.shared.supportsAlternateIcons` is false (vanishingly rare but the official guard). |
| `CurrencyPickerView` | `CurrencyPickerView.swift` | Currency selection: region chips, search bar, checkmark list. `interactiveDismissDisabled` in setup mode. |
| `ManageCategoriesView` | `ManageCategoriesView.swift` | Default categories (swipe delete → moves expenses to Other), deleted defaults (restore), custom categories (edit/delete/add). |
| `SummaryCustomizationView` | `SummaryCustomizationView.swift` | Pick up to 4 categories to pin on Home. Rebuilt around one idea: **the selected cards are the preview**. The large miniature-tile preview was retired (it competed with the real selection cards and shrank everything to fit). Replaced with a compact horizontal "Home line-up" chip strip at the top that confirms the picks in pinned order (empty slots render as dashed chips, horizontally scrollable for small screens). Below that, the selection grid uses beefed-up `CategorySelectionCard`s at a fixed 144 pt (iPhone) / 158 pt (iPad) height, mirroring the `PinnedCategoryCard` idiom — icon medallion tinted on selection, title (14 pt semibold), **20 pt rounded-bold amount in primary** for real decision data, expense count (12 pt medium secondary), checkmark badge, gradient tint + color border when selected. Unselected-and-disabled (when the lineup is full) eases from harsh 0.45 opacity to 0.62 so ghosted cards stay legible. Reset link surfaces only when selection differs from defaults; single floating Save bar. `maxSelections` is a single source of truth paired with `ExpenseViewModel.getSummaryCardsData`'s matching `prefix(4)` clamp. |
| `ExportDataView` | `ExportDataView.swift` | Choose CSV/JSON format, export, share via `UIActivityViewController`. Records backup metadata. |
| `ImportDataView` | `ImportDataView.swift` | File picker (`.fileImporter`), progress overlay with fake progress, success/error alerts. |
| `DonationView` | `DonationView.swift` | StoreKit tip jar: gradient cards per product, processing overlay. |
| `AboutView` | `AboutView.swift` | Static info: features, what's new, contact email, website, privacy. |
| `FeedbackRequestView` | `FeedbackRequestView.swift` | Overlay prompt: rate (SKStoreReviewController), share, dismiss. Gated by `FeedbackManager`. |
| `DiagnosticsView` | `DiagnosticsView.swift` | `#if DEBUG` only. Data refresh, currency checks, smoke tests, feedback reset. |

---

## 8. Components

| Component | File | Description |
|-----------|------|-------------|
| `PinnedCategoryCard` | `PinnedCategoryCard.swift` | Premium Home pinned-category tile. Icon medallion + rounded amount (with `contentTransition(.numericText())`) + category title + expense-count line + optional thin budget progress bar when a budget exists for that category. Top-right **trend pill** (↑/↓ %, Flat, or New/sparkle) driven by the previous comparable period. Strong **selected** treatment (gradient border + soft color-tinted shadow) when the card is the active Recent-Expenses filter on Home. `ScaleButtonStyle`. |
| `ExpenseCard` | `ExpenseCard.swift` | Primary expense row. `Equatable` + precomputed fields for perf. Icon, title, category, notes, amount, date. |
| `ExpenseRow` | `ExpenseRow.swift` | Simpler expense row using `@EnvironmentObject`. Less optimized, compact style. |
| `CategoryItem` | `CategoryItem.swift` | Horizontal default category chip with selection ring. `Equatable`, `drawingGroup`. |
| `CustomCategoryItem` | `CustomCategoryItem.swift` | Horizontal custom category chip. Same pattern as CategoryItem. |
| `CategoryDonutChart` | `CategoryDonutChart.swift` | Interactive donut + legend. Tap center clears selection, legend toggles slices. `drawingGroup` on ring. |
| `ExpenseTrendChart` | `ExpenseTrendChart.swift` | Custom `Path` line/area chart by time frame. Grid, tooltips, adaptive labels. iPad-aware height. |
| `SpendingHeatmap` | `SpendingHeatmap.swift` | GitHub-style calendar heatmap (horizontal scroll). Tap day for total. Caps at 365 days. |
| `SubscriptionRow` | `SubscriptionRow.swift` | Redesigned subscription cell. Category icon, **single status line** (colored dot + one of `Paused` / `Overdue by N days` / `Due today` / `Due in N days` / `Renews Mar 20, 2026`) — all previous redundancy (inline PAUSED badge + bottom Paused label + separate due line + "Soon"/"Active"/"Overdue" status label) consolidated. Monthly equivalent is shown **only when frequency ≠ monthly** (removed pointless self-repeat for monthly subs). Trailing column shows the amount and, when due/overdue, a compact inline **Mark paid** pill (no full-row CTA). Quick swipe actions: leading = Pause/Resume, trailing = Delete. Context menu kept for Edit + long-press access. |
| `FloatingAddButton` | `FloatingAddButton.swift` | Circular FAB for Home tab. Medium haptic on tap. |
| `AddButton` | `AddButton.swift` | Gradient add button variant with preview sizes. |

---

## 9. Utilities

| Utility | File | Description |
|---------|------|-------------|
| `HapticManager` | `HapticManager.swift` | Singleton with cached `UIImpactFeedbackGenerator`s. Methods: `lightTap`, `mediumTap`, `heavyTap`, `success`, `warning`, `error`, `selectionChanged`. Pre-prepares generators. |
| `DeepLinkRouter` | `DeepLinkRouter.swift` | `ObservableObject` singleton. Parses notification `userInfo` into `DeepLinkRoute` (.allExpenses with filter, .export). Drives `.sheet(item:)` in `CashLensApp`. |
| `ExpenseFilter` | `ExpenseFilter.swift` | Pure function `apply(expenses:category:customCategoryId:timeFrame:referenceDate:)`. Also supports explicit date range `[start, end)`. |
| `NotificationScheduler` | `NotificationScheduler.swift` | Schedules one-shot weekly/monthly digest, backup reminder, and the **Pro Smart Insights** weekly push via `UNUserNotificationCenter`. `DigestStatsCalculator` powers digest bodies; `scheduleNextSmartInsight(viewModel:)` evaluates `SmartInsightsEngine` on every foreground refresh and only schedules when an insight clears the firing bar. `refreshScheduledNotificationsIfNeeded(viewModel:isPro:)` is the single entry point — `isPro` gates Smart Insights without leaking ProManager into the scheduler. |
| `SmartInsightsEngine` | `SmartInsightsEngine.swift` | Pure, `Sendable`-safe value-type engine that selects the highest-priority weekly insight (or `nil`) for the Pro Smart Insights notification. Six kinds in priority order: `streakRecord`, `refundWindfall`, `categorySpike` (≥ 2.4× over 4-week baseline + ≥ $50 absolute delta), `categoryAllTime`, `subscriptionsDue` (≥ 3 in next 7 days), `weekTotalNew`. Each candidate carries a fingerprint persisted in `HistoryRecord` (UserDefaults key `smartInsightsHistory`) so the same headline can't refire within `cooldownDays = 14`. History auto-prunes at 60 days. |
| `StatisticsCalculator` | `StatisticsCalculator.swift` | `previousPeriodExpenses` for comparison, `insights` returning `[StatInsight]`, `categoryBreakdown` returning `[CategoryExpenseData]` with colors, `paymentMethodBreakdown` returning a refund-aware `PaymentMethodBreakdown` (Pro donut), `weekdayAverages` and `topSpendingDays` for the Trend pager. |
| `AdvancedStatsCalculator` | `AdvancedStatsCalculator.swift` | Pro-tier pure functions: `dailyPace`, `velocity` (projecting vs completed states), `yearOverYear` (single-pass bucketing, window-length free). All Sendable-safe — called from the existing detached-task pipeline. |
| `PDFReportGenerator` | `PDFReportGenerator.swift` | Pro-tier PDF export. `generate(data:) -> URL` composes a multi-page US-Letter report via `UIGraphicsPDFRenderer` (cover, total banner, stat grid, category breakdown w/ bars, zebra-striped top-expenses table, per-page footer). Caller hands the URL to `ShareSheet`. |
| `ImportUtilities` | `ImportUtilities.swift` | `ImportResult` (expenses, subscriptions, customCategories, deletedDefaultCategories). `ImportError` enum. Parses sectioned CSV (`=== SECTION ===`) and JSON. Robust CSV field parsing with quote handling. |
| `UserDefaultsKeys` | `UserDefaultsKeys.swift` | Caseless enum with all `static let` string constants. Single source of truth for all UserDefaults keys. |
| `ExpenseDraft` | `ExpenseDraft.swift` | `Codable` struct: raw amount string, title, category, customCategoryId, date, notes, timestamp, optional `isRefund`, optional `paymentMethod` (raw String w/ a `resolvedPaymentMethod` computed property using `PaymentMethod.tolerant(from:)`). Persisted to `UserDefaultsKeys.expenseDraft`. |
| `CategorySuggester` | `CategorySuggester.swift` | Pure value-type. `suggest(for:history:) -> Suggestion?` builds a normalized-token frequency map from up to the last 1500 expenses and returns the best category match for a typed title. Min confidence 0.45, min query 2 chars. Drives the "Suggested" pill in `AddExpenseView`. |
| `StreakCalculator` | `StreakCalculator.swift` | Pure enum. `summary(from:now:calendar:) -> StreakSummary` returns `noSpendDaysThisMonth`, `currentStreak`, `bestStreak` (90-day lookback). `isMeaningful` decides whether the Home hero shows the leaf streak chip. Refund-aware via `signedAmount`. |
| `ExpenseTemplateStore` | `ExpenseTemplateStore.swift` | `@MainActor`-isolated `ObservableObject` singleton (`shared`) backing the saved-template chip strip in `AddExpenseView`. Persists `[ExpenseTemplate]` to `UserDefaults` (key `expense_templates_v1`) via `JSONEncoder` (ISO-8601 dates). Capped at 12 templates with LRU-style eviction, `displayOrder` sorts most-recently-used first, `markUsed(id:)` bumps `lastUsedAt`, `containsTemplate(matching:)` powers the "Save as template" affordance gating. Templates are intentionally local-only and **not** part of JSON/CSV backups. |
| `ThemeStore` | `ThemeStore.swift` | `@MainActor ObservableObject` singleton (`shared`) backing the active accent theme. Holds `currentTheme: AppTheme` (`@Published`) for SwiftUI views *plus* a `nonisolated(unsafe)` `activeTheme` static for the dynamic `Color.appPrimary` / `Color.appSecondary` UIColor closures (which UIKit can resolve off-main). `applyTheme(_:)` updates the published value, persists to `UserDefaults.activeThemeId`, fires `.themeDidChange`, and runs a soft `UIView.transition` cross-dissolve on the key window's `overrideUserInterfaceStyle` so cached UIKit dynamic colors invalidate cleanly without a jarring redraw. **Single read/write surface for theme** — `Color.appPrimary` reads `ThemeStore.activeTheme` directly so the ~150 call sites need zero change. |
| `AppIconStore` | `AppIconStore.swift` | `@MainActor ObservableObject` singleton (`shared`) wrapping `UIApplication.setAlternateIconName(_:)` (iOS 18+ async API). On init it reconciles three potentially-divergent sources of truth — the OS's current `alternateIconName`, our persisted `activeAppIconId`, and `AppIconOption.primary` — preferring the OS value so a CloudKit-synced UserDefaults value can't override what the device is actually showing. `apply(_:)` guards on `supportsAlternateIcons`, short-circuits on the primary case, persists *only after* the OS confirms (no stale id on failure), and surfaces `ApplyError` so the picker can show a friendly alert. |

---

## 10. Extensions

| File | Contents |
|------|----------|
| `ButtonStyles.swift` | `ScaleButtonStyle` (scale 0.9 + spring + medium haptic), `OpacityButtonStyle` (opacity 0.7 + light haptic), `CustomAddButtonStyle` (scale 0.95 + heavy haptic) |
| `NotificationExtension.swift` | `Notification.Name` constants: `.appearanceDidChange`, `.dataDidClear`, `.subscriptionCurrencyUpdated` |
| `ViewExtensions.swift` | `.if(_:transform:)` conditional modifier, `cornerRadius(_:corners:)` per-corner rounding via `RoundedCorner` shape |

---

## 11. Design System

The app has a formal design system under `CashLens/Design/`. All UI code should reach for tokens and shared components from this folder instead of hard-coded values. This keeps every screen visually coherent and makes future redesigns a one-file change.

### Tokens (`Design/Theme.swift`)

One namespace, `Theme`, with nested token families. Pick the **role**, not a raw number.

| Family | Members | Purpose |
|--------|---------|---------|
| `Theme.Spacing` | `xxs(2)`, `xs(4)`, `sm(8)`, `md(12)`, `lg(16)`, `xl(20)`, `xxl(24)`, `xxxl(32)`, `tabBarInset(120)` | Rhythm for padding and `VStack` / `HStack` spacing |
| `Theme.Radius` | `chip(12)`, `row(14)`, `card(16)`, `container(18)`, `hero(22)` | Corner radii — never use naked `cornerRadius(14)` style numbers in views |
| `Theme.Stroke` | `hairline(0.5)`, `thin(1)`, `medium(1.5)` | Border widths |
| `Theme.Typography` | `pageTitle`, `sectionTitle`, `subsectionTitle`, `rowTitle`, `caption`, `numeric`, `numericSmall` | Semantic type styles |
| `Theme.Shadow` | `cardColor/Radius/Y`, `elevatedColor/Radius/Y` | Elevation |
| `Theme.Motion` | `snappy`, `tap`, `emphasized` | Only three animations — use them everywhere |
| `Theme.Icon` | `chip(13)`, `row(18)`, `heroRow(22)`, `emptyState(36)` | SF Symbol sizes per role |

**Gradient helpers** on `LinearGradient`:

- `.appPrimary` — horizontal mauve → jordyBlue, used on CTAs
- `.appPrimaryDiagonal` — diagonal variant for larger surfaces
- `.appPrimarySoft` — subtle tinted variant for backgrounds (pro teaser, badges)

> **Note (Phase 4 — Personalization):** `Color.appPrimary` and `Color.appSecondary` are now **computed dynamic colors** that read `ThemeStore.activeTheme` at render time. They resolve through `Color(UIColor { trait in ... })` so light/dark adaptation still happens automatically per theme — every theme ships hand-tuned light + dark hex pairs. The static `LinearGradient.appPrimary` etc. are deliberately **not** themed because they're used on hero CTAs where the canonical brand gradient is intentional; large pill-shaped surfaces have already been migrated from gradient to flat `Color.appPrimary` in Phase 4 prep so they pick up the theme.

### View modifiers (`Design/ViewModifiers.swift`)

| Modifier | Purpose |
|----------|---------|
| `.cardSurface(radius:fill:stroke:strokeWidth:)` | Canonical card background — replaces hand-rolled `RoundedRectangle(...)  + .fill(.secondarySystemBackground)` |
| `.sectionContainer(padding:)` | Outer tinted wrapper for grouped sections (Profile blocks, iPad Home blocks) |
| `.softShadow()` | Subtle card elevation for things that need to float |
| `.primaryGlow(strength:)` | Mauve-tinted glow for primary CTAs |

### Shared components (`Design/Components/`)

| Component | Purpose |
|-----------|---------|
| `SectionHeader(title:style:trailing:)` | Canonical in-page section header. Styles: `.page`, `.section`, `.subsection` |
| `SectionHeaderLink(title:icon:action:)` | "See All" / "Customize" style trailing link |
| `PillChip(title:icon:isSelected:shape:fullWidth:action:)` | Filter / selection chip. Shape: `.capsule` or `.rounded` |
| `PrimaryGradientButton(title:icon:width:isEnabled:action:)` | Primary gradient CTA — "Create Budget", "Save Changes" |
| `SecondaryOutlineButton(title:icon:width:action:)` | Outline companion to primary CTA |
| `EmptyStatePanel(icon:title:message:tint:action:)` | Full-screen empty state: tinted icon + title + message + CTA |
| `InlineEmptyState(icon:title:message:)` | Compact empty state for inside lists |
| `SettingsRow(icon:iconTint:title:subtitle:showsChevron:trailing:)` | Canonical settings / menu row |
| `SettingsRowValue(text:)` | Value label for the trailing slot (e.g. "USD") |
| `SettingsRowDestructive(icon:title:)` | Red destructive row variant |

### Color Palette (`Components/ColorExtension.swift`)

The app uses a **pastel palette** with light/dark variants.

| Color Name | Usage |
|------------|-------|
| `mauve` | **Primary accent** (`appPrimary`) |
| `jordyBlue` | **Secondary accent** (`appSecondary`) |
| `teaRose` | **Tertiary accent** (`appAccent`) |
| `lemonChiffon`, `champagnePink`, `pinkLavender`, `nonPhotoBlue`, `electricBlue`, `aquamarine`, `celadon` | Category / custom category options |

**Category colors:** Each `Expense.Category` maps to a named color via `Color.forCategory(_:)`.

### Haptic Feedback

Heavy use of `HapticManager` throughout:

- **Light tap**: Navigation, minor UI touches
- **Medium tap**: Tab changes, category selections, primary taps (default for `ScaleButtonStyle`)
- **Heavy tap**: Add expense, "Create Your First …" CTAs
- **Success**: Successful save operations
- **Warning**: Budget threshold crossings, alerts
- **Selection changed**: Chart / heatmap interactions, segmented controls

### Usage Rules

1. **Never hard-code corner radii.** Use `Theme.Radius.*`.
2. **Never hand-roll a new card background.** Use `.cardSurface()`.
3. **Never compose a new "icon + title + chevron" row.** Use `SettingsRow`.
4. **Never write a new empty state.** Use `EmptyStatePanel` or `InlineEmptyState`.
5. **Animations must be one of three.** `Theme.Motion.snappy`, `.tap`, or `.emphasized`.
6. **Typography goes through `Theme.Typography`**, not ad-hoc `.title3` / `.system(size:weight:)`.

### Adoption status

| Screen | Status |
|--------|--------|
| `HomeView` | Fully migrated (Phase B) + redesigned landing — hero spending card with period-delta pill, period selector moved above content, pinned-categories grid, matched-geometry recent filter, unified `SectionEntrance` cascade; dropped the redundant dark-mode toggle (lives in Profile → Appearance) and the private `homeSectionTransition` helper (replaced by the app-wide entrance modifier) |
| `ProfileView` | Fully migrated (Phase C) — every row uses `SettingsRow`/`SettingsRowValue`/`SettingsRowDestructive`, every section wrapped in `.sectionContainer()`, Pro card + Backup Health card tokenized. File is 1,699 → ~900 lines. |
| `StatisticsView` | Redesigned around six unified sections — Hero Overview, Pro Insights, Highlights, Where It Goes, Spending Pattern, Trend. All section titles use `SectionHeader`; time-frame pills use `PillChip`; every card (including the merged donut+rows card) uses `.cardSurface()`; a single `SectionEntrance` modifier drives the entrance cascade across every section with a 60 ms spring offset. Empty state is `EmptyStatePanel` + `PrimaryGradientButton`. |
| `SubscriptionsView` | Fully migrated (Phase D) — page title via `Theme.Typography.pageTitle`, compact header "Add" CTA uses `LinearGradient.appPrimary` + `.primaryGlow()`, stat mini cards tokenized via `.cardSurface()`, empty state uses `EmptyStatePanel` + `PrimaryGradientButton`, grouped subsections ("Due Soon" / "Later" / "Paused") use `SectionHeader(style: .subsection)`, filter status chip tokenized. |
| `AllExpensesView` | Fully migrated (Phase E) — filter chips use `PillChip(shape: .rounded)`, sort/date pill buttons use `LinearGradient.appPrimary` + `Capsule()`, empty states use `EmptyStatePanel` + `PrimaryGradientButton`, date-group header/badge tokenized, onAppear animation via `Theme.Motion.emphasized`. **Search consolidated**: the inline search bar was removed in favor of routing the toolbar magnifying glass into `QuickSearchView`, so the app has exactly one search surface. |
| `AddExpenseView` | Fully migrated (Phase E) — every field (amount, title, date, notes) uses `.cardSurface()`+`.softShadow()`, quick-date chips tokenized, draft-restored banner tokenized, save button uses `LinearGradient.appPrimary` with tokenized radius/shadow, onAppear spring → `Theme.Motion.emphasized`. |
| `BudgetSetupView` | Fully migrated (Phase E) — `SectionHeader(style: .subsection)` for Details/Alerts/Apply To, category picker uses `PillChip(shape: .rounded)`, period buttons use `LinearGradient.appPrimary`, CTA is `PrimaryGradientButton`, amount hero card via `.cardSurface(radius: Theme.Radius.container)`. |
| `BudgetListView` | Fully migrated (Phase E) — empty state is `EmptyStatePanel` + `PrimaryGradientButton`, `BudgetListRow` uses `.cardSurface(radius: Theme.Radius.row)`, typography via `Theme.Typography.rowTitle`/`.caption`, spacing fully tokenized. |
| `PaywallView` | Fully migrated (Phase E) — hero uses `LinearGradient.appPrimaryDiagonal`, feature card via `.cardSurface(radius: .container, fill:)`, plan cards tokenized with `Theme.Radius.card`, purchase CTA is `PrimaryGradientButton`, animations via `Theme.Motion`. |
| `AboutView` | Fully migrated (Phase F) — every section block uses `.cardSurface()` with tokenized padding, contact links use `.cardSurface(radius: .chip, fill: .tertiarySystemBackground)`, spacing tokens throughout. |
| `ImportDataView` / `ExportDataView` | Fully migrated (Phase F) — primary CTA gradient buttons share `LinearGradient.appPrimary` + `.primaryGlow()`, loading overlays use `.cardSurface()`, warning callout uses `.cardSurface(radius: .chip, fill: .orange.opacity(0.1))`, haptics routed through `HapticManager.shared.mediumTap()` (removed per-view `hapticFeedback(style:)` helpers that allocated a fresh `UIImpactFeedbackGenerator` on each tap). |
| `OnboardingView` | Fully migrated (Phase F) — Get Started / Next button uses `Theme.Radius.card` + `Theme.Spacing.lg` padding. |
| `CurrencyPickerView` | Fully migrated (Phase F) — search field uses `.cardSurface(radius: .chip)`. |
| `DiagnosticsView` | Already clean — no straggler tokens detected. |

### Performance notes

- `HomeView`'s `AdaptiveGrid` no longer uses `GeometryReader` — it derives columns from the idiom (2 on iPhone, 3 on iPad). This removes a layout pass on every size change and eliminates the old fixed-height hack that capped summary cards at 160pt.
- The Home landing cascade is now one unified `SectionEntrance` spring (0.06s stagger) matching Statistics and Subscriptions. The old hand-rolled per-section `.animation(..., value: animateCards)` calls and the private `homeSectionTransition` helper are gone — one modifier drives all seven sections, so SwiftUI only has one animation curve to diff.
- Home's hero delta pill is powered by a debounced (`80ms`) `Task.detached` that sums the previous comparable period off-main. For users with thousands of expenses this never blocks the UI; for everyone else it returns in a few ms and fades in with `Theme.Motion.tap`.
- All `withAnimation` call sites on Home + Profile funnel through `Theme.Motion.tap` / `.snappy` / `.emphasized`. When future screens also do this, SwiftUI's animation coalescing gets better because it sees fewer unique `Animation` values.
- `ProfileView` collapsed from 1,699 to ~900 lines by replacing 16 hand-rolled rows with `SettingsRow` primitives. Less code means faster Swift type-checking on incremental builds **and** a simpler SwiftUI body graph (fewer anonymous `HStack { ... }` sub-expressions for the renderer to diff).
- Replaced Profile's private `hapticFeedback(style:)` helper — which allocated a fresh `UIImpactFeedbackGenerator` on every single tap — with the singleton `HapticManager.shared.*`. Haptics now reuse a prepared generator.
- Moved sheet bindings on Profile from attached-to-individual-rows up to their section containers so row-level bodies have fewer modifiers to re-evaluate when unrelated state changes.
- `StatisticsView` dropped the 0.8s ease-out animation on category progress bars to 0.3s. The bars still animate when the filter or date range changes, but the transition now feels instantaneous — important because Statistics filters can update several times per second while a user scrolls the date range.
- `StatisticsView` replaced a hand-rolled `timeFrameButton` (Capsule fill with solid `Color.mauve`) with `PillChip`, so the selected-state visual is now identical to Home's time-frame selector and the rendering path is shared (better SwiftUI identity coalescing across tabs).
- `SubscriptionsView` replaced direct `UIImpactFeedbackGenerator` calls with `HapticManager.shared.lightTap()` / `.mediumTap()` / `.success()` — haptics reuse a prepared generator instead of allocating one per tap.
- All three of Stats/Subs/Home now share `PillChip`, `SectionHeader`, `EmptyStatePanel`, `PrimaryGradientButton`, `.cardSurface()`, and `Theme.Motion` tokens. Any future visual tweak (e.g. bumping card radius from 16 → 18) is a one-line change in `Theme.swift`.
- `AllExpensesView` replaced its custom `filterChip(...)` (inline `Button` with its own gradient/`cornerRadius` logic) with `PillChip`, so the full-length expense filter row now shares its rendering path — and selected-state identity — with Home, Statistics, and Subscriptions. That's four screens using one chip type; SwiftUI can fully coalesce their animation timing.
- `AllExpensesView` swapped `HapticManager.shared.impact(style: .light/.medium)` for the semantic `lightTap()` / `mediumTap()` / `success()` calls — every tap, swipe-to-delete, and context-menu delete now reuses a prepared generator instead of allocating one.
- `AddExpenseView` now applies `.cardSurface()` + `.softShadow()` to all five field cards (amount, title, date, notes, plus the draft-restored banner) and the date row icon, replacing hand-rolled `background(.secondarySystemBackground)` + `cornerRadius(16)` + `shadow(0.1)`. The shadow density drops from 0.1 → 0.04 opacity, matching every other card in the app — forms now look lighter and more consistent with the dashboard.
- `AddExpenseView`'s save button route is now a single `handleSaveTap()` function (extracted from the button label closure), keeping the SwiftUI body graph for the form simpler and the save path easier to audit.
- `BudgetSetupView`, `BudgetListView`, and `PaywallView` all collapsed their one-off gradient buttons to `PrimaryGradientButton` — one button component, three screens. `BudgetListView` went from 236 → 180 lines; `BudgetSetupView` kept the same size but every spacing/radius is now tokenized. Any CTA-style tweak (shadow strength, tap bounce) now lives in `PrimaryGradientButton.swift` only.

### Phase F — Cleanup & code hygiene (April 2026)

Phase F focused on removing build warnings, unblocking Swift 6 concurrency, and sweeping the last straggler styles in misc. views. No functional changes; the goal was a clean build and a consistent token story across every screen.

**Swift 6 concurrency:**
- `ProManager` / `DonationManager`: made product IDs and helper state `nonisolated`, replaced `MainActor.run` captures with direct async main-actor method calls (`markPro()`, `recordPurchasedProductID(_:)`). Eliminates the "captured `self` in concurrently-executing code" warnings.
- `BudgetViewModel` / `SubscriptionViewModel`: the Core Data `viewContext` is now `nonisolated let`, and `saveContext()` was refactored into a `nonisolated persistIfNeeded()` helper that's safe to call from inside `performAndWait` closures. `@preconcurrency import CoreData` suppresses the `NSFetchRequest` Sendable warnings at the import level.
- `CategoryViewModel` / `BudgetViewModel` / `SubscriptionViewModel`: FRC delegate extensions declare `controllerDidChangeContent` as `nonisolated` so the conformance no longer crosses an actor boundary.
- `ExpenseViewModel+CoreData`: `saveContextAsync` now captures `viewContext` as a local `let` before entering the `perform` closure, avoiding the non-Sendable `self` capture warning.
- `StatisticsView` / `AllExpensesView`: mutable aggregates produced inside `Task.detached` are now frozen into immutable `let` snapshots before the `MainActor.run` hop — eliminates ten "reference to captured var" warnings.

**Deprecations:**
- All deprecated `.onChange(of:perform:)` call sites converted to the two-param / zero-param iOS 17 form (across `StatisticsView`, `AllExpensesView`, `QuickSearchView`, `SpendingHeatmap`).
- `Locale.currencyCode` → `Locale.current.currency?.identifier` in `ExpenseViewModel.autoSelectCurrencyIfNeeded()`.
- `SKStoreReviewController.requestReview(in:)` replaced with SwiftUI's `@Environment(\.requestReview)` action in `FeedbackRequestView`; removes the window scene lookup entirely and the `StoreKit` duplicate import.

**Misc. view sweep (AboutView, ImportDataView, ExportDataView, OnboardingView, CurrencyPickerView):**
- Replaced `.background(Color.secondarySystemBackground).cornerRadius(16)` with `.cardSurface()` in five screens.
- Deleted two copies of the private `hapticFeedback(style:)` helper (Import + Export). Each allocated a new `UIImpactFeedbackGenerator` per tap — now they reuse `HapticManager.shared.mediumTap()`.
- `AboutView`'s tap-to-open contact links now use `.cardSurface(radius: .chip, fill: .tertiarySystemBackground)`, giving them a proper secondary surface instead of blending into the parent card.

**Build signal:**
- Clean build is now **zero warnings** (down from ~60+ before Phase F, including ~15 Swift 6 concurrency errors-to-be and ~25 onChange deprecations). This means the codebase is ready for Swift 6 language mode without additional rework.

### Phase G — Enterprise-level performance pass (May 2026)

Phase G was scoped from a five-pronged audit (hot paths, view rebuild storms, persistence, asset I/O, foreground/tab path) that found the same dominant pattern: every CRUD operation forced an O(N) main-thread chain that scaled with expense count, so the app felt instant with empty data and progressively sluggish with real data. The fixes are layered in four ascending-risk bands so each layer can be rolled back independently.

**Phase 1 — Stop the @Published storm (low risk, very high impact):**
- `ExpenseViewModel.scheduleFilterRecompute` now computes the filter result *and* all five cached totals inside a single `Task.detached` pass and commits everything to the view model in **one synchronous main-thread block** (`applyFilterAndTotalsResult`). Previously each filter cycle fired 6–8 separate `@Published` writes spread across two async tasks, causing 2–3 SwiftUI body re-evaluations per save. Removed the dead `isFilteringInProgress` published flag (set but never read by any view) so it stopped contributing two extra invalidation passes per filter.
- `refreshData()` no longer calls the redundant synchronous `updateFilteredExpenses()` — that path duplicated the off-main pipeline's work on every foreground transition, causing two filter passes (one blocking, one not). Deleted `updateFilteredExpenses()` since it had no other callers. Subsequently switched `refreshData()` itself to `loadExpensesAsync()` so the fetch happens on a background context too.
- Receipt-file `delete` on the edit path moved to `Task.detached`, matching the existing bulk-delete pattern; the main thread never blocks on an `unlink` syscall again.
- `cleanupReceiptOrphansInBackground()` now captures the expense snapshot by value (COW makes this free) and does the `compactMap` + `Set` build *inside* the detached task, not on main.
- `NotificationScheduler` builds a `[UUID: String]` category-name map **once** per schedule call (in `makeCategoryNameLookup(viewModel:)`) and passes a closure that does O(1) dictionary reads to `DigestStatsCalculator` and `SmartInsightsEngine`. Previously `viewModel.categoryDisplayName(for:)` ran a **full Core Data fetch** inside the digest / insight loops — 1,500 expenses with even a handful of custom categories meant 1,500+ synchronous Core Data fetches on the MainActor every foreground.

**Phase 2 — Stop O(N) work on main-thread hot paths (low–medium risk, high impact):**
- Added Core Data fetch indexes (`fetchIndex` elements in `CashLens.xcdatamodel/contents`) on `ExpenseEntity.date` (the sort key behind every `loadExpenses` call), `id` (every single-row CRUD lookup), `category`, `customCategoryId`, `subscriptionId`, plus `SubscriptionEntity.nextDueDate` / `id` / `isActive`. Indexes are storage-only changes — Core Data picks them up via lightweight migration on first launch, no version bump needed.
- `HomeView.heroAveragePerActiveDay` no longer runs `filteredExpenses.map { $0.date }.min()` inside `body` for the `.all` timeframe. The earliest-expense date is cached in `@State cachedAllTimeStartDate`, populated by `recomputeNoSpendStreak()` in the same detached pass it already runs (it walks the snapshot anyway).
- `HomeView.recentExpensesList` uses a lazy `.lazy.filter { $0.isFromSubscription }.prefix(5)` chain when the user toggles "subscriptions only" — short-circuits after 5 matches instead of filtering the whole array.
- `HomeView.onAppear` only fires `recomputePreviousPeriodTotal()` / `recomputePinnedCategoryMetrics()` / `recomputeNoSpendStreak()` when their respective caches are `nil`. Tab returns from Statistics / Subscriptions no longer trigger triple O(N) detached passes when nothing has changed.
- `AddExpenseView.recentTitles()` dropped the pointless `.sorted` (Core Data already returns rows in date-desc order) and bails after collecting `limit` unique titles via `Set.insert(_:).inserted` — O(k × distinct-density) instead of O(N log N) on every keystroke that surfaces suggestions.
- `StatisticsView` now tracks tab visibility (`@State isStatsTabVisible` toggled in `onAppear` / `onDisappear`). The `onReceive(viewModel.$expenses)` skips the recompute entirely while the tab is hidden and just sets a `statsRecomputePending` flag; the next `onAppear` picks it up. Statistics no longer races detached recomputes on every save while the user is on Home / Subscriptions. First-visit recompute is gated by `didFirstStatsRecompute` so tab returns from Home don't redo work either.

**Phase 3 — Incremental in-memory updates (medium–high risk, biggest dataset-scale win):**
This is the structural change that removes the dominant "slow with data" feeling.

Previously, every CRUD method ended with `loadExpenses()`, which did a full SQLite fetch + remapped *every* `ExpenseEntity` to a Swift `Expense` value type on the main queue's context. Adding one expense to a 1,500-row dataset paid for 1,500 row materializations. The new pattern: after `saveContext()` succeeds, mutate the in-memory `expenses` array in place to mirror what just hit disk.

- Three new helpers in `ExpenseViewModel+CoreData.swift`:
  - `applyIncrementalInsert(_ expense:)` — sorted-insert into the array (single linear scan to find insert position, no Core Data round-trip).
  - `applyIncrementalUpdate(_ expense:)` — replace in place if the date is unchanged, remove + sorted-reinsert if the date moved. Falls back to a full `loadExpenses()` if the row isn't present (drift safety).
  - `applyIncrementalDelete(ids:)` — single `removeAll(where:)` pass, handles single and bulk delete uniformly.
- Wired through every CRUD path: `addExpense`, `updateExpense`, `deleteExpense(at:)`, `deleteExpenseById`, `deleteExpenses(ids:)`, `bulkChangeCategory`, `bulkAddTag`, plus the special-case `moveExpensesFromDeletedCategory` and `updateAllExpensesToCurrentCurrency` (which used to refetch the whole table after a global rewrite).
- `loadExpenses()` itself is still kept for the four cases that legitimately need it: cold-launch initial load, post-backup-restore (`reloadAfterBackupRestore`), `clearAllData` (which resets `expenses = []` directly), and the catch-branch fallback when a CRUD fetch throws (in case in-memory state has drifted from disk).
- Contract: helpers must be called **only after `saveContext()` succeeds**, so the in-memory array can never get ahead of Core Data. Because the app's `viewContext` is the sole writer of its own SQLite store (backup import goes through `reloadAfterBackupRestore`'s full reload; widgets and notification scheduler read-only), there's no race window where another context could mutate the data behind us.

**Phase 4 — Polish:**
- Added `.equatable()` to `ExpenseCard` in `ExpenseCalendarView` (it was missing it, while every other surface had it).
- Replaced `ProfileView`'s global `UserDefaults.didChangeNotification` listener with a targeted `.backupMetadataDidChange` notification (declared in `Notification+Extension.swift`, posted from `ExportDataView.recordBackup`). Previously every UserDefaults write app-wide — currency changes, theme bumps, draft autosaves, smart-insight history, digest scheduling timestamps — triggered a backup metadata re-read while Profile was mounted.
- Removed the dead `.animation(.spring(...), value: 1.0)` on `FloatingAddButton` (animation was keyed on a constant — never fired, but the SwiftUI dependency tracker still considered it on every diff).

**Net effect on the per-save hot path at ~1,500 expenses:**
- Before: one save → full Core Data fetch + 1,500 entity remaps on main → 6–8 `@Published` writes across two cascading tasks → 2–3 body re-evaluations across every observing surface → digest/insight loops calling `getCustomCategories()` per expense.
- After: one save → one in-memory mutation (single scan or O(1) replace) → one detached filter+totals pass → one synchronous burst of `@Published` writes → one body re-evaluation → digest/insight loops use a precomputed dictionary.

---

## 12. Monetization

### Tip Jar (Consumables)

**StoreKit 2 consumable products** — voluntary donations, no feature gating:

| Product ID | Name | Price |
|------------|------|-------|
| `com.cashlens.donation.coffee` | Coffee | $0.99 |
| `com.cashlens.donation.lunch` | Lunch | $4.99 |
| `com.cashlens.donation.fuel` | Fuel | $9.99 |

**Implementation:**
- `DonationManager` — singleton, loads products, handles purchase, listens for `Transaction.updates`
- `DonationView` — UI with gradient cards per product
- Entry point: "Support the App" section in `ProfileView`

### CashLens Pro (Subscriptions + Lifetime)

**StoreKit 2 auto-renewable subscriptions** + one non-consumable lifetime purchase:

| Product ID | Type | Price (USD) | Trial |
|------------|------|-------------|-------|
| `com.cashlens.pro.monthly` | Auto-Renewable | $2.99/mo | 7-day free |
| `com.cashlens.pro.yearly` | Auto-Renewable | $19.99/yr | 7-day free |
| `com.cashlens.pro.lifetime` | Non-Consumable | $39.99 | — |

All three belong to subscription group `"CashLens Pro"` (group ID `D4E8F2A1`). Apple handles international currency conversion via price tiers — `Product.displayPrice` shows the user's local currency automatically.

**Implementation:**
- `ProManager` (`Models/ProManager.swift`) — singleton `ObservableObject`. Exposes `@Published isPro: Bool`. Checks `Transaction.currentEntitlements` on launch, listens to `Transaction.updates`, handles purchase and restore via `AppStore.sync()`. Completely separate from `DonationManager`.
- `PaywallView` (`Views/PaywallView.swift`) — full-screen upgrade UI with feature list, monthly/yearly/lifetime plan cards, free trial badge, savings percentage, restore purchases, and Apple ToS text.
- **ProfileView** — shows "Upgrade to Pro" CTA card (or "Active" badge if already Pro) below the profile header. Tapping opens `PaywallView` as a sheet.
- **Feature gating** — use `ProManager.shared.isPro` anywhere in the app to check entitlement.

**UserDefaultsKeys added:** `hasSeenPaywall`, `paywallImpressionCount`.

---

## 13. Notifications

### Types

1. **Weekly Spending Digest** — Scheduled on configurable weekday/time. Body includes total spent, category breakdown, comparison to previous week.
2. **Monthly Spending Digest** — Scheduled on configurable day of month/time. Similar body with monthly stats.
3. **Backup Reminder** — Scheduled reminder to export data. Shows days since last backup.
4. **Subscription Due Reminders** — Per-subscription, X days before due date. Calendar-based trigger.

### Deep Links

Notification taps route through `DeepLinkRouter`:
- Weekly/monthly digest → Opens `AllExpensesView` with appropriate time filter
- Backup reminder → Opens `ExportDataView`

### Permission Flow

- Not requested on launch
- Requested contextually when user enables reminders or notification-dependent features
- Settings screen shows current permission status

---

## 14. Import / Export

The backup/restore pipeline lives in `CashLens/Backup/` and is intentionally split into four small, single-purpose files. The legacy `ExpenseViewModel+ImportExport.swift` is kept only as a thin compatibility shim that delegates to these modules.

```
CashLens/Backup/
├── BackupBundle.swift        # Codable schema (v2)
├── BackupExporter.swift      # Snapshot store + write JSON / CSV
├── BackupImporter.swift      # Detect format, parse, apply with mode
└── GenericCSVAdapter.swift   # Mint / YNAB / bank-statement CSV ingest
```

### 14.1 Canonical Backup Bundle (`BackupBundle`)

A single `BackupBundle` JSON file is sufficient to fully restore an install — every Core Data entity, every preference, every notification schedule.

```json
{
  "schema": {
    "version": "2.0",
    "minimumReaderVersion": "2.0",
    "exportedAt": "2026-04-25T11:30:00Z",
    "appVersion": "1.4 (231)",
    "device": "iPhone16,2"
  },
  "data": {
    "expenses":             [ ... Expense ],
    "subscriptions":        [ ... Subscription ],
    "customCategories":     [ ... CustomCategory ],
    "budgets":              [ ... CodableBudget ],
    "deletedDefaultCategories": [ "Health", ... ]
  },
  "preferences": {
    "userName": "...",
    "selectedCurrency": "USD",
    "defaultHomeTimeFrame": "Month",
    "appearanceMode": "system",
    "preferredSummaryCategories": [ "Food", "custom:UUID", ... ],
    "notifications": {
      "weeklySummary":  { "enabled": true, "weekday": 2, "hour": 9, "minute": 0 },
      "monthlyDigest":  { "enabled": true, "dayOfMonth": 1, "hour": 9, "minute": 0 },
      "backupReminder": { "enabled": true, "dayOfMonth": 1, "hour": 9, "minute": 0 }
    }
  }
}
```

**Versioning rules** (`BackupBundle.Schema`):

| Change | Bump |
|---|---|
| Add a new optional field | `version` minor (e.g. `2.0` → `2.1`). Old readers still parse. |
| Rename / remove a field, change semantics | `version` major + raise `minimumReaderVersion`. Old readers refuse the file gracefully with `ImportError.fileTooNew`. |

`CodableBudget` flattens `Budget.CategoryFilter` into three simple optional fields (`type`, `defaultRaw`, `customId`) so the JSON is readable and forward-compatible. Backup metadata such as `lastBackupDate` / `totalBackupCount` is **deliberately not** in the bundle — restoring it would be misleading.

### 14.2 Export Formats (`BackupExporter`)

Two formats are exposed in `ExportDataView`:

| Format | Extension | Contents | Use for |
|---|---|---|---|
| **Complete Backup** | `.cashlens.json` | Entire `BackupBundle` (all entities + preferences) | Full restore on a new device |
| **Spreadsheet** | `.csv` | Flat, RFC 4180 CSV of expenses only | Analysis in Numbers / Excel / Sheets |

Implementation details:

- `BackupExporter.buildBundle()` runs on a background context (`performAndWait`), snapshots all entities + reads relevant `UserDefaultsKeys`, and returns a fully-typed `BackupBundle`.
- JSON is written with `JSONEncoder` + `.prettyPrinted` + `.sortedKeys`, ISO 8601 dates.
- CSV is written via `BackupExporter.writeCSV(_:)` — RFC 4180-compliant: every field passes through `csvEscape` (quotes, commas, newlines, leading `=` / `+` / `-` / `@` for spreadsheet-formula safety). Dates are ISO 8601 (locale-independent). The header includes an `Is Refund` column (`true` / `false`) so refund flags round-trip through CSV exports; older importers that don't know the column simply ignore it.
- Files are written into `FileManager.default.temporaryDirectory` with timestamped names like `CashLens_2026-04-25_113000.cashlens.json`.

### 14.3 Import Pipeline (`BackupImporter`)

`ImportDataView` drives a three-step UX: **pick → preview → apply**.

#### Step 1 — Pick

`fileImporter` accepts `.json`, `.commaSeparatedText`, and a custom `UTType` for `.cashlens.json`. The selected URL is forwarded to `BackupImporter.preview(url:fallbackCurrency:)` on a `Task.detached` so the UI never stalls.

#### Step 2 — Detect & Parse

`BackupImporter.detectFormat(data:fileName:)` inspects the file and returns one of:

| `DetectedFormat` | Heuristic | Pro-gated |
|---|---|---|
| `.cashlensJSONv2` | JSON with `schema.version >= 2.0` | No |
| `.cashlensJSONv1` | JSON with `exportVersion: "1.0"` (legacy) | No |
| `.cashlensCSVv1` | Text starting with `=== EXPENSES ===` | No |
| `.foreignCSV(vendor:)` | Any other CSV that `GenericCSVAdapter` can map | **Yes** |
| `.unknown` | Otherwise → `ImportError.unrecognizedFormat` | — |

For CashLens v1 files, `LegacyV1Reader` converts the old shape into a `BackupBundle` so the rest of the pipeline is uniform.

For foreign CSVs, `GenericCSVAdapter.parse(_:fallbackCurrency:)` does column auto-detection:

- Tries to match common header aliases (`date`, `posting date`, `transaction date`, `amount`, `debit`, `credit`, `description`, `payee`, `merchant`, `category`, `notes`, `memo`).
- Reports the detected vendor (Mint, YNAB, Apple Card, generic) for display.
- Parses dates against a list of known formats (US, EU, ISO, slashed, hyphenated, with/without time).
- Parses amounts robustly: strips currency symbols, locale separators, parentheses-as-negative `(12.34)`, leading `-`.
- Splits debit/credit columns into signed amounts and turns them into expenses.
- Returns `RowError`s for unparseable rows so the user sees exactly what was skipped.

The result is wrapped in a `BackupImporter.Preview` containing the `BackupBundle`, the `DetectedFormat`, the column→role mapping (for foreign CSVs), and any `RowError`s.

#### Step 3 — Preview UI (`ImportPreviewSheet`)

Before any change is committed, the user sees:

- Detected format badge (e.g. *Mint CSV* / *CashLens Backup (v2)*).
- Per-entity counts (expenses, subscriptions, custom categories, budgets, deleted-defaults, preferences updated).
- For foreign CSVs: which spreadsheet column was mapped to which role, plus a collapsible "Issues" section listing skipped rows with the reason.
- A **Merge** vs **Replace** toggle:

| Mode | Effect |
|---|---|
| `.merge` (default) | Add new records, skip duplicates by ID then by content (title + amount + date + category). Preferences with values in the file overwrite current ones; missing prefs are left alone. |
| `.replace` | Wipes the existing store + matching preference set, then imports. **Requires explicit confirmation alert.** |

#### Step 4 — Apply

`BackupImporter.apply(_:mode:context:completion:)` runs entirely on a private NSManagedObjectContext (`.privateQueueConcurrencyType`) with `mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy`. Order is fixed:

1. (`.replace` only) Wipe `ExpenseEntity` / `SubscriptionEntity` / `CustomCategoryEntity` / `BudgetEntity`.
2. Custom categories first (so expenses can reference them).
3. Expenses with dual dedup (by ID, then by content hash). Invalid rows fail `isValidExpense` and are skipped.
4. Subscriptions, budgets, deleted-default categories.
5. Preferences (each key only written if present in the bundle, so a partial backup never wipes settings).
6. `context.save()` → main-thread reload via `ExpenseViewModel.reloadAfterBackupRestore()` and a `Notification.Name.backupImportDidComplete` post.

Result is an `ImportSummary` with imported / skipped / failed counts per entity plus the list of preference keys touched. The post-import `ImportSummarySheet` renders this as a friendly receipt.

### 14.4 Pro Gating

| Capability | Free | Pro |
|---|---|---|
| Export Complete Backup (`.cashlens.json`) | ✅ | ✅ |
| Export Spreadsheet (`.csv`) | ✅ | ✅ |
| Import CashLens backup (any version) | ✅ | ✅ |
| **Import foreign CSV** (Mint, YNAB, bank statement) | 🔒 → `PaywallView` | ✅ |

Gating is enforced in `ImportDataView.startParse(url:)`: if `preview.format.requiresPro && !proManager.isPro`, the paywall is presented instead of the preview sheet.

### 14.5 Backup Health

`ProfileView` shows a live backup health card backed by `UserDefaults` keys (`lastBackupDate`, `lastBackupFormat`, `totalBackupCount`). It listens to `UserDefaults.didChangeNotification` so the card updates **instantly** after a successful export without needing the user to navigate away and back.

### 14.6 Backward Compatibility Guarantee

**Every backup file ever produced by CashLens is still readable.** `BackupImporter.detectFormat` recognises three legacy shapes in addition to the current v2:

| Legacy format | How it's detected | Reader |
|---|---|---|
| **v1 JSON** with `exportVersion: "1.0"` | `json["exportVersion"] is String` | `LegacyV1Reader.parseJSON` |
| **v1 JSON** without `exportVersion` (partial / hand-edited) | `json["expenses"] != nil \|\| json["subscriptions"] != nil` | `LegacyV1Reader.parseJSON` |
| **v1 sectioned CSV** (`=== EXPENSES ===` blocks) | Text contains any `=== … ===` section header | `LegacyV1Reader.parseCSV` |

The legacy reader uses the original `Expense(from:)`, `Subscription(from:)`, `CustomCategory(from:)`, `Expense(fromCSV:)`, `Subscription(fromCSV:)`, `CustomCategory(fromCSV:)` initialisers, all of which remain in `Models/`. Each `try?` per-row so a single corrupt entry never aborts the whole file. Newer fields absent from the file (e.g. `tags` was added in v1.4) fall back to `nil`/defaults rather than throwing.

If you ever need to remove or rename any of those `init` paths, also bump `BackupBundle.currentSchemaVersion` and add a clear migration test — losing the ability to read an older file would be a regression.

The `ImportDataView` surface has a small "Older backups still work" reassurance pill so users on long-running installs know to trust their existing files.

### 14.7 Adding a new backed-up field

When you add a new piece of state that must survive a reinstall:

1. Add the property to the matching model (`Expense`, `Subscription`, etc.) and its `Codable` keys.
2. Mirror it in the relevant `Entity+Extensions` mapping.
3. If it lives in `UserDefaults`, add the key to `UserDefaultsKeys` **and** to `BackupBundle.Preferences` (or `NotificationPreferences`).
4. Read it in `BackupExporter.buildPreferences()` and apply it in `BackupImporter.applyPreferences(_:mode:)`.
5. If the change is purely additive, that's it — `version` stays at `2.0`. If you renamed or removed a field, bump `BackupBundle.currentSchemaVersion` and `minimumReaderVersion`.

---

## 15. Navigation Flow

```
App Launch
  └─ SplashScreenView (z-index 2, auto-dismiss ~2s)
  └─ OnboardingView (z-index 1, first launch only)
      └─ CurrencyPickerView (sheet, after onboarding)
  └─ MainTabView
      ├─ Tab 1: HomeView
      │   ├─ → ProfileView (sheet)
      │   │   ├─ → CurrencyPickerView (sheet)
      │   │   ├─ → AboutView (sheet)
      │   │   ├─ → ExportDataView (sheet)
      │   │   ├─ → ImportDataView (sheet)
      │   │   └─ → DonationView (sheet)
      │   ├─ → AllExpensesView (sheet)
      │   │   ├─ → AddExpenseView (sheet, edit mode)
      │   │   ├─ → QuickSearchView (sheet, from toolbar magnifying glass)
      │   │   │   └─ → AddExpenseView (sheet, edit mode)
      │   │   └─ → ExpenseCalendarView (sheet, from toolbar calendar icon)
      │   │       └─ → AddExpenseView (sheet, edit mode)
      │   ├─ → AddExpenseView (sheet, add mode)
      │   │   └─ → ManageCategoriesView (sheet)
      │   ├─ → SummaryCustomizationView (sheet)
      │   ├─ → ManageCategoriesView (sheet)
      │   │   └─ → CustomCategoryForm (sheet)
      │   └─ → QuickSearchView (sheet, from header magnifying glass)
      │       └─ → AddExpenseView (sheet, edit mode)
      │
      ├─ Tab 2: SubscriptionsView
      │   └─ → AddSubscriptionView (sheet, add/edit)
      │       └─ → ManageCategoriesView (sheet)
      │
      └─ Tab 3: StatisticsView
          └─ → AddExpenseView (sheet, from empty state)

Deep Links (from notifications):
  └─ AllExpensesView with filter (sheet from root)
  └─ ExportDataView (sheet from root)
```

---

## 16. Key Patterns & Conventions

### Code Organization
- **ViewModel extensions** split by concern (`+CRUD`, `+CoreData`, `+Currency`, etc.) to keep files focused
- **Bridge pattern** between Core Data entities and value-type structs
- **Combine** for reactive filtering with debouncing
- **NSFetchedResultsController** in `SubscriptionViewModel` and `CategoryViewModel` for auto-sync

### Performance
- `Equatable` views (`ExpenseCard`, `CategoryItem`) to minimize redraws
- Cached totals/counts for O(1) access from views
- Background thread filtering and aggregation
- `drawingGroup()` on chart/icon components
- Paginated `AllExpensesView` (250 per chunk)
- Batch fetch size of 100 for expenses

### Safety
- `amount.isFinite` guards throughout to prevent NaN/Infinity corruption
- Validation on import with reasonable date range checks
- Duplicate detection on import (by ID and content)
- Draft auto-save for unfinished expense forms
- `scenePhase` monitoring for data refresh

### Naming Conventions
- Views: `*View.swift` (e.g., `HomeView.swift`)
- ViewModels: `*ViewModel.swift` or `*ViewModel+*.swift` for extensions
- Models: Named after domain concept (`Expense.swift`, `Subscription.swift`)
- Components: Named after what they render (`SummaryCard.swift`, `ExpenseCard.swift`)
- Utilities: Named after their function (`HapticManager.swift`, `ExpenseFilter.swift`)

### Notification Names
- `.appearanceDidChange` — Posted when appearance mode changes
- `.dataDidClear` — Posted after `clearAllData()`
- `.subscriptionCurrencyUpdated` — Posted after bulk currency sync on subscriptions

---

## 17. Dependencies

**Zero external dependencies.** The app uses only Apple frameworks:

| Framework | Usage |
|-----------|-------|
| SwiftUI | All UI |
| CoreData | Persistence |
| Combine | Reactive filtering/state |
| StoreKit | Tip jar IAP |
| UserNotifications | Push notifications |
| UIKit | Haptics, share sheet, app delegate |

No SPM packages, no CocoaPods, no Carthage.

---

## 18. Build & Run

1. Open `CashLens.xcodeproj` in Xcode 16+
2. Select a simulator or device running iOS 18.0+
3. Build and run (⌘R)
4. On first launch: splash → onboarding → currency picker → home

**Team ID:** `6C72999Z38`  
**Supported devices:** iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`)

### Debug Tools
- `DiagnosticsView` available in `#if DEBUG` builds from ProfileView
- Data health checks, currency consistency, feedback state reset

---

## 19. Widgets (Pro)

CashLens ships **six widgets** across two surfaces — Home Screen and Lock Screen — built on a single shared data contract that keeps the widget extension narrow, fast, and crash-proof.

### 19.1 Architecture

The widget extension cannot reach the main app's Core Data store directly, so the main app **projects** a versioned `WidgetSnapshot` JSON file into an App Group container and the widgets read it. This keeps widget rendering at zero work past file I/O — every value is pre-aggregated.

```
┌────────────────────┐     debounce 300ms     ┌──────────────────────────┐
│  Main app          │ ─────────────────────► │ WidgetSnapshotCoordinator│
│  (mutations from   │                        │ (@MainActor singleton)   │
│  ExpenseVM, Budget │                        │                          │
│  VM, Theme, etc.)  │                        │ Combine + NSManagedObj   │
└────────────────────┘                        │ ContextDidSave subs.     │
                                              └────────────┬─────────────┘
                                                           ▼
                                              ┌──────────────────────────┐
                                              │ WidgetSnapshotBuilder    │
                                              │ (pure value-type, runs   │
                                              │ on Task.detached(.utility│
                                              └────────────┬─────────────┘
                                                           ▼
            ┌────────────────────────────────────┐    write atomically
            │ App Group container                │ ◄────────────────────
            │ group.com.rushi.CashLens.shared    │
            │ └── WidgetSnapshot-v1.json         │
            └──────────────┬─────────────────────┘
                           ▼ mmap'd read
            ┌────────────────────────────────────┐
            │ CashLensWidgetsExtension           │
            │ (TimelineProvider → SwiftUI views) │
            └────────────────────────────────────┘
                           ▲
                           │ WidgetCenter.reloadAllTimelines() fires after every successful write
```

### 19.2 Shared layer (`Shared/` — synchronized folder, member of both targets)

| File | Description |
|------|-------------|
| `Shared/SharedAppGroup.swift` | App Group identifier `group.com.rushi.CashLens.shared` + `snapshotFileURL` helper. Single source of truth — must match both `.entitlements` files. |
| `Shared/WidgetSnapshot.swift` | `Codable, Hashable, Sendable` data contract. Versioned via `schemaVersion: Int` (currently 1). Carries `generatedAt`, `currencyCode`, `isPro`, `activeThemeId`, `userName`, plus pre-aggregated `spending.byTimeframe`, `budgets[]`, `upcomingSubscriptions[]`, `streak`. All collections capped (≤ 6 categories per timeframe, ≤ 8 budgets, ≤ 6 upcoming subs) so the snapshot file stays ≤ 5 KB even for power users. Includes `.placeholder` static for fallback. |
| `Shared/WidgetSnapshotIO.swift` | Atomic read/write helpers. Encoder uses ISO-8601 dates + sorted keys (stable diffs). Read returns `WidgetSnapshot.placeholder` on every failure mode (no file, bad JSON, no App Group container, future schema). Write uses `.atomic` flag so a partially-written file is never observable by the widget process. |

### 19.3 Main-app coordinator

| File | Description |
|------|-------------|
| `CashLens/Utilities/WidgetSnapshotBuilder.swift` | Pure value-type builder that turns a `Builder.Inputs` snapshot of live state into a `WidgetSnapshot`. Refund-aware (uses `Expense.signedAmount`). Includes a private `CategoryHex` palette mirroring `ColorExtension.LightColors` so widget categories render in the same brand colors as the in-app UI. Hard caps applied to top-categories and upcoming-subs lists. |
| `CashLens/Utilities/WidgetSnapshotCoordinator.swift` | `@MainActor ObservableObject` singleton. `bootstrap(...)` installs Combine subscriptions to `expenseVM.$expenses/$selectedCurrency/$userName`, `budgetVM.$budgets/$budgetProgress`, `categoryVM.$customCategories`, `proManager.$isPro`, `themeStore.$currentTheme`, plus an `NSManagedObjectContextDidSave` observer scoped to `SubscriptionEntity` (so subscription mutations propagate even when `SubscriptionsView` has never been mounted — its VM is tab-scoped). All emits coalesce through a 300 ms debounce; refresh runs on `Task.detached(priority: .utility)`; `WidgetCenter.shared.reloadAllTimelines()` fires on completion. `refreshNow()` is the explicit entry point used by the scene-foreground hook. |

Wired into `CashLensApp.swift`: `bootstrap` is called once on `.onAppear` (after every app-level dependency is alive), `refreshNow()` is called whenever `scenePhase == .active` so foreground-after-background → instant widget refresh.

### 19.4 Widget extension (`CashLensWidgets/`)

Synchronized folder, member of `CashLensWidgetsExtension` target. Bundle entry point: `CashLensWidgetsBundle.swift` (`@main WidgetBundle`).

| File | Widget kind | Sizes | Tier | Configurable |
|------|-------------|-------|------|---------------|
| `SpendingWidget.swift` | `SpendingSnapshot` | Small / Medium / Large | **Free** | ✅ App Intent (timeframe: today/week/month/year) |
| `BudgetWidget.swift` | `BudgetProgress` | Small / Medium | Pro | — (Small auto-picks most-relevant budget) |
| `SubscriptionsWidget.swift` | `SubscriptionsDue` | Medium | Pro | — |
| `StreakWidget.swift` | `NoSpendStreak` | Small / Medium | Pro | — |
| `LockScreenWidgets.swift` | `SpendingLockScreen` | Circular / Rectangular / Inline | Free | — |
| `LockScreenWidgets.swift` | `StreakLockScreen` | Circular / Rectangular / Inline | Pro | — |

Supporting infrastructure:

| File | Description |
|------|-------------|
| `CashLensWidgets/WidgetTheme.swift` | Pure theme resolver mirroring `AppTheme` (catalog of mauve/ocean/forest/sunset/berry/graphite). `resolve(id:)` lookup + per-color-scheme `primary(for:)` / `secondary(for:)` `Color` accessors. Includes a tolerant `Color(hex:)` initializer. **Keep in sync with `CashLens/Models/AppTheme.swift`** — both files cross-reference each other in comments. |
| `CashLensWidgets/WidgetMoneyFormatter.swift` | Compact (`$1.2K`), full (`$1,234.56`), and percent-delta (`+12%`) formatters. Currency-aware via `NumberFormatter` with cached symbol lookup. |
| `CashLensWidgets/WidgetProUpsellView.swift` | Shared "Unlock with CashLens Pro" tile shown on Pro-gated home widgets when `snapshot.isPro == false`. Quiet design — lock medallion + widget name + one-line CTA. |
| `CashLensWidgets/SpendingWidget.swift` (also defines) | `SpendingBackground` — the subtle theme-tinted gradient used as `containerBackground` for every home widget. Light/dark adaptive via `\.colorScheme`. |

### 19.5 Pro gating

The snapshot includes `isPro: Bool` (sampled at write time, in the main app, against `ProManager.shared.isPro`).

- **Spending Snapshot** — intentionally free for everyone. It's the hero surface that drives Pro upgrades by demonstrating the visual quality bar.
- **Home Screen Pro widgets** (Budget / Subscriptions / Streak) — `XEntryView` checks `entry.snapshot.isPro` first. If false → `WidgetProUpsellView`. If true → render real data.
- **Lock Screen Streak widget** — too cramped for a full upsell tile, so a tiny `lock.fill` glyph + "Pro" label is shown instead. Tap drops into the app for the upgrade flow.

### 19.6 Theming

Widgets resolve `snapshot.activeThemeId` against `WidgetTheme.resolve(id:)` on every render. Each render resolves `primary(for: scheme)` / `secondary(for: scheme)` to a fresh `Color` from a hand-tuned light/dark hex pair, so:

- A theme change in the app instantly cascades to widgets (the coordinator's `themeStore.$currentTheme` subscription writes a new snapshot, `WidgetCenter` reloads).
- Light/dark mode adaptation is automatic via `\.colorScheme`.
- Categories use their own hex (from `CategoryHex` in the builder) so brand colors stay consistent regardless of accent theme.

### 19.7 Performance

- **Render path is zero-work** — every value the widget shows is pre-aggregated in the snapshot.
- **Snapshot is mmap'd** via `Data(contentsOf:options: .mappedIfSafe)`.
- **Builder runs off-main** on `Task.detached(priority: .utility)`.
- **Mutation bursts coalesce** — 300 ms debounce + `Task.cancel()` chain means a 50-mutation backup-restore writes one snapshot, not 50.
- **Subscription fetch is on-demand** — done inside `performRefresh()` from the main `viewContext`, so it never has to be kept in memory between refreshes.

### 19.8 Failure modes (all silent + user-invisible)

| Failure | Behavior |
|---------|----------|
| App Group container unreachable | Coordinator logs nothing, write returns `false`. Widget reads `placeholder` next render. |
| Snapshot file missing | Widget reads `placeholder`. |
| Snapshot file corrupted | Widget reads `placeholder`. |
| Schema version mismatch (newer snapshot, older widget) | Widget reads `placeholder` rather than crash. |
| Builder receives empty inputs | Snapshot encodes empty arrays + zero totals — widgets show their respective empty states ("No expenses yet", "No budgets yet", "Nothing due in the next 2 weeks", "Start a streak today"). |
| Pro state lapses mid-session | Snapshot's next refresh writes `isPro: false`, Pro-gated widgets switch to upsell variant on next reload. |

### 19.9 Adding a new widget

1. Drop the `.swift` file into `CashLensWidgets/` — the synchronized folder auto-includes it in the widget target.
2. Add it to `CashLensWidgetsBundle.body`.
3. If it needs new data, add fields to `Shared/WidgetSnapshot.swift` (additive only — existing widgets must still decode v1 snapshots unchanged) and have the builder populate them.
4. If it's Pro-gated, gate inside its EntryView's body (`if !entry.snapshot.isPro { WidgetProUpsellView(...) }`).
5. **Keep the widget's `kind` string stable for the lifetime of the binary** — changing it orphans every widget the user has already placed.

### 19.10 Schema migration

If a backwards-incompatible change is needed (a renamed field, a removed enum case), bump `WidgetSnapshot.schemaVersion` and update `WidgetSnapshotIO.read()`'s tolerant version check. Because reads fall back to `placeholder` on schema mismatch, the user sees a momentary "no data" widget rather than a crash, and the next snapshot write (≤ 1 sec after launching the new app build) restores live data.
