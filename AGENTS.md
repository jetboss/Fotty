# Fotty Agent Start Here

Before architecture work, broad refactors, release planning, or unfamiliar debugging, read the short entry points:

- `agent/AGENT-START.md`
- `docs/notebooklm/Current-State.md`

Then retrieve only the relevant topic sections from Project-Memory.md,
Decisions-Log.md and Architecture-Map.md. These contain dated history, not a
mandatory full-corpus reading assignment. Verify claims against current code
and, for deployments or live behavior, current external evidence.

Use the private brain when the question depends on project history:

```bash
./tools/agent-start.sh "Describe the task"
```

After significant implementation, prepend the durable decision and update the
current summary only if its state changed, then run:

```bash
./tools/agent-finish.sh "Describe what changed"
```

Read-only discussion/audits stop at their findings; do not regenerate memory or
publish anything merely to finish an audit. Source-only changes stop after the
relevant local checks. Device installs and shared TestFlight releases are separate
requested gates; preserve `docs/notebooklm/Workflow.md` release requirements.

Once the owner has approved a fix and a named owner-device testing gate, continue
the known repairs, local checks, rebuild/install and testing within that scope
without requesting the same approval again. The owner clarified this on
2026-10-03. Ask only for a material new decision, changed target or genuinely
missing access; an unlock request is not approval. This does not authorize
shared TestFlight releases, Git publication, backend deployment, spending,
privacy/security changes or destructive user-data operations.

## UI and design work

Before a UI audit, redesign or meaningful polish pass, read
`docs/FOTTY-UI-DESIGN-STANDARD.md` and use the `apple-ui-design` skill when available.
Follow relevant current Apple HIG guidance, preserve Fotty's badges/sport artwork,
and translate approved concepts into native acceptance criteria. Compare actual
native screens with the reference; source checks or a build are not visual proof.
Keep guidance/preview work separate from app edits and device/release authority.

For substantive native-reference handoffs and runtime responsiveness work, read
`agent/playbooks/ios-skills.md`. It routes to tested reusable workspace candidates
and existing Fotty tools; staging does not mean personal/global skill activation.
Do not run combined build/install helpers for source-only or read-only requests.

## Workstation resource limits

This project is developed on a 256 GB Mac with 8 GB RAM. Treat build products
as short-lived resources:

- Never create a new DerivedData directory for every test, configuration, build
  number, or device. Reuse one bounded directory for the active gate.
- Use a cleanup trap for temporary Xcode output and delete it after the artifact
  is installed and verified, including on failure or interruption.
- Check free disk space before and after broad Xcode work. Do not leave result
  bundles, screenshots, archives, or duplicate signed apps in `/tmp`.
- Run builds sequentially and do not use simulators on this Mac.
