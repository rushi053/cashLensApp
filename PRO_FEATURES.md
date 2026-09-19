# CashLens Pro — Feature Roadmap

> **Baseline:** v1.0.5 (Build 5, App Store 2026-01) — everything that existed then is still free  
> **Shipped:** CashLens Pro launched with the v2 redesign; live on the App Store as **2.1** since 2026-08-29 (repo `MARKETING_VERSION` 2.0.1 / build 7 — the store string was set in App Store Connect)  
> **Next:** 2.2 (build 8) — see [Version Plan](#version-plan)  
> **Monetization:** Auto-renewable subscriptions (monthly / yearly, 7-day trial) **and** a lifetime unlock. Both stay — see decision below  
> **Branch:** `redesign/v2` is what store 2.1 shipped from (`pro-features` was a single snapshot commit, `cb26f47`, that is an ancestor of it). `release/2.2` is cut from it and carries the 2.2 work (`MARKETING_VERSION = 2.2`, build 8). `main` is stale at 1.0.5.  
> **Doc status:** phases were logged as they were built; this refresh (2026-09-19) adds the missing Phase 13, sets Phase 8's status, and rewrites the version plan to match what actually shipped.

---

## Pricing Strategy

| Tier | Product ID | Price | Notes |
|------|------------|-------|-------|
| Monthly | `com.cashlens.pro.monthly` | $2.99/mo | 7-day free trial (shown only when `ProManager.isEligibleForIntroOffer`) |
| Yearly | `com.cashlens.pro.yearly` | $19.99/yr | ~$1.67/mo, savings badge computed from live prices |
| Lifetime | `com.cashlens.pro.lifetime` | $39.99 | One-time non-consumable, for subscription-averse users |

All three are listed on the live App Store page alongside the three tips ($0.99 / $4.99 / $9.99).

**Monetization decision (Rushiraj, 2026-09-19): subscriptions AND lifetime both stay.** An earlier HQ decision ("never subscription") is reversed; the app has been selling all three tiers since launch and none is being retired. Logged here so the paywall, App Store listing and content calendar can be truth-passed against one statement.

**Tip jar** (existing) stays as-is for users who want to support without Pro. Past donors are grandfathered into Pro — see [Donor Grandfathering](#donor-grandfathering-wave-2).

---

## What Stays Free (never gated)

- Unlimited expense tracking (add/edit/delete), tags (adding), payment method, refunds, templates, bulk select
- All 10 default categories and custom categories (no cap is enforced in code)
- Subscription/bill tracking with reminders
- Basic statistics (donut, trend pager, heatmap, highlights), Monthly Recap
- Import/Export (`.cashlens.json`, `.csv`, `.cashlens-archive`) and import of any CashLens backup
- Weekly/monthly digest notifications, backup reminder
- Dark mode + appearance toggle
- Draft recovery
- Today screen and its customization
- App Lock (Face ID / Touch ID / passcode)
- Siri / Shortcuts intents (`Log Expense`, `Check Spending`)
- Spending Snapshot widget (Home + Lock Screen) and the Quick Log widget with one template
- Viewing and removing existing receipts (capture is Pro)

---

## Feature Priority & Build Order

Features are ordered by: **user value × revenue impact × implementation safety**

### Phase 1: Pro Infrastructure (Build First) — ✅ COMPLETED

| # | Feature | Risk | Effort | Revenue Impact | Status |
|---|---------|------|--------|----------------|--------|
| 1.1 | **StoreKit 2 Subscription Setup** | Low | Medium | Foundation for all Pro revenue | ✅ Done |
| 1.2 | **Paywall View** | Low | Medium | Conversion gate | ✅ Done |
| 1.3 | **ProManager (entitlement checker)** | Low | Low | Feature gating | ✅ Done |

**What was built:**

- **StoreKit 2 Subscription:** Added `com.cashlens.pro.monthly` ($2.99/mo) and `com.cashlens.pro.yearly` ($19.99/yr) auto-renewable subscriptions with 7-day free trial, plus `com.cashlens.pro.lifetime` ($39.99) non-consumable. All in subscription group "CashLens Pro" (`D4E8F2A1`). Existing tip jar products untouched.
- **ProManager** (`Models/ProManager.swift`): Singleton `@MainActor ObservableObject`. Exposes `@Published isPro: Bool`. Checks `Transaction.currentEntitlements` on launch, listens to `Transaction.updates` for real-time entitlement changes. Handles purchase and restore (`AppStore.sync()`). Computes `yearlySavingsPercent` dynamically from live product prices.
- **PaywallView** (`Views/PaywallView.swift`): Full-screen upgrade UI with animated feature list, plan selector cards (monthly/yearly/lifetime), savings badge, free trial notice, purchase button, restore link, and Apple subscription terms.
- **ProfileView** updated: Pro status card below profile header — shows "Upgrade to Pro" CTA or "Active" badge.
- **CashLensApp** updated: `ProManager.shared` injected as `@StateObject` + `.environmentObject`.
- **UserDefaultsKeys** updated: Added `hasSeenPaywall`, `paywallImpressionCount`.

**Files created:**
- `CashLens/Models/ProManager.swift`
- `CashLens/Views/PaywallView.swift`

**Files modified:**
- `CashLens/Donations.storekit` — added subscription group + lifetime product
- `CashLens/CashLensApp.swift` — injected ProManager
- `CashLens/Views/ProfileView.swift` — added Pro section + paywall sheet
- `CashLens/Utilities/UserDefaultsKeys.swift` — added Pro keys

---

### Phase 2: Budgets & Budget Alerts — ✅ IMPLEMENTED

| # | Feature | Status |
|---|---------|--------|
| 2.1 | **Budget Model & Core Data Entity** | ✅ `Budget`, `BudgetEntity`, `BudgetEntity+Extensions` |
| 2.2 | **BudgetViewModel** | ✅ FRC + debounced recompute + background progress + crossing-based alerts |
| 2.3 | **Budget Setup / List** | ✅ `BudgetSetupView`, `BudgetListView` |
| 2.4 | **Budget Progress on Home** | ✅ `BudgetProgressCard` / `BudgetMiniCard`; budget strip below header (iPhone + iPad); **Pro** teaser for free users |
| 2.5 | **Budget Alert Notifications** | ✅ `BudgetAlertState` + `UNUserNotificationCenter`; opens **All Expenses** for period + category; **no false alerts** on first observation of a period |

**Implementation notes:**

- **Pro gating:** `ProManager.isPro` — Home shows upgrade teaser or real budgets; Profile “Manage Budgets” opens paywall or list; `BudgetSetupView` dismisses if not Pro.
- **Performance:** Expense changes debounced **120ms**; progress aggregation runs **off the main thread**; UI updates via `@Published budgetProgress`.
- **Alerts:** Only when utilization **crosses** 80% or 100% upward; persisted per period via `BudgetAlertState` (last % + fired flags); notification `userInfo` uses existing `allExpenses` deep link with date range and optional category.

---

### Phase 3: Smart Tags — SHIPPED ✅

| # | Feature | Risk | Effort | Revenue Impact | Status |
|---|---------|------|--------|----------------|--------|
| 3.1 | **Tags on Expense Model** | Low | Low | — | ✅ Shipped |
| 3.2 | **Tag Input UI (chips + autocomplete)** | Low | Medium | — | ✅ Shipped |
| 3.3 | **Tag Filtering in All Expenses** | Low | Medium | Medium — power user retention | ✅ Shipped (Pro-gated) |

**Gating strategy (final):**

- **Adding tags is FREE** — keeps the add flow addictive, removes friction from the dopamine loop.
- **Filtering by tag is PRO** — free users see a subtle "Filter by tag with Pro" nudge in `AllExpensesView` whenever any expenses have tags. Tapping opens the paywall.
- **Tag *search* in Quick Search (`#tag` queries) is FREE — deliberately.** Search is search: silently returning nothing for a `#` query would read as broken, and gating a text search feels punitive. The Pro pitch is the persistent *filter chip* workflow in Activity, not the ability to type `#coffee` once. (Bulk-adding a tag from selection mode is Pro — it's a power-user efficiency tool, distinct from the free single-expense tagging.)
- **Free users always see their tags** on `ExpenseCard` (glanceable context, works even post-downgrade — implicit grandfathering).

**Implementation notes:**

- `Expense.tags: [String]?` — optional, nil-by-default, backward-compatible.
- `ExpenseEntity.tags` — Transformable `NSArray` with `NSSecureUnarchiveFromDataTransformerName`. Nil for all legacy rows; no migration work needed.
- `Tag.normalize(_:)` — canonicalizes user input (trim, strip leading `#`, collapse whitespace to `-`, lowercase, 30-char cap). Stored without `#`; always rendered with `#` via `Tag.displayForm`.
- `TagSuggestionProvider.computeStats(from:)` — runs off-main, debounced 200ms, exposes usage counts, recent-first list, and popularity-sorted list. Backs both autocomplete and the filter strip.
- `TagInputField` — chip flow + text field with live autocomplete. Commits on space, comma, return, or tap-to-add from suggestions. Light haptic on commit, warning haptic on duplicate / 10-tag cap.
- Import/Export round-trip:
  - **JSON:** adds `"tags": [String]` to each expense; absent on legacy exports.
  - **CSV:** adds a 9th `"Tags"` column (semicolon-separated); import tolerates 8-column legacy files.

**Files shipped:**
- `CashLens/Models/Expense.swift`
- `CashLens/Models/ExpenseEntity+Extensions.swift`
- `CashLens.xcdatamodeld/CashLens.xcdatamodel/contents` — `tags` attribute
- `CashLens/Utilities/Tag.swift` — normalization + display helpers
- `CashLens/Utilities/TagSuggestionProvider.swift` — off-main stats aggregator
- `CashLens/Utilities/ExpenseDraft.swift` — drafts carry tags (nil-safe decoding for old drafts)
- `CashLens/Components/TagChip.swift` — 4-style chip component (inline / standard / selected / editable)
- `CashLens/Components/TagInputField.swift` — input control with flow layout and autocomplete
- `CashLens/Components/ExpenseCard.swift` — inline tags row (up to 3 + `+N` overflow)
- `CashLens/ViewModels/ExpenseViewModel.swift` — `@Published tagStats` + debounced recompute
- `CashLens/ViewModels/ExpenseViewModel+CRUD.swift` — persist tags on update
- `CashLens/ViewModels/ExpenseViewModel+ImportExport.swift` — CSV/JSON round-trip
- `CashLens/Views/AddExpenseView.swift` — new `tagsField` section; `onSave` signature + draft wiring
- `CashLens/Views/AllExpensesView.swift` — Pro-gated `tagsFilterRow`; tag match included in search
- `CashLens/Views/HomeView.swift`, `QuickSearchView.swift` — updated edit call sites

---

### Phase 4: App Icons & Themes — SHIPPED ✅

The Personalization tier — six accent color themes that recolor every primary surface in the app, plus eight alternate app icons (six theme-matched colored variants + Mono Light + Mono Dark). Both are **Pro** features, both share the same picker UX (live preview + tap-to-apply + paywall on a Pro-locked tap), and both are designed so a free user can browse and try every option *visually* before being asked to upgrade — the conversion moment happens with the user already in love with their pick.

| # | Feature | Risk | Effort | Status |
|---|---------|------|--------|--------|
| 4.1 | **Accent Color Themes** (6) | Low | Low | ✅ Shipped |
| 4.2 | **Alternate App Icons** (7 + primary) | Low | Low | ✅ Shipped |

**What was built:**

- **4.1 Color Themes — `AppTheme` + `ThemeStore`:** Six themes shipped (Mauve / Ocean / Forest / Sunset / Berry / Graphite). Each is an immutable `AppTheme` value carrying hand-tuned light + dark hex pairs for both `primary` and `secondary` colors, so contrast stays AA-safe in either appearance mode. `Color.appPrimary` and `Color.appSecondary` were converted from static lets to dynamic computed properties that resolve `Color(UIColor { trait in ... })` against `ThemeStore.activeTheme` at render time — a one-line change at the source that cascades across ~150 surfaces (tab bar tint, pills, FAB, charts, info badges, paywall accents, `Color.appPrimary.opacity(...)` washes) with **zero call-site churn**. `ThemeStore` is a `@MainActor ObservableObject` singleton with a `nonisolated(unsafe)` thread-safe snapshot for the dynamic UIColor closures, persists the active theme id in `UserDefaults` (`activeThemeId`), and on `applyTheme(_:)` also performs a soft `UIView.transition` cross-dissolve on the key window's `overrideUserInterfaceStyle` so cached UIKit dynamic colors invalidate cleanly — the user sees a smooth fade, not a jarring redraw.

- **4.2 App Icons — `AppIconOption` + `AppIconStore`:** Eight options shipped (Mauve primary + Ocean / Forest / Sunset / Berry / Graphite / Mono Light / Mono Dark). All seven alternates are 1024×1024 PNGs generated by `Scripts/generate_app_icons.swift` (a tiny CoreGraphics renderer that draws the existing CashLens coin/$/glint geometry in each theme color — pixel-deterministic, re-runnable, family-cohesive), checked into the asset catalog as `*.appiconset` folders. The build is wired with `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES` and `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "AppIcon-Ocean ..."` so Xcode auto-generates the `CFBundleIcons.CFBundleAlternateIcons` Info.plist entries from the catalog — no manual plist editing, no risk of drift. `AppIconStore` is a `@MainActor ObservableObject` singleton wrapping `UIApplication.setAlternateIconName(_:)` (iOS 18+ async API), with three guards: (1) `supportsAlternateIcons` check up front, (2) `isPrimary` short-circuit when clearing back to the default, (3) persistence (`activeAppIconId`) only after the OS confirms — so a failed apply doesn't leave a stale value.

- **Personalization overhaul (v2.4):** The theme picker grew into `AppearanceStudioView` — a unified "make it yours" studio holding the light/dark/system mode selector (moved out of General), both theme families (6 Classics + 6 Pastels) with **duotone swatches**, a miniature-Today live preview, and a **"Complete the look"** card that one-tap applies the theme-matched app icon (`AppTheme.matchingIconId` ↔ `AppIconOption`). Each theme's previously-unused secondary color now earns its keep: `LinearGradient.appDuotone` (primary → primary blended 45 % toward secondary, computed via `UIColor.mixed(with:amount:)`) is the one sanctioned gradient, applied to hero brand moments only — FAB, `PrimaryGradientButton`, Today's first-expense CTA, the studio Apply bar — so switching themes visibly changes a designed color *pair* across the app, not a flat accent.

- **Pickers (`AppearanceStudioView`, `AppIconPickerView`):** Identical UX shape so users build muscle memory across both. Each picker has three sections: a **live preview card** at the top (theme picker shows pills + a tinted progress bar + a FAB mock; icon picker shows a 132 pt rounded square of the previewed icon with shadow), a **swatch / tile grid** in the middle (3-up for themes, 4-up for icons), and a **conditional Pro CTA** at the bottom that only appears when a free user is previewing a Pro option. Tapping any swatch always updates the live preview instantly (`@State previewTheme` / `previewIcon`) — that's the marketing moment — but only commits to the store if the user is Pro or picked the free default. Active selections get a checkmark badge + accent ring; Pro-locked options get a tiny lock badge in the corner. Both pickers ship with `HapticManager.shared.success()` on a real apply, `.warning()` on a paywall hit.

- **ProfileView Personalization section:** New section between Preferences and Reminders, holding two rows (`colorThemeRow`, `appIconRow`). For Pro users the trailing slot shows the active theme name + a swatch dot, or the active icon name + a tiny rounded preview tile. For free users both rows show the same `proLockChip` (consistent with the Smart Insights row) so the Pro story reads as a coherent tier across the screen, not a series of one-offs. Tapping always opens the picker (never the paywall directly) so the user gets to *see* what they're paying for before any commerce ask.

**Files created:**
- `CashLens/Models/AppTheme.swift`
- `CashLens/Models/AppIconOption.swift`
- `CashLens/Utilities/ThemeStore.swift`
- `CashLens/Utilities/AppIconStore.swift`
- `CashLens/Views/AppearanceStudioView.swift` (superseded `ThemePickerView.swift` in the v2.4 personalization overhaul)
- `CashLens/Views/AppIconPickerView.swift`
- `Scripts/generate_app_icons.swift` — re-runnable icon-PNG renderer
- `CashLens/Assets.xcassets/AppIcon-{Ocean,Forest,Sunset,Berry,Graphite,MonoLight,MonoDark}.appiconset/` — 7 alternate appiconsets with single 1024×1024 universal entries

**Files modified:**
- `CashLens/Components/ColorExtension.swift` — `appPrimary` / `appSecondary` now compute from `ThemeStore.activeTheme`; new tolerant `UIColor(hex:)` helper
- `CashLens/Utilities/UserDefaultsKeys.swift` — `activeThemeId`, `activeAppIconId`
- `CashLens/CashLensApp.swift` — injects `ThemeStore` + `AppIconStore` as `@StateObject` env objects
- `CashLens/Views/ProfileView.swift` — new `personalizationSection`, `colorThemeRow`, `appIconRow`, shared `proLockChip`
- `CashLens.xcodeproj/project.pbxproj` — `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`, `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` listing all 7 alternates (both Debug + Release)

**Safety / migration notes:**
- **Backward compatible by default.** A user with no `activeThemeId` resolves to `AppTheme.default` (Mauve), which is the *exact same* hex pair the app shipped with — visually identical until the user explicitly opts in. Same for icons: `AppIconStore.init` checks `UIApplication.shared.alternateIconName` first and falls back to `.primary`, so existing users see no change.
- **Dark mode contrast.** Each theme ships separate `primaryLight` / `primaryDark` and `secondaryLight` / `secondaryDark` hex values. Light variants are tuned for legibility on `Color.systemBackground` (white-ish); dark variants are lifted ~10–15 % brighter for the same legibility on near-black backgrounds. Mono Light and Mono Dark are intentional inverses so power users running system-wide dark mode have a properly contrasted icon either way.
- **No Core Data changes.** Personalization is entirely `UserDefaults`-backed.
- **Pro downgrade.** If a Pro user lapses, `Color.appPrimary` keeps reading from `ThemeStore.activeTheme` (no auto-revert) — this is intentional, the user keeps the look they paid for. Re-applying a non-default theme from the picker will be paywall-gated again.
- **Alternate icon API quirks.** `setAlternateIconName(_:)` on iOS 18+ presents an automatic system alert ("'CashLens' Has Updated Its Icon"). This is a system-level UX we cannot suppress and is part of the native iOS contract — accepted. Errors are caught and surfaced via a friendly in-picker alert so we never ship an inconsistent UI/persistence state.

---

### Phase 5: Advanced Statistics & PDF Reports — SHIPPED ✅

| # | Feature | Status |
|---|---------|--------|
| 5.1 | **Year-over-Year Comparison** | ✅ Shipped |
| 5.2 | **Daily Pace** (Average Daily Spend) | ✅ Shipped |
| 5.3 | **PDF Report Generation** | ✅ Shipped |
| 5.4 | **Spending Velocity** | ✅ Shipped |

**What shipped:**

- **Pro Insights section** inserted into `StatisticsView` directly below the Overview cards (no layout fragmentation — Pro content slots into the same flow).
  - **Daily Pace card** — "$X / day so far" with ↑↓ % change vs the prior same-length period.
  - **Velocity card** — projects end-of-period total from current pace; shows ↑↓ % vs prior period. Switches to "Final Total" when the range has already ended.
  - **Year over Year chart** — grouped bar chart comparing this-year vs same months last year for the trailing 6 months. Ignores the date-range filter intentionally (YoY is year-wide).
  - **Teaser for free users** — single premium-styled card with preview pills and an "Unlock Pro Insights" CTA. Tap opens `PaywallView`.
- **Export PDF Report** — icon button (top-right of Statistics header) with a tiny lock badge for free users.
  - Pro: generates a polished multi-page PDF (cover + total banner + stat grid + category breakdown table + top 40 expenses) on a background task, opens the native share sheet.
  - Free: tap → `PaywallView`.
  - Gracefully disabled when there are no expenses yet.

**Gating strategy (tie-in with the "give all the value to Pro" principle):**

- Free tier keeps every pre-existing statistic (summary, insights, donut, heatmap, breakdown, trend chart) untouched — nothing was taken away.
- Pro unlocks **forward-looking** metrics (projection, pace, YoY) plus the PDF artifact. The teaser card makes this upgrade-worthy content visible (and blurred-behind-a-lock feel), so free users know exactly what they're unlocking.

**Files created:**
- `CashLens/Utilities/AdvancedStatsCalculator.swift` — pure functions for daily pace, velocity, YoY (Sendable-safe, side-effect free).
- `CashLens/Utilities/PDFReportGenerator.swift` — `UIGraphicsPDFRenderer`-based layout with cover banner, stat grid, category rows w/ bars, zebra-striped expense table, footer on every page.
- `CashLens/Components/YearOverYearChart.swift` — SwiftUI Charts grouped bars.
- `CashLens/Views/ProInsightsSection.swift` — section wrapper (Pro cards + free teaser).

**Files modified:**
- `CashLens/Views/StatisticsView.swift` — Pro section wiring, advanced-stats aggregation inside the existing detached-task pipeline (zero extra main-thread work), export button, paywall/share sheets.

---

### Phase 6: Receipt Scanner — SHIPPED ✅ (on-device storage + cross-device portability via `.cashlens-archive`)

| # | Feature | Status |
|---|---------|--------|
| 6.1 | **VisionKit Document Scanner** | ✅ `VNDocumentCameraViewController` with auto-crop / perspective-correction. Page 1 of any multi-page scan is taken (multi-page support still deferred — see below). Receipt OCR auto-fill was added later (Phase 13.9). |
| 6.2 | **PhotosUI Library Picker** | ✅ Native `PhotosPicker` for non-camera attachments. |
| 6.3 | **Pro-gated capture, free-forever viewing** | ✅ Capture buttons gated behind `ProManager.isPro`; downgraded users keep viewing/removing existing receipts. |
| 6.4 | **In-form preview + paperclip badge on `ExpenseCard`** | ✅ Compact attached-card UI with thumbnail, Replace, Remove. Tiny accent paperclip on rows with attached receipts. |
| 6.5 | **Full-screen viewer** | ✅ `ReceiptViewerView` — pinch-to-zoom (1×–5×), double-tap toggle, pan, native share sheet, destructive delete with confirmation. |
| 6.6 | **Lifecycle / orphan cleanup** | ✅ Replace deletes the prior file at save commit. CRUD layer cleans up on single/by-id/bulk delete via `Task.detached(.background)`. Once-per-foreground orphan sweep in `CashLensApp.scenePhase` catches any crash-window strays. |
| 6.7 | **Cross-device backup/restore via `.cashlens-archive`** | ✅ Pure-Swift STORE-only zip writer (`Utilities/Zip/CRC32.swift` + `ZipWriter.swift` + `ZipReader.swift`) bundles `data.json` plus every receipt JPEG into a single file. Zero external dependencies. Real `.zip` under the hood, opens anywhere. |

**What was built:**

- **`Utilities/ReceiptStorage.swift`** — pure file-IO helper, no Core Data, no `@MainActor`. Saves to `Documents/Receipts/<uuid>.jpg` at JPEG 0.7 with 2400 px max edge (downscaled via `UIGraphicsImageRenderer` to honest pixel dimensions, not points × scale). Stores **filename only** in `Expense.receiptImagePath` — never an absolute path — so iCloud restores, sandbox UUID changes, and Documents migrations never break the reference. Provides `save / url(for:) / loadImage / delete / cleanupOrphans(keep:) / totalBytesUsed`.
- **`Components/DocumentScannerView.swift`** — thin `UIViewControllerRepresentable` over VisionKit. Static `isSupported` for the rare device without document-camera support; we degrade silently to library-only on those.
- **`Views/ReceiptViewerView.swift`** — full-screen viewer with the standard zoom/pan/share/delete affordances. Uses `.ultraThinMaterial` for the floating control bar over the dark canvas. Local `ReceiptShareSheet` to avoid colliding with the existing `ShareSheet` in `ExportDataView.swift`.
- **`Models/Expense.swift`** — `receiptImagePath: String?` added with the same backward-compatible `decodeIfPresent` pattern as `paymentMethod`. Every legacy backup decodes cleanly.
- **`Models/ExpenseEntity+Extensions.swift`** + **`CashLens.xcdatamodeld`** — optional Core Data attribute (lightweight migration). Round-tripped in both directions of `fromExpense` / `toExpense`.
- **`Views/AddExpenseView.swift`** — `receiptField` between `notesField` and the save button. Two states (empty CTA card / attached preview card). Pro gate on capture buttons; free users get a lock chip and a paywall sheet on tap. PhotosPicker selection lands via `.onChange(of: pickedPhotoItem)` and routes through `attachReceipt(image:)` which compresses + persists off-main. Clean dismiss path (`cleanupUnsavedReceipt()` on the close button) deletes any session-attached file the user never committed by saving.
- **`Components/ExpenseCard.swift`** — accent-tinted paperclip badge in the title row when `receiptImagePath != nil`. Included in the `Equatable.==` so attach/detach re-renders without waiting for navigation.
- **`ViewModels/ExpenseViewModel+CRUD.swift`** — `updateExpense`, `deleteExpense(at:)`, `deleteExpenseById`, and `deleteExpenses(ids:)` all snapshot the prior `receiptImagePath`(s) before the Core Data save and dispatch `cleanupReceiptFiles(_:)` on a background detached task so the UI never blocks.
- **`CashLensApp.swift`** — `cleanupReceiptOrphansInBackground()` runs on every `scenePhase == .active` transition. Snapshots referenced filenames off the main view model, then hops to a detached background task for the directory sweep.
- **Info.plist (via build settings)** — `INFOPLIST_KEY_NSCameraUsageDescription` and `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` added to both Debug and Release configurations of the main app target. Required for VisionKit and PhotosPicker; without them the app would crash on first capture/pick.
- **`Views/PaywallView.swift`** — feature bullet updated to "**Receipt Scanner** / Scan or attach receipts — back up & restore with your CashLens archive". Honest about the cross-device story now that `.cashlens-archive` ships.
- **`Utilities/Zip/CRC32.swift`** — pure-Swift PKZIP CRC-32 (polynomial `0xEDB88320`) with a one-time 256-entry lookup table. ~80 ms for a 200 MB archive on A15-class hardware.
- **`Utilities/Zip/ZipWriter.swift`** — STORE-only ZIP writer. Streams entries directly to a `FileHandle` (atomic via sibling `.tmp` + rename), keeps only the central directory in memory, sets GP bit 11 for UTF-8 filenames, refuses inputs that would overflow the spec's 4 GB limit. ~150 LoC.
- **`Utilities/Zip/ZipReader.swift`** — STORE-only ZIP reader. Scans back from EOF for the EOCD signature (handles trailing comments up to 64 KiB), walks the central directory (the authoritative metadata source per spec — local headers can lie), rejects ZIP64 cleanly, **verifies CRC-32 on every extraction** so corrupt archives surface a useful per-entry error instead of bad bytes. ~200 LoC.
- **`Backup/BackupExporter.swift`** — new `Format.archive` case + `writeArchive(_:)`. Builds the JSON identically to `writeJSON` (so a `.cashlens-archive` opened in Finder / unzipped manually gives byte-identical `data.json` to a `.cashlens.json` export), then walks every expense's `receiptImagePath`, dedupes by filename, and writes `receipts/<filename>.jpg` entries.
- **`Backup/BackupImporter.swift`** — new `DetectedFormat.cashlensArchive` case routed by file extension (`.cashlens-archive` or `.cashlens-archive.zip` for share-extensions that re-stamp). Special preview path (`previewArchive`) copies the security-scoped source into our caches dir, opens with `ZipReader`, parses just `data.json` for the preview UI (no full receipt blob load). `apply` then re-opens the cached zip, restores every `receipts/*` entry to `Documents/Receipts/` (path-traversal sanitised), counts restored vs failed for the post-import sheet, and cleans up the cache copy.
- **`Views/ExportDataView.swift`** — third format option **"Full Archive"** with the `archivebox.fill` icon. Subtitle: *"Everything above + receipt photos"*. Bullet list calls out the single-file portability story.
- **`Views/ImportDataView.swift`** — `.fileImporter` accepts `UTType(filenameExtension: "cashlens-archive")` plus `.zip` as a fallback. `formatIcon` extended for `.cashlensArchive`. Preview surfaces a "Receipt photos" extras-row with the count from the archive; post-import summary surfaces "Receipt photos restored: +N" with a "M failed" badge if any entries couldn't be written.

**Storage budget:**

- ~150–400 KB per receipt (typical, JPEG 0.7 at 2400 px). 100 receipts ≈ 30 MB. 500 receipts ≈ 150 MB. Well within iOS's tolerance for app Documents data; flagged for revisit if power users push past 1 GB.

**Pro gating contract:**

- **Capture is Pro.** Free users see Scan + Library buttons with a "PRO" lock chip; tapping any opens `PaywallView`.
- **Viewing existing receipts is always free.** A Pro user who lapses keeps every receipt they previously attached, with full viewer access — they just can't capture new ones until they restore. Matches the "themes/icons persist after lapse" rule from Phase 4.
- **Removing existing receipts is always free.** Removing your own data is never gated.

**Cross-device portability — shipped via `.cashlens-archive`:**

- The user picks **Settings → Export → Full Archive** and gets a single `.cashlens-archive` file (under-the-hood a STORE-method zip — opens in Finder, Files.app, Windows Explorer, anything). The archive contains `data.json` plus every receipt JPEG keyed by filename.
- On the new device they pick **Settings → Import** and select the same file. Receipts restore to `Documents/Receipts/` before Core Data is touched, so a half-finished restore can never leave Core Data referencing files that aren't on disk.
- Why pure-Swift (no `ZIPFoundation` / `Compression` framework dependency): JPEGs are already compressed, so STORE method costs nothing in size and keeps the implementation surface tiny. The whole zip layer is ~250 LoC under our own control — no library version pinning, no transitive deps, no surprises.
- Why this isn't redundant with a future iCloud sync: CloudKit (not built; decision pending — see Version Plan) would handle **passive sync between the user's own devices**. The `.cashlens-archive` flow handles **explicit user-driven backup/restore** — the file users email themselves "just in case", AirDrop to a friend's phone, or save to Dropbox/Drive as an off-platform safety net. Today the archive is the only cross-device path.

**Deferred (originally "to v2.1"; still not built as of 2.2 planning, 2026-09-19):**

- **iCloud auto-sync via `NSPersistentCloudKitContainer`.** Different problem from cross-device backup — CloudKit gives passive multi-device sync without user action; the archive gives the user direct control over a portable file they own. **Status: not built; decision pending** (see Version Plan). Making iPad a first-class layout in 2.2 without sync is a known review risk.
- **System-wide UTType registration** (so tapping a `.cashlens-archive` in Files.app opens CashLens). Today the user goes through the in-app **Import** button and picks the archive from the file picker. Surfacing the type to iOS requires editing the project's Info.plist entries (the project uses `GENERATE_INFOPLIST_FILE = YES`, which makes `UTExportedTypeDeclarations` array-of-dict surgery fiddly). **Status: not built.**
- **Multi-image attachments per expense** (long pharmacy receipts, multi-page hotel folios). Today we take page 1 of any multi-page VisionKit scan (`DocumentScannerView`). Lifting this requires a model migration to `[String]` and a small UX rethink for the in-form preview. **Status: not built; candidate for 2.2** (small, Pro value).

**Testing checklist** (audited 2026-09-19 against the code on `redesign/v2`; there are no automated tests for any of these — `CashLensTests` is a stub — so "code-verified" means the code path exists and does what the item describes, not that it was exercised on a device):

- [ ] **Unverified (device run needed)** — First-time scan on a real device — VisionKit prompts for camera. Code: `INFOPLIST_KEY_NSCameraUsageDescription` is set in both Debug and Release configs of `project.pbxproj`.
- [ ] **Unverified (device run needed)** — Library picker on a real device. Code: `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` is set in both configs.
- [x] **Code-verified** — Free user → tap Scan → paywall opens; Pro → scanner opens. `AddExpenseView.handleScanTapped()` guards on `proManager.isPro` → `showingReceiptPaywall`, then on `DocumentScannerView.isSupported` → `showingScanner`. `handleLibraryTapped()` is only reachable for free users and opens the paywall; Pro users get a real `PhotosPicker`.
- [x] **Code-verified** — Attach + remove without saving → file deleted. `AddExpenseView.cleanupUnsavedReceipt()` runs on close for session-attached files; `attachReceipt(image:)` deletes a prior in-session file after the new one lands.
- [x] **Code-verified** — Replace receipt during edit → old file deleted on save commit. `ExpenseViewModel+CRUD.updateExpense` snapshots the prior `receiptImagePath` and dispatches `cleanupReceiptFiles` on `Task.detached` after the save.
- [x] **Code-verified** — Bulk-delete N expenses with receipts → files cleaned up. `deleteExpenses(ids:)` (and `deleteExpense(at:)` / `deleteExpenseById`) snapshot the paths before the save and clean up on a detached task.
- [x] **Code-verified** — Force-quit during attach → next foreground removes the orphan. `CashLensApp.cleanupReceiptOrphansInBackground()` runs on every `.active` transition, gated on `viewModel.isFullyHydrated` and a non-empty expense set so it can never wipe live receipts against a partial keep-set.
- [x] **Code-verified** — JSON backup with a receipt-bearing expense round-trips. `Expense` encodes/decodes `receiptImagePath`; the paperclip badge in `ExpenseCard` keys off `receiptImagePath != nil`. The image only exists on the device that holds the file (JSON carries the filename, not the bytes). Unverified on device.
- [x] **Code-verified** — Pre-2.0 JSON backup still imports. `Expense.init(from:)` uses `decodeIfPresent` for `receiptImagePath` (and `isRefund`, `paymentMethod`, `tags`).
- [ ] **Unverified (needs two devices)** — Export Full Archive → AirDrop → import on a second device with 0 / 1 / 50 receipts. Code: `BackupExporter.writeArchive` and `BackupImporter.restoreReceipts(fromArchive:)` exist; receipts are restored before Core Data is touched.
- [ ] **Unverified (manual)** — Open a `.cashlens-archive` in 7-Zip / Finder. Code: `ZipWriter` is a STORE-only PKZIP writer with a standard central directory; `writeArchive` configures its `JSONEncoder` identically to `writeJSON` (`.prettyPrinted, .sortedKeys, .withoutEscapingSlashes`, ISO-8601 dates) so `data.json` should be byte-identical — not confirmed by a test.
- [x] **Code-verified** — Truncated archive is rejected. `ZipReader` throws `Error.truncated` when the EOCD/central directory can't be read and `Error.crcMismatch(name:expected:actual:)` on every extraction whose CRC-32 fails; `BackupImporter.apply` fails the import before touching Core Data if the archive can't be opened.
- [ ] **Unverified (manual)** — Re-import the same archive twice in merge mode is idempotent. Code: expense dedup by ID then content exists in `BackupImporter.apply`; receipt restore overwrites by filename. The exact "+0 / +N skipped" summary copy is not covered by a test.

---

### Phase 7: Forecasting & Projections — SHIPPED ✅

| # | Feature | Status |
|---|---------|--------|
| 7.1 | **Historical Pattern Analysis** | ✅ Recency-weighted weekday seasonality + outlier capping in `ForecastEngine` |
| 7.2 | **Projection Chart** | ✅ 30/60/90-day horizon chart with ±1σ confidence band |
| 7.3 | **Subscription Impact View** | ✅ "Subscriptions" mini-card showing $ and % of forecast |

**What was built:**

- **`Utilities/ForecastEngine.swift`** — pure, Sendable-safe compute. Single entry point: `ForecastEngine.compute(history:upcomingSubscriptions:horizonDays:)` returns a `Forecast` struct with per-day points, headline sums, confidence range, and a top-driver category. Algorithm:
  1. Last 90 days of history, filtered to discretionary expenses (`isFromSubscription == false`) so subscription cashflows aren't double-counted when added back as overlays.
  2. Daily totals bucketed by `Calendar.weekday` — each future day projects from its own weekday's mean.
  3. Recency weighting via `0.5 ^ (daysAgo / 30)` so habit changes show up quickly.
  4. Outlier capping at `mean + 3σ` on a provisional pass, then re-meaning, so a single $1,200 day doesn't poison Tuesday.
  5. Subscription overlay walks each active sub forward from `nextDueDate` using `Subscription.calculateNextDueDate(...)` with a 400-iteration safety cap.
  6. Confidence band is ±1σ of daily residuals from the weekday mean, clamped to ≥0 with an 8% floor on the band width so it never collapses to a misleading zero on flat data.
  7. Data-quality gate suppresses the projection when there's `< 14 days` of history or `< 5` active spending days.

- **`Components/ForecastChart.swift`** — SwiftUI Charts renderer. Solid `LineMark` for actual history, dashed `LineMark` for projection (with a "bridge" point so there's no visual gap at "today"), faint `AreaMark` confidence band, vertical `RuleMark` for "Today", yellow `PointMark` dots on subscription cashflow days. Render-only.

- **`Views/ForecastSection.swift`** — section composer. Pro: horizon switcher (`30d / 60d / 90d`, gradient pill capsule), headline card (projected total + range + chart + legend), Subscriptions and Top Driver mini-cards side-by-side. Free: premium teaser (gradient icon + three preview pills + "Try Pro" capsule + lock badge) matching the Pro Insights teaser style. `InsightInfoButton(.forecast)` opens a plain-English explanation sheet.

- **`Components/InsightInfoButton.swift`** — added `InsightInfo.forecast` copy entry.

- **`Views/StatisticsView.swift`** — added `cachedForecast` + `forecastHorizon` state, computes the forecast on the same `Task.detached` pipeline as the rest of the stats (loading active subscriptions from a `newBackgroundContext()`), slots `ForecastSection` between Pro Insights and Highlights, recomputes immediately when the horizon is switched. The forecast deliberately uses **all** expenses (not the date-range filter) — looking-back ≠ looking-forward.

**Files created:**
- `CashLens/Utilities/ForecastEngine.swift`
- `CashLens/Components/ForecastChart.swift`
- `CashLens/Views/ForecastSection.swift`

**Files modified:**
- `CashLens/Views/StatisticsView.swift` — wired forecast into recompute pipeline + layout
- `CashLens/Components/InsightInfoButton.swift` — added `.forecast` copy

---

### Phase 8: Multi-Currency with Live Rates — NOT BUILT (deferred)

**Status (2026-09-19): Not built, deferred until App Store Connect data shows demand.** The app still has a single global currency (`selectedCurrency`, 170+ codes with locale auto-detection); `ExpenseViewModel+Currency.syncCurrencyAcrossStoredData()` bulk-rewrites every stored row when it changes. None of the files listed under "Files to create" exist. This is the only phase in the roadmap with no shipped code. It would also be the first feature to add a network dependency to an app whose privacy positioning is "no servers, no trackers" — that trade-off needs a decision before any build starts.

| # | Feature | Risk | Effort | Revenue Impact | Status |
|---|---------|------|--------|----------------|--------|
| 8.1 | **Per-Expense Currency** | Medium | High | — | Not built |
| 8.2 | **Exchange Rate API** | Medium | Medium | — | Not built |
| 8.3 | **Conversion Display** | Medium | Medium | High — travelers/expats | Not built |

**Details (original design, unchanged):**

- **Per-Expense Currency:** Currently all expenses forced to `selectedCurrency`. Pro allows choosing currency per expense. Home currency used for totals via conversion.
- **Exchange Rate API:** Free API (e.g., exchangerate.host), cached daily. Stored locally. Fallback to last cached rate if offline.
- **Conversion Display:** Expense card shows original currency + converted amount in home currency. Totals always in home currency.

**Risk Note:** This is the most invasive change. The current `updateAllExpensesToCurrentCurrency` pattern bulk-overwrites all currencies. Pro multi-currency would need to preserve original currency and add a separate `convertedAmount` path.

**Files to create:**
- `CashLens/Models/ExchangeRateCache.swift`
- `CashLens/Utilities/CurrencyConverter.swift`

**Files to modify:**
- `CashLens/ViewModels/ExpenseViewModel+CRUD.swift` — stop forcing currency on add (for Pro users)
- `CashLens/ViewModels/ExpenseViewModel.swift` — conversion-aware totals
- `CashLens/Views/AddExpenseView.swift` — per-expense currency picker
- `CashLens/Components/ExpenseCard.swift` — dual currency display

---

### Phase 9: Expense Power Pack — SHIPPED ✅

A bundle of four expense-flow upgrades that compound daily value: smart auto-category, no-spend streak, bulk select & action, and refund tracking. All four are shipped to free users (no paywall) because they raise the floor of the entire app's expense experience; gating them would penalize logging discipline.

| # | Feature | Risk | Effort | Status |
|---|---------|------|--------|--------|
| 9.1 | **Smart auto-category** | Low | Low | ✅ Shipped |
| 9.2 | **No-spend streak** | Low | Low | ✅ Shipped |
| 9.3 | **Bulk select & action** | Medium | Medium | ✅ Shipped |
| 9.4 | **Refund tracking** | Medium-High | Medium | ✅ Shipped |

**What was built:**

- **9.1 Smart auto-category:** `CategorySuggester` builds an on-device frequency map from up to the last 1500 expenses, normalises titles (lowercased, punctuation stripped), and matches both exactly and via token overlap. Surfaces a single non-intrusive "Suggested" pill in `AddExpenseView` once the title hits 2+ chars and confidence ≥ 0.45. Tapping it sets the category with a haptic. Free, fast (O(n) over recent history), no network.
- **9.2 No-spend streak:** `StreakCalculator` derives no-spend days this month, current streak, and best streak (90-day lookback) from local data. `HomeView` shows a compact leaf chip on the hero card only when the streak is meaningful (current ≥ 2 days, or month progress ≥ 3 no-spend days), so it never clutters new accounts. Refund-aware via `signedAmount`.
- **9.3 Bulk select & action:** `AllExpensesView` now has a "Select" toggle in the toolbar. Selection mode reveals checkboxes per row and a sticky bottom action bar with **Category**, **Tag**, and **Delete** actions plus a live count. Bulk operations use new `ExpenseViewModel+CRUD` methods (`deleteExpenses`, `bulkChangeCategory`, `bulkAddTag`) that batch into a single Core Data save. Tap-to-toggle in selection mode, tap-to-edit otherwise — no accidental edits.
- **9.4 Refund tracking:** New optional `isRefund` Boolean on `ExpenseEntity` (lightweight migration, default `NO`). `Expense.signedAmount` returns `-amount` for refunds; new `Sequence.netTotal()` extension sums signed amounts. **Every aggregator was audited** and switched to refund-aware totals: `ExpenseViewModel.computeTotals`, `StatisticsCalculator` (insights, category breakdown, weekday averages, top spending days), `AdvancedStatsCalculator` (year-over-year), `ExpenseTrendChart`, `SpendingHeatmap` (clamps day to 0), `ForecastEngine` (clamps day to 0), `BudgetViewModel` (floors at 0), `NotificationScheduler.DigestStatsCalculator`, `AllExpensesView` day headers, `QuickSearchView` summary, `HomeView` hero & pinned categories. UI: `ExpenseCard` shows a green "Refund" badge and `-amount` in green; `AddExpenseView` has a refund toggle row above the title field. Backup: CSV gains an `Is Refund` column; JSON uses `decodeIfPresent` so old backups still import unchanged.

**Why ship for free:**
- Bulk select and refunds are correctness/quality-of-life features users expect from any modern finance app — gating would generate negative reviews.
- Smart auto-category and no-spend streak are habit drivers that increase logging frequency, which directly feeds Pro features (forecasting, advanced stats, budgets) with richer data.

**Files created:**
- `CashLens/Utilities/CategorySuggester.swift`
- `CashLens/Utilities/StreakCalculator.swift`

**Files modified (model + aggregation layer):**
- `CashLens/CashLens.xcdatamodeld/CashLens.xcdatamodel/contents` — `isRefund` attribute
- `CashLens/Models/Expense.swift` — `isRefund`, `signedAmount`, `netTotal()`, backward-compatible decode, JSON/CSV import
- `CashLens/Models/ExpenseEntity+Extensions.swift` — round-trip `isRefund`
- `CashLens/ViewModels/ExpenseViewModel.swift` — refund-aware totals
- `CashLens/ViewModels/ExpenseViewModel+CRUD.swift` — `isRefund` persist + bulk APIs
- `CashLens/Utilities/StatisticsCalculator.swift`
- `CashLens/Utilities/AdvancedStatsCalculator.swift`
- `CashLens/Utilities/ForecastEngine.swift`
- `CashLens/Utilities/NotificationScheduler.swift`
- `CashLens/Utilities/ExpenseDraft.swift` — refund draft persistence
- `CashLens/Components/ExpenseCard.swift` — refund badge + signed amount display
- `CashLens/Components/ExpenseTrendChart.swift`
- `CashLens/Components/SpendingHeatmap.swift`
- `CashLens/Backup/BackupExporter.swift` — CSV `Is Refund` column

**Files modified (UI):**
- `CashLens/Views/AddExpenseView.swift` — refund toggle + suggested-category pill
- `CashLens/Views/AllExpensesView.swift` — selection mode + bulk action bar + bulk sheets
- `CashLens/Views/HomeView.swift` — no-spend streak chip; pass `isRefund` to editor
- `CashLens/Views/QuickSearchView.swift` — pass `isRefund` to editor; signed totals

**Migration safety:**
- Core Data: optional Boolean with `defaultValueString="NO"` → lightweight migration only, no schema rewrite needed.
- JSON backups: custom `Expense.init(from:)` uses `decodeIfPresent`; missing `isRefund` defaults to `false`.
- CSV backups: importer treats missing `Is Refund` column as `false`; old exports remain valid.
- Aggregation: every total is now `signedAmount` based, but for non-refund expenses `signedAmount == amount`, so existing data renders identically until users mark refunds.

---

### Phase 10: Browse & Reuse Polish — SHIPPED ✅

Two free, additive polish features that complete the "expense lifecycle" loop: a calendar surface for *browsing* expenses by date and saved templates for *reusing* common entries. Both ship to free users — they're enhancements to flows that should always feel premium.

| # | Feature | Risk | Effort | Status |
|---|---------|------|--------|--------|
| 10.1 | **Expense Calendar View** | Low | Medium | ✅ Shipped |
| 10.2 | **Expense Templates** | Low | Low | ✅ Shipped |

**What was built:**

- **10.1 Expense Calendar (`ExpenseCalendarView.swift`)** — A modal month-grid surface reachable from `AllExpensesView`'s toolbar (calendar icon next to the search icon, on iPhone *and* iPad layouts). Each day cell shows the day number, up to three colored category dots (top categories that day by absolute amount), and a compact net total (e.g. `$42`, `$1.2k`). Today is highlighted with a soft primary tint; future days are visually muted and non-tappable. Tapping a day expands a detail section beneath the grid showing that day's expenses (sorted newest-first), with full edit capability via the same `AddExpenseView` editor used everywhere else — no separate code path. A summary strip below the grid surfaces month-level net total, transaction count, and active-day count. Aggregation runs in `Task.detached` and is rebuilt on month change or `viewModel.$expenses` updates, so swiping between months never blocks the main thread. Read-only browsing — never mutates data directly. Complements the heatmap (intensity) without duplicating it (browsing).

- **10.2 Expense Templates (`ExpenseTemplate.swift` + `ExpenseTemplateStore.swift`)** — User-saved presets (`Morning coffee · $4 · Food`, `Gas · Transportation`, etc.) that surface as a horizontal chip strip at the top of `AddExpenseView`. Tap a chip to fill the form (with the rule: never overwrite anything the user has already typed; tags/notes/refund flag are *additive* only). A bookmark icon in the form's header lets the user save the current form as a template, with a quick rename alert. Long-press / context-menu on a chip offers "Use" or "Delete". Storage is `UserDefaults`-backed (no Core Data migration), capped at 12 templates with LRU-style eviction. Most-recently-used surfaces first so frequent presets gravitate to the top. Templates live across app launches and are intentionally local-only — they're shortcuts, not data, so they're not part of the JSON/CSV backup payload.

**Why ship for free:**
- The calendar view is a *navigation* affordance — gating it would penalise users who simply want to find an expense from last Tuesday.
- Templates are a daily-driver speed boost. Charging for "type less" feels punitive and doesn't pair with the kind of feature density users expect from Pro.

**Files created:**
- `CashLens/Views/ExpenseCalendarView.swift`
- `CashLens/Models/ExpenseTemplate.swift`
- `CashLens/Utilities/ExpenseTemplateStore.swift`

**Files modified:**
- `CashLens/Views/AllExpensesView.swift` — calendar toolbar button + sheet wiring (iPhone + iPad branches).
- `CashLens/Views/AddExpenseView.swift` — templates chip strip above the form, "Save as template" header button, apply/delete flows with safe-merge semantics.

**Migration safety:**
- Core Data schema is untouched — templates use `UserDefaults` (`expense_templates_v1` key, internal to `ExpenseTemplateStore`).
- Apply-template logic *never* clobbers user-entered title/amount; tags/notes are merged additively.
- Calendar view never writes to Core Data directly; edits round-trip through `viewModel.updateExpense(...)` exactly like every other surface.
- Existing JSON/CSV exports unchanged — templates are local-only by design.

---

### Phase 11: Payment Method Tracking — SHIPPED ✅

A free, frictionless data-capture upgrade plus a Pro analytics surface. **Capturing** the payment method is free for everyone (you can't gate the data layer or you end up with dirty data), but **seeing** the cross-method donut is Pro — the moment a user upgrades, an instant new view appears that's powered by data they've already been collecting.

| # | Feature | Risk | Effort | Status |
|---|---------|------|--------|--------|
| 11.1 | **Per-expense `paymentMethod`** (free) | Low | Low | ✅ Shipped |
| 11.2 | **Payment Methods donut + breakdown** in Statistics (Pro) | Low | Medium | ✅ Shipped |

**What was built:**

- **11.1 Payment method picker (`PaymentMethod.swift`):** New enum with seven canonical methods (Cash / Credit / Debit / UPI / Bank Transfer / Wallet / Other), each carrying a display name, short label, SF Symbol, and tinted color. `PaymentMethod.tolerant(from:)` parses common aliases ("credit card", "visa", "venmo", "gpay", etc.) so foreign-CSV imports map cleanly. `AddExpenseView` shows a horizontal pill scroller (with a "None" pill to clear) right under Category — same shape language as the category picker so the form feels unified. Tapping the active pill clears the choice; long names wrap-safe via `.lineLimit(1)`.

- **11.2 Payment Methods Statistics section:** New Pro section (between *Where It Goes* and *Spending Pattern*) that mirrors the category-donut pattern: `CategoryDonutChart` reused with payment-method slices, a per-method row list with tinted icon medallions, exact amount, count, and percentage. Selecting a slice highlights its row (and vice versa) via `paymentDonutSelectedId`. Untagged expenses are surfaced as a "tag x more" footer instead of polluting the donut, with a coverage % so the user can see progress. Free-tier users see a focused upgrade teaser (icon + headline + CTA) — no live donut — so the Pro reveal feels meaningful. Aggregation runs in the existing background recompute pass via `StatisticsCalculator.paymentMethodBreakdown` (refund-aware, O(n)).

**Why this gating split:**
- Capturing the method has to be free — gating it would create dirty data ("free users have nil, Pro users have values"), making the donut useless until a critical mass of Pro users tag enough expenses.
- The donut + breakdown is a true *insight*, not a logging affordance, so it lands cleanly in the Pro tier alongside Forecasting and Advanced Insights.
- Backup/restore captures the field for everyone (CSV gains a "Payment Method" column; JSON uses `decodeIfPresent` for backward compatibility), so a free user who upgrades doesn't lose history.

**Files created:**
- `CashLens/Models/PaymentMethod.swift`
- `CashLens/Models/PaymentMethodBreakdown.swift`

**Files modified (model + persistence):**
- `CashLens/CashLens.xcdatamodeld/CashLens.xcdatamodel/contents` — optional `paymentMethod` String attribute on `ExpenseEntity` (lightweight migration)
- `CashLens/Models/Expense.swift` — `paymentMethod`, custom `Codable` (`decodeIfPresent`), JSON + CSV import
- `CashLens/Models/ExpenseEntity+Extensions.swift` — round-trip via raw value
- `CashLens/Models/ExpenseTemplate.swift` — templates remember the method too, so reusing a template fills it
- `CashLens/Utilities/ExpenseDraft.swift` — drafts persist the method
- `CashLens/ViewModels/ExpenseViewModel+CRUD.swift` — `updateExpense` saves it
- `CashLens/Backup/BackupExporter.swift` — CSV gains "Payment Method" column (12th)
- `CashLens/Backup/GenericCSVAdapter.swift` — header synonyms + tolerant parsing for foreign CSVs

**Files modified (UI):**
- `CashLens/Views/AddExpenseView.swift` — `paymentMethodField` pill scroller, draft autosave on change, template apply/snapshot includes method
- `CashLens/Views/HomeView.swift`, `AllExpensesView.swift`, `QuickSearchView.swift`, `ExpenseCalendarView.swift` — `onSave` signature now carries `PaymentMethod?`; init forwards the existing value when editing
- `CashLens/Utilities/StatisticsCalculator.swift` — `paymentMethodBreakdown(filteredExpenses:)` aggregator
- `CashLens/Views/StatisticsView.swift` — new `paymentMethodsSection` + `paymentDonutSelectedId` + cached breakdown plumbed through the recompute pass
- `CashLens/Components/InsightInfoButton.swift` — `.paymentMethods` info copy

**Migration safety:**
- Core Data: optional String attribute → lightweight migration only.
- JSON backups: `decodeIfPresent` defaults to `nil`; old backups import unchanged.
- CSV backups: missing column = `nil`; old exports remain valid.
- Foreign CSV imports: header synonyms cover the common aliases used by Mint, YNAB, Splitwise, etc., so payment method maps even when a user imports a third-party file.

---

### Phase 12: Proactive Smart-Insight Notifications — SHIPPED ✅

A single Pro-gated weekly notification that fires **only** when something genuinely interesting happened ("Your Food spend is 2.4× higher this week"). Reuses the existing notification scheduler. Built around a strict firing bar so the inbox never feels noisy.

| # | Feature | Risk | Effort | Status |
|---|---------|------|--------|--------|
| 12.1 | **Smart Insights engine** | Low | Medium | ✅ Shipped |
| 12.2 | **Weekly scheduling + Pro toggle** | Low | Low | ✅ Shipped |

**What was built:**

- **12.1 Engine (`SmartInsightsEngine.swift`):** Pure, `Sendable`-safe value-type code that scans the user's expense history and produces a single highest-priority headline (or `nil`). Six insight kinds in priority order:
  1. `streakRecord` — "Personal best — N no-spend days last week" (≥ 4 days, must have ended within 14 days)
  2. `refundWindfall` — Refunds outpaced spending last week (net < -$50)
  3. `categorySpike` — One category ≥ 2.4× its 4-week average **and** ≥ $50 absolute delta ("Food spike")
  4. `categoryAllTime` — Highest week ever for a category over a 12-week lookback (with non-zero prior history)
  5. `subscriptionsDue` — 3+ active subscriptions renewing in the next 7 days (with total)
  6. `weekTotalNew` — Highest-spend week in the last 12 (≥ $200, ≥ 4 weeks of history)
  
  Each insight carries a **fingerprint** (e.g. `spike:food:2026-w16`); `SmartInsightsEngine.record(insight:)` writes it to a `UserDefaults`-backed `HistoryRecord`, and the engine refuses to re-fire the same fingerprint within `cooldownDays = 14`. The history is auto-pruned at 60 days so it never grows unbounded.

- **12.2 Scheduler (`NotificationScheduler.scheduleNextSmartInsight`):** Hooks into the existing `refreshScheduledNotificationsIfNeeded` flow that runs on every app foreground. Default fire slot is **Sunday 10 AM** local time — a calm, weekly recap moment that doesn't compete with the Weekly Digest. The scheduler:
  - Cancels any pending request first (idempotent across foregrounds).
  - Builds engine inputs on the main actor (live expense set, active subscriptions fetched off-context, formatted-amount/category-display closures from the view model).
  - Calls `selectInsight(...)`. If `nil`, **no notification is scheduled** — a boring week stays silent.
  - On a hit, schedules a single `UNTimeIntervalNotificationTrigger` with the insight body, routes taps to All Expenses for the past week, and persists the firing to history.
  - Gated by `ProManager.isPro` — the scheduler accepts an `isPro` parameter passed from the Pro-aware call sites (`CashLensApp` foreground hook + every notification toggle in `ProfileView`).

- **ProfileView toggle:** Pro users see a Smart Insights row under Reminders with a `.tint(.appPrimary)` toggle. Free users see the same row with a "Pro" lock pill — tapping it opens the paywall directly. Discoverability without a hidden setting.

**Files created:**
- `CashLens/Utilities/SmartInsightsEngine.swift`

**Files modified:**
- `CashLens/Utilities/NotificationScheduler.swift` — `scheduleNextSmartInsight`, `smartInsightWeekly` identifier, `refreshScheduledNotificationsIfNeeded(isPro:)`, history persistence helpers, background-context subscription fetch
- `CashLens/Utilities/UserDefaultsKeys.swift` — `smartInsightsEnabled`, `smartInsightsHistory`, `smartInsightsLastFireDate`
- `CashLens/Views/ProfileView.swift` — `smartInsightsToggleRow` Pro/free variants
- `CashLens/CashLensApp.swift` — passes `proManager.isPro` to the foreground refresh

**Anti-spam properties:**
- One push per week max — multi-insight weeks collapse into the highest-priority headline.
- Boring weeks produce zero pushes (no "filler" notifications ever).
- Same headline can't repeat for 14 days (fingerprint cooldown).
- Free-tier downgrades immediately stop scheduling on the next foreground.

**Migration safety:**
- No Core Data changes — entirely additive `UserDefaults` keys, all defaulting to safe falsy values.
- Engine is pure value-type code; no shared mutable state, no force-unwraps.
- All scheduling paths are idempotent: a repeated foreground refresh either re-confirms the same insight, swaps to a new one, or stays silent — never produces duplicate pushes.

---

### Phase 13: v2 Redesign & Pre-Submission Wave — SHIPPED ✅ (as App Store 2.1)

> This phase was never written up when it was built — the numbering jumped from 12 to 14. Reconstructed on 2026-09-19 from the code on `redesign/v2` and `git log` (`777ee11` … `9ed0450` v2 redesign, May 2026; `74f476a` pre-submission wave, 2026-07-15; `60382e3` 2.0.0 (6); `4029ae0` 2.0.1 (7), 2026-08-29). Everything below is on the App Store as 2.1 except where marked.

Not a single feature but the release that turned the Pro wave into a shippable app: a new information architecture, a new landing screen, and the pre-submission set of trust, privacy and reach features. Tier per item is what the code enforces today.

| # | Item | Tier | Where | Status |
|---|------|------|-------|--------|
| 13.1 | **4-tab IA — Today / Activity / Insights / You** (was Home / Subscriptions / Statistics with Profile behind a header icon). iOS 26+ uses the native `TabView` + `SwiftUI.Tab` floating bar; iOS 18–25 keeps a custom bar. FAB on every tab except You. | Free | `Views/MainTabView.swift` | ✅ Shipped |
| 13.2 | **Today screen** — verdict hero (spend vs budget, days left, projected month-end, On Track / Tight / Over), 7-day strip, upcoming bills, recent, one `SmartInsightsEngine` insight, stacked budgets card, recap card; sections reorderable / hideable | Free (budget verdict needs a Pro budget; degrades to pace-vs-typical without one) | `Views/TodayView.swift`, `Views/TodayCustomizeView.swift` | ✅ Shipped |
| 13.3 | **Activity tab** — `AllExpensesView` promoted from a sheet to a tab root; List / Calendar toggle embeds `ExpenseCalendarView`; single search surface via `QuickSearchView` | Free (tag filter + bulk tag stay Pro) | `Views/AllExpensesView.swift` | ✅ Shipped |
| 13.4 | **You tab** — `ProfileView` promoted to a tab; every destination is a sheet (no root `UINavigationController`); grouped into Pro card / General / Privacy & Security / Personalization / Manage / Notifications / Data / About; `NotificationsSettingsView` hub behind the single "Reminders & Insights" row | Free | `Views/ProfileView.swift`, `Views/NotificationsSettingsView.swift` | ✅ Shipped |
| 13.5 | **Monthly Recap** — v2 rebuild of the deleted paged recap: single scrolling card sequence + `ShareLink` of an `ImageRenderer` card; Today card early in a new month + permanent Insights row | Free (shared card = organic growth) | `Utilities/MonthlyRecapEngine.swift`, `Views/MonthlyRecapView.swift` | ✅ Shipped |
| 13.6 | **App Lock** — Face ID / Touch ID / passcode with Immediately / 1 min / 5 min grace; privacy cover while inactive; relock-loop guards; deep links parked while locked | Free ("your money stays your business" is not a paywall) | `Utilities/AppLockManager.swift`, `Views/AppLockView.swift` | ✅ Shipped |
| 13.7 | **Siri / Shortcuts** — `LogExpenseIntent` (`IntentCurrencyAmount`, required title, category inference) and `GetSpendingIntent`, zero-setup phrases via `CashLensShortcuts`; headless writes through `QuickLogService` | Free | `Intents/`, `Utilities/QuickLogService.swift`, `Views/SiriShortcutsTipsView.swift` | ✅ Shipped |
| 13.8 | **Quick Log widget** (interactive) — today's total + one-tap template buttons; widget-process intent appends to `PendingExpenseQueue`, app drains on foreground | Free with 1 template; extra templates Pro | `CashLensWidgets/QuickLogWidget.swift`, `Shared/PendingExpenseQueue.swift` | ✅ Shipped |
| 13.9 | **Receipt OCR** — on-device Vision text recognition fills empty amount / merchant after a capture; never overwrites typed values; silent on failure | Pro (inherits the capture gate) | `Utilities/ReceiptOCRService.swift`, `AddExpenseView.runReceiptOCR` | ✅ Shipped |
| 13.10 | **Appearance Studio** — mode selector + 12 duotone themes (6 Classics + 6 Pastels) + "Complete the look" icon pairing; replaces `ThemePickerView` | Mode free; themes / icons Pro | `Views/AppearanceStudioView.swift`, `Models/AppTheme.swift` | ✅ Shipped (extends Phase 4) |
| 13.11 | **Custom budget date ranges** — `Budget.Period.custom` with `customStartDate` / inclusive `customEndDate`; Core Data model v2 | Pro | `Models/Budget.swift`, `CashLens 2.xcdatamodel` | ✅ Shipped (extends Phase 2) |
| 13.12 | **Privacy Dashboard** + **privacy manifests** (`PrivacyInfo.xcprivacy` in both targets) | Free | `Views/PrivacyDashboardView.swift` | ✅ Shipped |
| 13.13 | **Store recovery** — if the Core Data store fails to load, show `StoreRecoveryView` (never delete, offer raw `.sqlite` export) instead of crashing | — | `Persistence.swift`, `Views/StoreRecoveryView.swift` | ✅ Shipped |
| 13.14 | **Save error banner + save confirmation toast** — every `context.save()` failure is surfaced; successes get a short toast | — | `Utilities/SaveErrorReporter.swift`, `Components/SaveErrorBanner.swift`, `Components/SaveConfirmationToast.swift` | ✅ Shipped |
| 13.15 | **Post-value auto-paywall** — shows once, right after the save that crosses 10 expenses (`PaywallTrigger`); `PaywallContext` copy per feature; intro-offer eligibility check so "free trial" is never promised to an ineligible Apple ID | — | `Utilities/PaywallTrigger.swift`, `Views/PaywallView.swift`, `ProManager.isEligibleForIntroOffer` | ✅ Shipped |
| 13.16 | **Win-back sheet** after a Pro → free lapse (once per lapse, never for donors, "No thanks" is permanent) + **donor thank-you** sheet | — | `Views/WinBackView.swift`, `Views/DonorThanksView.swift`, `ProManager` | ✅ Shipped (mechanics in [Donor Grandfathering](#donor-grandfathering-wave-2)) |
| 13.17 | **Native one-tap rating prompt** — `requestReview` driven by `FeedbackManager` (12 actions across 3+ days or 5 after an export; 30-day cooldown; max 3; threshold 12 so it never collides with the 10th-expense paywall); replaced the custom modal | — | `MainTabView` (+ `Utilities/FeedbackManager.swift`, deleted in 2.2) | ✅ Shipped in 2.0.1 (7); **replaced in 2.2** by `ReviewPromptManager` (once per major.minor version, at the 10th expense or a 7-day streak, never over onboarding / paywall / any presentation / a dismissing sheet; the ask is spent only when actually shown) |
| 13.18 | **Single StoreKit transaction listener** — `ProManager` owns `Transaction.updates`, routes donations to `DonationManager`, finishes each transaction once (fixed a race that could drop a donation) | — | `Models/ProManager.swift` | ✅ Shipped |
| 13.19 | **Promoted In-App Purchases** — `PurchaseIntent.intents` listener so App Store product-page purchases complete in-app; promo images for yearly + lifetime. On `release/2.2` the listener also routes promoted tip products to `DonationManager.purchase()` (`7289d22`) | — | `ProManager.listenForPurchaseIntents()`, `Marketing/PromoImages/` | ⏳ **Unshipped** — on `redesign/v2` (2026-09-02) and `release/2.2`, not in store 2.1; ships in 2.2 |
| 13.20 | **Audit fixes** from the pre-submission review — atomic backup import, App Lock deep-link gating, save-success gating on CRUD paths, notification scheduling retries, PII-free release logging (`QuickLogService.diagTrail` redaction), restore-purchases feedback, dead-code removal; perf: visibility-gated Activity recomputes, equality-gated budget publishes, widget snapshot diffing | — | various | ✅ Shipped |

**Known leftovers from the redesign** (as of 2026-09-19): `PinnedCategoryCard`, `SummaryCustomizationView` and `DiagnosticsView` have no call sites — they belonged to the old Home screen / Profile. `DonationManager` still exists and is used; the "Support the App" row lives under You → About. Store 2.1 also shipped two different support addresses (`email@rushiraj.me` in the app, `rjadeja053@gmail.com` on the site); 2.2 unifies on `AppConstants.supportEmail = rjadeja053@gmail.com` (`4810369`).

**Not done in this phase (see Version Plan):** adaptive layout for iPad / landscape / iPhone SE — store 2.1 is a universal binary but a stretched phone layout on iPad (no sidebar, one `horizontalSizeClass` check, `userInterfaceIdiom` branches, fixed chart heights, fixed 3–4 column grids, no `systemExtraLarge` widgets). Being addressed on `release/2.2` (see the 2.2 row below). Also not done: iCloud sync, multi-currency.

---

### Phase 14: Home & Lock Screen Widgets (Pro) — ✅ SHIPPED

| # | Widget | Sizes | Tier | Risk | Status |
|---|--------|-------|------|------|--------|
| 14.1 | **Spending Snapshot** | Small / Medium / Large + Lock circular / rectangular / inline | Free (hero surface) | Low | ✅ Shipped |
| 14.2 | **Budget Progress** | Small / Medium | Pro | Low | ✅ Shipped |
| 14.3 | **Subscriptions Due** | Medium | Pro | Low | ✅ Shipped |
| 14.4 | **No-Spend Streak** | Small / Medium + Lock circular / rectangular / inline | Pro | Low | ✅ Shipped |
| 13.8 | **Quick Log** (interactive) | Small / Medium | Free with 1 template; more templates Pro | Medium | ✅ Shipped later, in the pre-submission wave — see Phase 13 |

The bundle therefore vends **seven** widgets (five Home Screen + two Lock Screen), not six. None supports `systemExtraLarge` (iPad) yet: `release/2.2` already writes `WidgetSnapshot.dailyNetLast7Days` (7 refund-adjusted daily nets, oldest first, from `WidgetSnapshotBuilder.buildDailyTotals`) for an Extra Large Spending sparkline, but the widget that reads it lives in the unmerged PR #8 (`feat/2.2-widgets-tests`).

**Architecture:**

The widget extension cannot reach the main app's Core Data store directly, so the main app **projects** a versioned `WidgetSnapshot` JSON into an App Group (`group.com.rushi.CashLens.shared`), and the widgets read it. This keeps the widget surface narrow (no `NSManagedObjectContext` gymnastics in extensions, no concurrency hazards) and makes the data contract auditable: one struct (`Shared/WidgetSnapshot.swift`), one file (`WidgetSnapshot-v1.json`), one read/write helper (`Shared/WidgetSnapshotIO.swift`).

**Flow:**

1. **Mutation in main app** (add expense, update budget, change theme, currency switch, Pro purchase, custom category edit, subscription Core Data save) →
2. `WidgetSnapshotCoordinator` (main app) hears it via Combine subscriptions or `NSManagedObjectContextDidSave` →
3. Coalesces with a **300 ms debounce** so a burst of `@Published` emits writes only one snapshot →
4. Marshals an immutable `WidgetSnapshotBuilder.Inputs` value, hands it to a `Task.detached(priority: .utility)` →
5. Builder produces the snapshot off-main, `WidgetSnapshotIO.write(_:)` writes atomically →
6. `WidgetCenter.shared.reloadAllTimelines()` tells the system to refresh every CashLens widget on every screen.

**Data contract (`Shared/WidgetSnapshot.swift`):**

A single `Codable, Hashable, Sendable` struct carrying:

- `schemaVersion: Int` (bumped on incompatible changes; the widget falls back to `placeholder` if it sees a future version it can't decode).
- `generatedAt`, `currencyCode`, `isPro`, `activeThemeId`, `userName`.
- `spending.byTimeframe[.today/.week/.month/.year]` — pre-aggregated `TimeframeAggregate` (net, previousNet, top categories, count). The widget never iterates raw expenses.
- `budgets[]` — pre-computed usage / cap / days remaining / over-budget flag.
- `upcomingSubscriptions[]` — sorted by `nextDueDate`, capped at 6, filtered to the next 14 days.
- `streak` — drawn from the same `StreakCalculator` the Home tab uses, so widget and in-app numbers match bit-for-bit.

All collections have hard caps so a giant history can't bloat the snapshot file (typical size ≤ 5 KB).

**Theming:**

Widgets resolve `activeThemeId` against `WidgetTheme.resolve(id:)` (a static catalog inside the widget extension, kept in sync with `AppTheme` in the main app). Each render computes the right primary/secondary `Color` from a hand-tuned light/dark hex pair, so the widget chrome follows the user's accent theme choice. Light/dark adaptation works automatically via the widget's `\.colorScheme` env.

**Pro gating:**

The snapshot includes `isPro: Bool` (sampled at write time). Pro-gated widget views check it on render:
- **Home Screen** — Pro widgets show `WidgetProUpsellView` (lock medallion + "Unlock with CashLens Pro" CTA).
- **Lock Screen** — gating is subtler: a tiny `lock.fill` glyph + "Pro" label, since accessory real estate is too cramped for a full upsell tile.

Spending Snapshot is **deliberately free for everyone** — it's the hero surface that drives Pro upgrades by demonstrating the visual quality bar; gating it would prevent that demo.

**Widget configurations:**

- **Spending Snapshot** uses `AppIntentConfiguration` with `SpendingWidgetIntent` so the user picks Today / Week / Month / Year on the long-press → Edit Widget sheet. The intent uses an `AppEnum` (`SpendingWidgetTimeframe`) that bridges 1:1 to the snapshot's wire-level `WidgetSnapshot.Timeframe`.
- **Budget Progress** uses `StaticConfiguration` and auto-picks the most-relevant budget for the Small surface (over-budget rows rank first, then highest usage %), Medium shows top 3.
- **Subscriptions Due** uses `StaticConfiguration` (Medium only) and refreshes every midnight so "in 2 days" rolls over correctly when the user wakes up.
- **No-Spend Streak** uses `StaticConfiguration` and refreshes at midnight so streaks tick up the moment a fresh no-spend day begins.

**Files created (Shared — both targets):**
- `Shared/SharedAppGroup.swift` — App Group identifier + snapshot URL helper
- `Shared/WidgetSnapshot.swift` — versioned data contract
- `Shared/WidgetSnapshotIO.swift` — atomic read/write helpers (ISO-8601 dates, `.atomic` writes, `.placeholder` fallback)

**Files created (main app):**
- `CashLens/Utilities/WidgetSnapshotBuilder.swift` — pure value-type builder + category color hex palette
- `CashLens/Utilities/WidgetSnapshotCoordinator.swift` — `@MainActor` singleton; Combine subscriptions; debounced refresh; `WidgetCenter` reload

**Files created (widget extension):**
- `CashLensWidgets/CashLensWidgetsBundle.swift` — `@main WidgetBundle` listing all widgets (seven once Quick Log was added)
- `CashLensWidgets/WidgetTheme.swift` — pure theme resolver mirror of `AppTheme` + `Color(hex:)` initializer
- `CashLensWidgets/WidgetMoneyFormatter.swift` — currency-aware compact / full / percent-delta formatters
- `CashLensWidgets/WidgetProUpsellView.swift` — shared "Unlock with CashLens Pro" tile
- `CashLensWidgets/SpendingWidget.swift` — Spending Snapshot Small/Medium/Large + `SpendingBackground` (used by all home widgets)
- `CashLensWidgets/BudgetWidget.swift` — Budget Progress Small (ring) / Medium (bars)
- `CashLensWidgets/SubscriptionsWidget.swift` — Subscriptions Due Medium
- `CashLensWidgets/StreakWidget.swift` — No-Spend Streak Small / Medium
- `CashLensWidgets/LockScreenWidgets.swift` — Spending + Streak Lock Screen accessories

**Files modified:**
- `CashLens/CashLensApp.swift` — bootstraps `WidgetSnapshotCoordinator` on `.onAppear`, calls `refreshNow()` on scene foreground
- `CashLens.xcodeproj/project.pbxproj` — adds `Shared/` synchronized folder, registers it with both `CashLens` and `CashLensWidgetsExtension` targets
- `CashLens.entitlements` + `CashLensWidgetsExtension.entitlements` — App Group `group.com.rushi.CashLens.shared`

**Performance characteristics:**

- Widget rendering does zero work past `WidgetSnapshotIO.read()` — every value is pre-aggregated.
- Snapshot file is mmap'd via `Data(contentsOf:options: .mappedIfSafe)` on read.
- Snapshot generation is debounced (300 ms) and runs on `Task.detached(priority: .utility)`, so even a 2,000-expense history never touches the UI thread.
- Atomic writes (`.atomic` flag) guarantee a half-written file is never observable by the widget process — partial reads are impossible.

**Migration safety:**

- Zero Core Data changes — widgets read a derivative file, not Core Data.
- Failures are silent at every layer: missing App Group container → `placeholder`, missing file → `placeholder`, decode failure → `placeholder`, schema mismatch → `placeholder`. The widget never shows a broken state.
- The `kind` strings (`"SpendingSnapshot"`, `"BudgetProgress"`, `"SubscriptionsDue"`, `"NoSpendStreak"`, `"SpendingLockScreen"`, `"StreakLockScreen"`) are stable for the lifetime of the binary — changing one would orphan every placed widget.
- Schema version (`1`) is bumped on incompatible changes; the widget refuses to decode a higher version and falls back to placeholder so a staged rollout where the user has the old widget binary but new snapshot file simply degrades to "no data" rather than crashing.
- Coordinator holds **weak** references to all view models — no retain cycles, no ownership shifts, deinitialization order unaffected.

---

## UI/UX Improvements (Free + Pro)

Original wish-list from the Pro planning, with status as of 2026-09-19 (checked against the code on `redesign/v2`):

| Priority | Improvement | Planned phase | Status |
|----------|-------------|---------------|--------|
| High | Redesigned Home hero card with sparkline + % change | Phase 2 | Superseded — the v2 Today verdict hero + 7-day strip replaced the Home hero (Phase 13) |
| High | Quick-add half-sheet (`.presentationDetents([.medium, .large])`) | Phase 2 | Not done — `AddExpenseView` is a full sheet; detents are used only on `BudgetSetupView`, `TodayCustomizeView`, `WinBackView`, `DonorThanksView` and Activity's date-range sheet |
| Medium | Statistics sub-tabs (Overview / Trends / Categories) | Phase 5 | Not done — Insights is one scrolling page; only the Trend section is a pager (`TrendChartPager`) |
| Medium | Subscription calendar strip with due date dots | Phase 2 | Not done — `SubscriptionsView` shows a "Next up" row and Due Soon / Later / Paused groups instead |
| Medium | Profile settings reorganization (grouped navigation) | Phase 4 | Done — `SettingsGroup` sections, every destination a sheet (Phase 13) |
| Medium | Pull-to-refresh on Home and Subscriptions | Phase 2 | Not done — no `.refreshable` in the app (data refreshes on foreground instead) |
| Low | Onboarding trim to 3-4 pages + interactive first expense | Phase 4 | Partially — `OnboardingView` has 5 steps (welcome, privacy, capability, firstExpense, finish) including an interactive first expense |
| Low | Illustrated empty states with clear CTAs | Phase 3 | Done — `EmptyStatePanel` / `InlineEmptyState` in the design system, used across tabs |
| Low | Contextual first-time feature tooltips | Phase 5 | Not done — no tooltip / coach-mark system; `InsightInfoButton` sheets cover Insights explanations |

---

## Donor Grandfathering (Wave 2)

Past tip-jar donors funded CashLens before Pro existed — they get Pro, automatically:

| Donation tier | Grant |
|---------------|-------|
| Lunch ($4.99) or Fuel ($9.99) — any verified transaction | **Founder** — permanent local Pro |
| Coffee ($0.99) only | **1 year of Pro** from the date the grant is first detected |

**Mechanics** (`ProManager.scanForDonorGrant()`):

- Scans `Transaction.all` on launch (async, after products load) and after restore-purchases. Requires `SKIncludeConsumableInAppPurchaseHistory = YES` (`CashLens-Info.plist`) so finished consumable donations appear in the history (iOS 18+).
- Grant type + date persist in `UserDefaults` (`donorGrantType`, `donorGrantDate`). The 1-year grant date is written once and never refreshed — an expired grant is never re-granted, but it upgrades in place to Founder if a $4.99+ donation is later found (e.g. history restored on a new device).
- `ProManager.isPro` = live StoreKit entitlement **OR** active donor grant, recomputed at every entitlement check (foreground, transaction updates, purchase, restore).
- One-time thank-you sheet ("Thanks for supporting CashLens early — Pro is on us") the first time a grant is applied (`DonorThanksView`).
- Grandfathered donors are excluded from the lapse win-back sheet — you don't win back a gift.

**Manual follow-up (App Store Connect):** offer codes for lapsed-donor outreach are out of scope for the in-app work — create them in ASC if/when we run that campaign.

---

## Version Plan

The original plan staged the phases across 2.0.0 → 2.3.0 on `pro-features`. That did not happen: every phase except Phase 8 shipped together in one release. This table is what actually happened and what is planned now (rewritten 2026-09-19).

| Version | Status | Contents | Branch / commit |
|---------|--------|----------|-----------------|
| **1.0.5 (5)** | Shipped 2026-01 | Free app, tip jar only, 3 tabs | `main` (`fbf8865`) — `main` has not moved since |
| **2.0.0 (6)** | Built 2026-07-16; whether it was published cannot be verified from the repo | Phases 1–7, 9–12, 14 + Phase 13 (v2 redesign + pre-submission wave) | `redesign/v2` (`60382e3`) |
| **2.1** (repo 2.0.1, build 7) | **Shipped 2026-08-29** — the current App Store release | 2.0.0 contents + native one-tap rating prompt + Mark-paid hint. Store version string 2.1 was set in App Store Connect; the repo still says 2.0.1. | `redesign/v2` (`4029ae0`) |
| **2.2 (8)** | **Code complete for Phases 0, A, B, C plus the launch-readiness review fixes on `release/2.2`** (32 commits ahead of `redesign/v2` at `99f5906`, 2026-09-19); **nothing compiled or run yet** — needs Rushiraj's Xcode 27 build and device pass before submission | **Phase 0 — housekeeping / monetization:** version 2.2 / build 8, tracked `xcuserdata` dropped (`be7a28b`); promoted-IAP listener routes tips too (`7289d22`; promo images still to be uploaded in App Store Connect before submission); paywall truth-pass (`9c9d840`); `ReviewPromptManager` (`8de55d1`); `AppConstants.supportEmail` (`4810369`); these docs. **Phase A — layout foundation:** `sidebarAdaptable` tab shell + size-class FAB (`0691176`); size classes replace `userInterfaceIdiom`, `.adaptiveHeight` (`f3e9942`, `da8a529`); `NavigationView` → `NavigationStack` (`bb47fde`); adaptive grids (`7a4e291`, superseded by `EvenColumnGrid` in Phase C); Activity list + detail on regular width + `AddExpenseView.onDismissRequest` (`eec249d`; the `NavigationSplitView` was later replaced by a two-pane `HStack`, see review fixes); `.readableColumn` for Today / You / Paywall (`0144e13`); compact-height onboarding + paywall (`7cac596`); `tabBarInset` retired (`46b7404`; clearance re-derived as 100 in review fixes); `@ScaledMetric` sweep (`5604e8d`); `WidgetSnapshot.dailyNetLast7Days` populated for the Extra Large sparkline (`3fb1b78` — the widget itself is in unmerged PR #8). Not applicable: two-column Today (v2 Today has no pin grid). **Phase B — iPad polish:** `AppCommands` Cmd-N / Cmd-F / Cmd-, + Esc on `SheetCloseButton` (`adefae7`); hover effects (`7517150`); multitasking audit — only fix was Activity ledger width 300/340/420 for 11" 50/50 and Duo inner (`ff20b27`); multiple scenes **left off** (per-scene lock / deep-link / draft state would be needed; 2.3 if ever). **Phase C — iPhone Duo prep (iOS 27 SDK):** toolbar audit — `Label`s for symbol items, `ToolbarItem` for legacy `navigationBarItems`, Esc on root Done buttons (`952a341`); safe-area audit, no change needed; `EvenColumnGrid` for every picker + `DuoLayoutSupport.divisionGutter` hook (`8f8362a`, `f34af68`); 27.1 stubs behind `CASHLENS_DUO_27_1` (`d535979`); fold-transition behaviour documented (state lives above the size-class-dependent containers; editor moves between sheet and detail pane, unsaved edits dropped — accepted). **Review fixes** (launch-readiness review, 0 blockers / 7 should-fix, all fixed): S1 FAB hidden on Activity at regular width, ledger header gets a "+" via `onRequestAddExpense` (`c9a63ed`); S2 `scrollBottomClearance` 32 → 100 (12 gap + 56 FAB + 32) on tab roots and the Activity list (`afdb5ce`); S3 Activity regular-width layout is a plain two-pane `HStack` (ledger 300/340/420 | `Divider` | editor) — `NavigationSplitView` removed entirely (`942efad`); S4 legacy tab-bar `.safeAreaPadding` moved onto the four tab roots (`56c6746`); S5 FAB disc fixed 56/66, only the glyph scales and is clamped (`58fdbb2`); S6 `ReviewPromptManager` keys on major.minor (`askVersionKey`), spends the ask only via `markRequested()` when actually shown, `deferWhilePresenting()` while anything is presented, streak trigger needs a prior recompute (`f98edeb`); S7 Cmd-N waits for `MainTabView.hasPresentation`, Esc answered only by the topmost sheet via `SheetHeader(escapeClosesSheet:)` / `SheetCloseButton(respondsToEscape:)` (`5121e1a`); N3 Insights two columns need regular width and ≥ 640 pt measured, N6 `resetForDebugging` is `#if DEBUG` (`d33ab47`). Deferred from the review by instruction: N1 (`SummaryCustomizationView` is orphaned), N4/N5 first-frame reflow of `EvenColumnGrid` / `adaptiveHeight`, N7 bulk action bar spanning both Activity panes (cosmetic), N8/N9 screenshot suite (PR #8), N11 Cmd-hold HUD grouping (verify only), accepted risks A1–A8. **Still open for 2.2:** `systemExtraLarge` widgets (PR #8), per-device screenshot suite replacing `RuntimeSmokeUITest` (PR #8), the Mac build + fix pass for the compile risks listed in the worklog (`onGeometryChange`, `Binding<Expense?>` ternary, `ContentUnavailableView`), Rushiraj's device run, promo image upload. Candidate: multi-page receipts. | `release/2.2` (cut from `redesign/v2`), one PR to `main` |
| **2.2.1** | Planned after Xcode 27.1 GM | Finish the iPhone Duo 27.1 APIs that 2.2 stubbed. All stubs are in `CashLens/Design/DuoLayoutSupport.swift` inside `#if CASHLENS_DUO_27_1` + `if #available(iOS 27.1, *)`; the flag is defined nowhere today so every helper is a no-op. **TODO (each line marked `// Duo 27.1`):** (1) `DuoLayoutSupport.divisionGutter(in:)` — `proxy.reservedRegions(kind: .division)` and the region's width accessor; (2) `View.duoHorizontalToolbar()` — `toolbarVerticalBehavior(.never)` modifier + case names (Paywall, Add Expense); (3) `View.duoTabBarCompression()` — `toolbarCompressionBehavior(.tabBarFirst)`; may need to move from the `TabView` onto the toolbar / tab bar; (4) `DuoArrangement.body` — `ArrangementView(.split)` initializer and `.split` / `.overlay` case names; decide whether `TrendChartPager`'s page tab bar is primary or secondary in table pose; (5) consider `onHingeChange` to reset `EvenColumnGrid` measurement if `onGeometryChange` does not fire on pose changes; (6) Duo simulator names for `Scripts/screenshots.sh` (PR #8). **Steps:** add `CASHLENS_DUO_27_1` to Active Compilation Conditions → fix the marked lines against the real SDK → build → drop the flag again if the SDK is not ready. Also verify on the 27.1 simulator: Duo inner (~626 pt) splits the Activity two-pane roughly 313 / 313 between ledger and editor; FAB vs. the outer-display vertical bar (FAB stays an overlay — a toolbar "+" would need navigation containers on the tab roots, which v2 removed for perf). Deployment target stays iOS 18. | to be branched from 2.2 |
| **iCloud sync** (`NSPersistentCloudKitContainer`) | **Decision pending** | Either scoped as a Pro feature in a later release (2.3 / 2.4) or iPad marketing stays quiet. Decided once App Store Connect numbers (downloads, trials, conversions) are in. | — |
| **Phase 8 Multi-currency with live rates** | Deferred until ASC data shows demand | See Phase 8 | — |
| **Also not scheduled** | — | System-wide UTType registration for `.cashlens-archive` | — |

Build constraint for every row above: Swift for iOS can only be compiled, run and screenshotted on a Mac with Xcode. Cloud workers write code on branches; build, test, screenshots and TestFlight happen on Rushiraj's Mac, and every PR needs his Xcode run before merge.

---

## Safety Guidelines

1. **Never remove free features** — only add Pro features on top
2. **Core Data changes are additive only** — new entities, new optional attributes. No renames, no deletions.
3. **No lightweight migration needed** — new optional attributes auto-migrate
4. **Feature gate, don't fork** — use `ProManager.shared.isPro` checks, not separate code paths
5. **Test with existing data** — always verify old data loads correctly after schema changes
6. **Export/import backward compatibility** — new fields optional in import, included in export
7. **Grandfather existing users** — if someone has 10 custom categories pre-Pro, don't lock them out
