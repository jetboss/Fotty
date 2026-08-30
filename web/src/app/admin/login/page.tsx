import { readFile } from "node:fs/promises";
import path from "node:path";
import { AdminLoginForm, type AdminLoginDevHints } from "@/app/admin/login/AdminLoginForm";

async function loadPocketBaseCredsFromRepo() {
  const credsPath = path.join(process.cwd(), "..", "pocketbase_creds.txt");
  try {
    const text = await readFile(credsPath, "utf8");
    const email = text.match(/Email:\s*(.+)/i)?.[1]?.trim() || null;
    const password = text.match(/Password:\s*(.+)/i)?.[1]?.trim() ?? null;
    return { email, password };
  } catch {
    return { email: null, password: null };
  }
}

export default async function AdminLoginPage() {
  let devHints: AdminLoginDevHints | null = null;

  if (process.env.NODE_ENV === "development") {
    const pocketBase = await loadPocketBaseCredsFromRepo();
    const pocketBaseAdminUrl =
      process.env.NEXT_PUBLIC_POCKETBASE_URL || process.env.POCKETBASE_BASE_URL
        ? `${(process.env.NEXT_PUBLIC_POCKETBASE_URL || process.env.POCKETBASE_BASE_URL || "").replace(/\/$/, "")}/_/`
        : null;
    devHints = {
      adminPassword: process.env.FOTTY_ADMIN_PASSWORD?.trim() || null,
      pocketBaseEmail: pocketBase.email,
      pocketBasePassword: pocketBase.password,
      pocketBaseAdminUrl,
      credsFile: "pocketbase_creds.txt (repo root)",
    };
  }

  return <AdminLoginForm devHints={devHints} />;
}
