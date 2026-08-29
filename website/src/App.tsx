import { useEffect, useRef, useState } from "react";
import { useReveal } from "./hooks/useReveal";

const APP_STORE = "https://apps.apple.com/us/app/cashlens/id6743153951";

/* ---------- Icons (Phosphor, duotone) ---------- */

const Icon = ({ d, opacity }: { d: string; opacity?: string }) => (
  <svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" fill="currentColor" viewBox="0 0 256 256">
    {opacity && <path d={opacity} opacity="0.2" />}
    <path d={d} />
  </svg>
);

const icons = {
  wallet: (
    <Icon
      opacity="M224,80V192a8,8,0,0,1-8,8H56a16,16,0,0,1-16-16V56A16,16,0,0,0,56,72H216A8,8,0,0,1,224,80Z"
      d="M216,64H56a8,8,0,0,1,0-16H192a8,8,0,0,0,0-16H56A24,24,0,0,0,32,56V184a24,24,0,0,0,24,24H216a16,16,0,0,0,16-16V80A16,16,0,0,0,216,64Zm0,128H56a8,8,0,0,1-8-8V78.63A23.84,23.84,0,0,0,56,80H216Zm-48-60a12,12,0,1,1,12,12A12,12,0,0,1,168,132Z"
    />
  ),
  clock: (
    <Icon
      opacity="M224,128a96,96,0,1,1-96-96A96,96,0,0,1,224,128Z"
      d="M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm0,192a88,88,0,1,1,88-88A88.1,88.1,0,0,1,128,216Zm64-88a8,8,0,0,1-8,8H128a8,8,0,0,1-8-8V72a8,8,0,0,1,16,0v48h48A8,8,0,0,1,192,128Z"
    />
  ),
  chart: (
    <Icon
      opacity="M224,64V208H32V48H208A16,16,0,0,1,224,64Z"
      d="M232,208a8,8,0,0,1-8,8H32a8,8,0,0,1-8-8V48a8,8,0,0,1,16,0V156.69l50.34-50.35a8,8,0,0,1,11.32,0L128,132.69,180.69,80H160a8,8,0,0,1,0-16h40a8,8,0,0,1,8,8v40a8,8,0,0,1-16,0V91.31l-58.34,58.35a8,8,0,0,1-11.32,0L96,123.31l-56,56V200H224A8,8,0,0,1,232,208Z"
    />
  ),
  sparkle: (
    <Icon
      opacity="M194.82,151.43l-55.09,20.3-20.3,55.09a7.92,7.92,0,0,1-14.86,0l-20.3-55.09-55.09-20.3a7.92,7.92,0,0,1,0-14.86l55.09-20.3,20.3-55.09a7.92,7.92,0,0,1,14.86,0l20.3,55.09,55.09,20.3A7.92,7.92,0,0,1,194.82,151.43Z"
      d="M197.58,129.06,146,110l-19-51.62a15.92,15.92,0,0,0-29.88,0L78,110l-51.62,19a15.92,15.92,0,0,0,0,29.88L78,178l19,51.62a15.92,15.92,0,0,0,29.88,0L146,178l51.62-19a15.92,15.92,0,0,0,0-29.88ZM137,164.22a8,8,0,0,0-4.74,4.74L112,223.85,91.78,169A8,8,0,0,0,87,164.22L32.15,144,87,123.78A8,8,0,0,0,91.78,119L112,64.15,132.22,119a8,8,0,0,0,4.74,4.74L191.85,144ZM144,40a8,8,0,0,1,8-8h16V16a8,8,0,0,1,16,0V32h16a8,8,0,0,1,0,16H184V64a8,8,0,0,1-16,0V48H152A8,8,0,0,1,144,40ZM248,88a8,8,0,0,1-8,8h-8v8a8,8,0,0,1-16,0V96h-8a8,8,0,0,1,0-16h8V72a8,8,0,0,1,16,0v8h8A8,8,0,0,1,248,88Z"
    />
  ),
  camera: (
    <Icon
      opacity="M208,64H176L160,40H96L80,64H48A16,16,0,0,0,32,80V192a16,16,0,0,0,16,16H208a16,16,0,0,0,16-16V80A16,16,0,0,0,208,64ZM128,168a36,36,0,1,1,36-36A36,36,0,0,1,128,168Z"
      d="M208,56H180.28L166.65,35.56A8,8,0,0,0,160,32H96a8,8,0,0,0-6.65,3.56L75.71,56H48A24,24,0,0,0,24,80V192a24,24,0,0,0,24,24H208a24,24,0,0,0,24-24V80A24,24,0,0,0,208,56Zm8,136a8,8,0,0,1-8,8H48a8,8,0,0,1-8-8V80a8,8,0,0,1,8-8H80a8,8,0,0,0,6.66-3.56L100.28,48h55.43l13.63,20.44A8,8,0,0,0,176,72h32a8,8,0,0,1,8,8ZM128,88a44,44,0,1,0,44,44A44.05,44.05,0,0,0,128,88Zm0,72a28,28,0,1,1,28-28A28,28,0,0,1,128,160Z"
    />
  ),
  heart: (
    <Icon
      opacity="M232,102c0,66-104,122-104,122S24,168,24,102A54,54,0,0,1,78,48c22.59,0,41.94,12.31,50,32,8.06-19.69,27.41-32,50-32A54,54,0,0,1,232,102Z"
      d="M178,40c-20.65,0-38.73,8.88-50,23.89C116.73,48.88,98.65,40,78,40a62.07,62.07,0,0,0-62,62c0,70,103.79,126.66,108.21,129a8,8,0,0,0,7.58,0C136.21,228.66,240,172,240,102A62.07,62.07,0,0,0,178,40ZM128,214.8C109.74,204.16,32,155.69,32,102A46.06,46.06,0,0,1,78,56c19.45,0,35.78,10.36,42.6,27a8,8,0,0,0,14.8,0c6.82-16.67,23.15-27,42.6-27a46.06,46.06,0,0,1,46,46C224,155.61,146.24,204.15,128,214.8Z"
    />
  ),
  arrow: (
    <Icon d="M204,64V168a12,12,0,0,1-24,0V93L72.49,200.49a12,12,0,0,1-17-17L163,76H88a12,12,0,0,1,0-24H192A12,12,0,0,1,204,64Z" />
  ),
};

/* ---------- Content ---------- */

type Beat = {
  icon: keyof typeof icons;
  title: string;
  description: string;
  image: string;
};

const BEATS: Beat[] = [
  {
    icon: "wallet",
    title: "Log Expenses Fast",
    description: "Add an amount, category, notes, tags, and payment method in seconds.",
    image: "/alf/feature-1.webp",
  },
  {
    icon: "clock",
    title: "Stay Ahead of Bills",
    description: "Track subscriptions and see upcoming renewals before money leaves your account.",
    image: "/alf/feature-2.webp",
  },
  {
    icon: "chart",
    title: "Set Budget Progress",
    description: "See how much remains across groceries, monthly spending, and other budgets.",
    image: "/alf/feature-3.webp",
  },
  {
    icon: "sparkle",
    title: "Understand Spending",
    description: "Use category breakdowns, trends, and heatmaps to spot habits without clutter.",
    image: "/alf/feature-4.webp",
  },
  {
    icon: "camera",
    title: "Review Every Day",
    description: "Browse expenses by date, search your activity, and keep your history organized.",
    image: "/alf/feature-5.webp",
  },
  {
    icon: "heart",
    title: "Know If You\u2019re On Track",
    description: "Get a calm view of today\u2019s spending, weekly pace, and what needs attention.",
    image: "/alf/feature-1.webp",
  },
];

const SHOTS = [1, 2, 3, 4, 5, 6, 7, 8].map((n) => `/alf/shot-${n}.webp`);

/* ---------- Components ---------- */

function AppStoreBadge() {
  return (
    <a className="badge" href={APP_STORE} target="_blank" rel="noopener noreferrer">
      <img src="/images/app-store-badge.svg" alt="Download on the App Store" draggable={false} />
    </a>
  );
}

function Phone({ src, className = "" }: { src: string; className?: string }) {
  return (
    <div className={`phone ${className}`}>
      <div className="phone-notch" aria-hidden="true" />
      <img src={src} alt="CashLens app screenshot" draggable={false} />
    </div>
  );
}

function Nav() {
  return (
    <header className="nav">
      <div className="container nav-inner">
        <span className="brand">
          <img className="brand-logo" src="/images/app-icon.png" alt="" />
          <span>CashLens: Expense Tracker</span>
        </span>
        <a className="btn btn-primary" href={APP_STORE} target="_blank" rel="noopener noreferrer">
          <span>Download</span>
          {icons.arrow}
        </a>
      </div>
    </header>
  );
}

function Hero() {
  return (
    <section className="hero">
      <div className="hero-glow" aria-hidden="true" />
      <div className="container hero-grid">
        <div className="hero-copy">
          <span className="eyebrow enter" style={{ animationDelay: "0ms" }}>
            Private by design
          </span>
          <h1 className="display h1 enter" style={{ animationDelay: "80ms" }}>
            Clarity for Every Expense
          </h1>
          <p className="lede enter" style={{ animationDelay: "160ms" }}>
            Track spending, bills, and budgets privately on your iPhone, with no account or cloud sync.
          </p>
          <div className="enter" style={{ animationDelay: "240ms" }}>
            <AppStoreBadge />
          </div>
        </div>
        <div className="hero-visual enter" style={{ animationDelay: "120ms" }}>
          <div className="hero-stage" aria-hidden="true" />
          <Phone src="/alf/feature-1.webp" className="phone-hero" />
        </div>
      </div>
    </section>
  );
}

/** Scroll-driven feature story: sticky device, beats crossfade as you scroll. */
function Story() {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(0);
  const headRef = useReveal();

  useEffect(() => {
    const onScroll = () => {
      const el = wrapRef.current;
      if (!el) return;
      const total = el.offsetHeight - window.innerHeight;
      if (total <= 0) return;
      const progress = Math.min(0.999, Math.max(0, -el.getBoundingClientRect().top / total));
      setActive(Math.floor(progress * BEATS.length));
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <section className="features" id="features">
      <div className="container">
        <div className="section-head reveal" ref={headRef}>
          <h2 className="display h2">Money, Made Clear</h2>
          <p>The essentials are easy to find, from one quick expense to the bigger picture.</p>
        </div>
      </div>

      {/* Desktop: sticky scrollytelling stage */}
      <div className="story" ref={wrapRef} style={{ height: `${BEATS.length * 85}vh` }}>
        <div className="story-sticky">
          <div className="container story-grid">
            <div className="story-copy">
              <ol className="story-rail" aria-hidden="true">
                {BEATS.map((_, i) => (
                  <li key={i} className={i === active ? "is-active" : ""} />
                ))}
              </ol>
              {BEATS.map((beat, i) => (
                <article key={beat.title} className={`story-panel ${i === active ? "is-active" : ""}`} aria-hidden={i !== active}>
                  <span className="feature-icon" aria-hidden="true">
                    {icons[beat.icon]}
                  </span>
                  <h3 className="display">{beat.title}</h3>
                  <p>{beat.description}</p>
                </article>
              ))}
            </div>
            <div className="story-device">
              {BEATS.map((beat, i) => (
                <Phone key={i} src={beat.image} className={i === active ? "is-active" : ""} />
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Mobile: simple stacked cards */}
      <div className="container story-mobile">
        {BEATS.map((beat) => (
          <article key={beat.title} className="story-card">
            <span className="feature-icon" aria-hidden="true">
              {icons[beat.icon]}
            </span>
            <div>
              <h3 className="display">{beat.title}</h3>
              <p>{beat.description}</p>
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}

function Showcase() {
  const headRef = useReveal();
  return (
    <section className="showcase">
      <div className="container">
        <div className="section-head reveal" ref={headRef}>
          <h2 className="display h2">A Clearer Money View</h2>
          <p>See the screens that keep spending, bills, and budgets within reach.</p>
        </div>
      </div>
      <div className="marquee-viewport">
        <div className="marquee">
          {[...SHOTS, ...SHOTS].map((src, i) => (
            <div className="marquee-item" key={i}>
              <img src={src} alt={`CashLens screenshot ${(i % SHOTS.length) + 1}`} loading="lazy" decoding="async" />
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function Cta() {
  const ref = useReveal();
  return (
    <section className="cta">
      <div className="container">
        <div className="cta-panel reveal" ref={ref}>
          <h2 className="display h2">Take Back Your Money View</h2>
          <p className="lede">Start tracking privately on your iPhone with no account, ads, or cloud sync.</p>
          <AppStoreBadge />
        </div>
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="footer">
      <div className="container footer-inner">
        <div>
          © {new Date().getFullYear()} CashLens · Made by <a href="mailto:email@rushiraj.me">Rushiraj Jadeja</a>
        </div>
        <ul className="footer-links">
          <li>
            <a href="/privacy">Privacy Policy</a>
          </li>
          <li>
            <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/" target="_blank" rel="noopener noreferrer">
              Terms of Use
            </a>
          </li>
          <li>
            <a href="mailto:rjadeja053@gmail.com">Support</a>
          </li>
        </ul>
      </div>
    </footer>
  );
}

export default function App() {
  return (
    <div className="site">
      <Nav />
      <main>
        <Hero />
        <Story />
        <Showcase />
        <Cta />
      </main>
      <Footer />
    </div>
  );
}
