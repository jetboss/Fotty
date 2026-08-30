import { expect, test } from "@playwright/test";

test("stream token rejects spoofed email without session", async ({ request }) => {
  const response = await request.get("/api/stream/token", {
    headers: {
      "X-Fotty-Email": "paid-spoof@example.com",
    },
  });
  expect([401, 403]).toContain(response.status());
});
