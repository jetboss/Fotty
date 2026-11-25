# Security review: CS streams rejected for `http://` Referer/Origin

9 November 2026, about 10:40 UTC. This is a read-only review requested by the owner after the Jet live-cricket check. No code has been changed and nothing has been deployed. Every probe printed only shapes, status codes and hashes; no stream URL, token or query value was saved.

## Correction to the earlier report

The first report said the rejected CS streams used a new, unreviewed `/api` route. **That was wrong.** All three CS deliveries use `/api/manifest.m3u8` on `nuviosports.xyz`, which is the already reviewed wrapper route (`LocalStreamProxyPolicy.isCommunitySportsManifestRoute`).

## What CS returned for Pakistan v Sri Lanka (`nuvio_sports_live`, `_source` = `ak47`)

| Entry | Nested `url` target | Child playlist and segments | Fotty today | Should Fotty admit it? |
|---|---|---|---|---|
| 0 | none (donation `externalUrl`) | n/a | rejected | no |
| 1, "T SPORTS HD", 720p | HTTPS on a public hostname, port 443 | The master points to one same-origin `/api/manifest.m3u8` child. The child is a live media playlist (sequence 245024, 9 s target, 6 segments) whose `.ts` segments are HTTPS on a public third-party host. The child URI was unchanged across three reloads. A segment returned 206 `video/MP2T` with valid sync bytes and no redirect, with or without the extra headers. | rejected | **yes, under the contract below** |
| 2, 3 | `http://` to a raw IP address | Segments are `http://` to a raw IP | rejected | **no**. The nested-target rule rejects them correctly, and the relay would refuse every segment. |

## Why entry 1 is rejected

`CommunitySportsAddonClient.admittedRequestHeaders` requires the advertised Referer and Origin values to pass `LocalStreamProxyPolicy.allowsDestination`, which means HTTPS. CS advertises both as **`http://` page addresses**: `http://www.fawanews.sc/` and `http://www.fawanews.sc`. Every other gate passes:

- the reviewed route and same origin;
- the header count, canonical names and ASCII length limits;
- exact equality between the Referer/Origin headers and the URL's `referer`/`origin` parameters;
- Origin and Referer sharing a host;
- the nested target being HTTPS on port 443 with a public host and an `.m3u8` path.

Referer and Origin are **header values, not destinations**. Fotty never connects to them. The relay already handles the same case by silently dropping an `http://` Referer or Origin from upstream requests (`LocalStreamProxyPolicy.remoteRequest`) rather than refusing the stream.

The wrapper and its child playlist both return 200 with a valid playlist when sent **User-Agent only**. The route already carries the same provenance in its own URL parameters.

## Recommended contract

Admit a CS delivery with `http` provenance only when **all** of these hold:

1. The manifest is the reviewed `https://nuviosports.xyz/manifest.json`, and the delivery is exactly the reviewed `/api/manifest` or `/api/manifest.m3u8` route on that origin.
2. The single nested `url` target passes `allowsDestination` unchanged: HTTPS, port 443, a public host, and an `.m3u8` path. Entries 2 and 3 therefore stay rejected.
3. The Referer and Origin are `http://`, on a public DNS hostname (not an IP literal or local suffix), on the default port, with no credentials, query or fragment. The Origin has no path. Both share a host, and each equals its URL parameter exactly.
4. **Fotty does not send those two headers.** Only the validated User-Agent is kept, which matches what the relay already does.
5. Everything else is unchanged:
   - the relay's per-request destination, redirect, public-address, byte-limit and loopback rules;
   - the 8443 origin exception;
   - the playlist-profile host list;
   - wrapped-target validation;
   - identity matching, and the rejection of every `http` or IP-literal media destination.

**Network and privacy effect.** Fotty contacts no new host and sends no new header. The only change is that it accepts one more already-reviewed same-origin route whose provenance is `http://`.

**Expected gain.** One additional CS 720p choice for this match today, and for any other CS listing that uses `http` provenance. The label "T SPORTS HD" is a Bangladeshi channel. **Programme correctness is not established.** A device decode with a screenshot must confirm that it shows this match before it counts as a backup.

## Tests the change would add

- **Admitted**: `http` provenance on the reviewed route, with matching parameters and an HTTPS public target. The resulting session headers contain User-Agent only.
- **Rejected**:
  - `http` provenance with an IP-literal host;
  - a non-default port;
  - credentials, query or fragment in the provenance;
  - Origin with a path;
  - a header that differs from its parameter;
  - Referer and Origin on different hosts;
  - `http` provenance on any other route;
  - an `http` or IP nested target, which remains rejected even with valid provenance.
- **Relay unchanged**: an `http` Referer is still never forwarded upstream.
