# CashLens Pro — Feature Roadmap

> **Baseline:** v1.0.5 (Build 5) — All current features remain free  
> **Target:** v2.0.0 — CashLens Pro launch  
> **Monetization:** Auto-renewable subscription + optional lifetime unlock  
> **Branch:** `pro-features`

---

## Pricing Strategy

| Tier | Price | Notes |
|------|-------|-------|
| Monthly | $2.99/mo | 7-day free trial |
| Yearly | $19.99/yr | ~$1.67/mo, best value badge |
| Lifetime | $39.99 | One-time, for subscription-averse users |

**Tip jar** (existing) stays as-is for users who want to support without Pro.

---

## What Stays Free (never gated)

- Unlimited expense tracking (add/edit/delete)
- All 10 default categories
- Up to 5 custom categories (grandfather existing users with more)
- Subscription/bill tracking with reminders
- Basic statistics (donut, trend, heatmap)
- Import/Export (CSV/JSON)
- Weekly/monthly digest notifications
- Dark mode + appearance toggle
- Draft recovery

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

- **Pickers (`ThemePickerView`, `AppIconPickerView`):** Identical UX shape so users build muscle memory across both. Each picker has three sections: a **live preview card** at the top (theme picker shows pills + a tinted progress bar + a FAB mock; icon picker shows a 132 pt rounded square of the previewed icon with shadow), a **swatch / tile grid** in the middle (3-up for themes, 4-up for icons), and a **conditional Pro CTA** at the bottom that only appears when a free user is previewing a Pro option. Tapping any swatch always updates the live preview instantly (`@State previewTheme` / `previewIcon`) — that's the marketing moment — but only commits to the store if the user is Pro or picked the free default. Active selections get a checkmark badge + accent ring; Pro-locked options get a tiny lock badge in the corner. Both pickers ship with `HapticManager.shared.success()` on a real apply, `.warning()` on a paywall hit.

- **ProfileView Personalization section:** New section between Preferences and Reminders, holding two rows (`colorThemeRow`, `appIconRow`). For Pro users the trailing slot shows the active theme name + a swatch dot, or the active icon name + a tiny rounded preview tile. For free users both rows show the same `proLockChip` (consistent with the Smart Insights row) so the Pro story reads as a coherent tier across the screen, not a series of one-offs. Tapping always opens the picker (never the paywall directly) so the user gets to *see* what they're paying for before any commerce ask.

**Files created:**
- `CashLens/Models/AppTheme.swift`
- `CashLens/Models/AppIconOption.swift`
- `CashLens/Utilities/ThemeStore.swift`
- `CashLens/Utilities/AppIconStore.swift`
- `CashLens/Views/ThemePickerView.swift`
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
| 6.1 | **VisionKit Document Scanner** | ✅ `VNDocumentCameraViewController` with auto-crop / perspective-correction. Page 1 of any multi-page scan is taken (multi-page support deferred to v2.1 with multi-image attachments). |
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
- Why this isn't redundant with future iCloud sync: CloudKit (v2.1) handles **passive sync between the user's own devices**. The `.cashlens-archive` flow handles **explicit user-driven backup/restore** — the file users email themselves "just in case", AirDrop to a friend's phone, or save to Dropbox/Drive as an off-platform safety net. Both ship, neither obsoletes the other.

**Deferred to v2.1 (intentional):**

- **iCloud-Drive auto-sync via `NSPersistentCloudKitContainer`.** Different problem from cross-device backup — CloudKit gives passive multi-device sync without user action; the archive gives the user direct control over a portable file they own. v2.1 ships both.
- **System-wide UTType registration** (so tapping a `.cashlens-archive` in Files.app opens CashLens). Today the user goes through the in-app **Import** button and picks the archive from the file picker — works perfectly, just one extra tap. Surfacing the type to iOS requires editing the project's complex Info.plist entries (the project uses `GENERATE_INFOPLIST_FILE = YES` which makes `UTExportedTypeDeclarations` array-of-dict surgery fiddly); deferred as polish.
- **Multi-image attachments per expense** (long pharmacy receipts, multi-page hotel folios). Today we take page 1 of any multi-page VisionKit scan. Lifting this requires a model migration to `[String]` and a small UX rethink for the in-form preview.

**Testing checklist:**

- [ ] First-time scan on a real device — VisionKit prompts for camera; `INFOPLIST_KEY_NSCameraUsageDescription` resolves to the friendly explanation we wrote.
- [ ] Library picker on a real device — `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` resolves correctly.
- [ ] Free user → tap Scan → paywall opens. Restore Pro → tap Scan → scanner opens.
- [ ] Attach + remove without saving → file is gone from `Documents/Receipts/` (use Files.app or `cleanupOrphans` debug to verify).
- [ ] Replace receipt during edit → old file is deleted on save commit.
- [ ] Bulk-delete N expenses with receipts → all files cleaned up post-save.
- [ ] Force-quit during attach → next foreground sweep removes the orphan file.
- [ ] Round-trip a JSON backup with a receipt-bearing expense → import succeeds, paperclip badge appears, viewer shows the image (only on the same device where the file lives).
- [ ] Round-trip an *old* JSON backup created before v2.0 → still imports cleanly (no `receiptImagePath` key → decoded as `nil`).
- [ ] Export **Full Archive** → AirDrop to a second device → import → all receipts present, viewer opens each one. Try with 0 / 1 / 50 receipts.
- [ ] Open a `.cashlens-archive` in 7-Zip / macOS Finder → confirm it's a real zip (no encryption prompt, files visible, `data.json` byte-identical to a `.cashlens.json` export).
- [ ] Truncate a `.cashlens-archive` (delete last 100 bytes) → import surfaces "checksum mismatch" or "archive truncated", **never** silently accepts bad data.
- [ ] Re-import the same archive twice (merge mode) → second pass reports "+0 expenses, +N skipped" and "+N receipts restored" (overwrites with bit-identical bytes — idempotent).

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

### Phase 8: Multi-Currency with Live Rates (Most Complex)

| # | Feature | Risk | Effort | Revenue Impact |
|---|---------|------|--------|----------------|
| 8.1 | **Per-Expense Currency** | Medium | High | — |
| 8.2 | **Exchange Rate API** | Medium | Medium | — |
| 8.3 | **Conversion Display** | Medium | Medium | High — travelers/expats |

**Details:**

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

### Phase 14: Home & Lock Screen Widgets (Pro) — ✅ SHIPPED

| # | Widget | Sizes | Tier | Risk | Status |
|---|--------|-------|------|------|--------|
| 14.1 | **Spending Snapshot** | Small / Medium / Large + Lock circular / rectangular / inline | Free (hero surface) | Low | ✅ Shipped |
| 14.2 | **Budget Progress** | Small / Medium | Pro | Low | ✅ Shipped |
| 14.3 | **Subscriptions Due** | Medium | Pro | Low | ✅ Shipped |
| 14.4 | **No-Spend Streak** | Small / Medium + Lock circular / rectangular / inline | Pro | Low | ✅ Shipped |

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
- `CashLensWidgets/CashLensWidgetsBundle.swift` — `@main WidgetBundle` listing all six widgets
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

These improvements benefit all users and should be done incrementally:

| Priority | Improvement | Phase |
|----------|-------------|-------|
| High | Redesigned Home hero card with sparkline + % change | Phase 2 |
| High | Quick-add half-sheet (`.presentationDetents([.medium, .large])`) | Phase 2 |
| Medium | Statistics sub-tabs (Overview / Trends / Categories) | Phase 5 |
| Medium | Subscription calendar strip with due date dots | Phase 2 |
| Medium | Profile settings reorganization (grouped navigation) | Phase 4 |
| Medium | Pull-to-refresh on Home and Subscriptions | Phase 2 |
| Low | Onboarding trim to 3-4 pages + interactive first expense | Phase 4 |
| Low | Illustrated empty states with clear CTAs | Phase 3 |
| Low | Contextual first-time feature tooltips | Phase 5 |

---

## Version Plan

| Version | Contents | Branch |
|---------|----------|--------|
| **2.0.0** | Phase 1 (Pro infra) + Phase 2 (Budgets) + key UI improvements | `pro-features` |
| **2.1.0** | Phase 3 (Tags) + Phase 4 (Icons/Themes) | `pro-features` |
| **2.2.0** | Phase 5 (Advanced Stats/PDF) + Phase 6 (Receipt Scanner + `.cashlens-archive` cross-device backup) | `pro-features` |
| **2.3.0** | Phase 7 (Forecasting) + Phase 8 (Multi-Currency) | `pro-features` |
| **v2.1+** (post-launch) | iCloud auto-sync via `NSPersistentCloudKitContainer`. System-wide UTType registration for `.cashlens-archive`. Multi-image attachments per expense. | future |

---

## Safety Guidelines

1. **Never remove free features** — only add Pro features on top
2. **Core Data changes are additive only** — new entities, new optional attributes. No renames, no deletions.
3. **No lightweight migration needed** — new optional attributes auto-migrate
4. **Feature gate, don't fork** — use `ProManager.shared.isPro` checks, not separate code paths
5. **Test with existing data** — always verify old data loads correctly after schema changes
6. **Export/import backward compatibility** — new fields optional in import, included in export
7. **Grandfather existing users** — if someone has 10 custom categories pre-Pro, don't lock them out
