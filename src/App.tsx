import { createContext, useEffect, useRef, useContext, useState, type ReactNode } from "react";

type Screen = "welcome" | "home" | "analytics" | "profile" | "notifications";

type Notice = {
  id: number;
  title: string;
  body: string;
  time: string;
  tone: string;
  icon: string;
  read: boolean;
};

const initialNotices: Notice[] = [
  {
    id: 1,
    title: "New order received",
    body: "Wireless Headphone x2 was ordered for $501.50.",
    time: "2m ago",
    tone: "purple",
    icon: "bag",
    read: false,
  },
  {
    id: 2,
    title: "Payment received",
    body: "$1,240.00 has been added to your earnings.",
    time: "1h ago",
    tone: "mint",
    icon: "download",
    read: false,
  },
  {
    id: 3,
    title: "Low stock alert",
    body: "Running Shoes is down to 12 units.",
    time: "3h ago",
    tone: "peach",
    icon: "box",
    read: false,
  },
  {
    id: 4,
    title: "Delivery completed",
    body: "Order #13620 was delivered to the customer.",
    time: "Yesterday",
    tone: "blue",
    icon: "truck",
    read: true,
  },
  {
    id: 5,
    title: "Monthly report ready",
    body: "Your July 2024 report is ready to export.",
    time: "2 days ago",
    tone: "purple",
    icon: "chart",
    read: true,
  },
];

const NavContext = createContext<{ go: (s: Screen) => void; unread: number }>({
  go: () => {},
  unread: 0,
});

const orders = [
  {
    icon: "headphones",
    name: "Wireless Headphone",
    price: "$250.75",
    units: "150 Units",
    tone: "purple",
  },
  { icon: "watch", name: "Smart Watch", price: "$320.60", units: "120 Units", tone: "mint" },
  { icon: "shoe", name: "Running Shoes", price: "$180.45", units: "80 Units", tone: "peach" },
];

const insightCards = [
  { icon: "bag", label: "Total Orders", value: "11,240", tone: "purple" },
  { icon: "box", label: "Total Products", value: "3,126", tone: "mint" },
  { icon: "users", label: "Total Customers", value: "28,450", tone: "peach" },
  { icon: "truck", label: "Total Deliveries", value: "13,620", tone: "blue" },
];

function Icon({
  name,
  size = 22,
  strokeWidth = 1.8,
}: {
  name: string;
  size?: number;
  strokeWidth?: number;
}) {
  const paths: Record<string, ReactNode> = {
    arrow: (
      <>
        <path d="M5 12h14M14 6l6 6-6 6" />
      </>
    ),
    back: (
      <>
        <path d="m15 18-6-6 6-6" />
        <path d="M9 12h12" />
      </>
    ),
    bell: (
      <>
        <path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9" />
        <path d="M10 21h4" />
      </>
    ),
    menu: (
      <>
        <path d="M5 7h14M5 12h10M5 17h6" />
      </>
    ),
    home: (
      <>
        <path d="m4 11 8-7 8 7v9H5v-9" />
        <path d="M9 20v-6h6v6" />
      </>
    ),
    chart: (
      <>
        <path d="M4 20v-7M10 20V9M16 20V4M22 20H2" />
        <path d="m4 10 6-5 5 2 6-5" />
      </>
    ),
    user: (
      <>
        <circle cx="12" cy="8" r="4" />
        <path d="M4 21c.6-4.1 3.2-6 8-6s7.4 1.9 8 6" />
      </>
    ),
    download: (
      <>
        <path d="M12 3v12M7 10l5 5 5-5M5 21h14" />
      </>
    ),
    bag: (
      <>
        <path d="M5 8h14l1 13H4L5 8Z" />
        <path d="M9 9V6a3 3 0 0 1 6 0v3" />
      </>
    ),
    box: (
      <>
        <path d="m4 7 8-4 8 4-8 4-8-4Z" />
        <path d="m4 7v10l8 4 8-4V7M12 11v10" />
      </>
    ),
    users: (
      <>
        <circle cx="9" cy="8" r="3" />
        <circle cx="17" cy="9" r="2.5" />
        <path d="M3 20c.5-4 2.5-6 6-6s5.5 2 6 6M14 15c4-.5 6 1.5 7 5" />
      </>
    ),
    truck: (
      <>
        <path d="M3 6h11v11H3zM14 10h4l3 4v3h-7z" />
        <circle cx="7" cy="19" r="2" />
        <circle cx="18" cy="19" r="2" />
      </>
    ),
    headphones: (
      <>
        <path d="M4 13v-2a8 8 0 0 1 16 0v2" />
        <path d="M4 13h3v7H5a2 2 0 0 1-2-2v-3a2 2 0 0 1 1-2ZM20 13h-3v7h2a2 2 0 0 0 2-2v-3a2 2 0 0 0-1-2Z" />
      </>
    ),
    watch: (
      <>
        <path d="M9 2h6l1 5H8l1-5ZM9 22h6l1-5H8l1 5Z" />
        <rect x="6" y="7" width="12" height="10" rx="3" />
        <path d="M9 10h6" />
      </>
    ),
    shoe: (
      <>
        <path d="M3 15c3 0 5-5 6-9 2 4 5 6 10 7 2 .5 3 2 2 5H4c-2 0-3-2-1-3Z" />
        <path d="m10 9 2-1M13 11l2-1" />
      </>
    ),
    spark: (
      <>
        <path d="m12 2 1.4 5.1L18 9l-4.6 1.9L12 16l-1.4-5.1L6 9l4.6-1.9L12 2Z" />
      </>
    ),
    gear: (
      <>
        <circle cx="12" cy="12" r="3" />
        <path
          d="M19 13.5v-3l-2.2-.6-.7-1.7 1.1-2-2.1-2.1-2 1.1-1.7-.7L10.8 2h-3l-.6 2.5-1.7.7-2-1.1-2.1 2.1 1.1 2-.7 1.7-2.2.6v3l2.2.6.7 1.7-1.1 2 2.1 2.1 2-1.1 1.7.7.6 2.5h3l.6-2.5 1.7-.7 2 1.1 2.1-2.1-1.1-2 .7-1.7 2.2-.6Z"
          transform="translate(2.2 0) scale(.82)"
        />
      </>
    ),
    trend: (
      <>
        <path d="m4 16 5-5 4 3 7-8" />
        <path d="M15 6h5v5" />
      </>
    ),
  };
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {paths[name]}
    </svg>
  );
}

function StatusBar() {
  return (
    <div className="status-bar">
      <span>9:41</span>
      <div className="status-icons">
        <span className="signal">
          <i />
          <i />
          <i />
          <i />
        </span>
        <svg viewBox="0 0 18 14">
          <path d="M2 5.5C6 2 12 2 16 5.5M5 8.5c2.5-2 5.5-2 8 0M8 11.5c.7-.6 1.3-.6 2 0" />
        </svg>
        <span className="battery">
          <i />
        </span>
      </div>
    </div>
  );
}

function RoundButton({
  children,
  label,
  onClick,
}: {
  children: ReactNode;
  label: string;
  onClick?: () => void;
}) {
  return (
    <button className="round-button" aria-label={label} onClick={onClick}>
      {children}
    </button>
  );
}

function AppHeader({ onBack }: { onBack?: () => void }) {
  const { go, unread } = useContext(NavContext);
  return (
    <header className="app-header">
      {onBack ? (
        <RoundButton label="Go back" onClick={onBack}>
          <Icon name="back" />
        </RoundButton>
      ) : (
        <button className="avatar" aria-label="View profile" onClick={() => go("profile")}>
          <span className="avatar-hair" />
          <span className="avatar-face">A</span>
        </button>
      )}
      <div className="header-actions">
        <RoundButton label="Notifications" onClick={() => go("notifications")}>
          <Icon name="bell" />
          {unread > 0 && <b className="badge">{unread}</b>}
        </RoundButton>
        <RoundButton label="Open menu" onClick={() => go("profile")}>
          <Icon name="menu" />
        </RoundButton>
      </div>
    </header>
  );
}

function Welcome({ onStart }: { onStart: () => void }) {
  return (
    <main className="screen welcome-screen">
      <StatusBar />
      <div className="welcome-content">
        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: '8px' }}>
          <img src="/favicon.png" alt="JengaBiz" style={{ width: '42px', height: '42px', borderRadius: '12px' }} />
        </div>
        <div className="hero-art">
          <span className="hero-dot dot-a" />
          <span className="hero-dot dot-b" />
          <img
            src="/assets/duka-growth-hero.png"
            alt="Phone displaying business growth analytics beside coins and a plant"
          />
        </div>
        <section className="welcome-copy">
          <p className="eyebrow">SMARTER BUSINESS, EVERY DAY</p>
          <h1>
            Kickstart Your Business
            <br />
            Growth Today
          </h1>
          <div className="feature-row">
            <div className="feature-icon purple">
              <Icon name="chart" size={27} />
            </div>
            <div>
              <h3>Smart lead tracking</h3>
              <p>Stay organized and monitor every lead in one place with real-time updates.</p>
            </div>
          </div>
          <div className="feature-row">
            <div className="feature-icon teal">
              <Icon name="gear" size={28} />
            </div>
            <div>
              <h3>Automated workflow</h3>
              <p>
                Save time with automated tasks, follow-ups, and reminders to close deals faster.
              </p>
            </div>
          </div>
        </section>
      </div>
      <button className="primary-cta" onClick={onStart}>
        <span>Let&apos;s Get Started</span>
        <i>
          <Icon name="arrow" size={25} />
        </i>
      </button>
      <div className="home-indicator" />
    </main>
  );
}

function BottomNav({
  active,
  onChange,
}: {
  active: "home" | "analytics" | "profile";
  onChange: (screen: Screen) => void;
}) {
  const ref = useRef<HTMLElement>(null);
  const [hidden, setHidden] = useState(false);
  useEffect(() => {
    const el = ref.current?.parentElement;
    if (!el) return;
    let timer: number;
    const onScroll = () => {
      setHidden(true);
      window.clearTimeout(timer);
      timer = window.setTimeout(() => setHidden(false), 300);
    };
    el.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      el.removeEventListener("scroll", onScroll);
      window.clearTimeout(timer);
    };
  }, []);
  return (
    <nav
      ref={ref}
      className={`bottom-nav ${hidden ? "hidden" : ""}`}
      aria-label="Primary navigation"
    >
      <button
        className={active === "home" ? "active" : ""}
        onClick={() => onChange("home")}
        aria-label="Home"
      >
        <Icon name="home" />
      </button>
      <button
        className={active === "analytics" ? "active" : ""}
        onClick={() => onChange("analytics")}
        aria-label="Analytics"
      >
        <Icon name="chart" />
      </button>
      <button
        className={active === "profile" ? "active" : ""}
        onClick={() => onChange("profile")}
        aria-label="Profile"
      >
        <Icon name="user" />
      </button>
    </nav>
  );
}

function Home({ onChange }: { onChange: (screen: Screen) => void }) {
  return (
    <main className="screen scroll-screen">
      <StatusBar />
      <div className="page-content">
        <AppHeader />
        <section className="greeting">
          <p>
            Hi, <strong>Alex Smith</strong>
          </p>
          <span>here&apos;s your business overview</span>
        </section>
        <button className="earnings-card" onClick={() => onChange("analytics")}>
          <div className="wallet-icon">
            ▰<i />
          </div>
          <div>
            <span>Total Earnings</span>
            <strong>
              $12,540.90 <em>↗ 18%</em>
            </strong>
            <small>vs last month</small>
          </div>
          <svg viewBox="0 0 90 58">
            <path d="M2 52C14 49 15 33 26 36s10 12 20 6 10-31 21-29 8 16 21-11" />
          </svg>
        </button>
        <div className="profit-card">
          <div className="pie-chart">
            <i />
          </div>
          <div>
            <span>Net Profit</span>
            <strong>
              $7,540.90 <em>↗ 18%</em>
            </strong>
            <small>vs last month</small>
          </div>
        </div>
        <div className="section-title">
          <h2>Latest Orders</h2>
          <button>
            See All <Icon name="arrow" size={17} />
          </button>
        </div>
        <div className="orders-list">
          {orders.map((order) => (
            <button className={`order-card ${order.tone}`} key={order.name}>
              <i className="product-icon">
                <Icon name={order.icon} size={29} />
              </i>
              <span>
                <small>{order.name}</small>
                <strong>{order.price}</strong>
              </span>
              <em>{order.units}</em>
            </button>
          ))}
        </div>
      </div>
      <BottomNav active="home" onChange={onChange} />
      <div className="home-indicator" />
    </main>
  );
}

function Analytics({ onChange }: { onChange: (screen: Screen) => void }) {
  const bars = [
    { spent: 37, received: 19, label: "1–7" },
    { spent: 55, received: 33, label: "8–14" },
    { spent: 67, received: 43, label: "15–21" },
    { spent: 72, received: 48, label: "22–28" },
    { spent: 52, received: 32, label: "29–31" },
  ];
  return (
    <main className="screen scroll-screen analytics-screen">
      <StatusBar />
      <div className="page-content">
        <AppHeader onBack={() => onChange("home")} />
        <div className="analytics-heading">
          <button className="month-picker">
            July 2024 <span>⌄</span>
          </button>
          <button className="export-button">
            <Icon name="download" size={18} /> Export
          </button>
        </div>
        <div className="stat-grid">
          <div className="stat-card">
            <span>Total Spent</span>
            <strong>$9,280.60</strong>
            <small>↗ 15% vs last month</small>
          </div>
          <div className="stat-card">
            <span>Total Received</span>
            <strong>$12,540.90</strong>
            <small>↗ 18% vs last month</small>
          </div>
        </div>
        <section className="chart-card">
          <div className="chart-legend">
            <span>
              <i className="received" /> Received <strong>$7,200.00</strong>
            </span>
            <span>
              <i className="spent" /> Spent <strong>$5,100.60</strong>
            </span>
          </div>
          <div className="chart-area">
            <div className="y-axis">
              <span>$10K</span>
              <span>$8K</span>
              <span>$6K</span>
              <span>$4K</span>
              <span>$2K</span>
              <span>$0</span>
            </div>
            <div className="grid-lines">
              {[1, 2, 3, 4, 5].map((n) => (
                <i key={n} />
              ))}
            </div>
            <div className="bars">
              {bars.map((bar) => (
                <div className="bar-column" key={bar.label}>
                  <div className="bar">
                    <i style={{ height: `${bar.spent}%` }} />
                    <b style={{ height: `${bar.received}%` }} />
                  </div>
                  <span>{bar.label}</span>
                </div>
              ))}
            </div>
          </div>
        </section>
        <section className="insights">
          <h2>Business Insights</h2>
          <div className="insight-grid">
            {insightCards.map((card) => (
              <button className={`insight-card ${card.tone}`} key={card.label}>
                <Icon name={card.icon} size={25} />
                <span>↗</span>
                <small>{card.label}</small>
                <strong>{card.value}</strong>
              </button>
            ))}
          </div>
        </section>
      </div>
      <BottomNav active="analytics" onChange={onChange} />
      <div className="home-indicator" />
    </main>
  );
}

function Toggle({ on, onClick, label }: { on: boolean; onClick: () => void; label: string }) {
  return (
    <button
      className={`toggle ${on ? "on" : ""}`}
      role="switch"
      aria-checked={on}
      aria-label={label}
      onClick={onClick}
    >
      <i />
    </button>
  );
}

function Notifications({
  items,
  setItems,
  onChange,
}: {
  items: Notice[];
  setItems: (n: Notice[]) => void;
  onChange: (s: Screen) => void;
}) {
  const unread = items.filter((n) => !n.read).length;
  return (
    <main className="screen scroll-screen">
      <StatusBar />
      <div className="page-content">
        <header className="app-header">
          <RoundButton label="Go back" onClick={() => onChange("home")}>
            <Icon name="back" />
          </RoundButton>
          <button
            className="export-button"
            onClick={() => setItems(items.map((n) => ({ ...n, read: true })))}
            disabled={!unread}
          >
            Mark all read
          </button>
        </header>
        <div className="analytics-heading">
          <h2 className="page-title">Notifications</h2>
          <span className="count-pill">{unread} new</span>
        </div>
        {items.length === 0 && <p className="empty">You&apos;re all caught up.</p>}
        <div className="orders-list">
          {items.map((n) => (
            <div key={n.id} className={`notice ${n.tone} ${n.read ? "" : "unread"}`}>
              <button
                className="notice-main"
                onClick={() =>
                  setItems(items.map((x) => (x.id === n.id ? { ...x, read: true } : x)))
                }
              >
                <i className="product-icon">
                  <Icon name={n.icon} size={24} />
                </i>
                <span>
                  <strong>{n.title}</strong>
                  <small>{n.body}</small>
                  <em>{n.time}</em>
                </span>
              </button>
              <button
                className="notice-x"
                aria-label="Dismiss"
                onClick={() => setItems(items.filter((x) => x.id !== n.id))}
              >
                ×
              </button>
            </div>
          ))}
        </div>
      </div>
      <div className="home-indicator" />
    </main>
  );
}

function Profile({ onChange, onLogout }: { onChange: (s: Screen) => void; onLogout: () => void }) {
  const { unread } = useContext(NavContext);
  const [prefs, setPrefs] = useState({
    push: true,
    orders: true,
    stock: true,
    email: false,
    biometric: true,
  });
  const flip = (k: keyof typeof prefs) => setPrefs({ ...prefs, [k]: !prefs[k] });
  const rows: { k: keyof typeof prefs; label: string; sub: string }[] = [
    { k: "push", label: "Push notifications", sub: "Alerts on your device" },
    { k: "orders", label: "Order updates", sub: "New orders and deliveries" },
    { k: "stock", label: "Low stock alerts", sub: "When products run low" },
    { k: "email", label: "Weekly email report", sub: "Summary every Monday" },
    { k: "biometric", label: "Biometric login", sub: "Face ID or fingerprint" },
  ];
  return (
    <main className="screen scroll-screen">
      <StatusBar />
      <div className="page-content">
        <header className="app-header">
          <RoundButton label="Go back" onClick={() => onChange("home")}>
            <Icon name="back" />
          </RoundButton>
          <RoundButton label="Notifications" onClick={() => onChange("notifications")}>
            <Icon name="bell" />
            {unread > 0 && <b className="badge">{unread}</b>}
          </RoundButton>
        </header>
        <section className="profile-card">
          <div className="avatar big">
            <span className="avatar-hair" />
            <span className="avatar-face">A</span>
          </div>
          <h2>Alex Smith</h2>
          <p>alex@dukaledger.com</p>
          <span className="count-pill">JengaBiz Pro</span>
        </section>
        <div className="stat-grid">
          <div className="stat-card">
            <span>Total Orders</span>
            <strong>11,240</strong>
          </div>
          <div className="stat-card">
            <span>Customers</span>
            <strong>28,450</strong>
          </div>
        </div>
        <button className="menu-row" onClick={() => onChange("notifications")}>
          <i className="mi purple">
            <Icon name="bell" size={20} />
          </i>
          <span>Notifications</span>
          {unread > 0 && <em className="count-pill">{unread} new</em>}
          <Icon name="arrow" size={18} />
        </button>
        <button className="menu-row" onClick={() => onChange("analytics")}>
          <i className="mi mint">
            <Icon name="chart" size={20} />
          </i>
          <span>Business analytics</span>
          <Icon name="arrow" size={18} />
        </button>
        <h3 className="group-title">Preferences</h3>
        <div className="prefs">
          {rows.map((r) => (
            <div className="pref" key={r.k}>
              <span>
                <strong>{r.label}</strong>
                <small>{r.sub}</small>
              </span>
              <Toggle on={prefs[r.k]} onClick={() => flip(r.k)} label={r.label} />
            </div>
          ))}
        </div>
        <button className="logout" onClick={onLogout}>
          Log out
        </button>
      </div>
      <div className="home-indicator" />
    </main>
  );
}

export default function App() {
  const [screen, setScreen] = useState<Screen>("welcome");
  const [notices, setNotices] = useState(initialNotices);
  const unread = notices.filter((n) => !n.read).length;
  return (
    <NavContext.Provider value={{ go: setScreen, unread }}>
      <div className="app-stage">
        <div className="phone-shell">
          {screen === "welcome" && <Welcome onStart={() => setScreen("home")} />}
          {screen === "home" && <Home onChange={setScreen} />}
          {screen === "analytics" && <Analytics onChange={setScreen} />}
          {screen === "profile" && (
            <Profile onChange={setScreen} onLogout={() => setScreen("welcome")} />
          )}
          {screen === "notifications" && (
            <Notifications items={notices} setItems={setNotices} onChange={setScreen} />
          )}
        </div>
      </div>
    </NavContext.Provider>
  );
}
