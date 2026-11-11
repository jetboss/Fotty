# Fotty 2.0.1 build 174 Flix source qualification

24 October 2026. Signed normal Release build installed, read back and launched
on Jet iPad. No phone, FPL, multi-stream, backend, Git publication or TestFlight
changes. **Flix remains OFF and unqualified. No additional working delivery was
accepted in this gate.**

## Source integration

`FlixStreamsAddonClient` owns a fixed public Flix-Streams Free contract:
`org.flixstreams.free` 1.0.0, the `essential-live-events` TV catalog and advertised
soccer/cricket genres. Search currently ignores its query, while pagination works.
The adapter completes pages 0, 40 and 80 before selecting an exact dated match;
a later malformed or conflicting sibling can veto an earlier hit.

The optional sixth bundled module is off by default. It is wired into the
existing match-source resolution path, including eligible official fixtures,
with opaque FS1–FS6 labels and a hashed `fs_` delivery key. Existing switches and
source families retain their identities. No separate fixture catalog or player
screen is introduced. Normal FS picker/control acceptance remains open.

Only the reviewed same-origin HTTPS port 443 HLS channel route and one opaque signed
query value are admitted. Headers must be empty, with no new native origin or
playlist profile. The existing guarded relay retains TLS, public-destination,
redirect, header-scope and resource restrictions. External links, DRM, torrents,
new header contracts and arbitrary manifests are excluded. A different wrapper
does not establish independent upstream supply or content rights.

## Confirmed parser repair

The first real-device lookup skipped before media because the initial parser
rejected the presence of `behaviorHints`. Fresh catalog evidence also contained
a single video entry. Synthetic fixtures had omitted that real envelope.

The repaired decoder validates the exact default-video hint against the catalog
ID, the single video's ID against that same target, and its explicit UTC release
time against the four-line description's UTC date/time. Positions remain inert
integer metadata. Different targets, dates, extra authority fields, malformed
types or duplicate videos fail closed and remain conflict evidence. Network
fixtures now reproduce the observed envelope rather than assuming it away.

## Local verification

The final focused Catalyst gate reports **306 passed, zero failed and three
intentional physical-only skips**, with no runtime warnings. It includes Flix
matching/schema/transport fixtures, source-family and redaction integration,
settings preservation, shared identity, CS/AS/LS regressions, discovery, relay
and optional official-fixture lookup. This is not the full application suite.

The final flagged physical test helper compiles. Native source membership,
version coherence, provider identity vectors, protected-file hashes, signed
normal Release build and strict/deep signature verification pass. No simulator
or concurrent heavy build was used.

## Actual Jet iPad results

The independent [ESPN Serie A scoreboard](https://site.api.espn.com/apis/site/v2/sports/soccer/ita.1/scoreboard?dates=20261024)
dated Lazio–Parma at 24 October 18:45 UTC and reported second-half play at
19:50 UTC (47 minutes) and 20:00 UTC (57 minutes). This was a general-football
compatibility candidate, not a Premier League or Champions League substitute.

| Check | Recorded result |
| --- | --- |
| Initial adapter | Skipped before media because the real metadata envelope was rejected; repaired as above. |
| FS1 after repair | Zero decoded frames. Initial upstream manifest GET returned HTTP 502; one retained failed relay request, zero completed. Canary elapsed 3.059 seconds. |
| First FS2 attempt | Failed during source discovery after 7.578 seconds, before relay/video; precise underlying request stage was not retained by that helper revision. |
| Fresh FS2 retry | Zero decoded frames. Initial upstream manifest GET returned HTTP 502; one retained failed relay request, zero completed. Canary elapsed 16.762 seconds. |

Separate bounded Mac probes earlier obtained valid master/media-playlist shapes;
a later fresh comparative lookup timed out. Those observations do not supersede
the failed physical gate. No 90-second decoded hold, correct-programme, normal FS
picker, controls, audio, fullscreen or PiP pass is claimed.

Read-only relay review found no reconstruction of the selected remote URL:
encoded channel separators and signed query values remain intact. Known HLS GETs
still suppress Range/conditional headers. The retained failures are upstream
HTTP 502 responses, not evidence of a local trust-policy rejection. No speculative
User-Agent, timeout, codec, buffer or security exception was introduced.

## Remaining coverage and another candidate

- Premier League live decoding remains open. Fresh ESPN fixtures list the next
  PL window on 25 October from 14:00 UTC, 10:00 Tobago time. Refresh descriptors
  and pin the real current fixture before another one-off test; do not reuse
  the expired Lazio canary or qualify a finished PL channel as current playback.
- Champions League remains open. The current teamless competition banner is
  rejected. [UEFA's next matchday is 3–4 November](https://www.uefa.com/uefachampionsleague/news/02a8-2174c9e9019d-f909a77bd77a-1000--2026-27-champions-league-all-the-league-phase-fixtures-and-results/).
- Cricket remains pending a supported existing fixture, independently verified
  live status and an exact source descriptor. The observed Iinyathi–Warriors
  row is not a current-programme or normal-picker pass. CSA access returned403;
  cached search scores or an unresolved display timezone do not close that gate.
- [StreamViX](https://github.com/qwertyuiop8899/StreamViX) is another direct-HLS
  lead, not an enabled source. Its sampled Chelsea–Tottenham metadata said
  14:30 UTC while the authoritative kickoff was 16:30 UTC; it must not be joined
  by guessing away the conflict. The sampled Champions League search returned
  African club fixtures, not European UCL proof, and cricket search was empty.
  No media or device qualification was performed for it.

## Preservation and artifact receipt

All 52 protected FPL/multi-stream file hashes, all four private FPL values and
all five existing source switches compare unchanged after installation. FS has
no saved enablement and therefore remains off. No UI-test runner was installed
by this gate. The signed normal app replaced the unit-test host. Device Hub's
preview connection later timed out; installation/readback/launch are CLI-verified,
not a claimed visual Home or FS-picker acceptance pass.

Pre-build receipt: 1,144 inputs; history-free temporary commit
`f7ccee9470ee8bbe5e620cf912a3f8ca3cca2628`; source SHA256
`ddac87debd450e7471bca0bdb623ebb1135e80954c0eca2507f8b2e69fc5c487`;
bundle SHA256 `e1eeb2d1eec9a1657c82adbb4f604ffd0d121df6b666d55f3d1157111789552b`.
Signed normal executable SHA256:
`28c893dd25134116664b2015e4166b6dcb4d42ddaff7752b456d8a67aa8e84ae`.
Frozen-source comparison passes before closeout documentation edits.

The owned 1.45 GiB gate, including both configurations' build products, result
bundles, copied preferences, diagnostics and temporary source bundle, was removed;
its keep-awake helper and supervisor are also gone. Absence was verified. Final
disk readback is 15 GiB free; unrelated artifacts/caches were preserved. Device
screen sharing was stopped without removing or changing the installed app.
