# pi-setup

A minimal, **measured** configuration for [pi](https://pi.dev) on macOS. Plans, task tracking,
search, and delegation use files or opt-in skills instead of always-on extension tools. Global
instructions still cost prompt tokens; the aim is to pay for what you actually use.

## Measured context cost

Prefill is the system prompt plus active tool schemas. Measured offline with `tools/ctx-audit.ts` on
Pi 0.86.1 in an isolated scratch directory; tokens use Pi's `ceil(chars / 4)` estimator.

| Configuration                    | Prefill   | vs bare Pi                  |
| -------------------------------- | --------- | --------------------------- |
| bare Pi (4 tools)                | 1304      | —                           |
| **this setup**, default          | **3451**  | +2147                       |
| **this setup**, `AGENTS.lean.md` | **2987**  | +1683                       |
| with common extensions installed | **16735** | +15419 (historical bare Pi) |

The last row is the ["install everything" stack](DESIGN.md#prefill-comparison): 26 active tools,
measured on Linux with Pi 0.85.1 against a **1316**-token bare baseline. It is not this setup plus
one extension, and its delta is not comparable to the current rows. This was measured in a old pi and extensions version, your measurements may differ.
Paths can shift totals slightly; task files load only when read, while global instructions are included above.

## What you get

| Decision                 | Implementation                                                           | Prompt cost              |
| ------------------------ | ------------------------------------------------------------------------ | ------------------------ |
| Plan before editing      | `prompts/plan.md` → `/plan` (a template, not a mode)                     | **0**                    |
| Project tracking         | `TODO.md` backlog convention in `AGENTS.md`                              | part of the global file  |
| Execute complex features | approved plan → scoped `.pi/tasks/<date>-<slug>-<id>.md` checklist       | part of the global file  |
| Web search + fetch       | `skills/brave-search/` — dependency-free script, Keychain-backed API key | ~110 (skill description) |
| Delegate to subagents    | `skills/herdr-subagents/` — disposable or persistent Pi children         | **0** (user-invoked)     |
| A stable default posture | `settings.json`, `env.example.sh`                                        | 0                        |

`/skill:herdr-subagents` defaults to an ephemeral child (`pi --no-session`, capture the answer,
close its pane). Its persistent mode creates a named Pi session and deliberately leaves the pane open
for follow-up prompts in that branch.

**No sandbox layer.** `pi-sandbox` blocked cross-call process signals and GUI/TCC work, required
toolchain workarounds, and did not enforce its domain allowlist in testing. This setup relies on
review and git checkpoints, **not OS isolation**. See the [decision](DESIGN.md#no-sandbox-layer-why-pi-sandbox-is-not-included)
and [failure modes](SANDBOX-FAILURE-MODES.md) for evidence; use a container/VM when isolation matters.

## Requirements

| Need             | Why                                   | Check               |
| ---------------- | ------------------------------------- | ------------------- |
| macOS with zsh   | what this is written for              | `echo $SHELL`       |
| Node ≥ 22.19     | required by the tested Pi 0.86.1      | `node --version`    |
| pi on `PATH`     | the thing being configured            | `pi --version`      |
| python3          | used by the installer and the tooling | `python3 --version` |
| herdr (optional) | only for the multi-pane workflow      | `herdr --version`   |

## Install

```bash
git clone <this-repo> ~/pi-setup
cd ~/pi-setup
./install.sh --dry-run        # see exactly what would change
./install.sh                  # apply the full setup
```

Nothing sandbox-related is installed, because this setup does not ship a sandbox layer — see
[why](DESIGN.md#no-sandbox-layer-why-pi-sandbox-is-not-included).

`install.sh` is idempotent. It skips identical files, **merges** `settings.json` — your
`defaultModel`, `defaultProvider` and anything else already there survive; this repo's keys win only
where they overlap — and backs up a file only when its content will change.
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

For a **new** project, copy the templates without overwriting existing files:

```bash
cp -n ~/pi-setup/templates/project/AGENTS.md  /path/to/project/AGENTS.md
cp -n ~/pi-setup/templates/project/TODO.md    /path/to/project/TODO.md
```

If either file already exists, **merge it instead of replacing it**: keep project-specific commands
and backlog items, and add the task-execution convention from the templates. Fill in the Commands
section for new projects — the agent cannot infer it. Project `AGENTS.md` layers on top of the
global one. Approve the project-trust prompt once per repo (or run `/trust`).

### Complex feature task files

`TODO.md` holds the project backlog; approved complex plans use locally ignored `.pi/tasks/`
checklists that survive resumption and are removed after validation. Simple tasks need no task file.

## Verify it works

```bash
pi                                    # inside a project
/plan  add a health endpoint          # expands the template, explores read-only
/skill:brave-search  pi 0.85 changelog
/skill:herdr-subagents  run an ephemeral research child
/skill:herdr-subagents  keep a persistent child for follow-ups
/todos                                # NOT available - there is no todo extension, by design
```

`./test-bundle.sh` installs into a scratch agent directory and verifies what Pi loads, skill
invocation modes, both `AGENTS.md` variants, and the absence of a sandbox. It prints context costs;
`--keep` preserves the scratch files. No provider API key is needed for the prompt dump. **The Brave
check is not offline:** it checks for an existing key and, if none is found, temporarily stores a
dummy key in the Keychain or config file and requests `api.search.brave.com` to verify the auth-error
path, then removes the dummy key. Review the script before running it on a machine with credentials.

## Files

```
install.sh                 idempotent installer: settings.json, AGENTS.md, /plan and the skills
config/settings.json       merged into ~/.pi/agent/settings.json
config/AGENTS.md           ~/.pi/agent/AGENTS.md   - full working agreement
config/AGENTS.lean.md      same rules, less prose  - swap in if you want the tokens back
prompts/plan.md            ~/.pi/agent/prompts/plan.md - /plan template
skills/brave-search/       ~/.pi/agent/skills/brave-search/ - SKILL.md + brave.mjs
skills/herdr-subagents/     ~/.pi/agent/skills/herdr-subagents/ - two-mode Herdr orchestration
templates/project/         copy into each repo: AGENTS.md + TODO.md; defines ephemeral .pi/tasks/ files
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

## Other good practices

### git checkpointing — pi has no undo

pi edits your files directly; its own documentation tells you to use git or another checkpointing
workflow. Concretely:

1. **Checkpoint before delegating.** Start from a clean tree, or make a commit:
   `git commit --allow-empty -m "checkpoint: before agent run"`.
2. **Read the diff, not the summary.** `git diff --stat` first, then `git diff`. Reviewing the actual
   patch is the only reliable check.
3. **Undo selectively.** Check `git status --short`, `git diff` and `git diff --cached` first;
   save work you want to keep. `git restore -- path/to/file` discards unstaged edits **to that file**;
   `git revert <commit>` can undo a reviewed commit. Preview untracked removals with `git clean -nd`,
   then remove only files you identified. Do not use blanket `git reset --hard` or `git clean -fd`
   as routine rollback.
4. **Commit small.** Rollback granularity is only as fine as your commits.
5. **Isolate bigger jobs** in a throwaway branch or worktree:
   `git worktree add ../proj-agent -b agent/task`.
6. **`/tree`, `/fork` and `/clone` rewind the conversation, not the files.** Useful when the context
   went bad; never a substitute for git.
7. **Ignore ephemeral agent scratch** such as `.pi/tasks/` through `.git/info/exclude` so it never lands
   in a commit, and stage selectively with `git add -p`.

## Undoing an installation

There is no automatic uninstall. `install.sh` backs up replaced files as `.bak.<timestamp>`;
`settings.json.orig` may hold an earlier settings snapshot, and a changed settings file gets its own
backup. Inspect each installed file and its backup before restoring a _specific_ file (for example,
`diff -u` to compare, then `cp -i` to restore). Remove a file only if you have confirmed this install
created it; otherwise you may delete an existing Pi setup. Settings are **merged**, so review and
revert only this setup's keys if you have made changes since installation.

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
