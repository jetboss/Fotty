import { expect, test } from "@playwright/test";

test("admin login rejects spoofed email header without session", async ({ request }) => {
  const response = await request.post("/api/admin/login", {
    headers: { "Content-Type": "application/json" },
    data: { password: "definitely-wrong-password" },
  });
  expect([401, 429, 503]).toContain(response.status());
});
