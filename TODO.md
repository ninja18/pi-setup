# TODO

Removing pi-sandbox from this repo (unfixable failures and per-toolchain workarounds; the rationale is
in DESIGN.md). Format: `- [ ]` pending, `- [~]` in progress, `- [x]` done,
`- [ ] (blocked: reason)` cannot proceed.

Nothing pending.

## Done

- [x] (2026-09-21) install.sh: dropped `--with-sandbox`, the package install, `sandbox.json`, the AGENTS.md append and every pi-sandbox check
- [x] (2026-09-21) test-bundle.sh: dropped the sandbox dry-run/install tests, the second scratch agent dir and the now-unused assertion helpers; 18/18 checks pass
- [x] (2026-09-21) deleted `config/sandbox.json`, `config/AGENTS.sandbox.md`, `config/settings.sandbox.json` and the `packages` entry in `config/settings.json`
- [x] (2026-09-21) added the herdr pane guidance to `config/AGENTS.md` and `config/AGENTS.lean.md`
- [x] (2026-09-21) dropped sandbox references from `env.example.sh`, `lib/merge-settings.py`, `skills/brave-search/`
- [x] (2026-09-21) DESIGN.md: replaced the security-model section with why pi-sandbox is not included; fixed the comparison and results tables
- [x] (2026-09-21) README.md: removed the sandbox sections, rows and commands; added a guardrail improvement item
- [x] (2026-09-21) re-measured the context cost (3163 default / 2736 lean) and updated README.md and DESIGN.md
- [x] (2026-09-21) SANDBOX-FAILURE-MODES.md: marked as removed, kept as the evidence for the decision
- [x] (2026-09-21) live setup: `pi remove npm:pi-sandbox`, `~/.pi/agent/sandbox.json` deleted, `./install.sh` re-run
- [x] (2026-09-21) checks: `bash -n` both scripts, `--dry-run` exit 0, python `ast` parse, `node --check`, `test-bundle.sh` 18/18
