#!/usr/bin/env python3
"""Generate screenshot-ready CashLens sample data.

Outputs:
  - CashLens-Screenshot-Demo.cashlens.json  (full backup — USE THIS)
  - CashLens-Screenshot-Demo.csv            (expenses-only fallback)

Dates are relative to "today" so Today / MTD / due-soon always look current.
Re-run before screenshot day if needed:

  python3 Marketing/ScreenshotSampleData/generate_screenshot_data.py
"""

from __future__ import annotations

import csv
import json
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

OUT = Path(__file__).resolve().parent

NOW = datetime.now(timezone.utc).replace(second=0, microsecond=0)
TODAY = NOW.replace(hour=0, minute=0, second=0, microsecond=0)


def iso(dt: datetime) -> str:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def day(offset: int, hour: int = 12, minute: int = 0) -> datetime:
    return TODAY + timedelta(days=offset) + timedelta(hours=hour, minutes=minute)


def fixed(seed: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"cashlens-screenshot:{seed}"))


def expense(
    seed: str,
    title: str,
    amount: float,
    offset: int,
    category: str,
    *,
    hour: int = 12,
    minute: int = 0,
    notes: str | None = None,
    tags: list[str] | None = None,
    payment: str | None = None,
    custom_id: str | None = None,
    is_from_sub: bool = False,
    sub_id: str | None = None,
    is_refund: bool = False,
) -> dict:
    cat = "Custom" if custom_id else category
    row = {
        "id": fixed(seed),
        "title": title,
        "amount": round(amount, 2),
        "currency": "USD",
        "date": iso(day(offset, hour, minute)),
        "category": cat,
        "isFromSubscription": is_from_sub,
        "isRefund": is_refund,
    }
    if notes:
        row["notes"] = notes
    if tags:
        row["tags"] = tags
    if payment:
        row["paymentMethod"] = payment
    if custom_id:
        row["customCategoryId"] = custom_id
    if sub_id:
        row["subscriptionId"] = sub_id
    return row


def main() -> None:
    coffee_id = fixed("cat-coffee")
    pets_id = fixed("cat-pets")

    custom_categories = [
        {
            "id": coffee_id,
            "name": "Coffee",
            "icon": "cup.and.saucer.fill",
            "colorName": "food",
        },
        {
            "id": pets_id,
            "name": "Pets",
            "icon": "pawprint.fill",
            "colorName": "other",
        },
    ]

    sub_netflix = fixed("sub-netflix")
    sub_spotify = fixed("sub-spotify")
    sub_icloud = fixed("sub-icloud")
    sub_gym = fixed("sub-gym")
    sub_adobe = fixed("sub-adobe")
    sub_yt = fixed("sub-youtube")

    subscriptions = [
        {
            "id": sub_netflix,
            "name": "Netflix",
            "amount": 15.49,
            "currency": "USD",
            "startDate": iso(day(-400, 9)),
            "frequency": "Monthly",
            "nextDueDate": iso(day(2, 9)),
            "category": "Entertainment",
            "notes": "Premium plan",
            "isActive": True,
            "reminderEnabled": True,
            "reminderDaysBefore": 1,
        },
        {
            "id": sub_spotify,
            "name": "Spotify Family",
            "amount": 16.99,
            "currency": "USD",
            "startDate": iso(day(-500, 10)),
            "frequency": "Monthly",
            "nextDueDate": iso(day(4, 10)),
            "category": "Entertainment",
            "isActive": True,
            "reminderEnabled": True,
            "reminderDaysBefore": 2,
        },
        {
            "id": sub_icloud,
            "name": "iCloud+",
            "amount": 2.99,
            "currency": "USD",
            "startDate": iso(day(-700, 8)),
            "frequency": "Monthly",
            "nextDueDate": iso(day(1, 8)),
            "category": "Utilities",
            "notes": "200GB",
            "isActive": True,
            "reminderEnabled": True,
            "reminderDaysBefore": 1,
        },
        {
            "id": sub_gym,
            "name": "Fitness Club",
            "amount": 49.00,
            "currency": "USD",
            "startDate": iso(day(-200, 7)),
            "frequency": "Monthly",
            "nextDueDate": iso(day(6, 7)),
            "category": "Health",
            "notes": "Membership",
            "isActive": True,
            "reminderEnabled": True,
            "reminderDaysBefore": 3,
        },
        {
            "id": sub_adobe,
            "name": "Adobe Creative Cloud",
            "amount": 59.99,
            "currency": "USD",
            "startDate": iso(day(-300, 11)),
            "frequency": "Monthly",
            "nextDueDate": iso(day(9, 11)),
            "category": "Other",
            "notes": "Photography plan",
            "isActive": True,
            "reminderEnabled": True,
            "reminderDaysBefore": 2,
        },
        {
            "id": sub_yt,
            "name": "YouTube Premium",
            "amount": 13.99,
            "currency": "USD",
            "startDate": iso(day(-180, 14)),
            "frequency": "Monthly",
            "nextDueDate": iso(day(12, 14)),
            "category": "Entertainment",
            "isActive": True,
            "reminderEnabled": True,
            "reminderDaysBefore": 1,
        },
    ]

    # Budgets sized so MTD looks "on track" (~50–65% used mid-month).
    budgets = [
        {
            "id": fixed("budget-overall"),
            "name": "Monthly Spend",
            "amount": 3200.0,
            "period": "Monthly",
            "categoryFilter": {"type": "overall"},
            "alertAtPercentages": [80.0, 100.0],
            "isActive": True,
            "createdAt": iso(day(-60)),
        },
        {
            "id": fixed("budget-food"),
            "name": "Food & Coffee",
            "amount": 650.0,
            "period": "Monthly",
            "categoryFilter": {"type": "default", "rawValue": "Food"},
            "alertAtPercentages": [80.0, 100.0],
            "isActive": True,
            "createdAt": iso(day(-60)),
        },
        {
            "id": fixed("budget-groceries"),
            "name": "Groceries",
            "amount": 450.0,
            "period": "Monthly",
            "categoryFilter": {"type": "default", "rawValue": "Groceries"},
            "alertAtPercentages": [80.0, 100.0],
            "isActive": True,
            "createdAt": iso(day(-60)),
        },
        {
            "id": fixed("budget-weekly"),
            "name": "This Week",
            "amount": 280.0,
            "period": "Weekly",
            "categoryFilter": {"type": "overall"},
            "alertAtPercentages": [80.0, 100.0],
            "isActive": True,
            "createdAt": iso(day(-14)),
        },
    ]

    expenses: list[dict] = []

    # --- TODAY (hero rows for Today tab / screenshot #1) ---
    expenses += [
        expense("t-coffee", "Blue Bottle Coffee", 5.45, 0, "Food", hour=8, minute=12,
                notes="Oat latte", tags=["coffee", "morning"], payment="apple", custom_id=coffee_id),
        expense("t-lunch", "Sweetgreen", 14.80, 0, "Food", hour=12, minute=35,
                notes="Harvest bowl", tags=["lunch", "work"], payment="credit"),
        expense("t-uber", "Uber", 11.20, 0, "Transportation", hour=9, minute=5,
                tags=["commute"], payment="credit"),
        expense("t-snack", "Trader Joe's Snack", 6.49, 0, "Groceries", hour=18, minute=10,
                tags=["quick"], payment="debit"),
    ]
    # Fix coffee payment — "apple" isn't valid; use wallet (Apple Pay-ish)
    expenses[0]["paymentMethod"] = "wallet"

    # --- YESTERDAY ---
    expenses += [
        expense("y-grocery", "Trader Joe's", 72.40, -1, "Groceries", hour=17, minute=40,
                tags=["weekly", "home"], payment="debit"),
        expense("y-dinner", "Thai Basil", 38.90, -1, "Food", hour=19, minute=45,
                notes="Dinner with Alex", tags=["dinner", "date"], payment="credit"),
        expense("y-gas", "Shell Gas", 48.20, -1, "Transportation", hour=8, minute=20,
                tags=["car"], payment="credit"),
        expense("y-pharmacy", "CVS Pharmacy", 18.75, -1, "Health", hour=11, minute=15,
                tags=["health"], payment="debit"),
    ]

    # --- Recent week (dense Activity / spark) ---
    recent = [
        ("r-target", "Target", 54.30, -2, "Shopping", 16, 20, ["home"], "debit", None),
        ("r-chipotle", "Chipotle", 12.65, -2, "Food", 13, 5, ["lunch"], "credit", None),
        ("r-lyft", "Lyft", 9.80, -2, "Transportation", 21, 10, ["night"], "credit", None),
        ("r-amazon", "Amazon", 29.99, -3, "Shopping", 14, 0, ["home", "order"], "credit", None),
        ("r-starbucks", "Starbucks", 6.25, -3, "Food", 8, 40, ["coffee"], "wallet", coffee_id),
        ("r-wholefoods", "Whole Foods", 86.15, -3, "Groceries", 18, 30, ["weekly"], "debit", None),
        ("r-movie", "AMC Movies", 32.00, -4, "Entertainment", 19, 15, ["weekend", "fun"], "credit", None),
        ("r-popcorn", "Cinema Snacks", 14.50, -4, "Food", 19, 40, ["weekend"], "cash", None),
        ("r-uber2", "Uber", 16.40, -4, "Transportation", 22, 5, ["night"], "credit", None),
        ("r-lunch2", "Shake Shack", 15.90, -5, "Food", 12, 50, ["lunch"], "credit", None),
        ("r-coffee2", "Local Roasters", 4.75, -5, "Food", 8, 15, ["coffee", "morning"], "wallet", coffee_id),
        ("r-pet", "Petco", 41.20, -5, "Other", 15, 0, ["pets"], "debit", pets_id),
        ("r-haircut", "Barber Shop", 35.00, -6, "Other", 11, 0, ["selfcare"], "cash", None),
        ("r-dinner2", "Olive Garden", 46.80, -6, "Food", 19, 20, ["dinner", "family"], "credit", None),
        ("r-parking", "City Parking", 8.00, -6, "Transportation", 10, 30, ["car"], "wallet", None),
    ]
    for seed, title, amt, off, cat, h, m, tags, pay, cid in recent:
        expenses.append(
            expense(seed, title, amt, off, cat, hour=h, minute=m, tags=tags, payment=pay, custom_id=cid)
        )

    # --- Subscription charges this month (linked) ---
    for seed, title, amt, off, cat, sid in [
        ("subx-netflix", "Netflix", 15.49, -14, "Entertainment", sub_netflix),
        ("subx-spotify", "Spotify Family", 16.99, -12, "Entertainment", sub_spotify),
        ("subx-icloud", "iCloud+", 2.99, -15, "Utilities", sub_icloud),
        ("subx-gym", "Fitness Club", 49.00, -10, "Health", sub_gym),
        ("subx-adobe", "Adobe Creative Cloud", 59.99, -7, "Other", sub_adobe),
        ("subx-yt", "YouTube Premium", 13.99, -8, "Entertainment", sub_yt),
    ]:
        expenses.append(
            expense(
                seed, title, amt, off, cat, hour=9, minute=0,
                tags=["subscription"], payment="credit",
                is_from_sub=True, sub_id=sid,
            )
        )

    # --- Month-to-date fillers (relatable, varied for donut/heatmap) ---
    mtd_templates = [
        ("Uber", 12.5, "Transportation", ["commute"], "credit"),
        ("Lyft", 14.0, "Transportation", ["commute"], "credit"),
        ("Starbucks", 5.85, "Food", ["coffee"], "wallet"),
        ("Blue Bottle Coffee", 5.45, "Food", ["coffee", "morning"], "wallet"),
        ("Chipotle", 13.2, "Food", ["lunch"], "credit"),
        ("Sweetgreen", 15.1, "Food", ["lunch", "work"], "credit"),
        ("Trader Joe's", 64.0, "Groceries", ["weekly"], "debit"),
        ("Whole Foods", 78.5, "Groceries", ["weekly"], "debit"),
        ("Amazon", 27.4, "Shopping", ["order"], "credit"),
        ("Target", 42.0, "Shopping", ["home"], "debit"),
        ("Shell Gas", 45.0, "Transportation", ["car"], "credit"),
        ("CVS Pharmacy", 16.2, "Health", ["health"], "debit"),
        ("Pharmacy — Refill", 22.0, "Health", ["health"], "debit"),
        ("Netflix snack run", 11.0, "Food", ["night"], "cash"),
        ("DoorDash — Tacos", 24.5, "Food", ["dinner", "delivery"], "credit"),
        ("Uber Eats — Sushi", 31.0, "Food", ["dinner", "delivery"], "credit"),
        ("Apple App", 4.99, "Entertainment", ["apps"], "credit"),
        ("Bookshop", 18.0, "Education", ["books"], "debit"),
        ("Coursera", 49.0, "Education", ["learning"], "credit"),
        ("Dry Cleaning", 28.0, "Other", ["chores"], "debit"),
        ("Electric Bill", 92.0, "Utilities", ["bills"], "bank"),
        ("Internet Bill", 70.0, "Utilities", ["bills"], "bank"),
        ("Phone Bill", 85.0, "Utilities", ["bills"], "bank"),
        ("Metro Card", 33.0, "Transportation", ["transit"], "wallet"),
        ("Parking Garage", 18.0, "Transportation", ["car"], "credit"),
        ("H&M", 56.0, "Shopping", ["clothes"], "credit"),
        ("Nike", 89.0, "Shopping", ["clothes"], "credit"),
        ("Petco", 36.0, "Other", ["pets"], "debit"),
        ("Vet Visit Copay", 65.0, "Health", ["pets", "health"], "credit"),
        ("Yoga Class", 22.0, "Health", ["fitness"], "wallet"),
        ("Concert Ticket", 75.0, "Entertainment", ["weekend", "fun"], "credit"),
        ("Spotify merch", 28.0, "Shopping", ["fun"], "credit"),
        ("Airport Lounge snack", 16.0, "Travel", ["trip"], "credit"),
        ("Airbnb cleaning fee", 45.0, "Travel", ["trip"], "credit"),
        ("Hotel — City Weekend", 189.0, "Travel", ["weekend", "trip"], "credit"),
        ("Flight seat upgrade", 49.0, "Travel", ["trip"], "credit"),
        ("Farmers Market", 28.5, "Groceries", ["fresh"], "cash"),
        ("Bakery", 9.75, "Food", ["weekend"], "cash"),
        ("Wine Bar", 42.0, "Food", ["dinner", "date"], "credit"),
        ("Birthday Gift", 40.0, "Shopping", ["gift"], "credit"),
        ("IKEA", 67.0, "Shopping", ["home"], "debit"),
        ("Home Depot", 38.0, "Shopping", ["home"], "debit"),
        ("Refund — Amazon", 29.99, "Shopping", ["order", "refund"], "credit"),
    ]

    # Spread across past ~45 days of current + previous month for charts.
    # Skips today/yesterday seeds already covered.
    idx = 0
    for offset in range(-7, -75, -1):
        # Weekends denser / more entertainment+food
        weekday = (TODAY + timedelta(days=offset)).weekday()  # 0=Mon
        picks = 2 if weekday < 5 else 3
        for _ in range(picks):
            title, base_amt, cat, tags, pay = mtd_templates[idx % len(mtd_templates)]
            idx += 1
            # Mild amount jitter so charts aren't flat
            jitter = 1.0 + ((idx % 7) - 3) * 0.04
            amt = round(base_amt * jitter, 2)
            hour = 8 + (idx % 12)
            minute = (idx * 7) % 60
            seed = f"hist-{offset}-{idx}"
            is_refund = title.startswith("Refund")
            cid = coffee_id if "coffee" in tags else (pets_id if "pets" in tags and cat == "Other" else None)
            # Map coffee custom category onto coffee-ish titles
            use_cat = cat
            if cid == coffee_id:
                use_cat = "Food"
            exp = expense(
                seed, title, amt, offset, use_cat,
                hour=hour, minute=minute, tags=tags, payment=pay,
                custom_id=cid, is_refund=is_refund,
            )
            expenses.append(exp)

    # A few intentional standout rows for Insights highlights
    expenses += [
        expense("big-rentish", "Apartment Utilities Split", 140.00, -18, "Utilities",
                hour=10, tags=["bills", "home"], payment="bank"),
        expense("big-date", "Anniversary Dinner", 128.00, -21, "Food",
                hour=20, minute=15, notes="Special night out", tags=["dinner", "date"], payment="credit"),
        expense("big-gear", "Running Shoes", 132.00, -28, "Shopping",
                hour=15, tags=["fitness", "clothes"], payment="credit"),
        expense("big-trip", "Weekend Getaway Airbnb", 246.00, -35, "Travel",
                hour=16, tags=["trip", "weekend"], payment="credit"),
    ]

    # Deduplicate by id (last wins) — shouldn't collide
    by_id = {e["id"]: e for e in expenses}
    expenses = list(by_id.values())
    expenses.sort(key=lambda e: e["date"], reverse=True)

    bundle = {
        "schema": {
            "version": "2.0",
            "minimumReaderVersion": "2.0",
            "exportedAt": iso(NOW),
            "appVersion": "2.0.0 (6)",
            "device": "Screenshot Demo",
        },
        "data": {
            "expenses": expenses,
            "subscriptions": subscriptions,
            "customCategories": custom_categories,
            "budgets": budgets,
            "deletedDefaultCategories": [],
        },
        "preferences": {
            "userName": "Alex",
            "selectedCurrency": "USD",
            "defaultHomeTimeFrame": "Month",
            "appearanceMode": "system",
            "preferredSummaryCategories": [
                "Food",
                "Groceries",
                "Transportation",
                "Entertainment",
                "Shopping",
            ],
            "notifications": {
                "weeklySummary": {"enabled": True, "weekday": 2, "hour": 9, "minute": 0},
                "monthlyDigest": {"enabled": True, "dayOfMonth": 1, "hour": 9, "minute": 0},
                "backupReminder": {"enabled": True, "dayOfMonth": 1, "hour": 10, "minute": 0},
            },
        },
    }

    json_path = OUT / "CashLens-Screenshot-Demo.cashlens.json"
    with json_path.open("w", encoding="utf-8") as f:
        json.dump(bundle, f, indent=2, ensure_ascii=False)
        f.write("\n")

    # Friendly CSV for GenericCSVAdapter / Pro import
    csv_path = OUT / "CashLens-Screenshot-Demo.csv"
    with csv_path.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            ["Date", "Title", "Amount", "Currency", "Category", "Notes", "Tags", "Payment Method"]
        )
        for e in sorted(expenses, key=lambda x: x["date"]):
            # CSV can't carry custom category UUIDs cleanly — flatten Coffee/Pets labels
            cat = e["category"]
            if e.get("customCategoryId") == coffee_id:
                cat = "Food"
            elif e.get("customCategoryId") == pets_id:
                cat = "Other"
            notes = e.get("notes") or ""
            tags = ";".join(e.get("tags") or [])
            pay = e.get("paymentMethod") or ""
            # Date as yyyy-MM-dd for broad compatibility
            date_only = e["date"][:10]
            title = e["title"]
            if e.get("isRefund"):
                notes = (notes + " | refund").strip(" |")
            w.writerow([date_only, title, f"{e['amount']:.2f}", "USD", cat, notes, tags, pay])

    mtd = sum(
        e["amount"] * (-1 if e.get("isRefund") else 1)
        for e in expenses
        if e["date"][:7] == TODAY.strftime("%Y-%m")
    )
    print(f"Wrote {json_path.name}")
    print(f"Wrote {csv_path.name}")
    print(f"Expenses: {len(expenses)}")
    print(f"Subscriptions: {len(subscriptions)}")
    print(f"Budgets: {len(budgets)}")
    print(f"Approx MTD net spend: ${mtd:,.2f} (budget $3,200)")
    print(f"Anchor today (UTC): {TODAY.date()}")


if __name__ == "__main__":
    main()
