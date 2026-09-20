# pi-setup

A minimal, **measured** configuration for [pi](https://pi.dev) on macOS: no plan-mode extension, no todo extension, no MCP, no subagent package.
The main principle behind this setup is keep pi away from bloating and still add features that we use in other harnesses.
This discipline comes from markdown files that cost nothing until they are used instead of extensions which consume context and self created extensions which need maintenance.

Total cost: **+1488 tokens per request** over a bare pi (and +1046 if you use the lean `AGENTS.md`).
For comparison, the popular `pi-lens` extension alone costs +5402 and `pi-subagents` costs +5918 —
see the [full measurements](DESIGN.md#results-pi-0851-linux-aarch64).

Everything here was verified on pi 0.85.1 by dumping what pi actually assembles into the prompt
(no API key needed). The reasoning behind each choice, the numbers, and why several well-known
extensions were deliberately left out are in **[DESIGN.md](DESIGN.md)**.

## What you get

| Decision                   | Implementation                                                           | Prompt cost                 |
| -------------------------- | ------------------------------------------------------------------------ | --------------------------- |
| Plan before editing        | `prompts/plan.md` → `/plan` (a template, not a mode)                     | **0**                       |
| Track multi-step work      | a `TODO.md` convention in `AGENTS.md`                                    | part of the ~930-token file |
| Web search + fetch         | `skills/brave-search/` — dependency-free script, Keychain-backed API key | ~110 (skill description)    |
| Delegate to subagents      | herdr's own skill, installed **user-invoked** as `/skill:herdr`          | **0**                       |
| Constrain writes + network | `npm:pi-sandbox@0.6.8` (pinned) + `sandbox.json`                         | **0**                       |
| A stable default posture   | `settings.json`, `env.example.sh`                                        | 0                           |

`pi-sandbox` is free in context terms because it wraps `bash` and gates the file tools rather than
registering new tools. It is a guardrail, not a security boundary — read
[what it is and is not](DESIGN.md#security-model-what-the-sandbox-is-and-is-not) before you rely on it.

## Requirements

| Need             | Why                                      | Check                                        |
| ---------------- | ---------------------------------------- | -------------------------------------------- |
| macOS with zsh   | what this is written for                 | `echo $SHELL`                                |
| Node ≥ 22.19     | pi 0.85.1 requires it                    | `node --version`                             |
| pi on `PATH`     | the thing being configured               | `pi --version`                               |
| **ripgrep**      | `pi-sandbox` refuses to start without it | `rg --version` → else `brew install ripgrep` |
| python3          | used by the installer and the tooling    | `python3 --version`                          |
| herdr (optional) | only for the multi-pane workflow         | `herdr --version`                            |

## Install

```bash
git clone <this-repo> ~/pi-setup
cd ~/pi-setup
./install.sh --dry-run     # see exactly what would change
./install.sh               # apply
```

`install.sh` is idempotent. It **merges** `settings.json` — your `defaultModel`, `defaultProvider`
and anything else already there survive; this repo's keys win only where they overlap — and it backs
up every file it replaces with a `.bak.<timestamp>` suffix. Re-run it after installing herdr to pick
up the release-matched skill.
`--dry-run` shows every step without writing anything (and verifies nothing, because nothing was written);
`--help` prints usage. It exits non-zero if a file fails to install or a config ends up invalid, so it is safe to chain in a setup script.

Then, once:

1. **Authenticate.** Run `pi`, then `/login` (or export your provider's API key). In an interactive
   session, save your startup defaults with `/model` + `Ctrl+S` and `/thinking` + `Ctrl+S`.
2. **Brave key.** `pbpaste | node ~/.pi/agent/skills/brave-search/brave.mjs setkey`
   This stores the token in the macOS Keychain. `keyinfo` tells you where the key came from without
   printing it.
3. **herdr (optional).** `brew install herdr`, then Herdr → Settings → Integrations → install the Pi
   integration, and check `herdr integration status`. Re-run `./install.sh` afterwards so the skill
   matches your herdr release.
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
/sandbox                              # effective sandbox config; the footer shows a lock while active
/plan  add a health endpoint          # expands the template, explores read-only
/skill:brave-search  pi 0.85 changelog
/skill:herdr                          # only meaningful inside herdr
/todos                                # NOT available - there is no todo extension, by design
```

`./test-bundle.sh` installs the whole configuration into a scratch agent directory, runs pi against it,
and **asserts** what loaded: that the base files exist, that the sandbox extension, `/plan` and both
skills registered, that each `AGENTS.md` variant reached the prompt, and that the Brave script fails
cleanly on a bad token. It prints the measured token cost, exits non-zero if any check fails, and
takes `--keep` to preserve the scratch directory for inspection. It needs `pi`, `node` and `python3`
on `PATH`, and no API key — the prompt is dumped before the auth check.

## Files

```
install.sh                 idempotent installer: merges settings, copies files, pins the sandbox
config/settings.json       merged into ~/.pi/agent/settings.json
config/sandbox.json        ~/.pi/agent/sandbox.json
config/AGENTS.md           ~/.pi/agent/AGENTS.md   - full working agreement (~930 tokens)
config/AGENTS.lean.md      same rules, less prose  (~370 tokens) - swap in if you want the tokens back
prompts/plan.md            ~/.pi/agent/prompts/plan.md - /plan template
skills/brave-search/       ~/.pi/agent/skills/brave-search/ - SKILL.md + brave.mjs
templates/project/         copy into each repo: AGENTS.md + TODO.md
tools/                     context audit harness: measure what a package costs before adopting it
lib/                       helper scripts used by install.sh
env.example.sh             optional shell exports, all commented out
test-bundle.sh             end-to-end self-test of this configuration
DESIGN.md                  why each choice was made, the measurements, and what was left out
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

## Sandbox behaviour (what you will actually feel)

| Situation                                                                   | What happens                                                                                 |
| --------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Edit files inside the project, run tests, `npm install`                     | allowed silently                                                                             |
| Write outside the project and `/tmp`                                        | **prompts**: abort (a 10-minute timeout aborts) / allow for session / project / all projects |
| Read outside the project (e.g. `~/Documents`)                               | prompts; granting adds the path to `allowRead`                                               |
| Write `.env`, `*.pem`, `*.key`, `~/.ssh`, `~/.aws`, `~/.pi/agent/auth.json` | **hard block**, never prompted                                                               |
| Reach a domain not on the allow list                                        | prompts per domain; pre-approve with `/sandbox-allow domain <host>`                          |
| A domain that is both allowed and denied                                    | stays blocked - check both files                                                             |

Check the sandbox.json for the network policy and update the allowlist as per the project needs.
`sandboxUserShell: true` means the `!` commands you type yourself are sandboxed too; `Alt+S` toggles
the sandbox for the session; `/sandbox` shows the effective config.

Add a host deliberately by editing `~/.pi/agent/sandbox.json` and restarting pi — grants saved to disk are not broadcast to running sessions.

**This is not real isolation.** It raises the cost of an accident and limits what a prompt-injected
instruction can reach; it is not a container, not a VM, and not protection against a malicious
extension (extensions run with your full user permissions). If you need a boundary, run pi itself in a
container or VM — see
[the security section of DESIGN.md](DESIGN.md#security-model-what-the-sandbox-is-and-is-not).

## Measured context cost

`tokens = ceil(chars/4)`, pi's own estimator; "prefill" is the system prompt plus **active** tool
schemas, re-sent on every request. Full table in [DESIGN.md](DESIGN.md#results-pi-0851-linux-aarch64).

| Configuration                                              | Prefill  | vs bare pi |
| ---------------------------------------------------------- | -------- | ---------- |
| bare pi (4 tools)                                          | 1316     | —          |
| **this setup**, full `AGENTS.md`                           | **2804** | +1488      |
| **this setup**, `AGENTS.lean.md`                           | **2362** | +1046      |
| + `@plannotator/pi-extension` (plan mode with a hard gate) | ~3285    | +1969      |
| + `pi-lens`, lean (6-tool allowlist)                       | ~4224    | +2908      |
| + `@juicesharp/rpiv-todo`                                  | ~3708    | +2392      |
| + `pi-web-access`                                          | ~5703    | +4387      |
| + `pi-subagents`                                           | ~8722    | +7406      |
| + `pi-lens` at full width (17 tools)                       | ~8206    | +6890      |
| "install everything"                                       | 16735    | +15419     |

The one line item worth understanding is the global `AGENTS.md`: it is ~930 tokens of the ~1488, so
`AGENTS.lean.md` exists as a drop-in if you want most of those back.

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
rm ~/.pi/agent/AGENTS.md ~/.pi/agent/sandbox.json
rm ~/.pi/agent/prompts/plan.md
rm -rf ~/.pi/agent/skills/brave-search ~/.pi/agent/skills/herdr
pi remove npm:pi-sandbox
ls ~/.pi/agent/*.bak.* ~/.pi/agent/settings.json.orig   # closest backups of what was replaced
```

Removing pi itself (`npm uninstall -g @earendil-works/pi-coding-agent`) leaves `~/.pi/agent/` in
place — settings, credentials and sessions are yours to keep.

## Improvements needed

- **Real isolation instead of a guardrail** — a container/VM path for pi itself (workspace-only mount,
  no host `~/.pi/agent`, no capabilities), plus Docker Sandboxes / Gondolin / OpenShell. `pi-sandbox`
  limits blast radius; it is not a security boundary.
- **Offload the Brave script to a managed skill** — `npx skills add badlogic/pi-skills@brave-search -g -y`
  installs the upstream skill (by pi's author) into `~/.agents/skills/`, which pi reads, tracked in
  `~/.agents/.skill-lock.json`, and drops our vendored `brave.mjs`. During research this worked, at the
  cost of an `npm install` in the skill dir and `BRAVE_API_KEY` instead of the Keychain lookup.
- **Add external memory** - to capture project details and quirks beyond what the Agents.md and TODO.md captures.
- **Tune `config/sandbox.json` from real usage** — after a few weeks fold the approvals you actually
  granted into deliberate defaults, drop the one-off mistakes, and revisit `allowLocalBinding`,
  `permissionPromptTimeoutSeconds` (600 s is generous) and what belongs in `denyWrite`.
- **Pin the managed skill** — `npx skills add` tracks `main`; add a version check once upstream tags a
  release.

## License

MIT — see [LICENSE](LICENSE).
