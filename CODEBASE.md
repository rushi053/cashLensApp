# CashLens — Codebase Documentation

> **App Store:** 2.1, released 2026-08-29 (App Store id `6743153951`; first App Store release 2025-03-24)  
> **Repo (`release/2.2`):** `MARKETING_VERSION = 2.2`, `CURRENT_PROJECT_VERSION = 8` in `CashLens.xcodeproj/project.pbxproj`. Store 2.1 was built from `redesign/v2` at `4029ae0` (repo said 2.0.1 / build 7; the store version string was set in App Store Connect).  
> **Unshipped relative to store 2.1:** everything on `release/2.2` — the `PurchaseIntent` listener for promoted In-App Purchases (`4f702fa`), `Marketing/PromoImages/`, and the 2.2 Phase 0 / A / B / C commits (version bump, `AppConstants.supportEmail`, `ReviewPromptManager`, paywall truth-pass, `sidebarAdaptable` tabs, size classes, `NavigationStack`, `EvenColumnGrid`, width-derived chart heights, readable column, Activity split view, compact-height onboarding/paywall, keyboard shortcuts, hover, Duo 27.1 stubs behind `CASHLENS_DUO_27_1`).  
> **Platform:** iOS 18.0+ (`IPHONEOS_DEPLOYMENT_TARGET = 18.0`), iPhone & iPad (`TARGETED_DEVICE_FAMILY = 1,2`)  
> **Language:** Swift 5.0 language mode (`SWIFT_VERSION = 5.0`) / SwiftUI; `LastSwiftUpdateCheck = 2600`  
> **Bundle ID:** `com.rushi.CashLens` · Team `6C72999Z38` · App Group `group.com.rushi.CashLens.shared`  
> **Created by:** Rushiraj Jadeja — first commit 2025-03-10  
> **Branches:** `main` is stale at 1.0.5 (2026-01-21, 70 Swift files, 3 tabs). `redesign/v2` (161 Swift files, 4 tabs) is what store 2.1 shipped from. `release/2.2` is cut from it and is where 2.2 is being built (166 Swift files, 41 commits ahead at `3af5bf4`, 2026-09-19, incl. nine launch-readiness review fixes and eight perf quick wins + a debug seeder). This document describes `release/2.2`; where a fact changed between `redesign/v2` and `release/2.2` it says so.  
> **Last updated:** 2026-09-19 (docs refresh for 2.2)

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
19. [Widgets](#19-widgets)
20. [Siri / App Intents & Quick Log](#20-siri--app-intents--quick-log)
21. [App Lock](#21-app-lock)
22. [Release History](#22-release-history)
23. [Performance](#23-performance)

---

## 1. App Overview

CashLens is a **local-first, privacy-focused personal expense tracker** for iOS. All data is stored on-device using Core Data — no accounts, no cloud sync, no server, no analytics SDK. The app is free with a **CashLens Pro** tier (StoreKit 2 subscriptions + lifetime unlock) and a separate tip jar.

### Core Features

| Feature | Tier | Description |
|---------|------|-------------|
| **Expense Tracking** | Free | Add, edit, delete expenses with amount, title, category, date, notes, tags, payment method, refund flag; templates; draft recovery; smart category suggestion |
| **Today tab** | Free | Budget verdict hero, 7-day strip, upcoming bills, recent expenses, one insight; sections reorderable/hideable (`TodayCustomizeView`) |
| **Activity tab** | Free | Full ledger (`AllExpensesView`) with search (`QuickSearchView`), calendar view, filters, bulk select; tag *filtering* and bulk-tag are Pro |
| **Insights tab** | Free + Pro | Donut, trend pager, heatmap, highlights free; Pro Insights (pace/velocity/YoY), Forecast (30/60/90d), Payment Methods donut, PDF report are Pro |
| **Recurring Bills** | Free | Subscriptions with frequency, due dates, reminders, pause/resume, manual "Mark paid" (`SubscriptionsView`, reached from You → Subscriptions) |
| **Budgets & alerts** | Pro | Weekly / monthly / custom-range budgets with 80% / 100% crossing alerts |
| **Receipts** | Pro capture, free viewing | VisionKit scan or Photos pick, on-device Vision OCR auto-fill of amount + merchant, `.cashlens-archive` backup |
| **Custom Categories** | Free | User-defined categories with SF Symbol icons and named colors |
| **Import/Export** | Free + Pro | `.cashlens.json` full backup, `.csv` spreadsheet, `.cashlens-archive` (JSON + receipt photos); **Pro:** import Mint / YNAB / bank CSV with auto column detection |
| **Notifications** | Free + Pro | Weekly/monthly digests, backup reminder, subscription due alerts, budget alerts (Pro), weekly Smart Insight (Pro) |
| **Widgets** | Free + Pro | 7 widgets across Home and Lock Screen; Spending Snapshot, Quick Log (1 template) and the Spending lock widget are free (§19) |
| **Siri / Shortcuts** | Free | `Log Expense` and `Check Spending` App Intents with zero-setup phrases (§20) |
| **App Lock** | Free | Face ID / Touch ID / passcode lock with grace period (§21) |
| **Monthly Recap** | Free | Month-in-review sheet with shareable card, surfaced on Today early in a new month and permanently in Insights |
| **Personalization** | Pro | 12 accent themes (6 Classics + 6 Pastels) and 8 app icons via `AppearanceStudioView` / `AppIconPickerView`; light/dark/system mode is free |
| **Privacy Dashboard** | Free | You → Privacy: what is stored, how much space, "three zeros" (servers, trackers, accounts) |
| **Multi-Currency** | Free | 170+ currencies with locale-based auto-detection — **single global currency**; per-expense currency with live rates is *not built* (see `PRO_FEATURES.md` Phase 8) |
| **Dark Mode** | Free | System/Light/Dark appearance toggle |
| **Rating prompt** | — | Native `requestReview` sheet driven by `ReviewPromptManager` (2.2): once per marketing version, at the save that reaches 10 expenses or a 7-day no-spend streak, never during onboarding / over a paywall / within 2 s of a sheet dismiss. Replaced the 2.0.1 `FeedbackManager`. |

---

## 2. Architecture

The app uses a **MVVM (Model-View-ViewModel)** architecture with Core Data as the persistence layer, plus two out-of-process surfaces (widget extension, App Intents) that talk to the store through narrow contracts.

```
┌────────────────────────────────────────────────────────────────┐
│                       SwiftUI Views                             │
│  MainTabView → Today / Activity / Insights / You                │
│  (TodayView, AllExpensesView, StatisticsView, ProfileView)      │
│  Root overlays: AppLockView, StoreRecoveryView, OnboardingView  │
└──────────────────────┬─────────────────────────────────────────┘
                       │ @EnvironmentObject / @StateObject
┌──────────────────────▼─────────────────────────────────────────┐
│                      ViewModels                                 │
│  ExpenseViewModel (+ extensions)   SubscriptionViewModel        │
│  CategoryViewModel                 BudgetViewModel (Pro)        │
└──────────────────────┬─────────────────────────────────────────┘
                       │ Core Data fetch/save (viewContext is the sole UI writer)
┌──────────────────────▼─────────────────────────────────────────┐
│                 Core Data (CashLens 2.xcdatamodel)              │
│  ExpenseEntity, SubscriptionEntity, CustomCategoryEntity,       │
│  BudgetEntity   ↕ bridge via *Entity+Extensions.swift           │
│  Expense, Subscription, CustomCategory, Budget (structs)        │
└──────────────────────┬─────────────────────────────────────────┘
                       │
   ┌───────────────────┼────────────────────────────┐
   ▼                   ▼                            ▼
 WidgetSnapshot      QuickLogService              ReceiptStorage
 (App Group JSON,    (headless writes on a        (Documents/Receipts/,
  read by widgets)    background context: Siri     filename-only refs)
                      intents + widget queue drain)

Singletons (@MainActor ObservableObject unless noted):
  ProManager (StoreKit 2 Pro), DonationManager (tip jar), ThemeStore,
  AppIconStore, AppLockManager, DeepLinkRouter, ReviewPromptManager (not
  main-actor isolated), ExpenseTemplateStore, WidgetSnapshotCoordinator
Preferences: UserDefaults via UserDefaultsKeys (caseless enum)
```

### Data Flow

1. **Core Data entities** are the durable store; the app's `viewContext` is the only UI-driven writer
2. **Bridge extensions** (`*Entity+Extensions.swift`) convert entities ↔ value-type structs
3. **ViewModels** hold `@Published` arrays of structs; views bind to these. CRUD paths mutate the in-memory array in place after a successful save (`applyIncremental*`, see Phase G in §11) instead of refetching
4. **Combine pipelines** debounce filter/sort changes for smooth UI
5. **UserDefaults** stores lightweight preferences (currency, appearance, onboarding flags, notification schedules, Today layout, App Lock, Pro/donor state)
6. **Headless writers** (`QuickLogService`) use a fresh background context and post `.expensesChangedExternally`; a live `ExpenseViewModel` reconciles via `loadExpensesAsync()`
7. **Widgets** never touch Core Data: `WidgetSnapshotCoordinator` projects a versioned `WidgetSnapshot` JSON into the App Group; the interactive Quick Log widget appends `PendingExpenseRecord`s to a per-file queue the app drains on foreground
8. **Failure surfaces**: `SaveErrorReporter` → `SaveErrorBanner` for any failed `context.save()`; `PersistenceController.storeLoadFailed` → `StoreRecoveryView` (never deletes the store, offers raw `.sqlite` export)

---

## 3. Project Structure

Repository root (166 Swift files on `release/2.2`; 161 on `redesign/v2`, plus the Xcode project, marketing assets, and a legacy `website/` folder). The tracked `CashLens.xcodeproj/xcuserdata/…/xcschememanagement.plist` that `redesign/v2` carried despite `.gitignore` was removed on `release/2.2` (`be7a28b`).

```
cashLensApp/
├── CashLens.xcodeproj/             # Targets: CashLens, CashLensWidgetsExtension, CashLensTests, CashLensUITests
├── CashLens/                       # Main app target (see tree below)
├── CashLensWidgets/                # Widget extension target (§19)
├── Shared/                         # Synchronized folder, member of BOTH app + widget targets
│   ├── SharedAppGroup.swift        # App Group id + snapshot / queue URLs
│   ├── WidgetSnapshot.swift        # Versioned widget data contract (schemaVersion 1; + optional dailyNetLast7Days in 2.2)
│   ├── WidgetSnapshotIO.swift      # Atomic read/write, placeholder fallback
│   └── PendingExpenseQueue.swift   # Per-file cross-process queue for Quick Log widget expenses
├── CashLensTests/CashLensTests.swift          # Swift Testing stub (`@Test func example`) — no real unit tests
├── CashLensUITests/                # Template launch tests + RuntimeSmokeUITest.swift (manual walkthrough, header says throwaway)
├── RuntimeSmoke.xctestplan         # Test plan for RuntimeSmokeUITest; points StoreKit config at CashLens/Donations.storekit
├── CashLens-Info.plist             # Merged with GENERATE_INFOPLIST_FILE: SKIncludeConsumableInAppPurchaseHistory,
│                                   #   ITSAppUsesNonExemptEncryption=false, NSFaceIDUsageDescription, cashlens:// URL scheme
├── CashLensWidgetsExtension.entitlements      # App Group
├── Donations.storekit              # Root copy of the StoreKit config (project also has CashLens/Donations.storekit)
├── Marketing/
│   ├── PromoImages/                # cashlens-pro-{yearly,lifetime}-promo.png for App Store promoted IAPs (unshipped in ASC)
│   └── ScreenshotSampleData/       # Demo .cashlens.json / .csv + generate_screenshot_data.py for App Store screenshots
├── Scripts/
│   ├── generate_app_icons.swift    # CoreGraphics renderer for the 7 alternate app icons
│   └── generate_stress_test_export.swift      # Produces stress-test-exports/CashLens_StressTest_5000.json
├── stress-test-exports/            # 5,000-expense JSON for perf testing
├── website/                        # Vite + React marketing site. NOT what is live at cashlens.app
│                                   #   (production is a separate Next.js deployment on Vercel whose source is not in this repo)
├── CODEBASE.md                     # This file
└── PRO_FEATURES.md                 # Pro roadmap / phase log
```

Main app target:

```
CashLens/
├── CashLensApp.swift              # @main. Wires all VMs before first render; StoreRecoveryView gate; AppLockView overlay;
│                                  #   deep-link sheets (.allExpenses / .export / .addExpense); foreground hooks (entitlements,
│                                  #   widget snapshot, Quick Log queue drain, notification refresh, receipt orphan sweep)
├── Persistence.swift              # PersistenceController: SQLite WAL, storeLoadError / storeLoadFailed / storeFileURLs
├── CashLens.entitlements          # App Group group.com.rushi.CashLens.shared
├── PrivacyInfo.xcprivacy          # Privacy manifest (UserDefaults accessed-API reason); widget target has its own
├── Donations.storekit             # StoreKit config: 3 tip consumables + Pro monthly / yearly / lifetime (group D4E8F2A1)
├── CashLens.xcdatamodeld/         # Two model versions; current = "CashLens 2" (adds Budget custom date range)
│
├── Models/
│   ├── Expense.swift              # Expense struct + Currency enum + Category enum
│   ├── Subscription.swift         # Subscription struct + Frequency enum
│   ├── CustomCategory.swift       # CustomCategory struct + available icons/colors
│   ├── Budget.swift               # Pro: Budget struct, Period (weekly / monthly / custom), CategoryFilter
│   ├── PaymentMethod.swift        # 7 payment methods + tolerant CSV parsing
│   ├── PaymentMethodBreakdown.swift # Pro donut aggregate
│   ├── ExpenseTemplate.swift      # Saved Add-Expense presets
│   ├── CurrencyData.swift         # Static currency code → symbol/name mapping
│   ├── CurrencyRegion.swift       # Currency grouped by world region for picker
│   ├── DonationManager.swift      # StoreKit 2 tip jar (3 consumable products)
│   ├── ProManager.swift           # StoreKit 2 Pro entitlements, donor grandfathering, win-back, intro-offer
│   │                              #   eligibility, PurchaseIntent listener (promoted IAPs)
│   ├── AppTheme.swift             # Pro: accent themes (Classics + Pastels), light/dark hex pairs, matchingIconId
│   ├── AppIconOption.swift        # Pro: 8 icon options (primary + 7 alternates)
│   ├── ExpenseEntity+Extensions.swift        # Core Data ↔ Expense bridge
│   ├── SubscriptionEntity+Extensions.swift   # Core Data ↔ Subscription bridge
│   ├── CustomCategoryEntity+Extensions.swift # Core Data ↔ CustomCategory bridge
│   └── BudgetEntity+Extensions.swift         # Core Data ↔ Budget bridge
│
├── Backup/                        # Backup / restore pipeline (see §14)
│   ├── BackupBundle.swift         # Canonical Codable schema (v2) — entities + preferences
│   ├── BackupExporter.swift       # Snapshots store + UserDefaults, writes JSON / CSV / .cashlens-archive
│   ├── BackupImporter.swift       # Format detection, parsing, merge/replace apply, receipt restore
│   └── GenericCSVAdapter.swift    # Auto-maps Mint / YNAB / bank CSV columns (Pro)
│
├── ViewModels/
│   ├── ExpenseViewModel.swift             # Main VM: state, filtering, preferences, tagStats, phased hydration
│   ├── ExpenseViewModel+CoreData.swift    # loadExpenses / loadExpensesAsync / applyIncremental* helpers
│   ├── ExpenseViewModel+CRUD.swift        # Add/update/delete, bulk ops, receipt file cleanup, amount formatting
│   ├── ExpenseViewModel+Categories.swift  # Custom categories, deleted defaults
│   ├── ExpenseViewModel+Currency.swift    # Global currency sync across all data
│   ├── ExpenseViewModel+ImportExport.swift # Compatibility shim → delegates to Backup/
│   ├── ExpenseViewModel+Maintenance.swift # Refresh, health check, clear all data
│   ├── ExpenseViewModel+Preferences.swift # Summary card customization tokens
│   ├── ExpenseViewModel+Preview.swift     # SwiftUI preview helper
│   ├── SubscriptionViewModel.swift        # Recurring bills: CRUD, Mark paid, reminders, overdue reconcile
│   ├── CategoryViewModel.swift            # Custom category CRUD via NSFetchedResultsController
│   └── BudgetViewModel.swift              # Pro: budgets, progress, 80/100% crossing alerts
│
├── Views/
│   ├── MainTabView.swift           # Root: 4 tabs (Today / Activity / Insights / You). iOS 26 native TabView path
│   │                               #   + iOS 18–25 custom tab bar path; FAB; auto-paywall, win-back, donor-thanks sheets;
│   │                               #   save-error banner + save-confirmation toast hosts; requestReview
│   ├── TodayView.swift             # Today tab: verdict hero, budgets, upcoming subs, 7-day strip, recent, insight, recap card
│   ├── TodayCustomizeView.swift    # Reorder / hide Today sections (TodaySectionID)
│   ├── AllExpensesView.swift       # Activity tab root (isRootTab) — ledger, filters, calendar toggle, bulk select;
│   │                               #   two-pane HStack (ledger | Divider | editor) on regular width (2.2)
│   ├── StatisticsView.swift        # Insights tab — free stats + Pro Insights / Forecast / Payment Methods / PDF; Monthly Recap row
│   ├── ProfileView.swift           # You tab root — settings hub
│   ├── SubscriptionsView.swift     # Recurring bills list; sheet from You → Subscriptions (no longer a tab)
│   ├── AddExpenseView.swift        # Expense create/edit; templates, tags, payment method, refund, receipt capture + OCR
│   ├── AddSubscriptionView.swift   # Subscription create/edit form
│   ├── BudgetSetupView.swift       # Pro: create/edit budget (weekly / monthly / custom range, alerts)
│   ├── BudgetListView.swift        # Pro: manage budgets (sheet from You and Today)
│   ├── QuickSearchView.swift       # Modal search (single search surface)
│   ├── ExpenseCalendarView.swift   # Month grid browse (embedded in Activity or modal)
│   ├── MonthlyRecapView.swift      # MonthlyRecapView + MonthlyRecapSheet (compute + ShareLink card)
│   ├── ReceiptViewerView.swift     # Full-screen receipt viewer (zoom, share, delete)
│   ├── PaywallView.swift           # CashLens Pro upgrade screen; PaywallContext for per-feature copy
│   ├── WinBackView.swift           # One-time sheet after a Pro → free lapse
│   ├── DonorThanksView.swift       # One-time thank-you when a donor grant is applied
│   ├── AppearanceStudioView.swift  # Mode selector (free) + theme grids + "Complete the look" (Pro)
│   ├── AppIconPickerView.swift     # Pro: alternate-icon picker
│   ├── NotificationsSettingsView.swift # Reminders & Smart Insights hub (sheet from You)
│   ├── PrivacyDashboardView.swift  # You → Privacy: storage facts + App Lock entry
│   ├── SiriShortcutsTipsView.swift # You → Siri & Shortcuts: lists the App Shortcut phrases
│   ├── AppLockView.swift           # Root overlay: lock screen / privacy cover
│   ├── StoreRecoveryView.swift     # Root fallback when the Core Data store fails to load
│   ├── ProInsightsSection.swift    # Pro Insights section (Daily Pace / Velocity / YoY) + free teaser
│   ├── ForecastSection.swift       # Forecast section + free teaser
│   ├── CurrencyPickerView.swift    # Currency selection with region chips + search + Recently Used
│   ├── ManageCategoriesView.swift  # Default + custom category management
│   ├── CustomCategoryForm.swift    # Create/edit custom category
│   ├── SummaryCustomizationView.swift # Pick pinned categories
│   ├── ExportDataView.swift        # Complete Backup / Spreadsheet / Full Archive
│   ├── ImportDataView.swift        # Pick → preview → apply
│   ├── DonationView.swift          # StoreKit tip jar UI
│   ├── AboutView.swift             # App info, contact (AppConstants.supportEmail), privacy/terms links
│   ├── OnboardingView.swift        # First-launch carousel
│   └── DiagnosticsView.swift       # #if DEBUG data health tools + stress-seeder buttons (unreferenced — no entry point)
│
├── Components/
│   ├── ColorExtension.swift        # Design system colors; dynamic appPrimary / appSecondary from ThemeStore
│   ├── ExpenseCard.swift           # Optimized expense row (Equatable), tags row, paperclip badge, refund badge
│   ├── PinnedCategoryCard.swift    # Pinned-category tile
│   ├── BudgetProgressCard.swift    # BudgetProgressCard + BudgetMiniCard
│   ├── CategoryItem.swift / CustomCategoryItem.swift  # Category chips
│   ├── CategoryDonutChart.swift    # Interactive donut + legend
│   ├── ExpenseTrendChart.swift     # Custom Path line/area chart
│   ├── TrendChartPager.swift       # Over time / By weekday / Top days pager
│   ├── YearOverYearChart.swift     # Pro: grouped bars (SwiftUI Charts)
│   ├── ForecastChart.swift         # Pro: projection chart (SwiftUI Charts)
│   ├── SpendingHeatmap.swift       # Calendar heatmap
│   ├── SubscriptionRow.swift       # Subscription cell with inline Mark paid
│   ├── TagChip.swift / TagInputField.swift  # Smart Tags UI
│   ├── InsightInfoButton.swift     # info button + explanation sheet for every Insights section
│   ├── DocumentScannerView.swift   # VNDocumentCameraViewController wrapper (page 1 only)
│   ├── SheetHeader.swift           # Canonical sheet header (title / subtitle / close)
│   ├── SaveErrorBanner.swift       # SaveErrorBanner + SaveErrorBannerHost modifier
│   ├── SaveConfirmationToast.swift # SaveConfirmationToast + host modifier
│   └── FloatingAddButton.swift     # FAB (all tabs except You)
│
├── Design/                         # Cross-cutting design system (§11)
│   ├── Theme.swift                 # Spacing (incl. scrollBottomClearance = 100), Radius, Stroke, Typography, Shadow, Motion, Icon, appDuotone
│   ├── ViewModifiers.swift         # .cardSurface(), .sectionContainer(), .softShadow(), .primaryGlow(), .fieldCard(),
│   │                               #   .adaptiveHeight(ratio:min:max:), .readableColumn(maxWidth:)  (2.2)
│   ├── DuoLayoutSupport.swift      # iPhone Duo iOS 27.1 stubs behind #if CASHLENS_DUO_27_1 — no-ops today (2.2, §11)
│   └── Components/
│       ├── SectionHeader.swift, PillChip.swift, PrimaryGradientButton.swift,
│       ├── EmptyStatePanel.swift, SettingsRow.swift, HeroGlyph.swift,
│       └── EvenColumnGrid.swift    # Adaptive LazyVGrid rounded down to even columns (2.2)
│
├── Extensions/
│   ├── ButtonStyles.swift          # ScaleButtonStyle, OpacityButtonStyle, CustomAddButtonStyle
│   ├── NotificationExtension.swift # Notification.Name constants (§16)
│   └── ViewExtensions.swift        # Conditional modifier, per-corner rounding
│
├── Intents/                        # App Intents (run in the app process, headless) — §20
│   ├── CashLensShortcuts.swift     # AppShortcutsProvider: zero-setup Siri phrases
│   ├── LogExpenseIntent.swift      # "Log ₹450 for coffee" (IntentCurrencyAmount, required title, category inference)
│   └── GetSpendingIntent.swift     # "How much did I spend today?"
│
├── Utilities/
│   ├── HapticManager.swift, DeepLinkRouter.swift, ExpenseFilter.swift, UserDefaultsKeys.swift
│   ├── NotificationScheduler.swift # Digests, backup reminder, Smart Insight (Pro), fingerprint skip
│   ├── SmartInsightsEngine.swift   # Pro weekly insight selection (also feeds Today's insight card)
│   ├── StatisticsCalculator.swift, AdvancedStatsCalculator.swift (Pro), ForecastEngine.swift (Pro)
│   ├── PDFReportGenerator.swift    # Pro PDF report
│   ├── MonthlyRecapEngine.swift    # MonthlyRecap value + compute
│   ├── CategorySuggester.swift, StreakCalculator.swift, Tag.swift, TagSuggestionProvider.swift
│   ├── ExpenseDraft.swift, ExpenseTemplateStore.swift, RecentCurrenciesStore.swift
│   ├── ImportUtilities.swift       # Legacy CSV/JSON parse helpers
│   ├── ReceiptStorage.swift        # Documents/Receipts/<uuid>.jpg, orphan cleanup
│   ├── ReceiptOCRService.swift     # Pro: Vision VNRecognizeTextRequest → total + merchant
│   ├── QuickLogService.swift       # Headless expense writes (Siri intents, widget queue drain), spendingSummary
│   ├── AppLockManager.swift        # LocalAuthentication state machine (§21)
│   ├── PaywallTrigger.swift        # Pure rule: auto-paywall once on the 10th-expense crossing
│   ├── ReviewPromptManager.swift   # Rating-ask timing (no UI); replaced FeedbackManager in 2.2
│   ├── AppConstants.swift          # supportEmail (rjadeja053@gmail.com) + mailto helper (2.2)
│   ├── AppCommands.swift           # Hardware-keyboard commands: AppCommandCenter + AppCommands (Cmd-N / Cmd-F / Cmd-,) (2.2)
│   ├── DebugExpenseSeeder.swift    # #if DEBUG whole file: 5k/20k stress seeder via NSBatchInsertRequest (2.2, §23)
│   ├── SaveErrorReporter.swift     # SaveErrorReporter + SaveConfirmationReporter
│   ├── BudgetAlertState.swift      # Per-budget-per-period alert flags
│   ├── ThemeStore.swift, AppIconStore.swift      # Personalization singletons
│   ├── WidgetSnapshotBuilder.swift, WidgetSnapshotCoordinator.swift  # §19
│   └── Zip/                        # Pure-Swift STORE-only zip
│       ├── CRC32.swift, ZipWriter.swift, ZipReader.swift
│
├── Assets.xcassets/                # AppIcon + 7 alternate appiconsets + IconPreview imagesets, accent color, logo
└── Preview Content/                # Preview assets
```

Files that existed in v1 and are **gone** on this branch: `HomeView.swift` (replaced by `TodayView`), `SplashScreenView.swift`, `ThemePickerView.swift` (replaced by `AppearanceStudioView`), `ExpenseRow.swift`, `AddButton.swift`.

---

## 4. Data Layer

### Core Data Schema

**4 Entities** defined in `CashLens.xcdatamodeld`. Two model versions exist: `CashLens.xcdatamodel` and the current `CashLens 2.xcdatamodel` (per `.xccurrentversion`), which adds `customStartDate` / `customEndDate` to `BudgetEntity` for custom-range budgets. All changes have been additive optional attributes plus fetch indexes, so migrations are lightweight.

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
| `receiptImagePath` | String | Yes | — | **Filename only** (never an absolute path) of the JPEG in `Documents/Receipts/`. Capture is Pro; viewing is free. |

Fetch indexes: `byDate` (descending), `byId`, `byCategory`, `byCustomCategoryId`, `bySubscriptionId`.

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

Fetch indexes: `byNextDueDate`, `byId`, `byIsActive`.

#### CustomCategoryEntity
| Attribute | Type | Optional | Default | Notes |
|-----------|------|----------|---------|-------|
| `id` | UUID | No | — | Primary identifier |
| `name` | String | No | — | Category display name |
| `icon` | String | No | — | SF Symbol name |
| `colorName` | String | No | — | Named color from palette |

Fetch index: `byId`.

#### BudgetEntity (Pro)
| Attribute | Type | Optional | Default | Notes |
|-----------|------|----------|---------|-------|
| `id` | UUID | No | — | Primary identifier |
| `name` | String | No | — | Budget label |
| `amount` | Double | No | 0.0 | Cap for the period |
| `period` | String | No | `Monthly` | `Budget.Period` raw value: `Weekly` / `Monthly` / `Custom` |
| `customStartDate` | Date | Yes | — | Custom period start (model v2) |
| `customEndDate` | Date | Yes | — | Custom period end, **inclusive** (model v2) |
| `categoryFilterType` | String | No | `overall` | `overall` / default category / custom category |
| `categoryFilterDefaultRaw` | String | Yes | — | `Expense.Category` raw value when filtering to a default category |
| `categoryFilterCustomId` | UUID | Yes | — | `CustomCategoryEntity.id` when filtering to a custom category |
| `alertAtPercentages` | Transformable | Yes | — | Alert thresholds |
| `isActive` | Boolean | No | YES | Paused budgets are excluded |
| `createdAt` | Date | No | — | Fallback anchor for custom periods |

Fetch index: `byId`. Bridged by `BudgetEntity+Extensions.swift` to `Models/Budget.swift`.

### Persistence Controller (`Persistence.swift`)

- **Singleton**: `PersistenceController.shared`
- **SQLite optimizations**: WAL journal mode, NORMAL synchronous
- **Merge policy**: `NSMergeByPropertyObjectTrumpMergePolicy`
- **Performance**: Undo manager disabled, auto-merges from parent context
- **Preview support**: In-memory store for SwiftUI previews
- **Load-failure recovery**: the store load is synchronous in `init`; a failure is captured in `storeLoadError` (never crashes, never deletes the store). `CashLensApp` then wires every view model to a throwaway in-memory container and renders `StoreRecoveryView`, which offers the on-disk `.sqlite` / `-wal` / `-shm` files (`storeFileURLs`) through a share sheet so the data is always recoverable.

### UserDefaults Keys (`UserDefaultsKeys.swift`)

All preference keys are centralized in a caseless enum:

| Group | Keys |
|-------|------|
| **Onboarding** | `hasCompletedOnboarding`, `hasLaunchedBefore`, `hasShownCurrencyPicker` |
| **Preferences** | `selectedCurrency`, `recentCurrencies` (`recent_currencies_v1`, cap 3), `selectedTimeFrame`, `defaultHomeTimeFrame`, `appearanceMode`, `userName` |
| **Summary** | `preferredSummaryCategories` |
| **Categories** | `deletedDefaultCategories` |
| **Drafts** | `expenseDraft` |
| **Quick Search** | `quickSearchRecents` (last 5) |
| **Review prompt** | `reviewPromptAskedVersion` (marketing version last asked for). The pre-2.2 `FeedbackManager` keys (`hasRequestedFeedback`, `successfulActionsCount`, `lastFeedbackAttempt`, `feedbackPromptCount`, `feedbackUsageDayCount`, `feedbackLastUsageDay`, `feedbackLegacyMigrated`) are orphaned on disk and harmless |
| **Notifications** | Weekly/monthly/backup: `*Enabled`, `*Weekday`/`*DayOfMonth`, `*Hour`, `*Minute`; `scheduledNotificationsFingerprint` (skips a reschedule when nothing changed) |
| **Smart Insights (Pro)** | `smartInsightsEnabled`, `smartInsightsHistory`, `smartInsightsLastFireDate` |
| **Today** | `verdictWarningLastDate` (once-per-day warning haptic), `todaySectionOrder`, `todayHiddenSections` |
| **Monthly Recap** | `monthlyRecapLastSeenMonth` (`yyyy-MM`) |
| **Backup** | `lastBackupDate`, `lastBackupFormat`, `totalBackupCount` |
| **Pro / paywall** | `hasSeenPaywall`, `paywallImpressionCount`, `hasAutoShownPaywall`, `lastAutoPaywallDate` |
| **Donor grandfathering** | `donorGrantType` (`founder` / `year`), `donorGrantDate`, `donorGrantThanksShown` |
| **Pro lapse / win-back** | `lastKnownIsPro`, `winBackPending`, `winBackDeclined` |
| **App Lock (free)** | `appLockEnabled`, `appLockGraceSeconds`, `appLockLastBackgroundedAt` |
| **Personalization (Pro)** | `activeThemeId` (`AppTheme.id` — defaults to `mauve` so existing users see no change), `activeAppIconId` (matches `AppIconOption.id`; `nil` ⇒ primary icon) |

Not in `UserDefaultsKeys` but also `UserDefaults`-backed: `expense_templates_v1` (private to `ExpenseTemplateStore`) and `BudgetAlertState` keys.

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
    var receiptImagePath: String?      // filename in Documents/Receipts/, never an absolute path

    var signedAmount: Double { isRefund ? -amount : amount }
}

extension Sequence where Element == Expense {
    func netTotal() -> Double { reduce(0) { $0 + $1.signedAmount } }
}
```

**Nested Types:**

- **`Currency`** — 170+ ISO 4217 codes as enum cases. `symbol` and `name` resolved via `CurrencyData`. `allCases` derived from `CurrencyData.allCurrencies`.
- **`Category`** — 11 built-in categories: Groceries, Food, Transportation, Entertainment, Shopping, Utilities, Health, Education, Travel, Custom, Other. Each has an `icon` (SF Symbol), `color` (named color key), and `displayName`.

**Import Support:** `init(from json:)` for JSON, `init(fromCSV:)` for CSV with multi-format date parsing. Custom `init(from decoder:)` uses `decodeIfPresent` for `isRefund`, `paymentMethod` and `receiptImagePath` so older backups decode unchanged with `isRefund = false` and the optionals `nil`. CSV imports also accept a "Payment Method" column with tolerant parsing via `PaymentMethod.tolerant(from:)`.

**Refund-aware aggregation:** All totals across the app go through `signedAmount` / `netTotal()` so refunds subtract from spending while sorting/displaying continues to use absolute `amount`. Touched aggregators include `ExpenseViewModel.computeTotals`, `StatisticsCalculator`, `AdvancedStatsCalculator`, `ForecastEngine`, `BudgetViewModel`, `NotificationScheduler.DigestStatsCalculator`, `ExpenseTrendChart`, `SpendingHeatmap`, `AllExpensesView` day headers, `QuickSearchView`, `TodayView`, `MonthlyRecapEngine`, and `WidgetSnapshotBuilder`.

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

User-selectable accent theme. Twelve options ship in two families: **Classics** (Mauve — default, preserves the historical CashLens brand — Ocean, Forest, Sunset, Berry, Graphite) and **Pastels** (six more). Each carries hand-tuned light + dark hex pairs for both `primary` and `secondary` so contrast stays AA-safe in either appearance mode. The six Classics carry a `matchingIconId` so `AppearanceStudioView` can offer the theme-matched app icon; Pastels have none.

```swift
struct AppTheme: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let primaryLightHex, primaryDarkHex: String
    let secondaryLightHex, secondaryDarkHex: String
    let matchingIconId: String?   // AppIconOption.id, Classics only

    var primaryColor: Color    // Color(UIColor { trait in ... }) — light/dark adaptive
    var secondaryColor: Color

    static let classics, pastels: [AppTheme]
    static let all: [AppTheme] = classics + pastels
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

### Budget (`Models/Budget.swift`) — Phase 2 (Pro)

Value type behind `BudgetEntity`. `Period` is `weekly` / `monthly` / `custom`; custom periods use `customStartDate` … `customEndDate` (inclusive), falling back to `createdAt`. `CategoryFilter` is `overall`, `defaultCategory(String)` or `customCategory(UUID)`. Progress and alert logic live in `BudgetViewModel` (§6).

### DonationManager (`Models/DonationManager.swift`)

StoreKit 2 wrapper for the tip jar consumables. Does **not** run its own `Transaction.updates` loop — `ProManager` owns the single listener and routes donation transactions to `DonationManager.recordPurchasedProductID(_:)` before finishing them. See [Monetization](#12-monetization).

### ProManager (`Models/ProManager.swift`)

StoreKit 2 Pro entitlements, donor grandfathering, win-back, intro-offer eligibility and the promoted-IAP `PurchaseIntent` listener. See [Monetization](#12-monetization).

### Entity Bridge Extensions

- **`ExpenseEntity+Extensions.swift`** — `fromExpense(_:context:)` and `toExpense()` conversions
- **`SubscriptionEntity+Extensions.swift`** — Same pattern + `updateFromSubscription(_:)` for in-place updates
- **`CustomCategoryEntity+Extensions.swift`** — Same pattern with defaults for missing icon/color
- **`BudgetEntity+Extensions.swift`** — Same pattern for `Budget`, flattening `CategoryFilter` into the three `categoryFilter*` attributes

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

**Views:** `BudgetSetupView`, `BudgetListView`, `Components/BudgetProgressCard` + `BudgetMiniCard`; Today's verdict hero is driven by the budget, and a stacked budgets card appears with 2+ budgets; You → Manage Budgets opens `BudgetListView` (or the paywall). `Budget.Period.custom` with `customStartDate` / inclusive `customEndDate` was added in the pre-submission wave (Core Data model v2).

### Smart Tags (Phase 3 Pro) — `ExpenseViewModel.tagStats` + `Utilities/Tag*.swift`

**Tags are a property of `Expense`** (`tags: [String]?`) persisted to `ExpenseEntity.tags` (Transformable `NSArray`, `NSSecureUnarchiveFromDataTransformerName`). The feature is split across three small, composable units:

- **`Utilities/Tag.swift`** — pure helpers. `Tag.normalize(_:)` canonicalizes user input (trim, strip `#`, whitespace-to-`-`, lowercase, 30-char cap). `Tag.displayForm(_:)` always renders with a `#` prefix. Constants: `maxLength = 30`, `maxPerExpense = 10`.
- **`Utilities/TagSuggestionProvider.swift`** — aggregator. `computeStats(from:)` walks expenses once and returns a `Stats` struct: `usageCounts`, `recentTags`, `popularTags`. Since `026960f` it **no longer re-sorts** the input: it relies on the documented invariant that `ExpenseViewModel.expenses` is kept date-descending (fetch sort descriptor + `applyIncrementalInsert` / `applyIncrementalUpdate`). `recentTags` order is identical for distinct dates; `usageCounts` / `popularTags` are order-independent. Callers must pass the array in that order. `suggestions(for:allTags:excluding:limit:)` produces autocomplete (prefix matches rank above substring, usage count breaks ties).
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
| `CashLensApp` | `CashLensApp.swift` | `@main` entry. Wires `ExpenseViewModel`, `BudgetViewModel`, `SubscriptionViewModel`, `CategoryViewModel` in `init` (so `markSubscriptionAsPaid` can never run with a nil expense VM), injects `ProManager`, `ThemeStore`, `AppIconStore`, `AppLockManager`, `DeepLinkRouter`. Body: `StoreRecoveryView` if the store failed to load, else `MainTabView` + onboarding overlay; `AppLockView` overlay at `zIndex(10)` above everything. Deep-link sheets (`.allExpenses`, `.export`, `.addExpense`), `onOpenURL` for `cashlens://`, `.commands { AppCommands() }` on the `WindowGroup` (2.2 keyboard shortcuts). On `.active`: refresh data + budget progress, widget snapshot `refreshNow()`, drain the Quick Log widget queue, re-check Pro entitlements + win-back, reconcile overdue subscriptions, refresh notifications, sweep orphan receipts. There is **no splash screen** on this branch. |
| `MainTabView` | `MainTabView.swift` | Root shell with **4 tabs — Today / Activity / Insights / You** (`enum Tab`). Two code paths: iOS 26+ `modernTabView` uses native `TabView` + `SwiftUI.Tab` with `.tabViewStyle(.sidebarAdaptable)` (2.2 — regular width such as iPad gets a sidebar automatically; compact keeps the system floating tab bar), `.tint(.appPrimary)`; iOS 18–25 `legacyTabView` draws a custom 60 pt tab bar with `UITabBar.appearance().isHidden = true`. `FloatingAddButton` overlay (`shouldShowFAB`) on every tab except You, hidden while Activity is in bulk-select mode and — since review fix `c9a63ed` — hidden on **Activity at regular width** (it overlapped the detail editor's Save; the ledger header carries "+" instead). Padding is driven by `horizontalSizeClass` (`isRegularWidth`) since 2.2 — the `userInterfaceIdiom` / `width > 768` checks from `redesign/v2` are gone. The FAB stays an overlay (not a toolbar item) because the tab roots deliberately have no `NavigationStack`, so there is no toolbar to host "+"; it sits on the `TabView`'s safe-area frame so it cannot enter a Duo vertical bar. The iOS 26 `TabView` also carries `.duoTabBarCompression()` (no-op today, §11). On the legacy path, `let legacyBarInset = tabBarHeight + geometry.safeAreaInsets.bottom` is applied as `.safeAreaPadding(.bottom, legacyBarInset)` **on each of the four tab roots** (`56c6746` moved it off the UIKit-backed `TabView`, where it did not take). `hasPresentation` (`showingAddExpense || showingAutoPaywall || showingCurrencyPicker || proManager.shouldShowWinBack || proManager.pendingDonorThanks != nil || DeepLinkRouter.shared.route != nil`) gates both Cmd-N and the rating ask. Keyboard: `handleKeyboardCommand` receives `AppCommandCenter` commands (guards App Lock + onboarding): Cmd-N opens the add sheet unless `hasPresentation`, Cmd-, selects You, Cmd-F selects Activity then re-emits `.presentActivitySearch` after 0.25 s so a freshly mounted Activity root can hear it. The You tab root is unmounted when hidden (`youTabRoot`) to stop Profile's environment fan-out from stuttering later tab switches. Hosts: `.saveErrorBannerHost()`, `.saveConfirmationToastHost()`, post-value auto-paywall (`PaywallTrigger`, `PaywallView(context: .insights)`), `DonorThanksView` and `WinBackView` sheets (flags consumed on `onAppear`), native `requestReview` driven by `ReviewPromptManager.shouldRequestReview` (on receipt: `consume()`; if locked or `hasPresentation` → `deferWhilePresenting()`, else `markRequested()` + `requestReview()`), add-expense and currency-picker sheets. |
| `AppLockView` | `AppLockView.swift` | Root overlay driven by `AppLockManager.isCoverVisible`: lock screen with unlock button, or plain privacy cover while the scene is inactive. |
| `StoreRecoveryView` | `StoreRecoveryView.swift` | Full-screen fallback when Core Data fails to load. Never deletes or resets; explains the data is safe, offers a share sheet with the raw store files and a support `mailto:` link (`AppConstants.supportMailURL`). |
| `OnboardingView` | `OnboardingView.swift` | First-launch carousel (5 steps: welcome, privacy, capability, firstExpense, finish) with Skip/Next/Get Started. Sets `hasCompletedOnboarding`; `CashLensApp` then shows `CurrencyPickerView(isInitialSetup: true)` once. 2.2: `pageContent` splits into `regularHeightPage` / `compactHeightPage` on `verticalSizeClass` — in landscape the hero sits beside a scrolling copy + control column; the first-expense page stays full width. Title no longer uses `lineLimit(2)` + `minimumScaleFactor`. |

### Primary Tabs

| View | File | Description |
|------|------|-------------|
| `TodayView` | `TodayView.swift` (Today tab) | Replaces v1 `HomeView`. One job: answer "am I OK right now?" **Pinned at top:** verdict hero (`TodayVerdict` — spend vs budget, days left, projected month-end, On Track / Tight / Over pill; degrades to pace-vs-typical-month when there is no budget; ring animates on first appear; over-budget pulse runs three times then settles). **Customizable sections** (`TodaySectionID`, order + hidden set persisted; edited in `TodayCustomizeView`): `summary`, `upcoming` (bills due in the next two weeks from `SubscriptionViewModel`), `weekStrip` (7-day bar strip tinted by dominant category, tappable days, no-spend streak flame chip from `StreakCalculator`), `recent` (three most recent expenses, "See all activity" → Activity tab), `insight` (single `TodayInsight` picked via `SmartInsightsEngine`). Also: stacked budgets card when 2+ budgets (`BudgetSnapshot`, opens `BudgetListView`), and a "Your <Month> recap is ready" card during the first days of a new month (`monthlyRecapLastSeenMonth`). Deliberately **no** timeframe selector, pinned categories or Pro teaser. All aggregates recompute off-main on one debounced task; once-per-day warning haptic when the verdict worsens (`verdictWarningLastDate`). Header arrows can jump to Insights with a preselected window via `.insightsRequestTimeFrame`. 2.2: `.readableColumn()` (680 pt) on regular width; scroll bottom clearance is `Theme.Spacing.scrollBottomClearance`; the streak recompute feeds `ReviewPromptManager.recordStreak`; `TodayInsight.pick` filters today's and this week's rows against precomputed `[todayStart, todayEnd)` / `[weekStart, todayStart)` ranges (same calendar, so DST days behave) instead of `cal.isDate(_:inSameDayAs:)` per row (`602b5b4`). |
| `AllExpensesView` | `AllExpensesView.swift` (Activity tab) | Mounted with `isRootTab: true` and `onRequestAddExpense` (from both tab paths). `activityNavContainer` picks the container by size class (2.2): **root tab + regular width** (`showsEditorInDetailColumn`) → a plain **two-pane `HStack(spacing: 0)`**: ledger `.frame(minWidth: 300, idealWidth: 340, maxWidth: 420)` | `Divider()` | `editorDetailColumn` (`AddExpenseView` with `.id(expense.id)` and `onDismissRequest { selectedExpense = nil }`, or a `ContentUnavailableView` placeholder). The first cut used `NavigationSplitView`; the launch-readiness review flagged a split view nested inside a `.sidebarAdaptable` `TabView` tab (finding S3) and it was replaced (`942efad`); the pane never collapses, so no sidebar toggle is needed — there is **no `NavigationSplitView` anywhere** now. `HStack` sizing: each child is offered half the width, the ledger clamps to 300…420 and the editor takes the rest (1366 → 420/946; Duo inner 626 → 313/313; 11" at 50/50 597 → 300/297). Because the root FAB is hidden on Activity at regular width (it overlapped the editor's Save), `activityPageHeader` shows a 32 pt icon-only "+" button (`.hoverEffect(.lift)`) that calls `onRequestAddExpense`. **Root tab + compact** → bare content (no `UINavigationController` under the tab bar); **sheet / deep-link** → `NavigationStack`. While the detail column owns the selection the editor sheet binding is `.constant(nil)`; a size-class flip mid-edit moves the editor between sheet and pane and drops unsaved field edits (accepted, logged in code). The list's bottom spacer is `Theme.Spacing.scrollBottomClearance` (was a hard-coded 96 / 40). Day grouping (2.2, `319af89` + `d26c541`): because the array is date-sorted, the recompute holds `currentDayStart` / `currentDayEnd` once per group and calls `calendar.startOfDay` only when a row leaves those bounds, falling back to the old per-row equality if the day-end lookup ever fails — identical groups, far fewer `Calendar` calls. Opens Quick Search on `AppCommandCenter` `.presentActivitySearch` when `isRootTab && isTabVisible`. Full description under *Lists & Search* below. |
| `StatisticsView` | `StatisticsView.swift` (Insights tab) | Full description below; also hosts the permanent **Monthly Recap** row that presents `MonthlyRecapSheet`. |
| `ProfileView` | `ProfileView.swift` (You tab) | Settings hub; full description under *Settings & Data* below. |
| `SubscriptionsView` | `SubscriptionsView.swift` (sheet from You → Subscriptions; **not a tab** in v2) | One **hero card** owns the summary: small "Per month" label, huge total, a **"Next up"** row previewing the earliest upcoming active sub, divider, then three inline mini-stats (Yearly / Due 7d / Average). Below: **segmented filter pills** (`All` / `Active` / `Due Soon`) with `matchedGeometryEffect` on the selection. List is grouped into Due Soon / Later / Paused subsections when "All" is active. Wrapped in `NavigationStack`. Includes a hint explaining when "Mark paid" appears (2.0.1). Sheets: add/edit subscription. |
| `StatisticsView` (detail) | `StatisticsView.swift` | Redesigned premium statistics dashboard. Filter bar (time-frame pills → **Apple-Fitness-style period chevrons** `< December 2024 >` with smart labels for Today / Yesterday / This week / Last week / named months / years + forward chevron disabled when at current period → optional category row). Hero Overview card: huge total + delta pill + three inline mini-stats (Expenses / Average / Highest) replacing the old three-card grid. Pro Insights (daily pace / velocity / YoY). **Forecast** (horizon switcher `30d / 60d / 90d`, projected total + confidence range, line-chart with dashed projection + ±1σ band + subscription dots, Subscriptions and Top Driver mini-cards). Highlights (auto insights). **Where It Goes** merges the donut chart + category rows into one card with tap-linked selection — tap a slice or a row and the other half highlights via shared `donutSelectedId`. **Payment Methods** (Pro): same donut + breakdown shape, but slices are payment methods; selection state is `paymentDonutSelectedId`. Untagged expenses surface as a "tag x more (N% covered)" footer instead of as a wedge. Free users see a focused upgrade teaser instead of a live donut so the Pro reveal feels meaningful. Section is hidden entirely when no expense in view has any payment method *and* the user is free. Spending Pattern (heatmap). **Trend is a three-page swipeable pager** (Over time / By weekday / Top days) with a segmented tab bar, page dots, and matched-geometry selection. Every section header (plus the hero label) has an `InsightInfoButton` that opens a plain-English explanation sheet. Unified `SectionEntrance` modifier gives every section a spring-based cascade that settles in ~0.4 s. Debounced background recomputation computes weekday averages + top-day aggregates + the forecast + the payment-method breakdown alongside the existing totals so swipes stay at 60 fps. Free users see teasers for Pro Insights, Forecast, and Payment Methods + lock-badged PDF export; all of them route to `PaywallView`. |

### Forms

| View | File | Description |
|------|------|-------------|
| `AddExpenseView` | `AddExpenseView.swift` | Expense create/edit. **Templates chip strip** at the top of the form when the user has saved presets — taps fill the form with safe-merge semantics (never overwrites typed title/amount; tags/notes/refund flag are *additive*); long-press / context-menu offers Use or Delete. **"Save as template"** bookmark in the header (right of close, only when the form is valid and not editing) opens a quick rename alert. Amount, **refund toggle row** (above title; flips the entry to subtract from totals), title, **smart "Suggested" category pill** (driven by `CategorySuggester`, surfaces once title ≥ 2 chars and confidence ≥ 0.45 — single tap sets the category with a haptic), category picker (`EvenColumnGrid(minimumItemWidth: 74)` since 2.2 with `.hoverEffect(.highlight)` tiles; fixed 4 columns before), date, **tags (chip field with live autocomplete / recent / popular suggestions, Pro-free for adding)**, notes. Draft save/restore (includes tags + `isRefund`), duplicate detection (`isPotentialDuplicate` — runs on main at the Save tap over every expense; since `0a46d6f` it checks amount, then the 5-minute date window, then the trimmed case-insensitive title, so the string work only runs on the handful of candidates; same pure-AND verdict), quick date chips, title suggestions. **Receipt field** (Pro capture, free viewing): Scan (`DocumentScannerView`, page 1 only) or Library (`PhotosPicker`); after a capture `ReceiptStorage.save` runs off-main and then `runReceiptOCR(on:)` (Pro, `ReceiptOCRService`) fills only *empty* amount/title fields; `handleScanTapped` / `handleLibraryTapped` route free users to `PaywallView(context: .receipts)`; `cleanupUnsavedReceipt()` deletes a session-attached file on close. Payment method pill scroller under Category. |
| `BudgetSetupView` | `BudgetSetupView.swift` | Pro: create/edit a budget — amount hero, name, period (Weekly / Monthly / Custom range with start + inclusive end date), category filter picker, alert thresholds. Dismisses if not Pro. |
| `BudgetListView` | `BudgetListView.swift` | Pro: manage budgets; the single canonical budget-management sheet, reused by You → Manage Budgets and by Today's budgets section. |
| `AddSubscriptionView` | `AddSubscriptionView.swift` | Subscription create/edit — **structural twin of `AddExpenseView` / `BudgetSetupView`** (same custom header with X + optional trash, `@FocusState`-driven `.fieldCard(isFocused:)` inputs, fixed bottom save button with gradient fade). Fields: amount (hero), service name, billing frequency (horizontal pill row), start date (compact row → `.graphical` date picker sheet) with live "Next: Mar 20, 2026 · Every month" preview, category picker (circle style identical to Budget), reminder card (toggle + 1d/2d/3d/7d pill chips replacing the old stepper), notes. Delete section shown when editing. |
| `CustomCategoryForm` | `CustomCategoryForm.swift` | Category name, icon picker (grid sheet), color picker (grid sheet). Validation. |

### Lists & Search

| View | File | Description |
|------|------|-------------|
| `AllExpensesView` | `AllExpensesView.swift` | Full list — the **Library** half of the search/browse pair, and the Activity tab root. In-content page header ("Activity" + Select toggle), then a promoted **search field button** (opens `QuickSearchView` — the app's single search surface) beside a **List / Calendar view-mode toggle** (calendar renders `ExpenseCalendarView(isEmbedded: true)` in place, preserving list state). Sort bar: sort pill (date/amount/category), date-range pill (sheet with one-tap **quick presets** — Last 7/30 days, This/Last month — plus custom pickers), and a live **"count · refund-aware net total"** label for the current filtered set. Filter chips: **"All" is a true reset** (clears category, subscription, tag, *and* date-range filters; lit only when nothing is filtered), subscription + default/custom category chips, and a menu-backed **Pro-gated Tags chip** (`tagsFilterChip`; free users get a paywall entry point). Pagination (250 chunks); recompute runs off-main with optimistic-delete suppression (`pendingDeletionIds`) and one-shot `scrollToTop` on every filter/sort mutation. PERF: recomputes are **visibility-gated** like StatisticsView — while the tab is hidden, `$expenses` publishes only set a `recomputePending` flag and the next `onAppear` runs one catch-up pass, so background saves never burn a filter+sort+group pass the user can't see. Row actions live in a **context menu** (Edit / Select / Delete) shared by both date-grouped and flat sort layouts — no `.swipeActions` (dead outside `List`). **Selection mode:** "Select"/"Done" toggle reveals checkboxes and a sticky bottom action bar with **Category**, **Tag** (Pro), and **Delete** bulk actions routing through the batch APIs in `ExpenseViewModel+CRUD.swift` (`deleteExpenses`, `bulkChangeCategory`, `bulkAddTag`) so all changes commit in a single Core Data save. The empty state is filter-aware — zero-result filters show "Clear Filters" + "Search instead"; a truly empty ledger shows the first-run panel. |
| `ExpenseCalendarView` | `ExpenseCalendarView.swift` | Modal **month-grid browse** surface — the calendar complement to the chronological `AllExpensesView` list and the intensity-based `SpendingHeatmap`. Reachable from `AllExpensesView`'s toolbar (`calendar` icon, iPhone + iPad). Each day cell shows the day number, up to three colored category dots (top categories that day by absolute amount), and a compact net total. Today is highlighted with an `appPrimary` tint; future days are visually muted and non-tappable. Tapping a day expands a detail section beneath the grid showing the day's expenses sorted newest-first; rows route to the same `AddExpenseView` editor used elsewhere — never a separate code path. A summary strip surfaces month net total, transaction count, and active-day count. Per-day aggregation runs in `Task.detached`, keyed off `visibleMonth` and `viewModel.$expenses`, so swiping months never blocks the main thread. **Read-only** — never mutates Core Data directly. |
| `QuickSearchView` | `QuickSearchView.swift` | Modal search — the **Spotlight** half of the search/browse pair. Opened from the search field button on `AllExpensesView` (and legacy Home header entry points), so search is the same experience everywhere in the app. `SheetHeader` chrome; hero search field uses `.fieldCard(isFocused:)` so the focus glow is consistent app-wide. Empty-query state is deliberately lean: **persisted Recent Searches** (last 5, dismissible chips, `UserDefaultsKeys.quickSearchRecents`) and one-tap **Quick Tips** chips ("This month", a real `$X` example anchored to the user's median spend, top tag/category). The former Browse-by-Category/Tag strips and Recent Activity preview were removed — they duplicated Activity's filter strip and the Activity tab itself. Results state shows a count + refund-aware net-total summary chip and groups results into Today / Yesterday / This Week / Earlier. Result rows highlight the matched substring of the title in `appPrimary` semibold and show category · date · first tag. **Ranking pipeline (PERF):** a pre-lowered `SearchIndexEntry` array is built off-main once per `expenses` snapshot (rebuilt via `.onReceive(viewModel.$expenses)`, which also re-runs an active query after edits); each keystroke (150 ms debounce, skipped for chip taps via `skipNextDebounce`) ranks against that index in a `Task.detached` pass that also prebakes the date groups and net total — `body` never walks the dataset. Scoring: title-prefix > title-contains > tag > category > notes > exact-amount. **Render cap (2.2, `19a32c3`):** only the top `maxRenderedResults = 200` ranked matches are grouped and rendered (`groupResults` runs on `results.prefix(200)`); the result count chip and net total still use the full match set, and when the set exceeds 200 a `truncationFooter` reads "Showing the top 200 of N matches. Narrow your search to see the rest." — nothing is hidden silently. This removed the last main-thread O(N) hang in the UI (each group is a non-lazy `VStack`, so a broad query at 20k rows used to build thousands of rows in one layout pass). Numeric amount parsing (`$50` ≈ `50.00`), `#tagname` tag-only mode, and natural date keywords (`today`, `yesterday`, `this week`, `this month`, `this year`) act as hard filters. Sections animate in with a `SearchEntrance` cascade matching Statistics / Subscriptions / Home. |

### Settings & Data

| View | File | Description |
|------|------|-------------|
| `ProfileView` | `ProfileView.swift` (You tab root) | Settings hub. **Top → bottom** (`proSection`, `generalSection`, `privacySection`, `personalizationSection`, `manageSection`, `notificationsSection`, `dataSection`, `aboutSection`): compact profile header (tap-to-edit name), Pro card (active or upgrade → `PaywallView`), **contextual Backup Warning Banner** (only when backup health is not `.good`, tap → export sheet), **General** (Default Currency → `CurrencyPickerView`, Default Time Frame `Menu`, Siri & Shortcuts → `SiriShortcutsTipsView`), **Privacy & Security** (Privacy → `PrivacyDashboardView`; App Lock toggle + "Require After" grace-period picker backed by `AppLockManager`), **Personalization** (Theme & Appearance → `AppearanceStudioView` for everyone; App Icon → `AppIconPickerView`, `proLockChip` for free users), **Manage** (Manage Budgets → `BudgetListView` or paywall, Categories → `ManageCategoriesView`, Subscriptions → `SubscriptionsView`, each with a live count badge), **Notifications** (single "Reminders & Insights" row → `NotificationsSettingsView`, "N active" badge from `@AppStorage` mirrors), **Data** (Last Backup / Total Backups, Export Data, Import Data, Clear All Data — metadata refreshes via `.backupMetadataDidChange`), **About** (Rate CashLens → App Store write-review link, Support the App → `DonationView`, Restore Purchases — free users only, runs `ProManager.restorePurchases()` with a result alert — About CashLens, community row: Instagram / X / Reddit), version footer. Every destination is a **sheet, not a navigation push** — the You tab never hosts a root `UINavigationController` because that caused permanent tab-switch stutter. 2.2: `.readableColumn()` (680 pt) on regular width. Built on `SettingsRow` / `SettingsRowValue` / `SettingsRowDestructive` + `SettingsGroup`. |
| `NotificationsSettingsView` | `NotificationsSettingsView.swift` | Sheet from You → Reminders & Insights. One card per reminder (weekly digest, monthly digest, backup reminder) with a schedule sub-row when enabled, plus a Smart Insights group (Pro toggle; free users see a lock pill that opens the paywall). Writes through the same `@AppStorage` keys `ProfileView` reads and triggers `NotificationScheduler` refresh on save. |
| `PrivacyDashboardView` | `PrivacyDashboardView.swift` | Sheet from You → Privacy. Renders the privacy story as facts: what is stored on this iPhone/iPad, database + receipts size (file IO off-main), the "three zeros" (servers, trackers, accounts), App Lock status, export shortcut. |
| `SiriShortcutsTipsView` | `SiriShortcutsTipsView.swift` | Sheet listing the zero-setup phrases registered by `CashLensShortcuts` ("Log an expense in CashLens", "How much did I spend today in CashLens", …). No configuration — App Shortcuts need none. |
| `TodayCustomizeView` | `TodayCustomizeView.swift` | Reorder and hide Today sections (`TodaySectionID.defaultOrder` = summary, upcoming, weekStrip, recent, insight). The verdict hero is not customizable. Persists `todaySectionOrder` / `todayHiddenSections`. |
| `MonthlyRecapView` / `MonthlyRecapSheet` | `MonthlyRecapView.swift` | Free month-in-review sheet: single scrolling sequence of design-system cards (total vs previous month, top category, biggest expense, no-spend days and best streak, busiest day, subscription total, an `Award`) ending with a `ShareLink` of an `ImageRenderer`-rendered summary card. `MonthlyRecapSheet` waits for full hydration, computes `MonthlyRecapEngine` off-main, and writes `monthlyRecapLastSeenMonth` on appear. Entry points: Today card (first days of a new month) and the permanent Insights row. |
| `ReceiptViewerView` | `ReceiptViewerView.swift` | Full-screen receipt viewer — pinch-to-zoom (1×–5×), double-tap toggle, pan, share, destructive delete with confirmation. Free for everyone (viewing existing receipts is never gated). |
| `WinBackView` | `WinBackView.swift` | One-time sheet on the first foreground after a Pro → free lapse. Calm copy (nothing was taken away), CTA opens `PaywallView`, "No thanks" calls `ProManager.declineWinBack()` and silences it forever. Never shown to active donor-grant holders or while App Lock is up. |
| `DonorThanksView` | `DonorThanksView.swift` | One-time thank-you when a donor grandfather grant is first applied (Founder = permanent Pro; Coffee = 1 year). No plan cards, no CTA other than dismiss. |
| `AppearanceStudioView` | `AppearanceStudioView.swift` | Unified "make it yours" studio (replaced `ThemePickerView`). **Top → bottom:** `SheetHeader` ("Appearance" / eyebrow "Make it yours"), **live preview card** — a miniature Today screen (spent hero, status pill, duotone progress bar, week strip, mock FAB) rendered entirely in the *previewed* theme so every accent surface recolors on a swatch tap; **Mode selector** — System/Light/Dark as three mini-mock cards (free, applies instantly via `viewModel.appearanceMode`); **two theme grids** — Classics + Pastels, even-column adaptive grid (`EvenColumnGrid(minimumItemWidth: 84, evenColumnsAbove: 3)` since 2.2 — keeps 3 on phones; fixed 3-up before), swatches are duotone circles filled with each theme's `heroGradient` so the grid communicates the color *pair*, checkmark on saved, accent ring on preview, lock badge on Pro options for free users; **"Complete the look"** card — appears when the previewed theme has a `matchingIconId` that isn't the applied icon, one-tap applies the theme-matched app icon via `AppIconStore` (Pro-gated). **Sticky bottom Apply bar** (duotone fill in the previewed theme) is the only commit path — Pro lock / Apply / "is active" states. `HapticManager.shared.success()` on apply, `.warning()` on a paywall hit. |
| `AppIconPickerView` | `AppIconPickerView.swift` | Pro-gated alternate-app-icon picker. Same UX shape as `AppearanceStudioView` so users build muscle memory: **132 pt rounded-square hero preview** at the top (with shadow + soft scale animation on apply), even-column adaptive grid (`EvenColumnGrid(minimumItemWidth: 62)` since 2.2; fixed 4 columns before) of rounded icon tiles (8 options — Mauve primary + 7 alternates), and a **conditional Pro CTA** for previewed-but-locked picks. Active selection gets a `checkmark.circle.fill` badge; Pro-locked picks get a tiny lock badge. Wraps `appIconStore.apply(_:)` in a `Task`, surfacing `ApplyError` via an in-picker alert and reverting the preview on failure so the UI never lies. Hides itself entirely on devices where `UIApplication.shared.supportsAlternateIcons` is false (vanishingly rare but the official guard). |
| `CurrencyPickerView` | `CurrencyPickerView.swift` | Currency selection: "Recently Used" shortcut (`RecentCurrenciesStore`, cap 3, recorded only on active picks), region chips, search bar, checkmark list. `interactiveDismissDisabled` in setup mode. |
| `ManageCategoriesView` | `ManageCategoriesView.swift` | Default categories (context-menu Hide → moves expenses & subscriptions to Other, deletes budgets filtered to that category), deleted defaults (restore), custom categories (edit/delete/add via context menu + edit-form trash button). No swipe actions — rows live in a ScrollView, where `.swipeActions` is silently dead. |
| `SummaryCustomizationView` | `SummaryCustomizationView.swift` | **Orphaned on this branch** — it was the pinned-categories picker for the v1 Home screen and nothing presents it since `TodayView` replaced `HomeView` (`preferredSummaryCategoryTokens` is still loaded by `ExpenseViewModel+Preferences`). Historical description: pick up to 4 categories to pin on Home. Rebuilt around one idea: **the selected cards are the preview**. The large miniature-tile preview was retired (it competed with the real selection cards and shrank everything to fit). Replaced with a compact horizontal "Home line-up" chip strip at the top that confirms the picks in pinned order (empty slots render as dashed chips, horizontally scrollable for small screens). Below that, the selection grid uses beefed-up `CategorySelectionCard`s at a fixed 144 pt (iPhone) / 158 pt (iPad) height, mirroring the `PinnedCategoryCard` idiom — icon medallion tinted on selection, title (14 pt semibold), **20 pt rounded-bold amount in primary** for real decision data, expense count (12 pt medium secondary), checkmark badge, gradient tint + color border when selected. Unselected-and-disabled (when the lineup is full) eases from harsh 0.45 opacity to 0.62 so ghosted cards stay legible. Reset link surfaces only when selection differs from defaults; single floating Save bar. `maxSelections` is a single source of truth paired with `ExpenseViewModel.getSummaryCardsData`'s matching `prefix(4)` clamp. |
| `ExportDataView` | `ExportDataView.swift` | Choose **Complete Backup** (`.cashlens.json`), **Spreadsheet** (`.csv`) or **Full Archive** (`.cashlens-archive` — "Everything above + receipt photos"), export via `BackupExporter`, share via `UIActivityViewController`. Records backup metadata and posts `.backupMetadataDidChange`. |
| `ImportDataView` | `ImportDataView.swift` | `.fileImporter` (JSON, CSV, `.cashlens-archive` / `.zip`) → preview sheet (detected format, per-entity counts, receipt-photo count, column mapping + issues for foreign CSVs, Merge/Replace) → apply via `BackupImporter`. Foreign CSV import is Pro-gated at `startParse(url:)`. Post-import summary shows receipts restored / failed. |
| `DonationView` | `DonationView.swift` | StoreKit tip jar: gradient cards per product, processing overlay. |
| `AboutView` | `AboutView.swift` | Static info: features, contact (`AppConstants.supportEmail` = `rjadeja053@gmail.com`, unified in 2.2 — `redesign/v2` / store 2.1 hard-coded `email@rushiraj.me` here and in `StoreRecoveryView`), website, Privacy and Terms links (added for 2.0.0). |
| `DiagnosticsView` | `DiagnosticsView.swift` | `#if DEBUG` only. Data refresh, currency checks, smoke tests, "Reset Review Prompt State", and (2.2) the stress-seeder buttons — "Seed 5,000 test expenses" / "Seed 20,000 test expenses" behind a confirmation dialog, "Delete seeded data" (destructive, confirmed), a status line, and a footnote naming the `-CLSeedExpenses <n>` launch argument (see §23). Not wired to any entry point on this branch; attach it manually. |

---

## 8. Components

| Component | File | Description |
|-----------|------|-------------|
| `PinnedCategoryCard` | `PinnedCategoryCard.swift` | **Orphaned on this branch** (no call sites since `HomeView` was removed; `BudgetProgressCard` still mirrors its layout constants). Historical: premium Home pinned-category tile. Icon medallion + rounded amount (with `contentTransition(.numericText())`) + category title + expense-count line + optional thin budget progress bar when a budget exists for that category. Top-right **trend pill** (↑/↓ %, Flat, or New/sparkle) driven by the previous comparable period. Strong **selected** treatment (gradient border + soft color-tinted shadow) when the card is the active Recent-Expenses filter on Home. `ScaleButtonStyle`. |
| `ExpenseCard` | `ExpenseCard.swift` | Primary expense row. `Equatable` + precomputed fields for perf. Icon, title, category, notes, amount, date, inline tags (up to 3 + `+N`), paperclip badge when a receipt is attached, green Refund badge + negative amount for refunds. |
| `BudgetProgressCard` / `BudgetMiniCard` | `BudgetProgressCard.swift` | Pro budget progress tiles (ring / bar, over-budget state). iPad-aware heights. |
| `CategoryItem` | `CategoryItem.swift` | Horizontal default category chip with selection ring. `Equatable`, `drawingGroup`. |
| `CustomCategoryItem` | `CustomCategoryItem.swift` | Horizontal custom category chip. Same pattern as CategoryItem. |
| `CategoryDonutChart` | `CategoryDonutChart.swift` | Interactive donut + legend. Tap center clears selection, legend toggles slices. `drawingGroup` on ring. |
| `ExpenseTrendChart` | `ExpenseTrendChart.swift` | Custom `Path` line/area chart by time frame. Grid, tooltips, adaptive labels. `.adaptiveHeight` since 2.2. Takes `currencySymbol: String` explicitly (`3faca45`) instead of `@EnvironmentObject var viewModel` — the chart only ever read `viewModel.currencySymbol`, and observing the whole view model made Swift Charts re-lay out on every publish. |
| `TrendChartPager` | `TrendChartPager.swift` | Three-page Trend pager. Also takes `currencySymbol: String` (passed by `StatisticsView` as `viewModel.currencySymbol`) and forwards it to `ExpenseTrendChart`; its dead `@EnvironmentObject` and the redundant `.environmentObject(viewModel)` re-injection were removed in `3faca45`. `StatisticsView` still observes the VM and passes a fresh symbol on currency change. |
| `SpendingHeatmap` | `SpendingHeatmap.swift` | GitHub-style calendar heatmap (horizontal scroll). Tap day for total. Caps at 365 days. |
| `SubscriptionRow` | `SubscriptionRow.swift` | Redesigned subscription cell. Category icon, **single status line** (colored dot + one of `Paused` / `Overdue by N days` / `Due today` / `Due in N days` / `Renews Mar 20, 2026`) — all previous redundancy (inline PAUSED badge + bottom Paused label + separate due line + "Soon"/"Active"/"Overdue" status label) consolidated. Monthly equivalent is shown **only when frequency ≠ monthly** (removed pointless self-repeat for monthly subs). Trailing column shows the amount and, when due/overdue, a compact inline **Mark paid** pill (no full-row CTA). Row tap = edit via `onTapGesture` on the card (not an enclosing `Button` — the inline Mark-paid `Button` would nest unreliably inside one); long-press context menu = Edit / Pause–Resume / Mark as Paid / Delete. No swipe actions — rows render in a `LazyVStack`, where `.swipeActions` never functions. |
| `YearOverYearChart` | `YearOverYearChart.swift` | Pro: SwiftUI Charts grouped bars, this year vs last year. |
| `ForecastChart` | `ForecastChart.swift` | Pro: SwiftUI Charts renderer for `ForecastEngine.Forecast` (history line, dashed projection, ±1σ band, subscription dots). |
| `InsightInfoButton` | `InsightInfoButton.swift` | `info.circle` button + explanation sheet ("What it means / How it's calculated / Why it matters") used by every Insights section; copy lives in `InsightInfo`. |
| `TagChip` / `TagInputField` | `TagChip.swift`, `TagInputField.swift` | Smart Tags chip (4 styles) and chip-flow input with live autocomplete. |
| `DocumentScannerView` | `DocumentScannerView.swift` | `UIViewControllerRepresentable` over `VNDocumentCameraViewController`; `isSupported` guard; takes page 1 of a multi-page scan. |
| `SheetHeader` | `SheetHeader.swift` | Canonical sheet chrome (title, subtitle, close, optional trailing) used by every You-tab sheet and the appearance studio. |
| `SaveErrorBanner` / `SaveErrorBannerHost` | `SaveErrorBanner.swift` | Non-blocking, auto-dismissing banner rendered over the tab bar whenever `SaveErrorReporter.report(...)` posts `.saveErrorOccurred`. |
| `SaveConfirmationToast` / host | `SaveConfirmationToast.swift` | Short-lived floating capsule ("Added ₹450 to Food", "Added N expenses from your widget") posted via `SaveConfirmationReporter`. |
| `FloatingAddButton` | `FloatingAddButton.swift` | Circular FAB shown on Today / Insights and on Activity at compact width (hidden on You, in bulk-select mode, and on Activity at regular width). Medium haptic on tap. 2.2: disc is a **fixed** 56 pt (compact) / 66 pt (regular); only the glyph is `@ScaledMetric(relativeTo: .body)` (24 / 28) and clamped to `min(…, 34)` / `min(…, 40)` so Dynamic Type cannot grow the disc unbounded (`58fdbb2`). `.hoverEffect(.lift)`. |

---

## 9. Utilities

| Utility | File | Description |
|---------|------|-------------|
| `HapticManager` | `HapticManager.swift` | Singleton with cached `UIImpactFeedbackGenerator`s. Methods: `lightTap`, `mediumTap`, `heavyTap`, `success`, `warning`, `error`, `selectionChanged`. Pre-prepares generators. |
| `DeepLinkRouter` | `DeepLinkRouter.swift` | `ObservableObject` singleton. Parses notification `userInfo` and `cashlens://` URLs (`DeepLinkURLs`, scheme registered in `CashLens-Info.plist`) into `DeepLinkRoute` (`.allExpenses(filter)`, `.export`, `.addExpense` — the Quick Log widget's "+" button). Drives `.sheet(item:)` in `CashLensApp`. Routes that arrive while App Lock is up are parked and released by `flushPendingRoute()` on `.appDidUnlock`. |
| `AppLockManager` | `AppLockManager.swift` | `@MainActor` singleton for the free Face ID / Touch ID / passcode lock — see §21. |
| `QuickLogService` | `QuickLogService.swift` | Headless expense writes on a fresh background context for Siri intents and the widget queue drain; `spendingSummary()` for `GetSpendingIntent`; rebuilds the widget snapshot directly from the store; posts `.expensesChangedExternally`. Diagnostic trail is redacted in Release — see §20. |
| `ReceiptStorage` | `ReceiptStorage.swift` | Pure file IO for receipts: `Documents/Receipts/<uuid>.jpg`, JPEG 0.7, 2400 px max edge, filename-only references, `cleanupOrphans(keep:)`, `totalBytesUsed`. |
| `ReceiptOCRService` | `ReceiptOCRService.swift` | Pro: on-device `VNRecognizeTextRequest` (accurate, language correction, no network) → `ReceiptOCRResult` (total amount ranked by proximity to TOTAL / AMOUNT DUE keywords, merchant from the top of the receipt). `parse(lines:)` is a pure function over `[OCRLine]`. Always best-effort and silent. |
| `MonthlyRecapEngine` | `MonthlyRecapEngine.swift` | `MonthlyRecap` value + `compute(...)`: total vs previous month, top category, biggest expense, no-spend days + best streak, busiest day, subscription total, derived `Award`. `Sendable`, no IO; callers gate on full hydration. |
| `PaywallTrigger` | `PaywallTrigger.swift` | Pure rule for the post-value auto-paywall: only when a single save crosses `expenseThreshold = 10`, user is free, never auto-shown before, and outside a 7-day cooldown. Persistence stays at the call site (`MainTabView`). |
| `ReviewPromptManager` | `ReviewPromptManager.swift` | Rating-ask timing only (no UI); replaced `FeedbackManager` in 2.2 (`8de55d1`, refined by review fix `f98edeb`). **Policy:** ask **once per major.minor version** — `askVersionKey` is the first two components of `CFBundleShortVersionString`, stored in `reviewPromptAskedVersion`, so 2.2 → 2.2.1 is one ask — at a delight moment: `recordExpenseSaved(totalExpenseCount:)` when the count reaches `expenseThreshold = 10` (called from `ExpenseViewModel+CRUD.addExpense`, with `nil` when only the launch hot-window count is known so the threshold is never trusted early), or `recordStreak(days:)` when a no-spend streak reaches `streakThreshold = 7` (called from `TodayView`'s streak recompute, guarded: `previousStreak != nil` — i.e. not the cold-launch recompute — hydrated, streak `isMeaningful`, an expense in the last 30 days, because `StreakCalculator` reports a long "streak" for an empty ledger). **Presentation rules:** `canAsk` requires onboarding complete and not yet asked for this key; `arm()` → `schedule()` fires `sheetQuietInterval = 2 s` after the later of now and the last `noteSheetDismissed()` (called by `MainTabView` when the add sheet closes), so the ask lands on a settled screen; `paywallDidAppear()` cancels the scheduled fire and `fireIfStillAllowed()` refuses while `isPaywallVisible` — the 10th-expense auto-paywall takes the moment and the ask stays pending for the next save; `paywallDidDisappear()` does **not** re-arm. `fireIfStillAllowed()` only publishes `shouldRequestReview = true`; it no longer writes the version key or clears `isPending`. The observer (`MainTabView`) calls `consume()`, then either `deferWhilePresenting()` (cancel timer, stay pending — App Lock up or `hasPresentation`; the next trigger or sheet dismiss reschedules) or `markRequested()` (writes the key, clears pending) immediately before `requestReview()`. So a blocked ask is never spent. Not `@MainActor` (triggers arrive from `ExpenseViewModel`). `resetForDebugging()` is `#if DEBUG` and wired only to `DiagnosticsView`. Apple's 3-per-365-days throttle is the backstop. Store 2.1 shipped the older `FeedbackManager` rule (12 actions across 3+ days or 5 after an export, 30-day cooldown, max 3). |
| `AppConstants` | `AppConstants.swift` | `supportEmail = "rjadeja053@gmail.com"` + `supportMailURL(subject:)`. Single source for the support address (2.2); used by `AboutView` and `StoreRecoveryView`. |
| `AppCommandCenter` / `AppCommands` | `AppCommands.swift` | 2.2 hardware-keyboard support (iPad, Duo with a keyboard). `AppCommands: Commands` is attached once via `WindowGroup { … }.commands { AppCommands() }` in `CashLensApp` and declares a `CommandGroup(after: .newItem)` with `Label`s (so the iPadOS Cmd-hold HUD names them): **Cmd-N** New Expense, **Cmd-F** Search Expenses, **Cmd-,** Settings. Each button sends an `AppCommandCenter.Command` (`newExpense`, `searchActivity`, `presentActivitySearch`, `openSettings`) through a `PassthroughSubject` (not `@Published`, so late subscribers never replay); `MainTabView` and `AllExpensesView` subscribe. **Esc** is not declared here: `SheetCloseButton(action:respondsToEscape:)` (`Components/SheetHeader.swift`) applies `.keyboardShortcut(respondsToEscape ? KeyboardShortcut.cancelAction : nil)` so every custom-chrome sheet closes through its own dismiss path (including `AddExpenseView.onDismissRequest`). `SheetHeader(escapeClosesSheet:)` (default `true`) forwards that flag so only the **topmost** sheet answers Esc (`5121e1a`): `AddExpenseView` passes `!hasPresentationAbove` (scanner, receipt viewer, receipt paywall, templates, manage categories, category picker, date picker, field editor), `AddSubscriptionView` `!showingCategoryPicker && !showingDatePicker`, `BudgetSetupView` `!showingCategoryPicker && !showingProPaywall`; the three category-picker Done buttons gained Esc. Lone close buttons (Paywall, Recap, Summary) keep the default. The root Done / Cancel buttons of Export, Import, ManageCategories, Diagnostics, About, AppIconPicker and SiriShortcutsTips carry `.keyboardShortcut(.cancelAction)` directly. |
| `SaveErrorReporter` / `SaveConfirmationReporter` | `SaveErrorReporter.swift` | Every `context.save()` catch site posts `SaveErrorReporter.report(operation:error:)`; the banner host in `MainTabView` renders it. Success sibling posts the confirmation toast. |
| `BudgetAlertState` | `BudgetAlertState.swift` | UserDefaults-backed last-utilization + fired flags per budget per period so 80% / 100% alerts fire only on an upward crossing. |
| `RecentCurrenciesStore` | `RecentCurrenciesStore.swift` | Most-recent-first list of actively picked currencies (cap 3) for the picker's "Recently Used" row. |
| `WidgetSnapshotBuilder` / `WidgetSnapshotCoordinator` | `WidgetSnapshot*.swift` | Widget data pipeline — see §19. |
| `Zip/` | `CRC32.swift`, `ZipWriter.swift`, `ZipReader.swift` | Pure-Swift STORE-only zip used by `.cashlens-archive`; reader verifies CRC-32 on every extraction and rejects ZIP64. |
| `ExpenseFilter` | `ExpenseFilter.swift` | Pure function `apply(expenses:category:customCategoryId:timeFrame:referenceDate:)`. Also supports explicit date range `[start, end)`. |
| `NotificationScheduler` | `NotificationScheduler.swift` | Schedules one-shot weekly/monthly digest, backup reminder, and the **Pro Smart Insights** weekly push via `UNUserNotificationCenter`. `DigestStatsCalculator` powers digest bodies; `scheduleNextSmartInsight(viewModel:)` evaluates `SmartInsightsEngine` on every foreground refresh and only schedules when an insight clears the firing bar. Since `9973bfa` the inputs (expenses, subscriptions, `UserDefaults` history, name lookup, `formattedAmount`) are still gathered on the main actor but `SmartInsightsEngine.selectInsight(inputs:)` runs in `Task.detached(priority: .utility)` and is awaited — it used to run synchronously on main at foreground. `refreshScheduledNotificationsIfNeeded(viewModel:isPro:)` is the single entry point — `isPro` gates Smart Insights without leaking ProManager into the scheduler. |
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
| `NotificationExtension.swift` | `Notification.Name` constants: `.appearanceDidChange`, `.dataDidClear`, `.subscriptionCurrencyUpdated`, `.currencyDidChange`, `.backupMetadataDidChange`, `.expensesChangedExternally`, `.appDidUnlock`, `.insightsRequestTimeFrame` (others such as `.themeDidChange`, `.saveErrorOccurred`, `.backupImportDidComplete` are declared next to their owners) |
| `ViewExtensions.swift` | `.if(_:transform:)` conditional modifier, `cornerRadius(_:corners:)` per-corner rounding via `RoundedCorner` shape |

---

## 11. Design System

The app has a formal design system under `CashLens/Design/`. All UI code should reach for tokens and shared components from this folder instead of hard-coded values. This keeps every screen visually coherent and makes future redesigns a one-file change.

### Tokens (`Design/Theme.swift`)

One namespace, `Theme`, with nested token families. Pick the **role**, not a raw number.

| Family | Members | Purpose |
|--------|---------|---------|
| `Theme.Spacing` | `xxs(2)`, `xs(4)`, `sm(8)`, `md(12)`, `lg(16)`, `xl(20)`, `xxl(24)`, `xxxl(32)`, `scrollBottomClearance(100)` | Rhythm for padding and `VStack` / `HStack` spacing. `tabBarInset(100)` was **renamed and re-derived in 2.2** (`46b7404`, `afdb5ce`): `scrollBottomClearance` = 12 pt gap + 56 pt FAB + 32 pt breathing room = 100, used by Today, Insights, the Activity list spacer and the embedded calendar. The tab bar itself is *not* part of the number — on iOS 26 the system `TabView` insets content via the safe area, and the legacy custom bar adds a matching `.safeAreaPadding` on each tab root. (A first cut set it to 32; the review found the FAB then covered the last row's amount on every iPhone.) |
| `Theme.Radius` | `chip(12)`, `row(14)`, `card(16)`, `container(18)`, `hero(22)` | Corner radii — never use naked `cornerRadius(14)` style numbers in views |
| `Theme.Stroke` | `hairline(0.5)`, `thin(1)`, `medium(1.5)` | Border widths |
| `Theme.Typography` | `pageTitle`, `sectionTitle`, `subsectionTitle`, `rowTitle`, `caption`, `numeric`, `numericSmall` | Semantic type styles |
| `Theme.Shadow` | `cardColor/Radius/Y`, `elevatedColor/Radius/Y` | Elevation |
| `Theme.Motion` | `snappy`, `tap`, `emphasized` | Only three animations — use them everywhere |
| `Theme.Icon` | `chip(13)`, `row(18)`, `heroRow(22)`, `emptyState(36)` | SF Symbol sizes per role |

**Gradient helper** on `LinearGradient`:

- `.appDuotone` — the ONE sanctioned gradient in the app: active theme's primary → primary blended 45 % toward the theme's secondary (`AppTheme.heroGradient`). Reserved for hero brand moments only — the FAB, `PrimaryGradientButton`, the Today first-expense CTA, and the Appearance studio's Apply bar. Everything non-hero stays solid. Exists so the user's chosen theme reads as the designed color *pair* every `AppTheme` ships, not a single flat accent.

> **Note (Personalization):** `Color.appPrimary`, `Color.appSecondary`, and `Color.appPrimaryBlend` are **computed dynamic colors** that read `ThemeStore.activeTheme` at render time. They resolve through `Color(UIColor { trait in ... })` so light/dark adaptation still happens automatically per theme — every theme ships hand-tuned light + dark hex pairs. `appPrimaryBlend` is derived via `UIColor.mixed(with:amount:)` rather than a third hand-tuned hex.

### View modifiers (`Design/ViewModifiers.swift`)

| Modifier | Purpose |
|----------|---------|
| `.cardSurface(radius:fill:stroke:strokeWidth:)` | Canonical card background — replaces hand-rolled `RoundedRectangle(...)  + .fill(.secondarySystemBackground)` |
| `.sectionContainer(padding:)` | Outer tinted wrapper for grouped sections (Profile blocks, iPad Home blocks) |
| `.softShadow()` | Subtle card elevation for things that need to float |
| `.primaryGlow(strength:)` | Mauve-tinted glow for primary CTAs |
| `.adaptiveHeight(ratio:min:max:)` | 2.2 (`AdaptiveHeightModifier`): width-derived, clamped height for charts and other full-width blocks; compact height (landscape phone) caps at 60 % of the regular max. Replaced the fixed 200 / 280 / 300 pt chart heights in `ExpenseTrendChart`, `TrendChartPager`, `ForecastChart`, `YearOverYearChart` |
| `.readableColumn(maxWidth: 680)` | 2.2 (`ReadableColumnModifier`): centers content in a capped-width column on **regular width only**. Applied to Today (680), You (680) and Paywall (640) so iPad / Duo inner do not stretch a phone column edge to edge |

### Adaptive grid (`Design/Components/EvenColumnGrid.swift`, 2.2)

`EvenColumnGrid` is a `LazyVGrid` whose column count is derived from the measured container width with the same arithmetic as `GridItem.adaptive`, then **rounded down to an even number** when the count is greater than `evenColumnsAbove` (default 2). Apple's iPhone Duo guidance is for grids to prefer even column counts so no tile straddles the fold in a partially folded pose; phones and iPads get the counts they had (4 on an iPhone category picker, 6 in an iPad form sheet), while the 5s and 7s that pure adaptive layout produces at in-between widths become 4s and 6s. Before the first `onGeometryChange` measurement it renders 2 columns rather than one stretched column. Column spacing is widened by `DuoLayoutSupport.divisionGutter(in:)` (0 everywhere today). It replaced the `GridItem(.adaptive(...))` grids from `7a4e291` at every picker:

| Grid | `minimumItemWidth` | Notes |
|------|--------------------|-------|
| Category pickers in `AddExpenseView`, `AddSubscriptionView`, `BudgetSetupView` | 74 | 4 on phones / 6 in an iPad form sheet / 6 on Duo inner (instead of 7) |
| `AppIconPickerView` | 62 | |
| `AppearanceStudioView` | 84, `evenColumnsAbove: 3` | keeps 3 on phones |
| `SummaryCustomizationView` | 160 | 2 / 4 (view is orphaned — no call sites) |

Insights' 2-column layout (`StatisticsView.usesTwoColumns`) requires regular width **and** a measured content width ≥ `twoColumnMinimumWidth = 640` (`onGeometryChange` on the `ScrollView`, `d33ab47`) — a 50/50 iPad split is regular but would give two columns narrower than an iPhone SE. Padding and the 1200 pt cap still key off `isWideLayout` alone. Today has no grid.

### iPhone Duo iOS 27.1 stubs (`Design/DuoLayoutSupport.swift`, 2.2)

The Duo-specific layout APIs (`ArrangementView`, `toolbarVerticalBehavior`, `toolbarCompressionBehavior`, `GeometryProxy.reservedRegions(kind:)`) are iOS 27.1 / Xcode 27.1 and are not in the release Xcode 27 SDK that 2.2 ships with; their exact spellings are not documented yet. Every line that names one lives in this file inside `#if CASHLENS_DUO_27_1` **and** `if #available(iOS 27.1, *)`. The compilation condition is **defined nowhere** (not in `project.pbxproj`), so on today's SDK each helper compiles to a plain no-op and the rest of the app sees exactly one call per site:

| Helper | Call site | Today | Intended (27.1) |
|--------|-----------|-------|-----------------|
| `View.duoHorizontalToolbar()` | `PaywallView` root, `AddExpenseView` root | `self` | `toolbarVerticalBehavior(.never)` — single-Close sheets keep a horizontal bar on the outer display |
| `View.duoTabBarCompression()` | iOS 26 `TabView` in `MainTabView` | `self` | `toolbarCompressionBehavior(.tabBarFirst)` — tab bar compresses before the add action |
| `DuoArrangement { primary } secondary: { … }` | `TrendChartPager` (page tab bar + chart pager / dots) | plain `VStack` | `ArrangementView(.split)` so the two halves sit on opposite sides of a partially folded inner display |
| `DuoLayoutSupport.divisionGutter(in:)` | `EvenColumnGrid.onGeometryChange` | returns 0 | max width of `proxy.reservedRegions(kind: .division)` — widens the middle gutter so it clears the hinge |

To finish for 2.2.1: add `CASHLENS_DUO_27_1` to Active Compilation Conditions, fix every line marked `// Duo 27.1` against the real SDK, build, and drop the flag again if the SDK is not ready. The TODO list is in `PRO_FEATURES.md` → Version Plan (2.2.1). Deployment target stays iOS 18.

### Toolbar and safe-area conventions (2.2, Duo prep)

- Toolbar items that carry a symbol use `Label(_:systemImage:).labelStyle(.titleAndIcon)` so the system can lay them out vertically on the Duo outer display (`AllExpensesView` "Back", `ExpenseCalendarView` "Month"). Text-only items (Done, Cancel, Save, Apply, Close, Select, Manage) stay text, per Apple. Deprecated `navigationBarItems` is gone — `ExportDataView` / `ImportDataView` use `ToolbarItem(placement: .confirmationAction / .cancellationAction)`.
- Every `ignoresSafeArea` in the app is a background fill, dimming overlay, the `AppLockView` cover, or a full-screen system view (document camera, receipt zoom). Headers live inside padded `ScrollView`s; the paywall CTA is in the scroll or a `safeAreaInset`; the FAB overlays the `TabView`'s safe-area frame; the legacy bar ignores only the bottom edge. No code change was needed for Duo safe-area compliance.
- Nothing is keyed on orientation or `userInterfaceIdiom` (the one remaining idiom read in `PrivacyDashboardView` is copy-only), so a fold that changes only the size class cannot pick a different screen. Expected fold behaviour: `MainTabView` state survives the bar ↔ sidebar swap; Activity's sheets are attached outside `activityNavContainer` and survive the two-pane ↔ stack swap while the editor moves between sheet and detail pane (unsaved field edits do not carry over; child state such as the embedded calendar month resets); onboarding `currentStep` and paywall `selectedPlan` persist while their layout flips on `verticalSizeClass`.

### Hover (2.2)

Pointer-only, no-op on touch: `.hoverEffect(.highlight)` on `ExpenseCard`, `SubscriptionRow` and the category tiles in the Add Expense / Add Subscription / Budget pickers; `.hoverEffect(.lift)` on `FloatingAddButton`, `PinnedCategoryCard` and `BudgetMiniCard`.

### Multiple scenes — deliberately off (2.2 decision)

`UIApplicationSupportsMultipleScenes` is not set, so iPad Stage Manager / Duo second-window is one window per app. Reasons, from the 2.2 audit: `AppLockManager` is a singleton with one `isSceneActive` flag driven by whichever scene changed phase last (a second window backgrounding would lock or cover the active one) and a global grace timestamp; `DeepLinkRouter.shared.route` is one `@Published` sheet binding attached to `MainTabView` in every scene (one widget tap would present in every window); `UserDefaultsKeys.expenseDraft` is a single slot (two Add Expense sheets would clobber each other's draft); `WidgetSnapshotCoordinator.bootstrap` runs from each scene's `onAppear`. Core Data and `ProManager` would be fine. Enabling needs per-scene lock state, per-scene routing and a guarded bootstrap — 2.3 work if multi-window ever matters.

### Shared components (`Design/Components/`)

| Component | Purpose |
|-----------|---------|
| `SectionHeader(title:style:trailing:)` | Canonical in-page section header. Styles: `.page`, `.section`, `.subsection` |
| `SectionHeaderLink(title:icon:action:)` | "See All" / "Customize" style trailing link |
| `PillChip(title:icon:isSelected:shape:fullWidth:action:)` | Filter / selection chip. Shape: `.capsule` or `.rounded` |
| `PrimaryGradientButton(title:icon:width:isEnabled:action:)` | Primary CTA — "Create Budget", "Save Changes". Fill is the sanctioned `LinearGradient.appDuotone` |
| `SecondaryOutlineButton(title:icon:width:action:)` | Outline companion to primary CTA |
| `EmptyStatePanel(icon:title:message:action:)` | Full-screen empty state: large hierarchical symbol (no bubble), title + message + CTA, one-shot bounce on appear |
| `InlineEmptyState(icon:title:message:)` | Compact empty state for inside lists/cards — hierarchical tertiary symbol |
| `HeroGlyph(systemName:tint:size:)` | Hero symbol for sheet headers — hierarchical rendering, replaces the old tinted-circle medallion |
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

The adoption log below was written during the v1 → Pro migration (Phases B–F) and is kept as history. Note that `HomeView` no longer exists — it was replaced by `TodayView` in the v2 redesign (commit `777ee11`, 2026-05), which was built on the design system from the start. All v2 screens (`TodayView`, `TodayCustomizeView`, `AppLockView`, `StoreRecoveryView`, `PrivacyDashboardView`, `NotificationsSettingsView`, `SiriShortcutsTipsView`, `MonthlyRecapView`, `WinBackView`, `DonorThanksView`, `AppearanceStudioView`) use `SheetHeader` / `HeroGlyph` / `.cardSurface()` / `Theme.*` tokens.

| Screen | Status |
|--------|--------|
| `HomeView` (removed in v2) | Was fully migrated (Phase B) + redesigned landing before being replaced by `TodayView` |
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

> Historical log from the v1 → Pro migration. References to `HomeView` describe the screen that `TodayView` replaced; the `StatisticsView`, `AllExpensesView`, `ProfileView` and view-model items still apply.

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
- `SKStoreReviewController.requestReview(in:)` replaced with SwiftUI's `@Environment(\.requestReview)` action (now invoked from `MainTabView`); removes the window scene lookup entirely and the `StoreKit` duplicate import.

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

**Phase 2 — Stop O(N) work on main-thread hot paths (low–medium risk, high impact):** *(the `HomeView` items below predate the v2 `TodayView`, which recomputes its aggregates on a single debounced detached task)*
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
- `DonationManager` — singleton, loads products, handles purchase, records purchased IDs. It does **not** run its own `Transaction.updates` loop (see below).
- `DonationView` — UI with gradient cards per product
- Entry point: "Support the App" row in `ProfileView` → About
- `SKIncludeConsumableInAppPurchaseHistory = YES` in `CashLens-Info.plist` so finished consumables stay visible in `Transaction.all` for donor grandfathering.

### CashLens Pro (Subscriptions + Lifetime)

**Decision (Rushiraj, 2026-09-19): subscriptions AND lifetime both stay.** Monthly, yearly and lifetime are all offered; none is being retired.

**StoreKit 2 auto-renewable subscriptions** + one non-consumable lifetime purchase (`CashLens/Donations.storekit`):

| Product ID | Type | Price (USD) | Trial |
|------------|------|-------------|-------|
| `com.cashlens.pro.monthly` | Auto-Renewable | $2.99/mo | 7-day free |
| `com.cashlens.pro.yearly` | Auto-Renewable | $19.99/yr | 7-day free |
| `com.cashlens.pro.lifetime` | Non-Consumable | $39.99 | — |

The two subscriptions belong to subscription group `"CashLens Pro"` (group ID `D4E8F2A1`); the lifetime product is a separate non-consumable. All three plus the three tips are listed on the live App Store page. Apple handles international pricing — `Product.displayPrice` shows the user's local currency.

**`ProManager` (`Models/ProManager.swift`)** — `@MainActor` singleton `ObservableObject`:
- `@Published isPro` = live StoreKit entitlement **OR** active donor grant, recomputed in `recomputeIsPro()` on launch, every foreground (`CashLensApp`), every `Transaction.updates` delivery, purchase and restore. Entitlement is always re-derived from `Transaction.currentEntitlements` — an update is never treated as a grant, so refunds/revocations are honored.
- **Single transaction listener** for the whole app: routes Pro IDs to `checkEntitlements()`, donation IDs to `DonationManager.recordPurchasedProductID(_:)` then `scanForDonorGrant()`, and finishes each transaction exactly once (unverified ones are finished without granting).
- `isEligibleForIntroOffer` — defaults to `false`; refreshed after products load and when the paywall opens so "Start free trial" copy is only shown when StoreKit confirms eligibility (intro offers are once per Apple ID).
- **Donor grandfathering** — `scanForDonorGrant()` walks `Transaction.all` on launch (after products load) and after restore: any verified Lunch/Fuel ($4.99+) tip → `DonorGrant.founder` (permanent local Pro); Coffee only → `DonorGrant.yearOfPro` (365 days from first detection, date written once, never re-granted). One-time `DonorThanksView`; consumed on the sheet's `onAppear`.
- **Win-back** — `recomputeIsPro()` sets `winBackPending` on a Pro → free lapse (unless an active donor grant covers the user); `evaluateWinBackPrompt()` runs on foreground / after unlock and shows `WinBackView` at most once per lapse, never after "No thanks" (`winBackDeclined`), never while App Lock is up.
- **Promoted In-App Purchases** — `listenForPurchaseIntents()` iterates `PurchaseIntent.intents` and completes purchases started on the App Store product page. Pro IDs go through `purchase()`; tip IDs go through `DonationManager.purchase()` so a promoted tip is never dropped (`7289d22`, 2.2 — the `redesign/v2` version was Pro-only). Required for App Store Connect promotions to display. **Unshipped** relative to store 2.1 (commit `4f702fa`); promo images live in `Marketing/PromoImages/` and only Pro products are promoted in ASC.
- **Paywall truth-pass (2.2, `9c9d840`)** — tip-jar and lifetime copy no longer implies the app has no subscription ("one-time tips, separate from CashLens Pro"; "One payment for the lifetime unlock. Never renews."); the paywall feature line reads "Budgets, receipt scanning, forecasts, PDF reports & more".
- `purchase(_:)`, `restorePurchases()` (`AppStore.sync()` + entitlement check + donor rescan), `yearlySavingsPercent`.

**Surfaces:**
- `PaywallView(context:)` — full-screen upgrade UI with feature list, monthly/yearly/lifetime plan cards, trial badge (eligibility-gated), savings percentage, restore, Apple standard EULA link. `PaywallContext` (`general`, `budgets`, `receipts`, `tags`, `themes`, `icons`, `insights`, `forecast`, `reports`, `importFormats`) tailors the headline to the feature that opened it. 2.2: `.readableColumn(maxWidth: 640)` on regular width; the 13 `.fixedSize(horizontal: false, vertical: true)` hits in Paywall / Import were audited and kept (they prevent truncation on wrapping text, not reflow); on compact height (`verticalSizeClass == .compact`) the header goes horizontal (glyph beside title) and the CTA moves into a `.safeAreaInset(edge: .bottom)` bar so it is always above the fold; eight `@ScaledMetric`s for medallions / glyphs / radio; `.duoHorizontalToolbar()` on the root (no-op today); calls `ReviewPromptManager.paywallDidAppear()` / `paywallDidDisappear()`.
- **Post-value auto-paywall** — `MainTabView` evaluates `PaywallTrigger` when the add-expense sheet closes; shows once ever, 1.2 s after the save that crosses 10 expenses, never over App Lock.
- **ProfileView** — Pro card (upgrade or Active), Restore Purchases row for free users.
- **Feature gating** — check `proManager.isPro` (environment object) at the call site. Gated today: budgets, tag *filtering* + bulk-tag, themes + alternate icons, Pro Insights, Forecast, PDF report, Payment Methods donut, receipt *capture* + OCR, foreign CSV import, Smart Insights notification, Budget / Subscriptions / Streak widgets, extra Quick Log templates. Everything else — including App Lock, Monthly Recap, Siri intents, widgets' Spending Snapshot — is free.

**UserDefaultsKeys:** `hasSeenPaywall`, `paywallImpressionCount`, `hasAutoShownPaywall`, `lastAutoPaywallDate`, `donorGrantType`, `donorGrantDate`, `donorGrantThanksShown`, `lastKnownIsPro`, `winBackPending`, `winBackDeclined`.

---

## 13. Notifications

### Types

1. **Weekly Spending Digest** — Scheduled on configurable weekday/time. Body includes total spent, category breakdown, comparison to previous week.
2. **Monthly Spending Digest** — Scheduled on configurable day of month/time. Similar body with monthly stats.
3. **Backup Reminder** — Scheduled reminder to export data. Shows days since last backup.
4. **Subscription Due Reminders** — Per-subscription, X days before due date. Calendar-based trigger. `SubscriptionViewModel.reconcileOverdueSubscriptions()` rolls past-due subs forward on foreground so reminders re-arm instead of dying after one cycle.
5. **Budget Alerts (Pro)** — 80% / 100% upward crossings, per budget per period (`BudgetAlertState`); opens Activity filtered to the budget's period + category.
6. **Smart Insight (Pro)** — one weekly push (default Sunday 10 AM) only when `SmartInsightsEngine` finds something notable; opt-in via `NotificationsSettingsView`.

`NotificationScheduler.refreshScheduledNotificationsIfNeeded(viewModel:isPro:)` runs on every foreground after `waitUntilFullyHydrated()`; a `scheduledNotificationsFingerprint` skips the full reschedule when settings, fire dates and data shape are unchanged. `AppDelegate` is the `UNUserNotificationCenterDelegate` (banner + list + sound + badge in foreground).

### Deep Links

Notification taps and `cashlens://` URLs route through `DeepLinkRouter`:
- Weekly/monthly digest, budget alert, smart insight → `AllExpensesView` with a filter
- Backup reminder → `ExportDataView`
- `cashlens://add-expense` (Quick Log widget "+" button) → `AddExpenseView`
- While App Lock is up the route is parked and presented after `.appDidUnlock`

### Permission Flow

- Not requested on launch
- Requested contextually when user enables reminders or notification-dependent features
- `NotificationsSettingsView` owns every schedule toggle; `ProfileView` shows an "N active" badge

---

## 14. Import / Export

The backup/restore pipeline lives in `CashLens/Backup/` and is intentionally split into four small, single-purpose files. The legacy `ExpenseViewModel+ImportExport.swift` is kept only as a thin compatibility shim that delegates to these modules.

```
CashLens/Backup/
├── BackupBundle.swift        # Codable schema (v2)
├── BackupExporter.swift      # Snapshot store + write JSON / CSV / .cashlens-archive
├── BackupImporter.swift      # Detect format, parse, apply with mode, restore receipts
└── GenericCSVAdapter.swift   # Mint / YNAB / bank-statement CSV ingest
CashLens/Utilities/Zip/       # Pure-Swift STORE-only zip used by the archive format
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

Three formats are exposed in `ExportDataView` (`BackupExporter.Format`):

| Format | Extension | Contents | Use for |
|---|---|---|---|
| **Complete Backup** | `.cashlens.json` | Entire `BackupBundle` (all entities + preferences) | Full restore on a new device |
| **Spreadsheet** | `.csv` | Flat, RFC 4180 CSV of expenses only (includes `Is Refund`, `Tags`, `Payment Method` columns) | Analysis in Numbers / Excel / Sheets |
| **Full Archive** | `.cashlens-archive` | STORE-only zip: `data.json` (byte-identical to the Complete Backup) + `receipts/<filename>.jpg` for every referenced receipt | Moving receipts to a new device; the only way receipt photos leave the phone |

Implementation details:

- `BackupExporter.buildBundle()` runs on a background context (`performAndWait`), snapshots all entities + reads relevant `UserDefaultsKeys`, and returns a fully-typed `BackupBundle`.
- JSON is written with `JSONEncoder` + `.prettyPrinted` + `.sortedKeys`, ISO 8601 dates.
- CSV is written via `BackupExporter.writeCSV(_:)` — RFC 4180-compliant: every field passes through `csvEscape` (quotes, commas, newlines, leading `=` / `+` / `-` / `@` for spreadsheet-formula safety). Dates are ISO 8601 (locale-independent). The header includes an `Is Refund` column (`true` / `false`) so refund flags round-trip through CSV exports; older importers that don't know the column simply ignore it.
- Files are written into `FileManager.default.temporaryDirectory` with timestamped names like `CashLens_2026-04-25_113000.cashlens.json`.

### 14.3 Import Pipeline (`BackupImporter`)

`ImportDataView` drives a three-step UX: **pick → preview → apply**.

#### Step 1 — Pick

`fileImporter` accepts `.json`, `.commaSeparatedText`, a custom `UTType` for `.cashlens.json`, `UTType(filenameExtension: "cashlens-archive")` and `.zip` (share extensions sometimes re-stamp the archive). The selected URL is forwarded to `BackupImporter.preview(url:fallbackCurrency:)` on a `Task.detached` so the UI never stalls. The archive type is **not** registered system-wide (no `UTExportedTypeDeclarations`), so tapping a `.cashlens-archive` in Files does not open CashLens — the user imports it from inside the app.

#### Step 2 — Detect & Parse

`BackupImporter.detectFormat(data:fileName:)` inspects the file and returns one of:

| `DetectedFormat` | Heuristic | Pro-gated |
|---|---|---|
| `.cashlensJSONv2` | JSON with `schema.version >= 2.0` | No |
| `.cashlensJSONv1` | JSON with `exportVersion: "1.0"` (legacy) | No |
| `.cashlensCSVv1` | Text starting with `=== EXPENSES ===` | No |
| `.cashlensArchive` | File name ends in `.cashlens-archive` / `.cashlens-archive.zip`; opened with `ZipReader`, `data.json` parsed for the preview | No |
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

0. (`.cashlensArchive` only) Restore every `receipts/*` entry to `Documents/Receipts/` (path-traversal sanitised) **before** Core Data is touched; counts land in `ImportSummary.receiptsRestored` / `receiptsFailed`.
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
| Export Full Archive (`.cashlens-archive`) | ✅ | ✅ |
| Import CashLens backup / archive (any version) | ✅ | ✅ |
| **Import foreign CSV** (Mint, YNAB, bank statement) | 🔒 → `PaywallView` | ✅ |

Gating is enforced in `ImportDataView.startParse(url:)`: if `preview.format.requiresPro && !proManager.isPro`, the paywall is presented instead of the preview sheet.

### 14.5 Backup Health

`ProfileView` shows backup health (warning banner when not `.good`, plus Last Backup / Total Backups rows) backed by `UserDefaults` keys (`lastBackupDate`, `lastBackupFormat`, `totalBackupCount`). It listens to the targeted `.backupMetadataDidChange` notification (posted by `ExportDataView.recordBackup` and on clear-all) — not the global `UserDefaults.didChangeNotification`, which used to fire on every unrelated preference write (Phase G).

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
App Launch (CashLensApp)
  ├─ StoreRecoveryView                     # only if PersistenceController.storeLoadFailed
  ├─ AppLockView (zIndex 10)               # overlay whenever AppLockManager.isCoverVisible
  ├─ OnboardingView (zIndex 1, first launch only)
  │   └─ CurrencyPickerView (sheet, isInitialSetup, once)
  └─ MainTabView  (+ FloatingAddButton on Today / Activity / Insights → AddExpenseView)
      ├─ Tab: Today — TodayView
      │   ├─ → AddExpenseView (edit, from recent rows)
      │   ├─ → BudgetListView (sheet, budgets section)
      │   ├─ → MonthlyRecapSheet (sheet, recap card)
      │   ├─ → TodayCustomizeView (sheet)
      │   ├─ "See all activity" → Activity tab
      │   └─ header arrows → Insights tab (.insightsRequestTimeFrame)
      │
      ├─ Tab: Activity — AllExpensesView(isRootTab: true)
      │   ├─ → QuickSearchView (sheet, search field)      └─ → AddExpenseView (edit)
      │   ├─ ExpenseCalendarView (embedded, List/Calendar toggle)  └─ → AddExpenseView (edit)
      │   ├─ → AddExpenseView (edit, row / context menu)
      │   ├─ → date-range sheet, bulk Category / Tag (Pro) sheets
      │   └─ Tags filter chip → PaywallView (free users)
      │
      ├─ Tab: Insights — StatisticsView
      │   ├─ → PaywallView (Pro Insights / Forecast / Payment Methods teasers, PDF lock badge)
      │   ├─ → ShareSheet (PDF report, Pro)
      │   ├─ → MonthlyRecapSheet (Monthly Recap row)
      │   ├─ → InsightExplanationSheet (every InsightInfoButton)
      │   └─ → AddExpenseView (empty state)
      │
      └─ Tab: You — ProfileView (all destinations are sheets)
          ├─ → PaywallView                       ├─ → CurrencyPickerView
          ├─ → SiriShortcutsTipsView             ├─ → AppearanceStudioView
          ├─ → AppIconPickerView                 ├─ → BudgetListView → BudgetSetupView
          ├─ → ManageCategoriesView → CustomCategoryForm
          ├─ → SubscriptionsView → AddSubscriptionView
          ├─ → NotificationsSettingsView         ├─ → PrivacyDashboardView
          ├─ → ExportDataView                    ├─ → ImportDataView (→ ImportPreviewSheet → ImportSummarySheet)
          ├─ → DonationView                      └─ → AboutView

Root-level sheets (MainTabView): AddExpenseView (FAB / widget), CurrencyPickerView,
  PaywallView(context: .insights) (auto-paywall), DonorThanksView, WinBackView, native requestReview

AddExpenseView children: DocumentScannerView (fullScreenCover), PhotosPicker, ReceiptViewerView,
  ManageCategoriesView, PaywallView(context: .receipts / .tags)

Deep Links (notifications + cashlens://, via DeepLinkRouter, parked while locked):
  ├─ .allExpenses(filter) → AllExpensesView (sheet from root)
  ├─ .export → ExportDataView (sheet from root)
  └─ .addExpense (cashlens://add-expense, Quick Log widget "+") → AddExpenseView (sheet from root)
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

### Out-of-process boundaries
- **Widget extension** never opens Core Data; it reads `WidgetSnapshot` JSON and writes `PendingExpenseRecord` files in the App Group
- **App Intents** are declared in the app target so they run in the app process (headless, no scene) and write through `QuickLogService` on a background context
- The Core Data store lives in the app container, **not** the App Group — moving it was judged too risky for live installs

### Naming Conventions
- Views: `*View.swift` (e.g., `TodayView.swift`)
- ViewModels: `*ViewModel.swift` or `*ViewModel+*.swift` for extensions
- Models: Named after domain concept (`Expense.swift`, `Subscription.swift`)
- Components: Named after what they render (`SummaryCard.swift`, `ExpenseCard.swift`)
- Utilities: Named after their function (`HapticManager.swift`, `ExpenseFilter.swift`)

### Notification Names
- `.appearanceDidChange` — Posted when appearance mode changes
- `.dataDidClear` — Posted after `clearAllData()`
- `.subscriptionCurrencyUpdated` — Posted after bulk currency sync on subscriptions
- `.currencyDidChange` — Posted when the user picks a new currency; flushes formatted-string caches
- `.backupMetadataDidChange` — Posted by export / clear-all; refreshes Profile's backup rows
- `.expensesChangedExternally` — Posted after a headless write (Siri intent, widget queue drain)
- `.appDidUnlock` — Posted by `AppLockManager` after a successful unlock
- `.insightsRequestTimeFrame` — Today → Insights tab handoff with a preselected `TimeFrame`
- `.themeDidChange` (`ThemeStore`), `.saveErrorOccurred` (`SaveErrorReporter`), `.saveConfirmationOccurred` (`SaveConfirmationToast`), `.backupImportDidComplete` (`BackupImporter`)

---

## 17. Dependencies

**Zero external dependencies.** The app uses only Apple frameworks:

| Framework | Usage |
|-----------|-------|
| SwiftUI | All UI |
| CoreData | Persistence |
| Combine | Reactive filtering/state |
| StoreKit 2 | Tip jar consumables, Pro subscriptions + lifetime, `PurchaseIntent`, `requestReview` |
| UserNotifications | Local notifications (digests, reminders, alerts) |
| WidgetKit | 7 Home / Lock Screen widgets (`CashLensWidgets` target) |
| AppIntents | Siri / Shortcuts intents, App Shortcuts, widget configuration + interactive widget buttons |
| VisionKit | `VNDocumentCameraViewController` receipt scanner |
| Vision | `VNRecognizeTextRequest` on-device receipt OCR |
| PhotosUI | `PhotosPicker` for receipt library attach |
| LocalAuthentication | App Lock (`LAContext`) |
| Charts | Year-over-year, forecast, weekday bars |
| UIKit | Haptics, share sheet, app delegate, PDF rendering (`UIGraphicsPDFRenderer`), alternate icons |
| os | `Logger` for the redacted Quick Log diagnostic trail |

No SPM packages, no CocoaPods, no Carthage. No analytics or crash-reporting SDK. No network calls from the app (the only network activity is StoreKit's own).

---

## 18. Build & Run

1. Open `CashLens.xcodeproj` in Xcode 26 (the project's `LastSwiftUpdateCheck` is 2600; the iOS 26 tab path needs the iOS 26 SDK). The 2.2 plan targets Xcode 27 / iOS 27 SDK.
2. Select a simulator or device running iOS 18.0+
3. Build and run (⌘R)
4. On first launch: onboarding → currency picker → Today tab (there is no splash screen)

**Team ID:** `6C72999Z38`  
**Targets:** `CashLens` (app), `CashLensWidgetsExtension`, `CashLensTests`, `CashLensUITests`  
**Supported devices:** iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`); iPhone portrait + landscape, iPad all orientations; `UIRequiresFullScreen` not set  
**Adaptivity (state on `release/2.2`, Phases A–C landed):** `.sidebarAdaptable` tab shell; `horizontalSizeClass` instead of `userInterfaceIdiom` for layout (the one remaining `userInterfaceIdiom` read is copy-only, in `PrivacyDashboardView`); `NavigationStack` everywhere (no `NavigationView` left); `EvenColumnGrid` for every picker; `.adaptiveHeight` charts; `.readableColumn` on Today / You / Paywall; Activity list + detail as a two-pane `HStack` on regular width (ledger 300–420 pt, header "+", root FAB hidden there); Insights two columns only at regular width **and** ≥ 640 pt measured; `verticalSizeClass` layouts for onboarding and paywall; `tabBarInset` → `scrollBottomClearance = 100`; legacy-bar `safeAreaPadding` on each tab root; `@ScaledMetric` on the FAB glyph (disc fixed), heatmap cells, card heights / icons, paywall medallions, rank badge; keyboard shortcuts (Cmd-N / Cmd-F / Cmd-, / Esc); hover effects; toolbar `Label`s for symbol items; Duo 27.1 stubs behind `CASHLENS_DUO_27_1`. Multitasking: Split View 1/3, Slide Over and narrow Stage Manager windows are compact and fall back to the phone layout. Not done: `systemExtraLarge` widgets (the sparkline data is in the snapshot; the widget is in unmerged PR #8), two-column Today (Today has no grid — pinned categories moved to Insights in v2, so there was nothing to reflow), multiple scenes (deliberately off, §11), the 27.1 Duo APIs themselves (2.2.1). Store 2.1 had none of this (stretched phone layout on iPad; see the adaptivity audit). Nothing here has been compiled or run yet — every 2.2 change awaits Rushiraj's Xcode build.  
**StoreKit testing:** `CashLens/Donations.storekit` (also referenced by `RuntimeSmoke.xctestplan`)  
**Build constraint:** the code can only be compiled, run and screenshotted on a Mac with Xcode. Cloud/Linux agents can edit and review but cannot build.

### Tests
- `CashLensTests/CashLensTests.swift` — Swift Testing stub only
- `CashLensUITests/` — Xcode template launch tests + `RuntimeSmokeUITest.swift` (long manual walkthrough with screenshot attachments; its header marks it throwaway / not for release gating), run via `RuntimeSmoke.xctestplan`
- No CI is configured on any branch; no snapshot or per-device test suite exists

### Debug Tools
- `DiagnosticsView` (`#if DEBUG`) still exists in `Views/` but is **not presented from any view** on this branch — the ProfileView entry point was removed in the v2 IA rework. Attach it manually if needed; it hosts the 2.2 stress-seeder buttons.
- `DebugExpenseSeeder` (`#if DEBUG`, §23): Diagnostics buttons or launch argument `-CLSeedExpenses <n>` fill the store with marked test rows for perf measurement; "Delete seeded data" removes only those rows.
- `QuickLogService.diagTrail` writes `Documents/quicklog-diagnostics.log` in Debug only (Release logs are redacted and the file is removed)
- `Scripts/generate_stress_test_export.swift` → `stress-test-exports/CashLens_StressTest_5000.json` for import/perf testing; `Marketing/ScreenshotSampleData/` for App Store screenshot data

---

## 19. Widgets

CashLens ships **seven widgets** across two surfaces — Home Screen and Lock Screen — built on a single shared data contract that keeps the widget extension narrow, fast, and crash-proof. Three are free (Spending Snapshot, Quick Log with one template, Spending lock widget); the rest are Pro. No widget supports `systemExtraLarge` (iPad) yet — that is on the 2.2 plan.

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
| `Shared/WidgetSnapshot.swift` | `Codable, Hashable, Sendable` data contract. Versioned via `schemaVersion: Int` (currently 1). Carries `generatedAt`, `currencyCode`, `isPro`, `activeThemeId`, `userName`, plus pre-aggregated `spending.byTimeframe`, `budgets[]`, `upcomingSubscriptions[]`, `streak`, optional `quickLogTemplates[]` (`QuickLogTemplate` — name, amount, category raw value, custom category id) for the Quick Log widget, and — since 2.2 (`3fb1b78`) — optional `dailyNetLast7Days: [DailyTotal]?` (`DailyTotal { date, net }`, start-of-day + refund-adjusted net, may be negative). Both new fields are optional so a v1 snapshot still decodes. All collections capped so the snapshot file stays small even for power users. Includes `.placeholder` static for fallback. |
| `Shared/WidgetSnapshotIO.swift` | Atomic read/write helpers. Encoder uses ISO-8601 dates + sorted keys (stable diffs). Read returns `WidgetSnapshot.placeholder` on every failure mode (no file, bad JSON, no App Group container, future schema). Write uses `.atomic` flag so a partially-written file is never observable by the widget process. |
| `Shared/PendingExpenseQueue.swift` | Cross-process handoff for the interactive Quick Log widget: one JSON file per `PendingExpenseRecord` under `<AppGroup>/PendingExpenses-v1/<uuid>.json`. The widget only ever creates files (atomic writes); the app drains by inserting into Core Data and deleting each file only after the insert commits. Replays dedup on the record's stable `id`. Ordering comes from `createdAt` inside the record. |

### 19.3 Main-app coordinator

| File | Description |
|------|-------------|
| `CashLens/Utilities/WidgetSnapshotBuilder.swift` | Pure value-type builder that turns a `Builder.Inputs` snapshot of live state into a `WidgetSnapshot`. Refund-aware (uses `Expense.signedAmount`). Includes a private `CategoryHex` palette mirroring `ColorExtension.LightColors` so widget categories render in the same brand colors as the in-app UI. Hard caps applied to top-categories and upcoming-subs lists. 2.2: `build(_:)` also passes `dailyNetLast7Days: buildDailyTotals(expenses:now:calendar:)` — a private static that buckets `signedAmount` by start-of-day for the trailing 7 days and returns 7 `DailyTotal`s oldest-first, today last, zero-filled for days with no expenses. **No widget in `CashLensWidgets/` reads the field yet**: the consumer (an Extra Large Spending widget with a sparkline) lives in the unmerged PR #8 (`feat/2.2-widgets-tests`); `Shared/WidgetSnapshot.swift` was taken byte-identical from that branch so both merge cleanly. |
| `CashLens/Utilities/WidgetSnapshotCoordinator.swift` | `@MainActor ObservableObject` singleton. `bootstrap(...)` installs Combine subscriptions to `expenseVM.$expenses/$selectedCurrency/$userName`, `budgetVM.$budgets/$budgetProgress`, `categoryVM.$customCategories`, `proManager.$isPro`, `themeStore.$currentTheme`, plus an `NSManagedObjectContextDidSave` observer scoped to `SubscriptionEntity` (so subscription mutations propagate even when `SubscriptionsView` has never been mounted — its VM is tab-scoped). All emits coalesce through a 300 ms debounce; refresh runs on `Task.detached(priority: .utility)`. PERF: the built snapshot is compared (ignoring `generatedAt`) against the last one actually written — identical content skips the disk write **and** `reloadAllTimelines()`, so no-op upstream publishes never wake the widget extension process. `refreshNow()` is the explicit entry point used by the scene-foreground hook. |

Wired into `CashLensApp.swift`: `bootstrap` is called once on `.onAppear` (after every app-level dependency is alive), `refreshNow()` is called whenever `scenePhase == .active` so foreground-after-background → instant widget refresh.

### 19.4 Widget extension (`CashLensWidgets/`)

Synchronized folder, member of `CashLensWidgetsExtension` target. Bundle entry point: `CashLensWidgetsBundle.swift` (`@main WidgetBundle`).

| File | Widget kind | Sizes | Tier | Configurable |
|------|-------------|-------|------|---------------|
| `SpendingWidget.swift` | `SpendingSnapshot` | Small / Medium / Large | **Free** | ✅ App Intent (timeframe: today/week/month/year) |
| `QuickLogWidget.swift` | `QuickLog` | Small / Medium | **Free with 1 template**; additional template buttons render locked until `isPro` | — (`Button(intent: QuickLogTemplateIntent)` per template; "+" button is a `Link` to `cashlens://add-expense`) |
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

### 19.4a Quick Log widget (interactive)

`Button(intent:)` runs `QuickLogTemplateIntent` **in the widget extension process**, which cannot open the app-container Core Data store. The intent therefore appends a `PendingExpenseRecord` to `PendingExpenseQueue` and reloads the widget timeline; `QuickLogTimelineProvider` adds queued-today records to the snapshot total so the displayed number bumps optimistically. On the app's next launch/foreground, `CashLensApp.drainWidgetQueueInBackground()` → `QuickLogService.drainWidgetQueue()` inserts the records, republishes the snapshot, and shows a "Added N expenses from your widget" toast. `QuickLogTemplateIntent` is `isDiscoverable = false` — it is plumbing, not a Shortcuts action (the app target vends `LogExpenseIntent` for that).

### 19.5 Pro gating

The snapshot includes `isPro: Bool` (sampled at write time, in the main app, against `ProManager.shared.isPro`).

- **Spending Snapshot** — intentionally free for everyone. It's the hero surface that drives Pro upgrades by demonstrating the visual quality bar.
- **Quick Log** — free with the first template; templates at index ≥ 1 render locked for free users.
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

---

## 20. Siri / App Intents & Quick Log

All App Intents live in the **app target** (`CashLens/Intents/`), not the widget extension, because the Core Data store is in the app container. App Intents in the app target run the app process in the background with no scene, so nothing may assume `ExpenseViewModel` or `WidgetSnapshotCoordinator` exists — every write goes through `QuickLogService`.

| Piece | File | Notes |
|-------|------|-------|
| `CashLensShortcuts` | `Intents/CashLensShortcuts.swift` | `AppShortcutsProvider` with zero-setup phrases. Every phrase contains `\(.applicationName)` (hard requirement). "Log an expense in CashLens" / "Add an expense to CashLens" / … → `LogExpenseIntent`; "How much did I spend today in CashLens" / "Check my spending in CashLens" / … → `GetSpendingIntent`. Tile color `.purple`. |
| `LogExpenseIntent` | `Intents/LogExpenseIntent.swift` | Free. `openAppWhenRun = false`. Parameters: `amount: IntentCurrencyAmount` (a bare `Double` mis-parsed "250 rupees" as 100 in device testing), **required** `title` ("What was it for?" — also feeds category inference), optional `category` via `ExpenseCategoryOptionsProvider`. The spoken currency code is ignored for storage; the app's selected currency is used. Returns a dialog + snippet view. |
| `GetSpendingIntent` | `Intents/GetSpendingIntent.swift` | Free. Answers "`<today> today · <month> this month`" from `QuickLogService.spendingSummary()` (direct Core Data fetch). Throws `storeUnavailable` if the store failed to load. |
| `QuickLogService` | `Utilities/QuickLogService.swift` | Headless write path shared by the intents and the widget queue drain. Fresh background context off `PersistenceController.shared`; posts `.expensesChangedExternally`; rebuilds the widget snapshot from the store. `diagTrail` logs with `privacy: .private` in Release and deletes any Debug-era plain-text log file. |
| `SiriShortcutsTipsView` | `Views/SiriShortcutsTipsView.swift` | You → Siri & Shortcuts: lists the phrases so users discover hands-free logging. |

Quick Log widget flow is described in §19.4a.

---

## 21. App Lock

Free feature by design ("your money stays your business" — nothing in `AppLockManager` checks `ProManager`). `NSFaceIDUsageDescription` is declared in `CashLens-Info.plist`.

- **`AppLockManager`** (`Utilities/AppLockManager.swift`) — `@MainActor` singleton. `isEnabled` (persisted; enabling requires one successful `LAContext` evaluation first so a user with neither biometrics nor passcode can never lock themselves out), `gracePeriod` (`immediately` / `oneMinute` / `fiveMinutes`, persisted as seconds), `isLocked` (re-auth required), `isCoverVisible` (overlay on screen — true whenever locked **and** while the scene is merely inactive so the app-switcher snapshot never shows amounts), `isAuthenticating`.
- **Relock-loop guards** — only `.background` (never `.inactive`) records a backgrounding timestamp; `isAuthenticating` suppresses phase handling while the system prompt owns the screen; the auto-prompt fires at most once per lock (`hasAutoPromptedSinceLock`) and the overlay button re-triggers after a cancel.
- **Cold launch** — locks unless the persisted `appLockLastBackgroundedAt` proves the app is still inside the grace window (covers iOS quietly terminating the app seconds earlier).
- **Integration** — `CashLensApp` mounts `AppLockView` at `zIndex(10)` above onboarding and even `StoreRecoveryView`, and forwards `scenePhase` to `handleScenePhase(_:)`. On unlock, `.appDidUnlock` releases parked deep links (`DeepLinkRouter.flushPendingRoute()`) and re-runs the win-back evaluation. `MainTabView` skips the auto-paywall while locked and defers the rating prompt (`ReviewPromptManager.deferWhilePresenting()`, so the ask is not spent); `ProManager.evaluateWinBackPrompt()` bails while locked.
- **Settings** — You → Privacy & Security: App Lock toggle + "Require After" picker; status also shown on `PrivacyDashboardView`.

---

## 22. Release History

Reconstructed from `git log` on `redesign/v2` and the App Store listing (checked 2026-09-19). Dates are commit dates.

| Date | Version / build | What |
|------|-----------------|------|
| 2025-03-10 | — | First commit (`76528de`) |
| 2025-03-24 | — | First App Store release (date from the App Store listing; version not recorded in the repo) |
| 2025 Mar–May | 1.x | Currency auto-select, donations, subscriptions with manual Mark paid, import/export, statistics + community links |
| 2026-01 | 1.0.5 (5) | App Store release from `main` (`fbf8865`); transaction automation added then removed (`9e7485a` / `28b15ef`). `main` has not moved since 2026-01-21. |
| 2026-05-16 | — | `cb26f47` Pro features wave + Phase G perf pass (branch `pro-features`, ancestor of `redesign/v2`) |
| 2026-05 | — | `777ee11` … `9ed0450` v2 redesign: 4-tab IA, Today screen, card system, Monthly Recap, You-tab grouping |
| 2026-07-15/16 | 2.0.0 (6) | `74f476a` pre-submission wave (Siri intents, Quick Log widget, App Lock, receipt OCR, Appearance Studio, custom budget ranges, privacy manifests, win-back + donor thanks, audit fixes); `60382e3` release blockers; marketing site commits |
| 2026-08-29 | 2.0.1 (7) → **store 2.1** | `4029ae0` native one-tap rating prompt + Mark-paid hint. Released to the App Store as **2.1** on 2026-08-29 (release notes match this commit; the version string was edited in App Store Connect). |
| 2026-09-02 | unshipped | `4f702fa` PurchaseIntent listener for promoted IAPs; `cfeeb2d` promo images + Cursor rule |
| 2026-09-19 | **2.2 (8)** in progress on `release/2.2` (41 commits ahead of `redesign/v2` at `3af5bf4`, not yet built on a Mac) | **Phase 0:** `be7a28b` bump to 2.2 (8) + drop tracked `xcuserdata`; `7289d22` tip-jar purchase intents; `9c9d840` paywall truth-pass; `8de55d1` `ReviewPromptManager`; `4810369` `AppConstants.supportEmail`. **Phase A:** `0691176` `sidebarAdaptable` + size-class FAB; `f3e9942` size classes replace `userInterfaceIdiom`, `.adaptiveHeight`; `bb47fde` `NavigationView` → `NavigationStack`; `7a4e291` adaptive picker grids; `da8a529` width-derived chart heights + Dynamic Type heatmap cells; `eec249d` Activity `NavigationSplitView` + `AddExpenseView.onDismissRequest`; `0144e13` `.readableColumn` for Today / You / Paywall; `7cac596` compact-height onboarding + paywall; `46b7404` retire `tabBarInset`; `5604e8d` `@ScaledMetric` sweep; `3fb1b78` `WidgetSnapshot.dailyNetLast7Days`. **Phase B:** `adefae7` `AppCommands` keyboard shortcuts + Esc; `7517150` hover effects; `ff20b27` Activity sidebar widths 300/340/420 for narrow-regular windows; multiple scenes left off (decision). **Phase C:** `952a341` toolbar audit (`Label`s, `ToolbarItem`, Esc on Done); safe-area audit (no change); `8f8362a` + `f34af68` `EvenColumnGrid` + `DuoLayoutSupport` hinge-gutter hook; `d535979` Duo 27.1 stubs behind `CASHLENS_DUO_27_1`. **Review fixes** (launch-readiness review, 0 blockers / 7 should-fix): `c9a63ed` S1 FAB hidden on Activity at regular width + ledger header "+"; `afdb5ce` S2 `scrollBottomClearance` 32 → 100; `942efad` S3 Activity `NavigationSplitView` → two-pane `HStack`; `56c6746` S4 legacy `safeAreaPadding` moved onto the tab roots; `58fdbb2` S5 FAB disc fixed, glyph clamped; `f98edeb` S6 review prompt `markRequested` / `deferWhilePresenting`, major.minor key, streak needs a prior recompute; `5121e1a` S7 Cmd-N waits for `hasPresentation`, Esc only on the topmost sheet; `d33ab47` N3 Insights two columns ≥ 640 pt + N6 `resetForDebugging` `#if DEBUG`; `99f5906` doc comment. **Perf quick wins** (from the 2.2 performance investigation, behaviour-preserving by condition): `19a32c3` Quick Search top-200 render cap + true-count footer; `9973bfa` `selectInsight` in `Task.detached`; `0a46d6f` `isPotentialDuplicate` cheap checks first; `602b5b4` `TodayInsight.pick` day-range compare; `319af89` + `d26c541` Activity day-bounds cache with equality fallback; `026960f` `computeStats` drops the redundant sort; `3faca45` charts take `currencySymbol` explicitly; `3af5bf4` `DebugExpenseSeeder` (DEBUG only). See §23. Remaining 2.2 scope and the 2.2.1 Duo TODO list are in `PRO_FEATURES.md` → Version Plan. |
| planned | 2.2.1 | iOS 27.1-only iPhone Duo APIs behind `#available` |

Whether 2.0.0 (6) was ever published, and which exact commit the store 2.1 binary was built from, cannot be verified from the repository — only from App Store Connect.

---

## 23. Performance

Two prior passes are recorded in §11 (Phase G, May 2026: incremental in-memory CRUD, single-burst filter/totals publish, fetch indexes, visibility-gated recomputes). A static performance investigation of `release/2.2` (2026-09-19, Linux read of the code — no profiler, no compile) concluded that no obvious main-thread O(N) loop remains in the common path except Quick Search rendering; what is left is structural: `ExpenseViewModel` is one object with 15 `@Published` properties observed whole by the App root, `MainTabView`, the three mounted tab roots, the open Add Expense sheet and (until 2.2) the chart components, so each save fires two or three invalidation bursts; every publish fans out into ~8–10 concurrent full-array passes that each do per-element `Calendar` work; every foreground re-materialises the whole table (`refreshData()` → `loadExpensesAsync()`); and Smart Insights ran synchronously on main at foreground. None of the 2.2 layout changes (`adaptiveHeight`, `EvenColumnGrid`, `readableColumn`, `onGeometryChange`) adds data-dependent cost.

### What landed in 2.2 (quick wins — no functionality change)

| Commit | Change | Where |
|--------|--------|-------|
| `19a32c3` | Quick Search renders only the top 200 ranked matches; count chip and net total still use the full set; footer states the true count when > 200 | `QuickSearchView.maxRenderedResults`, `truncationFooter` |
| `9973bfa` | `SmartInsightsEngine.selectInsight` runs in `Task.detached(priority: .utility)`; inputs (incl. the `UserDefaults` history read) stay on the main actor | `NotificationScheduler.scheduleNextSmartInsight` |
| `0a46d6f` | `isPotentialDuplicate` checks amount → 5-minute window → title (pure AND, same verdict) | `AddExpenseView` |
| `602b5b4` | `TodayInsight.pick` compares against precomputed `[todayStart, todayEnd)` instead of `isDate(inSameDayAs:)` per row | `TodayView` |
| `319af89`, `d26c541` | Activity day grouping computes day bounds once per group; per-row equality fallback kept | `AllExpensesView` recompute |
| `026960f` | `TagSuggestionProvider.computeStats` no longer re-sorts; documents the date-descending invariant of `ExpenseViewModel.expenses` | `TagSuggestionProvider` |
| `3faca45` | `TrendChartPager` / `ExpenseTrendChart` take `currencySymbol: String` instead of observing `ExpenseViewModel`; redundant `.environmentObject` re-injection removed | `StatisticsView` → pager → chart |
| `3af5bf4` | `DebugExpenseSeeder` for measurement (below) | `Utilities/DebugExpenseSeeder.swift`, `DiagnosticsView`, `CashLensApp.init` |

Skipped on purpose: coalescing Today's second recompute (changes verdict-refresh timing — observable) and heatmap memoisation (a `(start, end, count)` key can go stale when totals change with the same count).

### Debug stress seeder (`Utilities/DebugExpenseSeeder.swift`)

Whole file is `#if DEBUG`; no Release code path references it. Rows are written with `NSBatchInsertRequest(entity:managedObjectHandler:)` on `newBackgroundContext()`, the resulting object IDs are merged into the view context (`mergeChanges`), and `.expensesChangedExternally` is posted so the live `ExpenseViewModel` reloads through its normal `loadExpensesAsync()`.

- **Marker:** every seeded row has `subscriptionId == 0000C1EE-5EED-4000-8000-000000000000` (`sentinelSubscriptionID`) with `isFromSubscription == false`, so nothing treats it as a real subscription expense. Six custom categories are created once, named `Seed …` (`seededCategoryPrefix`).
- **Shape:** distributions mirror `Scripts/generate_stress_test_export.swift` — dates uniform over the last 730 days with a random time of day plus 3 % dated today, 3 % refunds, 20 % with 1–3 tags from a pool of 30, 40 % with a payment method, 12 % with notes `[seed] Note n`, 18 % in the seeded categories. Deviation from the investigation's spec: no subscriptions or budgets are seeded (add a budget by hand to exercise the Today verdict path).
- **Entry points:** `DiagnosticsView` (itself `#if DEBUG`, currently unreferenced — attach manually) with "Seed 5,000 / 20,000 test expenses" behind a confirmation dialog, "Delete seeded data" (destructive, confirmed) and a status line; and the launch argument **`-CLSeedExpenses <n>`**, read in `CashLensApp.init` via `UserDefaults.standard.integer(forKey: "CLSeedExpenses")` only when the store loaded, run synchronously before the view models hydrate so cold start can be measured against a full table, and idempotent (skips when the store already holds ≥ n seeded rows).
- **Delete path:** `deleteSeededData` runs two `NSBatchDeleteRequest`s — `subscriptionId == <sentinel>` on `ExpenseEntity` and `name BEGINSWITH "Seed "` on `CustomCategoryEntity` — merges the deleted IDs into the view context and posts `.expensesChangedExternally`. Nothing else is touched.
- Do not seed through Import: `BackupImporter` does two `count` queries per row, so 20k rows take tens of seconds and exercise the wrong path.

### Deferred to 2.3 (the structural work)

Recorded in the investigation's refactor list; none is attempted in 2.2 because each touches many files or user-visible behaviour:

1. **Observation split / `@Observable`** — per-property invalidation (deployment target is iOS 18), or split `ExpenseViewModel` into an expense store, a preferences store and per-screen filter state; delete the legacy `filteredExpenses` / `cached*` pipeline whose only consumers are the orphaned `SummaryCustomizationView` and one Quick Search chip.
2. **Change-token-gated foreground refresh** — observe `NSPersistentStoreRemoteChange` (the option is already set in `Persistence.swift`; nothing observes it) or a store-generation counter, and only re-fetch when the store changed outside the view model, instead of re-materialising every row on every scene activation.
3. **Denormalised daily aggregates** — a per-day (category, net, count) entity maintained on save so Today / Insights / Calendar / heatmap / widget read ≤ 365 rows instead of N.
4. **Row-level laziness** in Activity same-day groups and Quick Search groups (today one `LazyVStack` item is a whole day / group rendered as a non-lazy `VStack`).
5. Also listed: background write context for CRUD, shadow-radius token review after measuring hitches, import prefetch + `NSBatchInsertRequest`.

Measurement plan (scenarios, Instruments templates, target numbers) is in the Project store document `docs/performance-investigation-2.2.md`; the trace files from Rushiraj's Mac are the baseline 2.3 is judged against.
