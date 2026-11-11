import { createSign } from "node:crypto";

const API_ORIGIN = "https://api.appstoreconnect.apple.com";
const MAX_PAGES = 100;

function encodeBase64Url(value) {
  return Buffer.from(value).toString("base64url");
}

export function createAppStoreConnectToken({ issuerId, keyId, privateKey, now = Math.floor(Date.now() / 1000) }) {
  if (!issuerId || !keyId || !privateKey) {
    throw new Error("Issuer ID, key ID, and private key are required.");
  }
  const header = encodeBase64Url(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" }));
  const payload = encodeBase64Url(JSON.stringify({ iss: issuerId, iat: now, exp: now + 10 * 60, aud: "appstoreconnect-v1" }));
  const signingInput = `${header}.${payload}`;
  const signer = createSign("SHA256");
  signer.update(signingInput);
  signer.end();
  const signature = signer.sign({ key: privateKey, dsaEncoding: "ieee-p1363" });
  return `${signingInput}.${signature.toString("base64url")}`;
}

function allowedApiUrl(value) {
  const url = new URL(value, API_ORIGIN);
  if (url.origin !== API_ORIGIN || !url.pathname.startsWith("/v1/")) {
    throw new Error("App Store Connect returned an unexpected pagination URL.");
  }
  return url;
}

async function responseError(response) {
  try {
    const body = await response.json();
    const error = body?.errors?.[0];
    return [response.status, error?.code, error?.title].filter(Boolean).join(" · ");
  } catch {
    return String(response.status);
  }
}

export async function fetchAllPages(url, token, fetchImpl = fetch) {
  const rows = [];
  let next = allowedApiUrl(url);
  for (let page = 0; next && page < MAX_PAGES; page += 1) {
    const response = await fetchImpl(next, {
      headers: {
        Accept: "application/json",
        Authorization: `Bearer ${token}`,
      },
    });
    if (!response.ok) {
      throw new Error(`App Store Connect request failed: ${await responseError(response)}`);
    }
    const body = await response.json();
    if (!Array.isArray(body?.data)) throw new Error("App Store Connect returned an invalid data payload.");
    rows.push(...body.data);
    next = body?.links?.next ? allowedApiUrl(body.links.next) : null;
  }
  if (next) throw new Error(`App Store Connect pagination exceeded ${MAX_PAGES} pages.`);
  return rows;
}

function finiteCount(value) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : 0;
}

export function usageByTester(metricRows) {
  const metrics = new Map();
  for (const metric of metricRows ?? []) {
    const testerId = metric?.dimensions?.betaTesters?.data?.id;
    if (!testerId) continue;
    const values = (metric.dataPoints ?? []).reduce((totals, point) => ({
      sessionCount: totals.sessionCount + finiteCount(point?.values?.sessionCount),
      crashCount: totals.crashCount + finiteCount(point?.values?.crashCount),
      feedbackCount: totals.feedbackCount + finiteCount(point?.values?.feedbackCount),
    }), { sessionCount: 0, crashCount: 0, feedbackCount: 0 });
    const current = metrics.get(testerId) ?? { sessionCount: 0, crashCount: 0, feedbackCount: 0 };
    metrics.set(testerId, {
      sessionCount: current.sessionCount + values.sessionCount,
      crashCount: current.crashCount + values.crashCount,
      feedbackCount: current.feedbackCount + values.feedbackCount,
    });
  }
  return metrics;
}

export function classifyParticipation(invitationState, sessions7d, sessions30d) {
  if (invitationState === "REVOKED") return "Revoked";
  if (invitationState !== "INSTALLED") return "Not installed";
  if (finiteCount(sessions7d) > 0) return "Recently active";
  if (finiteCount(sessions30d) > 0) return "Used this month";
  return "No recent sessions";
}

function platformLabel(platform) {
  return {
    IOS: "iOS",
    MAC_OS: "macOS",
    TV_OS: "tvOS",
    WATCH_OS: "watchOS",
    VISION_OS: "visionOS",
  }[platform] ?? "Unknown";
}

export function buildTesterRows(testers, metrics7d, metrics30d) {
  const sevenDays = usageByTester(metrics7d);
  const thirtyDays = usageByTester(metrics30d);
  return (testers ?? []).map((tester) => {
    const attributes = tester?.attributes ?? {};
    const usage7d = sevenDays.get(tester.id) ?? {};
    const usage30d = thirtyDays.get(tester.id) ?? {};
    const device = Array.isArray(attributes.appDevices) ? attributes.appDevices[0] : null;
    const name = [attributes.firstName, attributes.lastName].filter(Boolean).join(" ").trim()
      || attributes.email || "Anonymous tester";
    const sessions7d = finiteCount(usage7d.sessionCount);
    const sessions30d = finiteCount(usage30d.sessionCount);
    return {
      testerId: tester.id,
      name,
      email: attributes.email ?? "Not shared",
      inviteType: attributes.inviteType ?? "UNKNOWN",
      invitationState: attributes.state ?? "UNKNOWN",
      participation: classifyParticipation(attributes.state, sessions7d, sessions30d),
      sessions7d,
      sessions30d,
      crashes30d: finiteCount(usage30d.crashCount),
      feedback30d: finiteCount(usage30d.feedbackCount),
      appBuildVersion: device?.appBuildVersion ?? null,
      model: device?.model ?? null,
      osVersion: device?.osVersion ?? null,
      platform: platformLabel(device?.platform),
    };
  }).sort((left, right) => {
    const rank = ["Recently active", "Used this month", "No recent sessions", "Not installed", "Revoked"];
    return rank.indexOf(left.participation) - rank.indexOf(right.participation)
      || right.sessions7d - left.sessions7d
      || left.name.localeCompare(right.name);
  });
}

export async function fetchTesterUsage({ appId, token, fetchImpl = fetch }) {
  if (!/^\d+$/.test(String(appId ?? ""))) throw new Error("A numeric App Store Connect app ID is required.");
  const testersUrl = new URL("/v1/betaTesters", API_ORIGIN);
  testersUrl.searchParams.set("filter[apps]", String(appId));
  testersUrl.searchParams.set("fields[betaTesters]", "firstName,lastName,email,inviteType,state,appDevices");
  testersUrl.searchParams.set("limit", "200");

  const metricUrl = (period) => {
    const url = new URL(`/v1/apps/${appId}/metrics/betaTesterUsages`, API_ORIGIN);
    url.searchParams.set("period", period);
    url.searchParams.set("groupBy", "betaTesters");
    url.searchParams.set("limit", "200");
    return url;
  };

  const [testers, metrics7d, metrics30d] = await Promise.all([
    fetchAllPages(testersUrl, token, fetchImpl),
    fetchAllPages(metricUrl("P7D"), token, fetchImpl),
    fetchAllPages(metricUrl("P30D"), token, fetchImpl),
  ]);
  return buildTesterRows(testers, metrics7d, metrics30d);
}

export function buildDashboardSnapshot({ rows, generatedAt = new Date().toISOString(), dashboardId }) {
  return {
    surface: "dashboard",
    id: dashboardId,
    title: "Fotty TestFlight participation",
    generatedAt,
    status: "live",
    buildStatus: "complete",
    filters: [
      { id: "participation", label: "Participation", field: "participation", defaultValue: "all" },
      { id: "platform", label: "Platform", field: "platform", defaultValue: "all" },
    ],
    queries: {
      tester_usage: {
        rows,
        source: {
          label: "Apple App Store Connect API — beta tester roster and usage metrics",
          executedAt: generatedAt,
          filters: ["One App Store Connect app", "Usage periods: P7D and P30D", "Metrics grouped by beta tester"],
          assumptions: [
            "Tester names and email addresses are private owner data and must not be published.",
            "App Store Connect sessions confirm recorded app use but do not identify a Fotty feature or prove successful playback.",
            "When Apple reports more than one app device, this snapshot displays the first reported device because the API supplies no device timestamp in this resource.",
          ],
          metricDefinitions: [
            { label: "Recently active", definition: "At least one App Store Connect session in the trailing seven days.", componentIds: ["active-testers", "participation-breakdown", "tester-roster"] },
            { label: "Used this month", definition: "No session in the trailing seven days and at least one session in the trailing 30 days.", componentIds: ["participation-breakdown", "tester-roster"] },
            { label: "No recent sessions", definition: "Tester state is INSTALLED and App Store Connect reports zero sessions in the trailing 30 days.", componentIds: ["no-recent-sessions", "participation-breakdown", "tester-roster"] },
            { label: "Not installed", definition: "Tester state is not INSTALLED or REVOKED. This includes pending invitations and accepted invitations without an install.", componentIds: ["not-installed", "participation-breakdown", "tester-roster"] },
          ],
        },
      },
    },
  };
}
