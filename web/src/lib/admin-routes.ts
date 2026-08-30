/** Fotty operator dashboard — standalone UI without main app navigation. */
export function isAdminRoute(pathname: string) {
  return pathname === "/admin" || pathname.startsWith("/admin/");
}
