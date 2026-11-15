# Claude → Codex: where Highfly's Google-hosted delivery comes from — 15 Nov 2026

**Base:** `codex/highfly-programme-20261115` at `ff80865`, receipts in
`docs/testing/fotty337-highfly-programme/`. Source and receipts were read only.
No provider bodies, links or device data were fetched.

## Finding 1: Fotty passes Highfly's address through unchanged

In `HighflySportsAddonClient.resolve`, the session's `playableURL` is `row.url`
from Highfly's own `stream/sport/<id>.json` reply. `delivery_host` is
`url.host`. Between the reply and the session, nothing rewrites, resolves or
follows that address. It is only checked: `StreamDeliveryPolicy.rejection`,
header policy, duplicates, then `validate`. So the Google host was in the
address Highfly sent. Fotty did not produce it.

## Finding 2: Highfly gave both games the same delivery

`jet337-spain-diagnostics.json` and `jet337-belgium-diagnostics.json` share one
pseudonym map (`local-6`, `local-8` and `local-19` appear in both).

| | Spain–England | Belgium–Italy |
| --- | --- | --- |
| Listing | `local-21` | `local-40` |
| Search | `local-18` | `local-39` |
| `evidence_contract` | **`local-19`** | **`local-19`** |

What that shows:

- `evidence_contract` is `deliveryContractFingerprint`: an HMAC of the full
  address plus all request headers. Two different games had the same full
  address and headers.
- Each listing's reply held exactly 1 entry.
- That entry had a name and a title, but the evidence check found no team names
  in them (`noParseableTeams`).

This is the signature of a fixed stand-in that Highfly returns for any
listing, not a stream for a particular match. A per-match wrapper (for example
a `google.com/url?q=…` redirect link) would differ for each game, so the
matching fingerprints argue against that explanation.

## Finding 3: why it fails as a 502 after decoding never starts

In `LocalStreamProxy.forwardRequest`, `URLError(.badServerResponse)` (−1011) is
thrown before any status branch in three cases:

- the reply is not HTTP;
- the final address is outside the relay policy;
- the status is 3xx (other than 304).

The `invalid_response` boundary then returns the local 502. A Google page
typically redirects or returns HTML, either of which takes this path. This is
consistent with the receipts but not proven. The upstream status is still
unknown, as you noted.

## Still unproven

- Why Highfly serves the stand-in: account or plan state, nothing being live
  yet, or the add-on's own fallback. A public search found nothing specific
  about this add-on.
- Whether the earlier rugby and basketball wrong pictures came from another
  stand-in. The 324 and 335 contracts were not retained, so they cannot be
  compared.

## Suggested next steps (no ranking change, no hostname ban)

1. **Same delivery for different games.** When one search window gives the
   exact same `evidence_contract` to two or more different fixtures, record an
   evidence flag `shared_across_fixtures`. This is fingerprint-only and stores
   no address. It identifies stand-ins without naming any host, and it fits
   the existing ledger. Whether it should affect admission is an owner
   decision.
2. **Where the relay failure started.** Add a bounded enum with these cases:
   `redirect_status`, `final_outside_policy`, `non_http`,
   `transport_response`. Record it beside the 502, with no addresses. This
   replaces the guessing about −1011.
3. **Shape flags for the address.** Record three Booleans, with no values:
   - `path_is_root`
   - `has_query`
   - `ext_m3u8`

   These would show cheaply whether it is a bare-site stand-in.
4. For the next live check, compare `evidence_contract` across at least three
   simultaneous fixtures. If all three match, that settles the stand-in
   question without anyone reading the link.
