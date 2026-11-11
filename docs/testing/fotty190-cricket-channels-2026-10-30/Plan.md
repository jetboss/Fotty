# Independent cricket channels and truthful availability

Owner request30October: fix the real discovery failure, especially the missing
Willow Cricket and Fox Cricket channels. Jet iPad is the approved repair/test
target. Phone, FPL, multi-stream, Git publication, backend activation and
TestFlight remain excluded.

## Confirmed failure and repair

The former channel rows depended on the failed primary catalog. The optional
adapters searched only dated two-team fixtures, so their independent channel
catalog could not restore Willow or Fox. CS3.1.3 explicitly advertises NETWORKS
search and lists both main channels. This is channel availability metadata, not
decoded playback or a statement about which match is on air.

Native190 keeps two stable, undated channel identities in the browsing projection
without adding fixtures, teams, source IDs or LIVE claims. CS opt-in permits a
separate exact-channel search, matching same-ID metadata and current descriptors
through the existing transport/admission guards. Two literal regional main-Willow
IDs may yield different deliveries; Willow2 and CrFOX501 are not main-channel
aliases. Fixture matching still requires its own date/team/competition authority.

The common fixture preflight owner now covers the existing native screens with
the unchanged bounded schedule. Readiness may survive the60/90second refresh gap
without reusing an expired URL; new empty/failure, opt-out, identity/day change
and clock regression revoke it. Test phase presentation no longer calls lunch,
stumps or missing active-play evidence LIVE. A conflicting provider Day3 row is
not rewritten as official Day4. Optional Test ordinal/end facts are additive;
the backend portion remains undeployed and cannot be claimed active here.

## Gates

- Frozen332 native input files;44 protected FPL/multi hashes unchanged.
- Focused current-source Catalyst tests and signed iOS Release build.
- Strict app/widget signatures, Jet profile membership, installed version190.
- In-place install preserves source flags and private FPL/profile preferences.
- Normal Cricket channel Watch/picker, actual advancing native video, pause/
  resume and native controls on Jet. Descriptor-only results do not pass playback.
- Clean owned build/private outputs and temporary keep-awake process at exit.

Results are recorded separately after execution. No result is implied by this plan.
