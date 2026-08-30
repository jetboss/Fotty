# Fotty Agent Start Here

Before architecture work, broad refactors, release planning, or unfamiliar debugging, read:

- `agent/AGENT-START.md`
- `docs/notebooklm/Project-Memory.md`
- `docs/notebooklm/Decisions-Log.md`
- `docs/notebooklm/Architecture-Map.md`

Use the private brain when the question depends on project history:

```bash
./tools/agent-start.sh "Describe the task"
```

After significant work, update durable memory and run:

```bash
./tools/agent-finish.sh "Describe what changed"
```

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
