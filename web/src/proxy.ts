import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { isAdminRoute } from "@/lib/admin-routes";
import { verifyAdminSessionToken, adminCookieName } from "@/lib/server/admin-auth";
import {
  isV2Enabled,
  v2CanonicalFromNextPath,
  v2HomePath,
} from "@/lib/v2/preview";

function isAdminLoginPath(pathname: string) {
  return pathname === "/admin/login" || pathname === "/api/admin/login";
}

function requiresAdminAuth(pathname: string) {
  return pathname === "/admin" || (pathname.startsWith("/admin/") && !isAdminLoginPath(pathname));
}

function withBareShell(response: NextResponse) {
  response.headers.set("x-fotty-bare-shell", "1");
  return response;
}

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (isV2Enabled()) {
    if (pathname === "/next" || pathname === "/next/") {
      return NextResponse.redirect(new URL(v2HomePath(), request.url));
    }
    const canonicalFromNext = v2CanonicalFromNextPath(pathname);
    if (canonicalFromNext) {
      const suffix = request.nextUrl.search;
      return NextResponse.redirect(new URL(`${canonicalFromNext}${suffix}`, request.url));
    }
  }

  if (!isV2Enabled()) {
    if (pathname === "/mvp" || pathname.startsWith("/mvp/")) {
      if (process.env.NODE_ENV === "production") {
        return NextResponse.redirect(new URL("/", request.url));
      }
    }

    if (pathname === "/next" || pathname.startsWith("/next/")) {
      if (process.env.NODE_ENV === "production") {
        return NextResponse.redirect(new URL("/", request.url));
      }
      if (process.env.FOTTY_PREVIEW_ROUTES_ENABLED !== "true") {
        return NextResponse.redirect(new URL("/", request.url));
      }
    }
  }

  const adminUi = isAdminRoute(pathname) && !pathname.startsWith("/api/admin");

  if (requiresAdminAuth(pathname)) {
    const token = request.cookies.get(adminCookieName())?.value;
    if (!(await verifyAdminSessionToken(token))) {
      const login = new URL("/admin/login", request.url);
      login.searchParams.set("next", pathname);
      return withBareShell(NextResponse.redirect(login));
    }
  }

  if (pathname.startsWith("/api/admin") && !isAdminLoginPath(pathname)) {
    const token = request.cookies.get(adminCookieName())?.value;
    if (!(await verifyAdminSessionToken(token))) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
  }

  if (adminUi) {
    return withBareShell(NextResponse.next());
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    "/",
    "/schedule",
    "/schedule/:path*",
    "/settings",
    "/settings/:path*",
    "/teams",
    "/teams/:path*",
    "/tables",
    "/tables/:path*",
    "/search",
    "/search/:path*",
    "/favorites",
    "/favorites/:path*",
    "/more",
    "/more/:path*",
    "/mvp",
    "/mvp/:path*",
    "/next",
    "/next/:path*",
    "/admin",
    "/admin/:path*",
    "/api/admin",
    "/api/admin/:path*",
  ],
};
