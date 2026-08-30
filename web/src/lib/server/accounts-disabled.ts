import { NextResponse } from "next/server";
import { ACCOUNTS_UNAVAILABLE_MESSAGE, isAccountsEnabled } from "@/lib/accounts";

export function accountsDisabledJson() {
  return NextResponse.json(
    {
      error: ACCOUNTS_UNAVAILABLE_MESSAGE,
      code: "accounts_disabled",
    },
    { status: 410 }
  );
}

/** Return a 410 response when accounts are disabled; otherwise null. */
export function rejectIfAccountsDisabled() {
  if (isAccountsEnabled()) return null;
  return accountsDisabledJson();
}
