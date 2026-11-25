# Fotty 2.0.0 (57) - private late Score808 discovery candidate

Date: 2026-09-04. Status: **installed only on Jet iPad for private testing**.

**Follow-up correction:** The owner still reports unavailable playback. The
donor mapping and stub-rejection assurances below were not established by the
tests. The owner's actual Score808 page plays through a different host in the
browser; it is not blocked by the same certificate. Treat this as a historical
build record, not an accepted fix. See the superseding
`docs/audit/Fotty-Score808-Route-Investigation-2026-09-04.md` before further work.

## Finding

Score808 is a late-availability source: its player commonly appears only about
20 minutes before kickoff. During Ipswich Town–Liverpool, all three current
event feeds exposed `admin`, `delta`, `echo` and `golf` but omitted the `hotel`
descriptor Fotty uses for Score808. The Watch resolver also trusted a cached
event as soon as any source existed, so it did not deliberately look again for
the late family.

A bounded diagnostic found that the event's `admin` identity produced a full
Score808 `hotel` player page of approximately 641 KB; the other event identities
returned only small stubs. Certificate verification was disabled only in that
read-only diagnostic to inspect the already-known expired provider host. Fotty
itself retains normal Apple trust enforcement.

## Correction

- From 30 minutes before a football kickoff through three hours after, an
  explicit Watch action refreshes event metadata even when the cached event
  already has another source.
- If the refreshed catalog still omits `hotel`, Fotty derives exactly one
  `hotel` descriptor from a non-empty `admin` identity and probes stream 1.
- The inferred route passes through the same HTTP/player-page validation as
  every ordinary candidate. It is exposed only if it is a real player; an
  empty stub, invalid page or trust error remains unavailable.
- No Score808 player-page traffic runs in the background. Fotty does not probe
  earlier than the bounded window, duplicate an explicit `hotel`, guess from
  `delta`/`echo`/`golf`, bypass ATS or retain a failed option.
- Home and Matchday keep their existing 90-second visible-screen catalog
  refresh. The extra lookup occurs only for the user's explicit Watch action.

## Verification and installation

- Regressions cover the 30-minute lead, football-only scope, three-hour tail,
  explicit-provider deduplication and refusal to guess without `admin`.
- The complete simulator-free Catalyst unit and generic iOS Release gate passed.
  Generated catalog checks and the current three-feed provider identity audit
  passed again during the signed-device run.
- Build 57 was allocated because private build 56 was already installed before
  this source changed. The signed build installed in place only on the
  authorized Jet iPad (`34E32922-73D6-54EA-8556-7904EE7804BD`). CoreDevice
  independently reports Fotty Sports Hub 2.0.0 (57), and both the normal app
  and Live Activity extension appear in the post-launch process list.
- No simulator ran. Owned DerivedData was removed and the data volume retains
  approximately 34 GiB free.

## Distribution and acceptance boundary

This is a private iPad pre-test. TestFlight remains build 55; no iPhone, other
iPad, tester group, Worker, web service, App Store submission or Git publication
changed. The current `embed.st` certificate is still expired, so the corrected
discovery path cannot make that provider route safe to play today. Once the
provider renews the certificate, build 57 can discover and validate the late
Score808 route without another rebuild. Exact physical proof of that successful
late route remains open until a valid provider transport is available.
