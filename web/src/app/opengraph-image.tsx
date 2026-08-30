import { ImageResponse } from "next/og";

export const dynamic = "force-static";

export const alt = "FOTTY — Live Sports & Match Day";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpenGraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: "72px 80px",
          backgroundColor: "#0a0d14",
          backgroundImage:
            "radial-gradient(ellipse at top left, rgba(224,31,71,0.28) 0%, rgba(10,13,20,0) 55%), radial-gradient(ellipse at bottom right, rgba(46,57,79,0.5) 0%, rgba(10,13,20,0) 60%)",
          fontFamily: "system-ui, sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 20 }}>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              width: 84,
              height: 84,
              borderRadius: 24,
              backgroundColor: "#e01f47",
              color: "#ffffff",
              fontSize: 34,
              fontWeight: 900,
              letterSpacing: 2,
            }}
          >
            FO
          </div>
          <div
            style={{
              color: "#ffffff",
              fontSize: 44,
              fontWeight: 900,
              letterSpacing: 10,
            }}
          >
            FOTTY
          </div>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
          <div
            style={{
              color: "#ffffff",
              fontSize: 88,
              fontWeight: 900,
              lineHeight: 1.05,
              letterSpacing: -2,
            }}
          >
            Stop searching.
          </div>
          <div
            style={{
              color: "#e01f47",
              fontSize: 88,
              fontWeight: 900,
              lineHeight: 1.05,
              letterSpacing: -2,
            }}
          >
            Start watching.
          </div>
          <div
            style={{
              marginTop: 14,
              color: "#a6a6a6",
              fontSize: 32,
              fontWeight: 600,
            }}
          >
            Live fixtures, feeds, and match-day tools in one sports hub.
          </div>
        </div>
      </div>
    ),
    size
  );
}
