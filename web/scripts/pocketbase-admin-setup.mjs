#!/usr/bin/env node
/**
 * One-time PocketBase setup for Fotty admin dashboard.
 *
 * Usage (from web/):
 *   PB_ADMIN_EMAIL=you@example.com PB_ADMIN_PASSWORD=secret npm run pb:admin-setup
 *
 * Or paste an API token from PocketBase /_/ → Settings → API keys:
 *   POCKETBASE_ADMIN_TOKEN=your_token npm run pb:admin-setup
 *
 * - Writes POCKETBASE_ADMIN_TOKEN into .env.local
 * - Adds optional `users` fields: entitlement, plan, entitlementExpiresAt, adminNote
 */

import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(__dirname, "..");
const envLocalPath = path.join(webRoot, ".env.local");

const baseURL = (process.env.POCKETBASE_BASE_URL || process.env.NEXT_PUBLIC_POCKETBASE_URL || "https://fotty-api.pixel-invoice.com").replace(/\/$/, "");
const identity = process.env.PB_ADMIN_EMAIL?.trim() || "";
const password = process.env.PB_ADMIN_PASSWORD || "";

const OPTIONAL_FIELD_NAMES = ["entitlement", "plan", "entitlementExpiresAt", "adminNote"];

function collectionSchemaEntries(collection) {
  return collection.schema || collection.fields || [];
}

function schemaTextField(name) {
  return {
    system: false,
    id: `fotty_${name}`,
    name,
    type: "text",
    required: false,
    presentable: false,
    unique: false,
    options: { min: null, max: null, pattern: "" },
  };
}

function authHeader(token) {
  return token.startsWith("Bearer ") ? token : `Bearer ${token}`;
}

async function resolveAdminToken() {
  const fromEnv = process.env.POCKETBASE_ADMIN_TOKEN?.trim();
  if (fromEnv) {
    console.log("ok using POCKETBASE_ADMIN_TOKEN from environment");
    return fromEnv;
  }

  if (!identity || !password) {
    console.error("Set PB_ADMIN_EMAIL + PB_ADMIN_PASSWORD, or POCKETBASE_ADMIN_TOKEN.");
    console.error("Token: PocketBase /_/ → Settings → API keys → create key.");
    process.exit(1);
  }

  const authResponse = await fetch(`${baseURL}/api/admins/auth-with-password`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ identity, password }),
  });

  if (!authResponse.ok) {
    const err = await authResponse.text();
    console.error(`Admin auth failed (${authResponse.status}): ${err}`);
    console.error("Reset the superuser password in /_/ or paste an API key:");
    console.error("  POCKETBASE_ADMIN_TOKEN=... npm run pb:admin-setup");
    process.exit(1);
  }

  const auth = await authResponse.json();
  const token = auth.token;
  if (!token) {
    console.error("No token in auth response.");
    process.exit(1);
  }

  console.log("ok admin authenticated");
  return token;
}

async function ensureUsersFields(token) {
  const headers = {
    Accept: "application/json",
    Authorization: authHeader(token),
  };

  const collectionsResponse = await fetch(`${baseURL}/api/collections?filter=${encodeURIComponent('name="users"')}`, {
    headers,
  });

  if (!collectionsResponse.ok) {
    console.warn(`Could not list users collection (${collectionsResponse.status}). Add fields manually in PocketBase UI.`);
    return;
  }

  const collectionsPayload = await collectionsResponse.json();
  let collection = collectionsPayload.items?.[0];
  if (!collection?.id) {
    console.warn("users collection not found — create it in PocketBase first.");
    return;
  }

  const detailResponse = await fetch(`${baseURL}/api/collections/${collection.id}`, { headers });
  if (detailResponse.ok) {
    collection = await detailResponse.json();
  }

  const existingNames = new Set(collectionSchemaEntries(collection).map((field) => field.name));
  const missingNames = OPTIONAL_FIELD_NAMES.filter((name) => !existingNames.has(name));

  if (missingNames.length === 0) {
    console.log("ok users collection already has entitlement fields");
    return;
  }

  const nextSchema = [...collectionSchemaEntries(collection), ...missingNames.map((name) => schemaTextField(name))];
  const body = collection.schema ? { schema: nextSchema } : { fields: nextSchema };
  const patchResponse = await fetch(`${baseURL}/api/collections/${collection.id}`, {
    method: "PATCH",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!patchResponse.ok) {
    const err = await patchResponse.text();
    console.warn(`Could not patch collection (${patchResponse.status}): ${err}`);
    console.warn("Add these text fields manually on users:", missingNames.join(", "));
    return;
  }

  console.log(`ok added fields: ${missingNames.join(", ")}`);
}

async function main() {
  console.log(`PocketBase: ${baseURL}`);

  const token = await resolveAdminToken();
  await patchEnvLocal("POCKETBASE_ADMIN_TOKEN", token);
  console.log("ok wrote POCKETBASE_ADMIN_TOKEN to .env.local");
  await ensureUsersFields(token);
}

async function patchEnvLocal(key, value) {
  let content = "";
  try {
    content = await readFile(envLocalPath, "utf8");
  } catch {
    content = "";
  }

  const line = `${key}=${value}`;
  const pattern = new RegExp(`^${key}=.*$`, "m");

  if (pattern.test(content)) {
    content = content.replace(pattern, line);
  } else {
    content = `${content.trimEnd()}\n\n# PocketBase admin API (auto setup)\n${line}\n`;
  }

  await writeFile(envLocalPath, content, "utf8");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
