# Screenshot sample data

Realistic demo data for App Store screenshots.

## Use this file (recommended)

**`CashLens-Screenshot-Demo.cashlens.json`**

Includes:
- ~190 relatable expenses (coffee, groceries, Uber, Netflix, travel, etc.)
- Tags + payment methods (credit / debit / cash / wallet / bank)
- Custom categories: Coffee, Pets
- 6 active subscriptions due soon (widgets look good)
- Budgets: Monthly Spend, Food & Coffee, Groceries, This Week
- Profile name: **Alex**, currency **USD**

Dates are relative to the day you generate the file, so **Today** always looks populated.

## CSV fallback

**`CashLens-Screenshot-Demo.csv`** — expenses only (no budgets / subscriptions).  
Use if you only need Activity / Insights spend charts.

## Import on your iPhone

1. AirDrop / Files-share `CashLens-Screenshot-Demo.cashlens.json` to the phone.
2. Open **CashLens** → **You** → **Data** → **Import**.
3. Pick the `.cashlens.json` file.
4. Choose **Replace** (not Merge) so screenshots aren’t mixed with your real data.
5. Confirm import, then open:
   - **Today** — daily rows + on-track feel  
   - **Activity** — dense timeline + tags  
   - **Insights** — donut / heatmap / trends  
   - **Subscriptions** / widgets — dues in the next 1–12 days  
   - **Budgets** (Pro) — progress bars mid-range  

## Before a fresh screenshot day

Regenerate so “today” stays current:

```bash
python3 Marketing/ScreenshotSampleData/generate_screenshot_data.py
```

## Tips for pretty screenshots

- Use **Light mode** + your preferred theme (Mauve looks on-brand).
- Scroll Activity so grocery / dinner / coffee rows are visible.
- Insights: set range to **This Month**.
- Hide the Dynamic Island clock / use clean status bar if possible.
- After screenshots, restore your real backup or clear demo data.
