# CashLens large-screen design (iPad, iPhone Duo)

Scope: every screen a paying customer sees on an iPad or on the iPhone Duo inner display, plus the Duo outer display where the system moves bars to a vertical strip on the right edge. iPhone layouts (compact width) are untouched; everything below is selected only when `horizontalSizeClass == .regular`, and lives in `CashLens/Views/LargeScreen/`.

## Principles

1. Two size classes, not poses or devices. Compact width = iPhone, Duo outer display, iPad Slide Over and 1/3 Split View. Regular width = iPad full screen and 1/2 Split View, Duo inner display (portrait and landscape). Book and table poses fall out of a good regular-width layout plus even column counts.
2. A big screen buys glanceability and fewer taps, not bigger cards. Every regular layout shows more rows, more sections side by side, and puts the editor inline instead of in a sheet.
3. Same hierarchy inside and out. Duo users open and close the phone constantly; the tab you were on, the expense you selected, and the filters you set survive the flip. Only the arrangement changes.
4. Even columns on regular width so a fold never runs through a tile.
5. Interactive controls never touch the trailing edge on Duo. Headers are inside the safe area; nothing edge-anchored is tappable.
6. On regular width, presentations are form-sized cards or inline panes, never full-height sheets.

## Width thresholds (measured container width, never device idiom)

| Threshold | Meaning |
|---|---|
| compact | existing iPhone layout |
| regular, < 700pt content | "narrow regular": Duo inner portrait (~626pt), iPad 11" and 13" at 50/50. Two-pane Activity, single-column dashboards with wider cards. |
| regular, ≥ 700pt | two-column dashboards (Today, Insights, You): iPad mini portrait, 11"/13" portrait and landscape, Duo inner landscape. |
| regular, ≥ 1000pt | Activity gains the filter rail (three regions). iPad 13" portrait and every iPad landscape. |

Accessibility Dynamic Type sizes collapse every two-column pair to one column. Dashboard side padding drops from 32pt to 20pt below 900pt measured width so iPad mini portrait and Duo inner landscape keep columns of ≥ ~340pt.

## Root shell

- iOS 26 `TabView(.sidebarAdaptable)`: sidebar or top bar on regular width; the system draws the Duo vertical bar itself.
- The floating "+" is hidden on regular width everywhere. Each tab places its primary action in its own header (see per-screen). Cmd-N still works.
- On compact width with a vertical system bar (Duo outer: trailing safe-area inset ≥ 44pt, regular height), the FAB drops to the bottom corner (20pt) because there is no bottom tab bar to clear. This condition is false on every iPhone (portrait insets are 0, landscape is compact height).

## Today

Compact (unchanged): header, recap card, verdict, then the user's ordered sections in one column.

Regular (≥ 700pt):

```
┌──────────────────────────────────────────────────────────────────────┐
│ Good morning                                    [+ Log expense] [⚙]  │
│ Rushiraj                                                             │
│ ┌────────────────────────── recap ready (if any) ──────────────────┐ │
│ └──────────────────────────────────────────────────────────────────┘ │
│ ┌─ Budgets ───────────────────┐  ┌─ Summary ─────────── This Week ▾┐ │
│ │ ON TRACK · 12 days left     │  │ TOTAL SPENT   │ TOP CATEGORY    │ │
│ │ SPENT ₹24,300      (ring)   │  │ ₹4,120        │ ₹1,900 Food     │ │
│ │ → projected ₹38k            │  └──────────────────────────────────┘ │
│ │ TODAY · LEFT/DAY · REMAINING│  ┌─ This week  🔥3-day ─── Insights→┐ │
│ └─────────────────────────────┘  │ ▂▄▆▃▇▂▅                          │ │
│ ┌─ Recent ─────────── See all→┐  └──────────────────────────────────┘ │
│ │ Coffee            ₹120     │  ┌─ Upcoming Subscriptions ─ Manage→┐ │
│ │ Groceries         ₹2,340   │  │ Netflix · due in 3 days   ₹649   │ │
│ │ Metro             ₹60      │  └──────────────────────────────────┘ │
│ │ … (6 rows)                 │  ┌─ insight ────────────────────────┐ │
│ └─────────────────────────────┘  │ You spent 30% less on Food…      │ │
│                                  └──────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

- More: Recent shows 6 rows (3 on iPhone); Summary, week strip, upcoming and insight are all above the fold beside the verdict.
- Alignment: verdict is the first pixel top-left (the screen's contract). The user's customised section order still applies: it is dealt alternately into the right column, then the left column under the verdict, so hiding or reordering in Customize Today keeps working.
- Primary action: "Log expense" pill in the header, leading of the Customize disc. The first-run hero keeps its own CTA and is centred in a 560pt column.
- Narrow regular (< 700pt): one column, same order as iPhone but Recent shows 6 rows.
- Duo table pose: the top half holds header + verdict (glanceable); the bottom half holds Recent and the tappable rows. Book pose: the two columns sit on either side of the fold.

## Activity

Compact (unchanged): header, search + mode toggle, sort bar, chips, ledger; editor as a sheet.

Regular, < 1000pt (two panes; extends the existing HStack):

```
┌────────────────────────────┬───┬──────────────────────────────────┐
│ Activity        Select  (+) │   │ EXPENSE                          │
│ [🔍 Search expenses] [≣][▦] │   │ Editing                          │
│ Newest ▾  📅      34 · ₹12k │   │ ┌──────────────────────────────┐ │
│ (All)(Subs)(Food)(Groceries)│   │ │ amount / title / category …  │ │
│ ┌ Today ─────────────────┐  │   │ └──────────────────────────────┘ │
│ │ Coffee          ₹120  │  │   │                                  │
│ │ Metro            ₹60  │  │   │            [Update Expense]      │
│ └────────────────────────┘  │   │                                  │
│ ┌ Yesterday ─────────────┐  │   │  (no selection: ledger summary   │
│ │ …                      │  │   │   + "Add expense" button)        │
└────────────────────────────┴───┴──────────────────────────────────┘
   300…420pt                        rest (≥ ~300pt)
```

Regular, ≥ 1000pt (three regions):

```
┌──────────────┬───┬──────────────────────────────┬───┬─────────────────────────┐
│ FILTERS      │   │ Activity          Select (+) │   │ EXPENSE · Editing       │
│ ● All        │   │ [🔍 Search expenses]   [≣][▦]│   │ …                       │
│ ○ Subscript. │   │                  34 · ₹12,450│   │                         │
│ ○ Food       │   │ ┌ Today ────────────────────┐│   │                         │
│ ○ Groceries  │   │ │ Coffee            ₹120   ││   │                         │
│ ○ Transport  │   │ │ Metro              ₹60   ││   │                         │
│ …            │   │ └──────────────────────────┘│   │                         │
│ TAGS         │   │ ┌ Yesterday ────────────────┐│   │                         │
│ ○ #work      │   │ │ …                        ││   │      [Update Expense]   │
│ SORT         │   │                              │   │                         │
│ Newest ▾     │   │                              │   │                         │
│ DATE RANGE   │   │                              │   │                         │
│ Last 30 days │   │                              │   │                         │
└──────────────┴───┴──────────────────────────────┴───┴─────────────────────────┘
  240pt               300…480pt                        rest
```

- More: the whole filter set is visible at once as a vertical list (categories, tags, sort, range) instead of a horizontal chip scroller; the ledger header keeps only the count and total. Rows hover-highlight; the selected row is tinted.
- Alignment: rail leading, ledger centre, editor trailing so the most-used region (ledger) is central and the editor sits beside the system bar on Duo landscape without colliding (it is inside the safe area).
- Primary action: "+" in the ledger header (existing), repeated as "Add expense" in the empty detail column.
- Selection, filters, view mode and bulk-select state live on `AllExpensesView` and survive the pane count changing (rail appears/disappears, fold, Split View drag). Calendar mode replaces the ledger only; rail and editor stay.
- Book pose: ledger left of the fold, editor right of it. Table pose: ledger top, editor bottom is not attempted; the layout stays side by side and the fold runs through the divider region (lists do not displace).

## Insights

Compact (unchanged): single column.

Regular (≥ 700pt):

```
┌──────────────────────────────────────────────────────────────────────┐
│ Insights                                                   (+) [↑]   │
│ This month · Sep 2026                                                 │
│ ┌ Week · Month · Year · All │ ‹ Sep 2026 › │ (All)(Food)(…) ─────┐   │
│ └────────────────────────────────────────────────────────────────┘   │
│ ┌─ TOTAL SPENT ──────────────┐  ┌─ Pro Insights ──────────────────┐  │
│ │ ₹24,300   ▼12% vs Aug      │  │ Daily pace │ Velocity           │  │
│ │ AVG · HIGHEST · COUNT      │  │ Year over year chart            │  │
│ └────────────────────────────┘  └─────────────────────────────────┘  │
│ ┌─ Trend ────────────────── Over time · Weekday · Top days ───────┐  │
│ │ ╭─╮   ╭╮                                                       │  │
│ │╭╯ ╰─╮╭╯╰╮   (wide line chart, range picker anchored above)     │  │
│ └────────────────────────────────────────────────────────────────┘  │
│ ┌─ Where It Goes ────────────┐  ┌─ Payment Methods ───────────────┐  │
│ │ (donut)  Food     45%      │  │ (donut) UPI 60% · Card 30%      │  │
│ └────────────────────────────┘  └─────────────────────────────────┘  │
│ ┌─ Spending Pattern ─────────┐  ┌─ Forecast ──────────────────────┐  │
│ │ ▦▦▦▦▦▦▦ heatmap            │  │ 30-day projection chart         │  │
│ └────────────────────────────┘  └─────────────────────────────────┘  │
│ ┌─ Highlights ── 2-column grid of insight cards ──────────────────┐  │
│ ┌─ Monthly Recap · August in review ──────────────────────────────┐  │
└──────────────────────────────────────────────────────────────────────┘
```

- More: hero and Pro cards share the first row; donut, payment methods, heatmap and forecast tile in even pairs; the trend chart gets the full width. When the Payment Methods section has nothing to show (free user, nothing tagged) the donut pairs with the heatmap and the forecast takes the full width, so no card sits beside a blank half.
- Primary action: "+" disc beside Export in the header (the FAB is gone on regular width).
- The trend section is wrapped in `DuoArrangement` (its pager tab bar as primary, chart as secondary) — an `ArrangementView(.split)` candidate on iOS 27.1 so the range picker and the chart land on opposite halves in book/table pose.
- Narrow regular (< 700pt): single column, existing order.

## You

Compact (unchanged): single column of grouped rows.

Regular (≥ 700pt):

```
┌──────────────────────────────────────────────────────────────────────┐
│ You                                                                  │
│ ┌─ (R) Rushiraj ✎ ───────────┐  ┌ GENERAL ────────────────────────┐  │
│ └────────────────────────────┘  │ Currency · Default period · Siri │  │
│ ┌─ ♛ CashLens Pro · Active ──┐  └─────────────────────────────────┘  │
│ └────────────────────────────┘  ┌ PRIVACY & SECURITY ─────────────┐  │
│ ┌─ Backup: 3 days ago ───────┐  └─────────────────────────────────┘  │
│ └────────────────────────────┘  ┌ PERSONALIZATION ────────────────┐  │
│ ┌ MANAGE ────────────────────┐  └─────────────────────────────────┘  │
│ │ Budgets (2) · Categories   │  ┌ NOTIFICATIONS ──────────────────┐  │
│ │ Subscriptions (7)          │  └─────────────────────────────────┘  │
│ └────────────────────────────┘  ┌ DATA ───────────────────────────┐  │
│ ┌ ABOUT ─────────────────────┐  │ Backup health · Export · Import │  │
│ └────────────────────────────┘  └─────────────────────────────────┘  │
│ v2.2 (8)                                                             │
└──────────────────────────────────────────────────────────────────────┘
```

- Left column: identity and status (profile, Pro, backup banner, the data managers, About). Right column: preferences (General, Privacy, Personalization, Notifications, Data). Both columns are ≤ 520pt so rows keep a readable measure.
- Settings-like sheets opened from You (Currency, Paywall, Export, Import, Appearance, App Icon, Privacy, Notifications, About, Siri tips, Donation) are form-sized cards on regular width. The three data managers (Budgets, Subscriptions, Categories) keep the taller page sheet because they are lists.
- A true sidebar + detail settings pane is deferred: each sub-screen owns its `SheetHeader` and `dismiss()`; hosting them inline needs the `onDismissRequest` treatment `AddExpenseView` already has.
- DEBUG builds only: the Developer group shows the live size classes so the Duo inner display can be confirmed as regular/regular.

## Onboarding

- Regular height (portrait): the page content is capped to a 560pt centred column so the hero, copy and control never stretch across an iPad. Compact height (landscape) keeps the Phase A side-by-side layout.
- The Skip pill sits inside the safe area; on the Duo outer display it stays clear of the vertical bar.

## Currency picker

- Header collision fix (shared, geometry-only): `SheetHeader` measures its trailing control and the title stack's natural width. When the centred stack would run under a wide trailing pill it keeps 44pt on the leading side and moves clear of the pill, centring in the remaining space; otherwise the old symmetric 44pt geometry is kept. Headers with the standard 36pt trailing slot render exactly as before. The only iPhone change is the first-run currency picker, whose subtitle already ran under the "Continue" pill on 393pt phones — it now sits clear of it.
- Regular width: presented as a form-sized card (540pt) from the first-run flow and from You.

## Paywall

- Regular width: form-sized card presentation from every presenter that knows its size class (tab shell auto-paywall, You, Insights, Activity tag paywall); content already caps at 640pt.
- Close button stays a `SheetCloseButton` inside the safe area (compact-height and Esc behaviour unchanged).

## Add / edit expense

- Regular width: form-sized card when presented as a sheet (tab shell, Today, Insights). Inline in the Activity detail column, where the form is capped at 640pt and centred so a 900pt editor pane does not stretch the fields.

## Duo pose matrix

| Pose | Size class | What the user sees |
|---|---|---|
| Closed, outer 5.4" | compact / regular height | iPhone layouts. System vertical bar on the right; FAB drops to the bottom corner; sheet headers pad their titles by the width of their trailing control. |
| Open, portrait | regular / regular, ~626pt | Narrow-regular: two-pane Activity, single-column dashboards with wider cards, sidebar-adaptable tabs (horizontal bar). |
| Open, landscape | regular / regular, ~890pt | Two-column Today/Insights/You, two-pane Activity (no rail below 1000pt), vertical system bar on the right; all trailing controls are inside the safe area. |
| Book (vertical fold) | regular / regular | Two columns / two panes straddle the fold along the gutter; `EvenColumnGrid` keeps even counts; alerts and form sheets move to the trailing half by the system. |
| Table (horizontal fold) | regular / regular | Top half: header + hero (glanceable); bottom half: rows and controls. Scrolling lists are not displaced. |

## iOS 27.1 hooks (`Design/DuoLayoutSupport.swift`, behind `CASHLENS_DUO_27_1`)

`DuoArrangement(mode: .split | .overlay)` (Insights trend), `duoHorizontalToolbar()` (Paywall, Add Expense), `duoTabBarCompression()` (tab shell), `DuoLayoutSupport.divisionGutter(in:)` (`EvenColumnGrid`). Everything compiles to a no-op with the flag undefined. `DuoLayoutSupport.hasVerticalSystemBar` is plain geometry and needs no flag.

To test on the 27.1 beta: Target → Build Settings → Swift Compiler – Custom Flags → Active Compilation Conditions (Debug) → add `CASHLENS_DUO_27_1`, build, and fix the lines marked `// Duo 27.1` against the real SDK names. Remove the flag before an App Store build from release Xcode.
