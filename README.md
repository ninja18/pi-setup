# pi-setup

A minimal, **measured** configuration for [pi](https://pi.dev) on macOS: no plan-mode extension, no todo extension, no MCP, no subagent package.
The main principle behind this setup is keep pi away from bloating and still add features that we use in other harnesses.
This discipline comes from markdown files that cost nothing until they are used instead of extensions which consume context and self created extensions which need maintenance.

Total cost: **+1847 tokens per request** over a bare pi (+1420 with the lean `AGENTS.md`). For
comparison, the popular `pi-lens` extension alone costs +5402 and `pi-subagents` costs +5918 — see the
[full measurements](DESIGN.md#results-pi-0851).

Everything here was verified on pi 0.85.1 by dumping what pi actually assembles into the prompt
(no API key needed). The reasoning behind each choice, the numbers, and why several well-known
extensions were deliberately left out are in **[DESIGN.md](DESIGN.md)**.

## What you get

| Decision                 | Implementation                                                           | Prompt cost                 |
| ------------------------ | ------------------------------------------------------------------------ | --------------------------- |
| Plan before editing      | `prompts/plan.md` → `/plan` (a template, not a mode)                     | **0**                       |
| Track multi-step work    | a `TODO.md` convention in `AGENTS.md`                                    | part of the ~910-token file |
| Web search + fetch       | `skills/brave-search/` — dependency-free script, Keychain-backed API key | ~110 (skill description)    |
| Delegate to subagents    | `skills/herdr-subagents/` — disposable or persistent Pi children         | **0** (user-invoked)      |
| A stable default posture | `settings.json`, `env.example.sh`                                        | 0                           |

`/skill:herdr-subagents` defaults to an ephemeral child (`pi --no-session`, capture the answer,
close its pane). Its persistent mode creates a named Pi session and deliberately leaves the pane open
for follow-up prompts in that branch.

**No sandbox layer, deliberately.** `pi-sandbox` was removed after an evaluation: its failures cannot
be fixed in its config (a process started in one tool call cannot be signalled from a later one;
`ps`, `top`, `sudo` and GUI apps do not run; the domain "allowlist" turned out not to be enforced),
and making real toolchains work inside it needs per-toolchain workarounds such as
`CLANG_MODULE_CACHE_PATH` for anything that builds Objective-C modules. It was a guardrail rather than
a boundary, and it cost more in day-to-day troubleshooting than it returned in safety. [Why](DESIGN.md#no-sandbox-layer-why-pi-sandbox-is-not-included),
with the full catalogue in [SANDBOX-FAILURE-MODES.md](SANDBOX-FAILURE-MODES.md).

## Requirements

| Need             | Why                                   | Check               |
| ---------------- | ------------------------------------- | ------------------- |
| macOS with zsh   | what this is written for              | `echo $SHELL`       |
| Node ≥ 22.19     | pi 0.85.1 requires it                 | `node --version`    |
| pi on `PATH`     | the thing being configured            | `pi --version`      |
| python3          | used by the installer and the tooling | `python3 --version` |
| herdr (optional) | only for the multi-pane workflow      | `herdr --version`   |

## Install

```bash
git clone <this-repo> ~/pi-setup
cd ~/pi-setup
./install.sh --dry-run        # see exactly what would change
./install.sh                  # apply the full setup

# Existing setup: install or update only the custom subagent skill
./install.sh --skill-only --dry-run
./install.sh --skill-only
```

Nothing sandbox-related is installed, because this setup does not ship a sandbox layer — see
[why](DESIGN.md#no-sandbox-layer-why-pi-sandbox-is-not-included).

`install.sh` is idempotent. It skips identical files, **merges** `settings.json` — your
`defaultModel`, `defaultProvider` and anything else already there survive; this repo's keys win only
where they overlap — and backs up a file only when its content will change. `--skill-only` touches
only `~/.pi/agent/skills/herdr-subagents/SKILL.md`, so it is the safe path for an already-configured
Pi installation.
`--dry-run` shows every step without writing anything (and verifies nothing, because nothing was written);
`--help` prints usage. It exits non-zero if a file fails to install or a config ends up invalid, so it is safe to chain in a setup script.

Then, once:

1. **Authenticate.** Run `pi`, then `/login` (or export your provider's API key). In an interactive
   session, save your startup defaults with `/model` + `Ctrl+S` and `/thinking` + `Ctrl+S`.
2. **Brave key.** `pbpaste | node ~/.pi/agent/skills/brave-search/brave.mjs setkey`
   This stores the token in the macOS Keychain. `keyinfo` tells you where the key came from without
   printing it.
3. **Herdr (for subagents).** `brew install herdr`, then Herdr → Settings → Integrations → install
   the Pi integration, and check `herdr integration status`. Start Pi inside Herdr before invoking
   `/skill:herdr-subagents`.
4. **Optional shell environment.** `echo 'source ~/pi-setup/env.example.sh' >> ~/.zshrc` — that file
   ships with everything commented out.

## Per project

```bash
cp ~/pi-setup/templates/project/AGENTS.md  /path/to/project/AGENTS.md
cp ~/pi-setup/templates/project/TODO.md    /path/to/project/TODO.md
```

Fill in the Commands section first — that is the one part the agent cannot infer. The project
`AGENTS.md` layers on top of the global one; specific rules win in practice. Approve the project-trust
prompt once per repo (or run `/trust`).

## Verify it works

```bash
pi                                    # inside a project
/plan  add a health endpoint          # expands the template, explores read-only
/skill:brave-search  pi 0.85 changelog
/skill:herdr-subagents  run an ephemeral research child
/skill:herdr-subagents  keep a persistent child for follow-ups
/todos                                # NOT available - there is no todo extension, by design
```

`./test-bundle.sh` installs the configuration into a scratch agent directory, runs pi against it, and
**asserts** what loaded: the base files, that `/plan`, `brave-search`, and `herdr-subagents`
registered, that both skills have the intended invocation mode, that each `AGENTS.md` variant reached
the prompt, that **no** sandbox layer is present, and that the Brave script fails cleanly on a bad
token. It also runs `--skill-only` twice against an existing scratch setup to prove the mode changes
no unrelated file and creates no backup on an identical second run. It prints the measured token cost
for both `AGENTS.md` shapes, exits non-zero if any check fails, and takes `--keep` to preserve the
scratch directory for inspection. It needs `pi`, `node` and `python3` on `PATH`, and no API key — the
prompt is dumped before the auth check.

## Files

```
install.sh                 idempotent installer: settings.json, AGENTS.md, /plan and the skills
config/settings.json       merged into ~/.pi/agent/settings.json
config/AGENTS.md           ~/.pi/agent/AGENTS.md   - full working agreement
config/AGENTS.lean.md      same rules, less prose  - swap in if you want the tokens back
prompts/plan.md            ~/.pi/agent/prompts/plan.md - /plan template
skills/brave-search/       ~/.pi/agent/skills/brave-search/ - SKILL.md + brave.mjs
skills/herdr-subagents/     ~/.pi/agent/skills/herdr-subagents/ - two-mode Herdr orchestration
templates/project/         copy into each repo: AGENTS.md + TODO.md
tools/                     context audit harness: measure what a package costs before adopting it
lib/                       helper scripts used by install.sh
env.example.sh             optional shell exports, all commented out
test-bundle.sh             end-to-end self-test of this configuration
DESIGN.md                  why each choice was made, the measurements, and what was left out
SANDBOX-FAILURE-MODES.md   the pi-sandbox evaluation: every denial, with rules and reproductions
```

## What settings.json sets, and why

| Key                      | Value               | Why                                                                |
| ------------------------ | ------------------- | ------------------------------------------------------------------ |
| `enableInstallTelemetry` | `false`             | no install/update ping, no provider attribution headers            |
| `showCacheMissNotices`   | `true`              | surfaces prompt-cache misses, compaction events, provider recovery |
| `defaultProjectTrust`    | `"ask"`             | keeps the project-local settings/extensions gate in place          |
| `compaction`             | explicit defaults   | `reserveTokens: 16384`, `keepRecentTokens: 20000`; tune per model  |
| `retry`                  | enabled, 3 attempts | a transient provider error should not end the task                 |

Environment variables are deliberately not written into `~/.zshrc`; `env.example.sh` has the
three worth knowing.

## Measured context cost

`tokens = ceil(chars/4)`, pi's own estimator; "prefill" is the system prompt plus **active** tool
schemas, re-sent on every request. Full table in [DESIGN.md](DESIGN.md#results-pi-0851).

| Configuration                                      | Prefill  | vs bare pi |
| -------------------------------------------------- | -------- | ---------- |
| bare pi (4 tools)                                  | 1316     | —          |
| **this setup**, default                            | **3163** | +1847      |
| **this setup**, `AGENTS.lean.md`                   | **2736** | +1420      |
| **if you add an extension instead**                |          |            |
| `@plannotator/pi-extension` (plan mode, hard gate) | —        | +481       |
| `@juicesharp/rpiv-todo`                            | —        | +904       |
| `pi-lens` (6-tool allowlist)                       | —        | +1420      |
| `pi-web-access`                                    | —        | +2899      |
| `pi-lens` at full width (17 tools)                 | —        | +5402      |
| `pi-subagents`                                     | —        | +5918      |
| "install everything" (all of the above)            | 16735    | +15419     |

The extension rows are deltas over bare pi, measured in [DESIGN.md](DESIGN.md#results-pi-0851);
add one to whichever baseline above you are actually running.

`pi-herdsman@0.14.2` was tested separately on its compatible Pi 0.87.1 range: prefill increased from
**3129 to 5472**, or **+2343 / +74.9%**. It cleaned up completed child panes but intentionally kept
child Pi sessions. For basic orchestration, that resident cost is why this repo uses the zero-cost
`herdr-subagents` skill instead. See the [full evaluation](DESIGN.md#pi-herdsman-evaluation-pi-0871).

The two line items worth understanding: the global `AGENTS.md` is ~910 tokens of the ~1847, and the
project `AGENTS.md` template is now the second largest at ~512 (it was ~267 before it was made
language-agnostic). `AGENTS.lean.md` exists as a drop-in if you want most of the first one back.

## Other good practices

### git checkpointing — pi has no undo

pi edits your files directly; its own documentation tells you to use git or another checkpointing
workflow. Concretely:

1. **Checkpoint before delegating.** Start from a clean tree, or make a commit:
   `git commit --allow-empty -m "checkpoint: before agent run"`.
2. **Read the diff, not the summary.** `git diff --stat` first, then `git diff`. Reviewing the actual
   patch is the only reliable check.
3. **Roll back in the right order.** `git restore .` (discard unstaged edits) →
   `git reset --hard <checkpoint>` (discard commits) → `git clean -fd` (remove files it created;
   `-n` first for a dry run).
4. **Commit small.** Rollback granularity is only as fine as your commits.
5. **Isolate bigger jobs** in a throwaway branch or worktree:
   `git worktree add ../proj-agent -b agent/task`.
6. **`/tree`, `/fork` and `/clone` rewind the conversation, not the files.** Useful when the context
   went bad; never a substitute for git.
7. **Ignore agent scratch** (`.pi/`, generated artefacts) so it never lands in a commit, and stage
   selectively with `git add -p`.

## Rollback

```bash
rm ~/.pi/agent/AGENTS.md
rm ~/.pi/agent/prompts/plan.md
rm -rf ~/.pi/agent/skills/brave-search ~/.pi/agent/skills/herdr-subagents
ls ~/.pi/agent/*.bak.* ~/.pi/agent/settings.json.orig   # closest backups of what was replaced
```

## Improvements needed

- **Add a guardrail layer for pi** — there is none today: pi's `bash`, `write` and `edit` tools run
  with your full user rights. `pi-sandbox` was tried and rejected (see
  [DESIGN.md](DESIGN.md#no-sandbox-layer-why-pi-sandbox-is-not-included)): its failures cannot be
  configured away, and real toolchains need per-toolchain workarounds. Candidates to measure next:
  `@gotgenes/pi-permission-system` (in-process read/write/command gating — no OS layer, so none of the
  `sandbox-exec` failure classes), a container/VM path where the whole of pi runs with a
  workspace-only mount and no host `~/.pi/agent`, and the managed options (Docker Sandboxes,
  Gondolin, OpenShell). Until then the guardrail is process: git checkpoints, small diffs, review.
- **Offload the Brave script to a managed skill** — `npx skills add badlogic/pi-skills@brave-search -g -y`
  installs the upstream skill (by pi's author) into `~/.agents/skills/`, which pi reads, tracked in
  `~/.agents/.skill-lock.json`, and drops our vendored `brave.mjs`. During research this worked, at the
  cost of an `npm install` in the skill dir and `BRAVE_API_KEY` instead of the Keychain lookup.
- **Add external memory** - to capture project details and quirks beyond what the Agents.md and TODO.md captures.
- **Pin the managed skill** — `npx skills add` tracks `main`; add a version check once upstream tags a
  release.

## License

MIT — see [LICENSE](LICENSE).
