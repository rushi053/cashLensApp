import type { ReactNode } from "react";
import { useReveal } from "./hooks/useReveal";

const APP_STORE = "https://apps.apple.com/us/app/cashlens/id6743153951";

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

function Shot({
  src,
  alt,
}: {
  src: string;
  alt: string;
}) {
  return (
    <div className="shot">
      <img src={src} alt={alt} loading="lazy" decoding="async" />
    </div>
  );
}

const mosaic = [
  { src: "/screenshots/2.jpg", caption: "Summary always at a glance" },
  { src: "/screenshots/3.jpg", caption: "Quickly add expenses" },
  { src: "/screenshots/5.jpg", caption: "Stop paying for what you don’t use" },
  { src: "/screenshots/6.jpg", caption: "Calendar view of your month" },
  { src: "/screenshots/7.jpg", caption: "Widgets, Siri & Shortcuts" },
  { src: "/screenshots/8.jpg", caption: "Visual spending habits" },
  { src: "/screenshots/9.jpg", caption: "See where every cent goes" },
  { src: "/screenshots/10.jpg", caption: "Dark mode for the owls" },
  { src: "/screenshots/11.jpg", caption: "Insights you’ll actually use" },
];

export default function App() {
  return (
    <div className="site">
      <nav className="nav" aria-label="Primary">
        <div className="nav-inner">
          <a className="brand" href="#top">
            <img src="/images/app-icon.png" alt="" width={30} height={30} />
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
        <div className="hero-inner">
          <div className="hero-copy">
            <p className="hero-brand">CashLens</p>
            <h1>Am I on track today?</h1>
            <p className="hero-sub">
              Privacy-first expense tracking for iPhone. No accounts, no cloud,
              no ads — just a clear read on your money.
            </p>
            <div className="cta-row">
              <a className="btn btn-dark" href={APP_STORE} target="_blank" rel="noreferrer">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                  <path d="M18.71 19.5C17.88 20.74 17 21.95 15.66 21.97C14.32 22 13.89 21.18 12.37 21.18C10.84 21.18 10.37 21.95 9.09997 22C7.78997 22.05 6.79997 20.68 5.95997 19.47C4.24997 16.97 2.93997 12.45 4.69997 9.39C5.56997 7.87 7.12997 6.91 8.81997 6.88C10.1 6.86 11.32 7.75 12.11 7.75C12.89 7.75 14.37 6.68 15.92 6.84C16.57 6.87 18.39 7.1 19.56 8.82C19.47 8.88 17.39 10.1 17.41 12.63C17.44 15.65 20.06 16.66 20.09 16.67C20.06 16.74 19.67 18.11 18.71 19.5ZM13 3.5C13.73 2.67 14.94 2.04 15.94 2C16.07 3.17 15.6 4.35 14.9 5.19C14.21 6.04 13.09 6.7 11.95 6.61C11.8 5.46 12.36 4.26 13 3.5Z" />
                </svg>
                Download on the App Store
              </a>
              <a className="btn btn-lavender" href="#privacy">
                Why it’s private
              </a>
            </div>
          </div>
          <div className="hero-shot">
            <img
              src="/screenshots/1.jpg"
              alt="CashLens budgets screen — Am I on track today?"
              fetchPriority="high"
            />
          </div>
        </div>
      </header>

      <section className="band band-ink" id="privacy">
        <div className="wrap split">
          <Reveal className="split-copy">
            <div className="band-head">
              <p className="kicker">Privacy</p>
              <h2>100% local. No accounts. No ads.</h2>
              <p className="lead">
                Your expenses never leave this iPhone. No CashLens servers, no
                analytics, no sign-up — App Store privacy label: Data Not Collected.
              </p>
              <div className="chips">
                <span className="chip">0 servers</span>
                <span className="chip">0 trackers</span>
                <span className="chip">0 accounts</span>
                <span className="chip">Face ID lock</span>
              </div>
            </div>
          </Reveal>
          <Reveal>
            <Shot src="/screenshots/4.jpg" alt="CashLens privacy dashboard" />
          </Reveal>
        </div>
      </section>

      <section className="band band-lavender">
        <div className="wrap split reverse">
          <Reveal className="split-copy">
            <div className="band-head">
              <p className="kicker">Today</p>
              <h2>Summary always at a glance</h2>
              <p className="lead">
                Totals, top categories, a week spark, and recent spends — so you
                know where you stand in seconds.
              </p>
            </div>
          </Reveal>
          <Reveal>
            <Shot src="/screenshots/2.jpg" alt="CashLens Today summary" />
          </Reveal>
        </div>
      </section>

      <section className="band band-lime">
        <div className="wrap split">
          <Reveal className="split-copy">
            <div className="band-head">
              <p className="kicker">Subscriptions</p>
              <h2>Stop paying for what you don’t use</h2>
              <p className="lead">
                See monthly burn, what’s due soon, and mark renewals paid —
                before they surprise you.
              </p>
            </div>
          </Reveal>
          <Reveal>
            <Shot src="/screenshots/5.jpg" alt="CashLens subscriptions" />
          </Reveal>
        </div>
      </section>

      <section className="band band-paper" id="features">
        <div className="wrap">
          <Reveal>
            <div className="band-head">
              <p className="kicker">Everything in CashLens</p>
              <h2>Built for real daily money habits</h2>
              <p className="lead">
                Budgets, activity, insights, widgets, and dark mode — the same
                screens you’ll see in the App Store.
              </p>
            </div>
          </Reveal>
          <div className="mosaic">
            {mosaic.map((item) => (
              <Reveal key={item.src}>
                <figure className="tile">
                  <img src={item.src} alt={item.caption} loading="lazy" decoding="async" />
                  <figcaption>{item.caption}</figcaption>
                </figure>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <section className="band band-lavender">
        <div className="wrap split reverse">
          <Reveal className="split-copy">
            <div className="band-head">
              <p className="kicker">Insights</p>
              <h2>See where every cent goes</h2>
              <p className="lead">
                Category breakdowns, forecasts, and highlights — calm charts
                without the spreadsheet noise.
              </p>
            </div>
          </Reveal>
          <Reveal>
            <Shot src="/screenshots/9.jpg" alt="CashLens category insights" />
          </Reveal>
        </div>
      </section>

      <section className="band band-paper" id="pro">
        <div className="wrap">
          <Reveal>
            <div className="band-head">
              <p className="kicker">Pricing</p>
              <h2>Generous free. Pro when you want more.</h2>
              <p className="lead">
                Unlimited tracking, widgets, Siri, App Lock, and export stay free.
              </p>
            </div>
          </Reveal>
          <div className="price-grid">
            <Reveal>
              <div className="price">
                <p className="tag">Free forever</p>
                <h3>CashLens</h3>
                <p className="amt">
                  $0 <small>/ always</small>
                </p>
                <ul>
                  <li>Unlimited expenses</li>
                  <li>Today, Activity & basic Insights</li>
                  <li>Subscriptions & reminders</li>
                  <li>Widgets, Siri & App Lock</li>
                  <li>Full export & backup</li>
                </ul>
              </div>
            </Reveal>
            <Reveal>
              <div className="price featured">
                <p className="tag">Most popular</p>
                <h3>CashLens Pro</h3>
                <p className="amt">
                  $19.99 <small>/ year</small>
                </p>
                <ul>
                  <li>7-day free trial</li>
                  <li>Budgets & smart alerts</li>
                  <li>Receipt OCR & PDF reports</li>
                  <li>Forecasts & advanced insights</li>
                  <li>Themes, icons & Pro widgets</li>
                </ul>
              </div>
            </Reveal>
            <Reveal>
              <div className="price">
                <p className="tag">Pay once</p>
                <h3>Lifetime</h3>
                <p className="amt">
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
        </div>
      </section>

      <section className="band band-paper" id="faq">
        <div className="wrap">
          <Reveal>
            <div className="band-head">
              <p className="kicker">FAQ</p>
              <h2>Straight answers</h2>
            </div>
          </Reveal>
          <div className="faq-list">
            {[
              {
                q: "Does CashLens connect to my bank?",
                a: "No. No Plaid, no bank login, no automatic sync. You enter expenses or import a CSV — that’s how we keep your finances private.",
              },
              {
                q: "Where is my data stored?",
                a: "Only on your device. There’s no CashLens cloud copy. Export anytime if you want an off-phone backup.",
              },
              {
                q: "What’s free vs Pro?",
                a: "Free includes unlimited tracking, subscriptions, widgets, Siri, App Lock, and export. Pro adds budgets, receipt OCR, forecasts, themes, and more. Yearly includes a 7-day free trial.",
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
        <Reveal>
          <h2>Your money. Your device. Your lens.</h2>
          <p className="lead">
            Download CashLens and start in seconds — no account required.
          </p>
          <div className="cta-row">
            <a className="btn btn-dark" href={APP_STORE} target="_blank" rel="noreferrer">
              Download on the App Store
            </a>
            <a className="btn btn-lime" href="#features">
              See the screens
            </a>
          </div>
        </Reveal>
      </section>

      <footer className="footer">
        <div className="footer-grid">
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
                  Terms of Use
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
