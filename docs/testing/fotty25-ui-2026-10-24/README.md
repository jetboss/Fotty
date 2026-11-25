# Fotty2.5 native component studies

Source-built24October2026 with official Xcode27.0(27A266a), macOS27.0.1,
arm64 Catalyst test host, UIHostingController.drawHierarchy at1x.
Test fixture composition: `Fotty25DesignRenderTests`.

These five retained PNGs are small, inspected production-component assemblies,
not physical iPhone/iPad screenshots or a complete interactive app journey.
Names/badges/status and source choices are synthetic, nonpersistent fixtures.
The iPad example uses light appearance; phone examples use dark appearance.

- `home-phone-dark.png`:393pt width; approved content order/art hierarchy.
- `home-phone-narrow.png`:320pt width;88pt compact minimum preserves three columns
  after16pt outer insets. Long names reflow; no font scaling to force a fit.
- `home-ipad-wide.png`:1180pt width; actual production1.55:1 overview Layout with
  real spotlight/schedule/sport-grid components. No invented match fills space.
- `settings-phone-narrow.png`:320pt width; real native Settings components,
  long value moves below label. This is not the complete Settings root.
- `single-player-phone.png`:393pt identity/source-state components, not decoded
  video, complete player chrome or actual picker/fullscreen/PiP interaction.

All21 temporary compositions were reviewed; only these five are retained.
Do not promote these studies into the original pixel-baseline manifest or call
the installed175 devices updated/qualified. Full receipt:
`../../audit/Fotty-2.5-UI-Completion-2026-10-24.md`.

25October: these unchanged images are inventoried as `historical-unbound`
component studies in `../../design/fotty25-ui-reference-contract.json`. Their
newly checked file hashes preserve artifact integrity, not retroactive build
provenance. See `../../design/UI-Reference-Workflow.md` for actual per-screen
coverage gaps and the source/reference evidence check. No new capture or approval.
