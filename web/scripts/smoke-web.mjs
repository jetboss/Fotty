const baseURL = process.env.FOTTY_WEB_BASE_URL || "http://localhost:3000";

const routes = ["/", "/schedule", "/more", "/search", "/favorites", "/settings", "/support", "/subscribe", "/collab", "/mvp", "/help", "/feedback", "/teams", "/tables", "/login", "/welcome", "/privacy", "/terms"];

async function fetchText(path) {
  const response = await fetch(new URL(path, baseURL), {
    headers: { Accept: "text/html,application/json" },
  });
  const body = await response.text();
  return { response, body };
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function checkFootballStandings() {
  const response = await fetch(new URL("/api/football/standings?league=premierLeague", baseURL));
  const data = await response.json();
  assert(response.ok, `/api/football/standings expected 200, got ${response.status}`);
  if (data.configured) {
    assert((data.standings?.length ?? 0) > 0, "/api/football/standings returned no rows");
  }
  console.log(`ok football standings configured=${Boolean(data.configured)} rows=${data.standings?.length ?? 0}`);
}

async function checkHomeSeo() {
  const { body } = await fetchText("/");
  const hasClassicHomeSeo = body.includes("Fotty live sports and match day");
  const hasV2HomeSeo = body.includes("Fotty home") && body.includes("Watch-first match day");
  assert(hasClassicHomeSeo || hasV2HomeSeo, "/ missing home SEO title (classic or v2)");
  assert(body.includes("data-server-feed") === false, "/ should not render SSR feed flash");
  console.log(`ok home seo (${hasV2HomeSeo ? "v2" : "classic"})`);
}

async function checkV2ShellSignals() {
  const checks = [
    { path: "/", needles: ['data-shell="v2"', "Live now"] },
    { path: "/search", needles: ["Discover", "data-shell=\"v2\""] },
    { path: "/schedule", needles: ["Schedule", "data-shell=\"v2\""] },
    { path: "/more", needles: ["More", "data-shell=\"v2\""] },
  ];

  for (const check of checks) {
    const { body } = await fetchText(check.path);
    for (const needle of check.needles) {
      assert(body.includes(needle), `${check.path} missing ${needle}`);
    }
    console.log(`ok v2 shell ${check.path}`);
  }

  const legacy = await fetch(new URL("/next/search", baseURL), { redirect: "manual" });
  assert([307, 308].includes(legacy.status), `/next/search should redirect, got ${legacy.status}`);
  const location = legacy.headers.get("location") || "";
  assert(location.endsWith("/search"), `/next/search should redirect to /search, got ${location}`);
  console.log("ok legacy /next redirect");
}

async function checkBillingRoutes() {
  const confirm = await fetch(new URL("/api/billing/confirm?plan=plus&email=smoke@fotty.app", baseURL));
  assert(confirm.status === 200, `/api/billing/confirm expected 200, got ${confirm.status}`);

  const checkout = await fetch(new URL("/api/billing/checkout-url?plan=plus&email=smoke@fotty.app", baseURL));
  assert([404, 200].includes(checkout.status), `/api/billing/checkout-url unexpected ${checkout.status}`);
  console.log("ok billing routes");
}

async function checkRoutes() {
  for (const route of routes) {
    const { response, body } = await fetchText(route);
    assert(response.ok, `${route} returned ${response.status}`);
    assert(body.length > 1000, `${route} returned a suspiciously small body`);
    console.log(`ok route ${route} ${response.status} ${body.length} bytes`);
  }
}

async function checkSupportFunnel() {
  const { body } = await fetchText("/support");
  for (const text of ["Match-Day Supporter", "One-Time Boost", "Collab with Fotty"]) {
    assert(body.includes(text), `/support missing ${text}`);
  }
  assert(body.includes("Selected path"), "/support missing selected checkout panel");
  assert(body.includes("Save pledge"), "/support missing local pledge fallback");
  assert(body.includes("Send details"), "/support missing feedback handoff action");
  console.log("ok support funnel");
}

async function checkSubscriptionPage() {
  const { body } = await fetchText("/subscribe");
  for (const text of ["Plans in TTD", "Fotty Plus", "Match-Day Pass", "Fotty Builder", "Fotty Collab", "Same Plus access on every paid plan"]) {
    assert(body.includes(text), `/subscribe missing ${text}`);
  }
  assert(
    body.includes("Pay & activate on WhatsApp") ||
      body.includes("Get access on WhatsApp") ||
      body.includes("WhatsApp") ||
      body.includes("NEXT_PUBLIC_FOTTY_WHATSAPP_NUMBER"),
    "/subscribe missing WhatsApp payment CTA"
  );
  console.log("ok subscription page");
}

async function checkCollabProduct() {
  const { body } = await fetchText("/collab");
  for (const text of ["Fotty Collab", "Watch Party Kit", "Community Hub", "Save collab inquiry"]) {
    assert(body.includes(text), `/collab missing ${text}`);
  }
  console.log("ok collab product");
}

async function checkMVPSignals() {
  const response = await fetch(new URL("/mvp", baseURL), {
    headers: { Accept: "text/html" },
    redirect: "manual",
  });

  if (response.status === 307 || response.status === 308) {
    console.log("ok mvp redirects in production");
    return;
  }

  const body = await response.text();
  assert(response.ok, `/mvp returned ${response.status}`);
  for (const text of ["MVP Signals", "Tracked teams", "Collab inquiries", "Support pledges", "MVP production switches", "PocketBase Write Targets"]) {
    assert(body.includes(text), `/mvp missing ${text}`);
  }
  console.log("ok mvp signals");
}

async function checkPocketBaseSyncRoutes() {
  const auth = await fetch(new URL("/api/pocketbase/auth", baseURL), {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ email: "", password: "" }),
  });
  assert(auth.status === 400, `/api/pocketbase/auth expected 400 for missing credentials, got ${auth.status}`);

  const sync = await fetch(new URL("/api/pocketbase/sync", baseURL), {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ type: "teamFollow", data: { name: "Arsenal" } }),
  });
  assert(sync.status === 401, `/api/pocketbase/sync expected 401 without PB session, got ${sync.status}`);
  console.log("ok pocketbase sync routes");
}

async function checkTeamAlerts() {
  const { body } = await fetchText("/teams");
  const hasClassic = body.includes("Team Alerts") && body.includes("Track team");
  const hasV2 = body.includes("Your teams") || body.includes("Track clubs");
  assert(hasClassic || hasV2, "/teams missing team tracking UI");
  console.log(`ok team alerts (${hasV2 ? "v2" : "classic"})`);
}

async function checkLoginCopy() {
  const { body } = await fetchText("/login");
  assert(body.includes("Fotty account"), "/login missing account copy");
  assert(!body.includes("signInWithPassword"), "/login leaked implementation detail");
  assert(!body.includes("accepts any password"), "/login leaked stub-auth copy");
  console.log("ok login copy");
}

async function checkFootballFirstFeed() {
  const { response, body } = await fetchText("/api/matches");
  assert(response.ok, `/api/matches returned ${response.status}`);
  const matches = JSON.parse(body);
  assert(Array.isArray(matches), "/api/matches did not return an array");
  assert(matches.length > 0, "/api/matches returned no matches");
  assert(matches[0]?.sport === "Football", `first match should be Football, got ${matches[0]?.sport || "unknown"}`);
  console.log(`ok football first feed ${matches.length} matches`);
}

async function checkPocketBaseBadges() {
  const { response, body } = await fetchText("/api/matches");
  assert(response.ok, `/api/matches returned ${response.status}`);
  const matches = JSON.parse(body);
  const pbBadgeMatch = matches.find((match) =>
    [match.teams?.home?.badge, match.teams?.away?.badge].some((badge) =>
      typeof badge === "string" && badge.includes("media.api-sports.io")
    )
  );

  assert(pbBadgeMatch, "/api/matches did not include any PocketBase team badge URLs");
  console.log("ok pocketbase team badges");
}

async function checkServerBoot() {
  const response = await fetch(new URL("/api/matches", baseURL));
  const data = await response.json();
  assert(response.ok, `/api/matches boot check expected 200, got ${response.status}`);
  assert(Array.isArray(data), "/api/matches boot check did not return an array");
  console.log(`ok server boot /api/matches (${data.length} items)`);
}

async function main() {
  console.log(`smoke target ${baseURL}`);
  await checkServerBoot();
  await checkRoutes();
  await checkHomeSeo();
  await checkV2ShellSignals();
  await checkFootballStandings();
  await checkBillingRoutes();
  await checkSupportFunnel();
  await checkSubscriptionPage();
  await checkCollabProduct();
  await checkMVPSignals();
  await checkTeamAlerts();
  await checkLoginCopy();
  await checkFootballFirstFeed();
  await checkPocketBaseBadges();
  await checkPocketBaseSyncRoutes();
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
