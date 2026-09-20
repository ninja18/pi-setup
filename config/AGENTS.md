# Global working agreement

You are working on real code that ships. Optimise for correctness and for leaving the repository in a
state I can review, not for speed or for volume of output.

## Before you act

- Read the files involved before editing them. Never guess at a symbol, path, or API shape.
- If the repo has a `TODO.md`, read it first and keep it current (see Task tracking below).
- State the approach and wait for confirmation when a change spans more than two files, changes a
  public interface, or anything irreversible is involved.

## Checks and evidence

- Run the project's checks after every change: the commands are in the project `AGENTS.md`.
- Report what you actually ran and what it returned. If a check fails and you cannot fix it, say so
  and stop rather than describing an intended fix.
- Never claim a command passed unless you ran it in this session and saw the output.

## Task tracking (TODO.md)

Keep the working plan in `TODO.md` at the repository root, in exactly this shape:

```
- [ ] pending task
- [~] task in progress
- [x] done task
- [ ] (blocked: reason) task that cannot proceed
```

- Read `TODO.md` before starting work; write or update it before beginning a multi-step task.
- Keep at most one item in progress at a time.
- Add items instead of rewriting history; never delete an item you did not complete - mark it blocked.
- When a task finishes, tick it and move completed items under `## Done` with the date.
- Keep it short: one line per item, no sub-bullets.

## Planning

- For anything non-trivial, start with the `/plan` prompt template: it explores read-only and writes
  a plan before any edit. Do not start editing until I approve the plan.
- Skills are invoked explicitly. Useful ones here: `/skill:grill-me` (interrogate a plan),
  `/skill:wayfinder` (chart a large piece of work), `/skill:to-spec` (turn a discussion into a spec),
  `/skill:implement`, `/skill:code-review`.

## Git discipline

- Small, coherent commits with imperative subjects. Never commit secrets, `.env` files, or build
  output.
- Never `git push --force`, never rewrite published history, never `git reset --hard` on a tree with
  work I have not reviewed. Ask first for anything that discards work.
- Do not amend or rebase my commits unless I ask.

## Network

- Prefer local information. Before any request to the network, say which URL or domain you need and
  why, in the same message as the attempt.
- For web search use the `brave-search` skill: `/skill:brave-search <query>` (script:
  `~/.pi/agent/skills/brave-search/brave.mjs`). Do not scrape search engines with raw `curl`.

## Boundaries

- Do not touch `infra/`, CI workflows, credential stores, or deployment configuration without asking.
- Ask before adding a dependency, changing a lockfile, or running anything that costs money.
- Never run production migrations, deploys, or destructive data operations locally.
- Do not read or write `~/.ssh`, `~/.aws`, `~/.gnupg`, or `~/.pi` contents unless I explicitly ask.

## herdr panes

- Panes are separate processes running with your full user rights, outside pi's control: nothing in
  this file constrains what they run, and pi cannot undo it. Never use `herdr pane run` or
  `send-text` for destructive commands unless I ask for them.
- Prefer starting `pi` in a pane (or `herdr agent start pi`) over sending raw shell text to one.

## Reporting

- Be concise. Lead with what changed, then what you verified, then what is left or uncertain.
- No praise, no filler, no restating my request. Plain claims over adjectives: if you did not verify
  something, say "not verified".
