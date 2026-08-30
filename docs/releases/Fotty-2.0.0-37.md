# Fotty 2.0.0 (37) — iPad diagnostic checkpoint

Status: historical iPad-only checkpoint, superseded by build 38; not uploaded.
TestFlight remains 2.0.0 (35). The owner explicitly requested iPad testing.

- Inherits build 36's playback control fixes and approved Home/cricket changes.
- Restores team badges/equipment icons and introduces optional light appearance.
- Final build-37 source passed 148 unit tests, one optional HLS soak skipped,
  zero runtime warnings, normal/Review Safe generic-iOS builds and normal signed
  Debug. App and extension are 2.0.0 (37); strict signature verification passed.
- Installed app version was independently checked through CoreDevice. Physical
  light Home and Settings were captured and inspected. This is not touch testing.
- Executable SHA-256 at install:
  `9acdf0e3a7900d517edefa15c4525585ebe15f3ea2b798aa38173d8e260b60fb`.

The physical review and owner feedback exposed the poor appearance-picker layout
and missing baseball fallback data. Source candidate 38 corrects these and removes
Engineering from normal Settings. It is not yet installed; the owner asked to
discuss equal sport-tile sizes and using more of the iPad width before further
layout changes. See the appearance audit for current evidence and remaining work.

No simulator, physical UI-test helper, TestFlight upload, tester change, paid API
or Git publication. Temporary diagnostic appearance overrides must be removed by
returning the normal app to an ordinary argument-free launch before handoff.
That restore completed and build 37 survived a 20-second foreground process hold.
The single 1.1 GB owned build/test/capture directory was removed; disk returned to
40 GiB free. Only small source, test and audit records remain.
