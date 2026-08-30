import { isV2RoutePath } from "@/lib/v2/preview";

/** Routes that use the v2 neutral shell. */
export function isV2ShellPath(pathname: string) {
  return isV2RoutePath(pathname);
}
