import React, { useMemo } from "react";
import {
  DataComponent,
  Filters,
  MetricCard,
  SortableItem,
  SortableRegion,
  useDataApp,
} from "../../data-app-public.jsx";
import "./dashboard.css";

const number = (value) => new Intl.NumberFormat().format(Number(value) || 0);

const invitationLabels = {
  NOT_INVITED: "Not invited",
  INVITED: "Invited",
  ACCEPTED: "Accepted",
  INSTALLED: "Installed",
  REVOKED: "Revoked",
};

function buildSummary(rows) {
  return rows.reduce((summary, row) => {
    summary.sessions7d += Number(row.sessions7d) || 0;
    summary.sessions30d += Number(row.sessions30d) || 0;
    summary.crashes30d += Number(row.crashes30d) || 0;
    summary.feedback30d += Number(row.feedback30d) || 0;
    if ((Number(row.sessions7d) || 0) > 0) summary.recentlyActive += 1;
    if (row.participation === "No recent sessions") summary.noRecentSessions += 1;
    if (row.participation === "Not installed") summary.notInstalled += 1;
    return summary;
  }, {
    testers: rows.length,
    recentlyActive: 0,
    noRecentSessions: 0,
    notInstalled: 0,
    sessions7d: 0,
    sessions30d: 0,
    crashes30d: 0,
    feedback30d: 0,
  });
}

function ParticipationBreakdown({ rows }) {
  const order = ["Recently active", "Used this month", "No recent sessions", "Not installed", "Revoked"];
  const counts = new Map(order.map((label) => [label, 0]));
  rows.forEach((row) => counts.set(row.participation, (counts.get(row.participation) || 0) + 1));
  const maximum = Math.max(1, ...counts.values());

  return <div className="tfu-participation-breakdown" data-reviewed-rows>
    {order.filter((label) => counts.get(label)).map((label) => <div className="tfu-participation-row" key={label}>
      <div className="tfu-participation-label">
        <span>{label}</span>
        <strong>{number(counts.get(label))}</strong>
      </div>
      <div className="tfu-participation-track" aria-hidden="true">
        <span data-participation={label} style={{ width: `${Math.max(8, (counts.get(label) / maximum) * 100)}%` }} />
      </div>
    </div>)}
  </div>;
}

function TesterRosterTable({ rows }) {
  return <div className="tfu-roster-scroll" data-reviewed-rows>
    <table className="tfu-roster-table">
      <caption className="tfu-visually-hidden">TestFlight tester participation</caption>
      <thead>
        <tr>
          <th scope="col">Tester</th>
          <th scope="col">Participation</th>
          <th scope="col">TestFlight status</th>
          <th scope="col" className="tfu-numeric">Sessions · 7d</th>
          <th scope="col" className="tfu-numeric">Sessions · 30d</th>
          <th scope="col" className="tfu-numeric">Crashes · 30d</th>
          <th scope="col" className="tfu-numeric">Feedback · 30d</th>
          <th scope="col">Build</th>
          <th scope="col">Latest device</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((row) => <tr key={row.testerId}>
          <td>
            <div className="tfu-tester-identity">
              <strong>{row.name || "Unnamed tester"}</strong>
              <span>{row.email || "No email reported"}</span>
            </div>
          </td>
          <td><span className="tfu-status-pill" data-participation={row.participation}>{row.participation}</span></td>
          <td>{row.invitationLabel}</td>
          <td className="tfu-numeric">{number(row.sessions7d)}</td>
          <td className="tfu-numeric">{number(row.sessions30d)}</td>
          <td className="tfu-numeric">{number(row.crashes30d)}</td>
          <td className="tfu-numeric">{number(row.feedback30d)}</td>
          <td>{row.build}</td>
          <td>{row.device}</td>
        </tr>)}
      </tbody>
    </table>
  </div>;
}

export function DashboardContent() {
  const shell = useDataApp();
  const { snapshot, queries, filters, setFilter, reviewedRows, visible } = shell;
  const rows = reviewedRows("tester_usage", ["testerId"]);
  const summary = useMemo(() => buildSummary(rows), [rows]);
  const sourceRows = rows;
  const generatedAt = snapshot.generatedAt
    ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(snapshot.generatedAt))
    : "Not refreshed";
  const isFixture = snapshot.status === "fixture";

  const tableRows = rows.map((row) => ({
    ...row,
    invitationLabel: invitationLabels[row.invitationState] ?? row.invitationState ?? "Unknown",
    device: [row.model, row.osVersion].filter(Boolean).join(" · ") || "Not reported",
    build: row.appBuildVersion || "—",
  }));

  const layoutRows = [
    { id: "testflight:metrics", kind: "metrics", items: ["active-testers", "sessions-seven-days", "no-recent-sessions", "not-installed"] },
    { id: "testflight:participation", items: ["participation-breakdown"] },
    { id: "testflight:roster", items: ["tester-roster"] },
  ];

  return <div className="tfu-dashboard">
    <div className="tfu-intro">
      <div>
        <p className="tfu-eyebrow">Owner-only TestFlight view</p>
        <h2>Who is actually testing Fotty?</h2>
        <p>Use Apple’s session counts to find active testers, quiet installs, and invitations that never reached an install.</p>
      </div>
      <div className="tfu-freshness">
        <span>Last checked</span>
        <strong>{generatedAt}</strong>
      </div>
    </div>

    <div className={isFixture ? "tfu-source-state tfu-source-preview" : "tfu-source-state tfu-source-live"} role="status">
      <strong>{isFixture ? "Preview data" : "Connected to App Store Connect"}</strong>
      <span>{isFixture
        ? "This view uses invented testers. Connect a private App Store Connect API key to load the real roster."
        : "The dashboard was generated from Apple’s tester roster and 7-day / 30-day beta usage metrics."}</span>
    </div>

    <Filters sticky filters={snapshot.filters} queries={queries} values={filters} onChange={setFilter}
      clearLabel="Reset filters" ariaLabel="Tester participation filters" />

    <SortableRegion id="testflight:dashboard" variant="canvas" columns={12} spacing="standard"
      rows={layoutRows} label="TestFlight participation blocks" authoredRevision={1}>
      {visible("active-testers") && <SortableItem id="active-testers" label="Active testers" kind="metric" span={3} minSpan={2}>
        <MetricCard id="active-testers" queryId="tester_usage" title="Active testers · 7d"
          description="Testers with at least one recorded session in the trailing seven days."
          value={`${number(summary.recentlyActive)} / ${number(summary.testers)}`}
          displayRows={[summary]} sourceRows={sourceRows} />
      </SortableItem>}

      {visible("sessions-seven-days") && <SortableItem id="sessions-seven-days" label="Sessions" kind="metric" span={3} minSpan={2}>
        <MetricCard id="sessions-seven-days" queryId="tester_usage" title="Sessions · 7d"
          description="Total TestFlight sessions recorded by Apple across the selected testers."
          value={number(summary.sessions7d)} displayRows={[summary]} sourceRows={sourceRows} />
      </SortableItem>}

      {visible("no-recent-sessions") && <SortableItem id="no-recent-sessions" label="No recent sessions" kind="metric" span={3} minSpan={2}>
        <MetricCard id="no-recent-sessions" queryId="tester_usage" title="Installed, no use · 30d"
          description="Installed testers with zero recorded sessions in the trailing 30 days."
          value={number(summary.noRecentSessions)} displayRows={[summary]} sourceRows={sourceRows} />
      </SortableItem>}

      {visible("not-installed") && <SortableItem id="not-installed" label="Not installed" kind="metric" span={3} minSpan={2}>
        <MetricCard id="not-installed" queryId="tester_usage" title="Not installed"
          description="Invited or accepted testers whose current App Store Connect state is not Installed."
          value={number(summary.notInstalled)} displayRows={[summary]} sourceRows={sourceRows} />
      </SortableItem>}

      {visible("participation-breakdown") && <SortableItem id="participation-breakdown" label="Participation mix" kind="chart" span={12} minSpan={4}>
        <DataComponent variant="card" id="participation-breakdown" queryId="tester_usage" kind="custom"
          title="Participation mix" description="Mutually exclusive operational categories derived from invitation state and Apple’s 7-day / 30-day session totals."
          displayRows={rows} sourceRows={sourceRows}>
          {rows.length ? <ParticipationBreakdown rows={rows} /> : <p className="tfu-empty-copy">No testers match these filters.</p>}
        </DataComponent>
      </SortableItem>}

      {visible("tester-roster") && <SortableItem id="tester-roster" label="Tester roster" kind="table" span={12} minSpan={6}>
        <DataComponent variant="card" id="tester-roster" queryId="tester_usage" kind="table"
          title="Tester roster" description="All selected testers are shown together. Device and build are Apple’s latest reported values when available."
          displayRows={tableRows} sourceRows={sourceRows}>
          {tableRows.length ? <TesterRosterTable rows={tableRows} /> : <p className="tfu-empty-copy">No testers match these filters.</p>}
        </DataComponent>
      </SortableItem>}
    </SortableRegion>

    <aside className="tfu-measurement-limit" aria-label="Measurement limit">
      <strong>What this can’t tell you</strong>
      <p>A TestFlight session confirms recorded app use. It does not show which Fotty screen was used, whether a stream played successfully, or how long a session lasted.</p>
      <span>30-day totals: {number(summary.sessions30d)} sessions · {number(summary.crashes30d)} crashes · {number(summary.feedback30d)} feedback items</span>
    </aside>
  </div>;
}
