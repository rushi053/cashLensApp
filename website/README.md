# CashLens website

Premium marketing site for [cashlens.app](https://cashlens.app).

## Local

```bash
cd website
npm install
npm run dev
```

## Build

```bash
npm run build
```

Output: `dist/`

## Deploy on Vercel

1. Push this folder as a GitHub repo (or connect the monorepo and set **Root Directory** to `website`).
2. Import in [vercel.com](https://vercel.com) → Framework: **Vite**.
3. Build command: `npm run build` · Output: `dist`.
4. Domains → add `cashlens.app` + `www.cashlens.app`.
5. At your DNS provider:
   - `A` / recommended: follow Vercel’s DNS records for the apex
   - `CNAME` `www` → `cname.vercel-dns.com`

## Privacy

Canonical URL: **`https://cashlens.app/privacy`**  
(`public/privacy.html` — also redirects from `/privacy.html`)

Use that same URL in App Store Connect and in the iOS app. No separate GitHub Pages repo needed once the domain is live; optionally redirect `rushi053.github.io/CashLens/*` → `cashlens.app/*`.
