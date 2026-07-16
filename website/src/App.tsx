import type { ReactNode } from "react";
import { useReveal } from "./hooks/useReveal";
import { InsightsPhone, PrivacyPhone, TodayPhone } from "./components/Phones";

const APP_STORE =
  "https://apps.apple.com/us/app/cashlens/id6743153951";

function Reveal({
  className = "",
  children,
}: {
  className?: string;
  children: ReactNode;
}) {
  const ref = useReveal<HTMLDivElement>();
  return (
    <div ref={ref} className={`reveal ${className}`.trim()}>
      {children}
    </div>
  );
}

export default function App() {
  return (
    <div className="site">
      <nav className="nav" aria-label="Primary">
        <div className="nav-inner">
          <a className="brand" href="#top">
            <img src="/images/app-icon.png" alt="" width={28} height={28} />
            CashLens
          </a>
          <div className="nav-links">
            <a href="#privacy">Privacy</a>
            <a href="#features">Features</a>
            <a href="#pro">Pro</a>
            <a href="#faq">FAQ</a>
          </div>
          <a className="nav-cta" href={APP_STORE} target="_blank" rel="noreferrer">
            Get the app
          </a>
        </div>
      </nav>

      <header className="hero" id="top">
        <div className="hero-grain" aria-hidden="true" />
        <div className="hero-grid">
          <div className="hero-copy">
            <p className="hero-brand">
              <span>CashLens</span>
            </p>
            <h1>See your spending clearly — privately.</h1>
            <p className="hero-sub">
              A calm expense tracker with no accounts, no cloud, and no
              analytics. Your money stays on your iPhone.
            </p>
            <div className="cta-row">
              <a className="btn-primary" href={APP_STORE} target="_blank" rel="noreferrer">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                  <path d="M18.71 19.5C17.88 20.74 17 21.95 15.66 21.97C14.32 22 13.89 21.18 12.37 21.18C10.84 21.18 10.37 21.95 9.09997 22C7.78997 22.05 6.79997 20.68 5.95997 19.47C4.24997 16.97 2.93997 12.45 4.69997 9.39C5.56997 7.87 7.12997 6.91 8.81997 6.88C10.1 6.86 11.32 7.75 12.11 7.75C12.89 7.75 14.37 6.68 15.92 6.84C16.57 6.87 18.39 7.1 19.56 8.82C19.47 8.88 17.39 10.1 17.41 12.63C17.44 15.65 20.06 16.66 20.09 16.67C20.06 16.74 19.67 18.11 18.71 19.5ZM13 3.5C13.73 2.67 14.94 2.04 15.94 2C16.07 3.17 15.6 4.35 14.9 5.19C14.21 6.04 13.09 6.7 11.95 6.61C11.8 5.46 12.36 4.26 13 3.5Z" />
                </svg>
                Download on the App Store
              </a>
              <a className="btn-ghost" href="#privacy">
                Why private matters
              </a>
            </div>
          </div>
          <div className="hero-stage">
            <TodayPhone />
          </div>
        </div>
      </header>

      <section className="privacy" id="privacy">
        <div className="section privacy-layout">
          <Reveal>
            <p className="section-kicker">Privacy by architecture</p>
            <h2 className="section-title">Zero servers. Zero trackers. Zero accounts.</h2>
            <p className="section-lead">
              CashLens doesn’t sync your expenses to the cloud, doesn’t profile
              how you spend, and never asks you to sign up. The only network
              path is Apple’s App Store for purchases — plus links you open
              yourself.
            </p>
            <ul className="trust-list">
              <li>
                <i>✓</i>
                <span>On-device storage with optional Face ID App Lock</span>
              </li>
              <li>
                <i>✓</i>
                <span>Works offline — airplane mode included</span>
              </li>
              <li>
                <i>✓</i>
                <span>Full export & backup whenever you want</span>
              </li>
              <li>
                <i>✓</i>
                <span>App Store privacy label: Data Not Collected</span>
              </li>
            </ul>
          </Reveal>
          <Reveal>
            <div className="mini-phone-wrap">
              <PrivacyPhone />
            </div>
          </Reveal>
        </div>
      </section>

      <section className="features" id="features">
        <div className="section">
          <Reveal>
            <p className="section-kicker">Built for daily clarity</p>
            <h2 className="section-title">Everything you need. Nothing that watches you.</h2>
            <p className="section-lead">
              Fast logging, calm insights, bills you won’t forget — designed to
              respect your attention.
            </p>
          </Reveal>
          <div className="feature-rail">
            {[
              {
                icon: "◎",
                title: "Today verdict",
                body: "Open the app and know if you’re on track — daily pace, recent spends, and a clear pulse on your week.",
              },
              {
                icon: "☰",
                title: "Activity that stays tidy",
                body: "Search, calendar, tags, bulk edit, and refunds. Find any expense without spreadsheet pain.",
              },
              {
                icon: "◔",
                title: "Insights & forecasts",
                body: "Category breakdowns, trends, heatmaps — plus Pro forecasts with subscription cashflow overlay.",
              },
              {
                icon: "↻",
                title: "Bills & subscriptions",
                body: "Track renewals, pause when needed, and get reminded before money leaves your account.",
              },
              {
                icon: "▢",
                title: "Widgets & Siri",
                body: "Home Screen and Lock Screen widgets. Log with Shortcuts — without opening the app.",
              },
              {
                icon: "⌁",
                title: "Receipts on-device",
                body: "Scan or attach receipts with on-device OCR. Archive backups include your photos.",
              },
            ].map((f) => (
              <Reveal key={f.title}>
                <article className="feature">
                  <div className="feature-icon" aria-hidden="true">
                    {f.icon}
                  </div>
                  <h3>{f.title}</h3>
                  <p>{f.body}</p>
                </article>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <section className="showcase" id="product">
        <div className="section">
          <Reveal>
            <p className="section-kicker">Product</p>
            <h2 className="section-title">Designed to feel quiet and expensive.</h2>
          </Reveal>

          <div className="showcase-block">
            <Reveal className="showcase-copy">
              <h3 className="section-title" style={{ fontSize: "clamp(1.7rem, 3vw, 2.3rem)" }}>
                Know where the month went
              </h3>
              <p className="section-lead">
                Beautiful charts without the dashboard noise. Payment methods,
                categories, and tags help you spot habits — still entirely on
                your device.
              </p>
            </Reveal>
            <Reveal>
              <div className="mini-phone-wrap">
                <InsightsPhone />
              </div>
            </Reveal>
          </div>

          <div className="showcase-block reverse">
            <Reveal className="showcase-copy">
              <h3 className="section-title" style={{ fontSize: "clamp(1.7rem, 3vw, 2.3rem)" }}>
                Budgets that nudge — never nag
              </h3>
              <p className="section-lead">
                Category and weekly budgets with clear progress. Alerts at 80%
                and 100%. Pro themes and alternate icons make it feel like your
                app.
              </p>
            </Reveal>
            <Reveal>
              <div className="mini-phone-wrap">
                <TodayPhone />
              </div>
            </Reveal>
          </div>
        </div>
      </section>

      <section className="pricing" id="pro">
        <div className="section">
          <Reveal>
            <p className="section-kicker">Pricing</p>
            <h2 className="section-title">Generous free. Pro when you want more.</h2>
            <p className="section-lead">
              Unlimited tracking, widgets, Siri, App Lock, and full export stay
              free. Upgrade for budgets, OCR, forecasts, and polish.
            </p>
          </Reveal>
          <div className="price-grid">
            <Reveal>
              <div className="price">
                <p className="price-tag">Free forever</p>
                <h3>CashLens</h3>
                <p className="amount">
                  $0 <small>/ always</small>
                </p>
                <ul>
                  <li>Unlimited expenses</li>
                  <li>Today, Activity & basic Insights</li>
                  <li>Subscriptions & reminders</li>
                  <li>Widgets, Siri & App Lock</li>
                  <li>JSON / CSV / archive export</li>
                </ul>
              </div>
            </Reveal>
            <Reveal>
              <div className="price featured">
                <p className="price-tag">Most popular</p>
                <h3>CashLens Pro</h3>
                <p className="amount">
                  $19.99 <small>/ year</small>
                </p>
                <ul>
                  <li>7-day free trial</li>
                  <li>Budgets & smart alerts</li>
                  <li>Receipt OCR & PDF reports</li>
                  <li>Advanced insights & forecasts</li>
                  <li>Themes, icons & Pro widgets</li>
                  <li>CSV import from other apps</li>
                </ul>
              </div>
            </Reveal>
            <Reveal>
              <div className="price">
                <p className="price-tag">Pay once</p>
                <h3>Lifetime</h3>
                <p className="amount">
                  $39.99 <small>/ forever</small>
                </p>
                <ul>
                  <li>All Pro features</li>
                  <li>One-time unlock</li>
                  <li>Family Sharing supported</li>
                  <li>No subscription to manage</li>
                </ul>
              </div>
            </Reveal>
          </div>
          <Reveal>
            <p className="section-lead" style={{ marginTop: 24 }}>
              Also available monthly at $2.99. Tip jar supporters can earn Pro
              through Coffee / Lunch / Fuel donations.
            </p>
          </Reveal>
        </div>
      </section>

      <section className="faq" id="faq">
        <div className="section">
          <Reveal>
            <p className="section-kicker">FAQ</p>
            <h2 className="section-title">Straight answers.</h2>
          </Reveal>
          <div className="faq-list">
            {[
              {
                q: "Does CashLens connect to my bank?",
                a: "No. There’s no Plaid, no bank login, and no automatic sync. You enter expenses (or import a CSV). That’s how we keep your finances private.",
              },
              {
                q: "Where is my data stored?",
                a: "Only on your device — including the App Group used by widgets. There’s no CashLens server copy. Export regularly if you want an off-phone backup.",
              },
              {
                q: "Can I use it offline?",
                a: "Yes. Logging, budgets, insights, and history all work without a network. Purchases use the App Store when you choose to buy Pro.",
              },
              {
                q: "What’s included for free?",
                a: "Unlimited expense tracking, subscriptions, basic insights, widgets, Siri, App Lock, and full export/backup. Pro adds budgets, receipt OCR, forecasts, themes, and more.",
              },
              {
                q: "Is there a free trial?",
                a: "Yes — CashLens Pro monthly and yearly include a 7-day free trial via the App Store. Cancel anytime in Subscriptions settings.",
              },
            ].map((item) => (
              <Reveal key={item.q}>
                <details>
                  <summary>{item.q}</summary>
                  <p>{item.a}</p>
                </details>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <section className="final">
        <div className="section">
          <Reveal>
            <h2 className="section-title">Your money. Your device. Your lens.</h2>
            <p className="section-lead">
              Download CashLens and start tracking in seconds — no account
              required.
            </p>
            <div className="cta-row">
              <a className="btn-primary" href={APP_STORE} target="_blank" rel="noreferrer">
                Download on the App Store
              </a>
            </div>
          </Reveal>
        </div>
      </section>

      <footer className="footer">
        <div className="footer-inner">
          <div>
            <div className="footer-brand">CashLens</div>
            <p>
              Privacy-first expense tracking for iPhone & iPad. Built by{" "}
              <a href="mailto:email@rushiraj.me">Rushiraj Jadeja</a>.
            </p>
          </div>
          <div>
            <h4>Product</h4>
            <ul>
              <li>
                <a href="#features">Features</a>
              </li>
              <li>
                <a href="#pro">Pricing</a>
              </li>
              <li>
                <a href={APP_STORE} target="_blank" rel="noreferrer">
                  App Store
                </a>
              </li>
            </ul>
          </div>
          <div>
            <h4>Legal</h4>
            <ul>
              <li>
                <a href="/privacy.html">Privacy Policy</a>
              </li>
              <li>
                <a
                  href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
                  target="_blank"
                  rel="noreferrer"
                >
                  Terms of Use (EULA)
                </a>
              </li>
              <li>
                <a href="mailto:rjadeja053@gmail.com">Support</a>
              </li>
            </ul>
          </div>
        </div>
        <div className="footer-bottom">
          <span>© {new Date().getFullYear()} CashLens. All rights reserved.</span>
          <span>Apple and the App Store are trademarks of Apple Inc.</span>
        </div>
      </footer>
    </div>
  );
}
