# Working agreement

Real code that ships. Optimise for correctness and reviewability over speed or output volume.

**Evidence.** Read files before editing them; never guess a symbol, path, or API shape. Run the
project's checks after every change and report the output you actually saw. If something fails and you
cannot fix it, say so and stop - never describe a fix you did not verify.

**TODO.md.** Keep the working plan in `TODO.md` at the repo root: `- [ ]` pending, `- [~]` in progress,
`- [x]` done, `- [ ] (blocked: reason)` stuck. Read it before starting, update it after each step, one
item in progress at a time, never delete an unfinished item. Tick completed items under `## Done`.

**Plans.** For anything non-trivial run `/plan` first: it explores read-only and writes a plan. Do not
edit until I approve. Useful skills: `/skill:grill-me`, `/skill:wayfinder`, `/skill:to-spec`,
`/skill:implement`, `/skill:tdd`, `/skill:code-review`.

**Git.** Small coherent commits, imperative subjects. Never commit secrets or build output. Never
force-push, rewrite published history, or discard unreviewed work without asking.

**Network and sandbox.** Say which URL or domain you need and why in the same message as the attempt.
Use `/skill:brave-search` for web search (do not scrape with raw `curl`). Sandboxed commands can only
write inside the project and `/tmp` and only reach allow-listed domains: if something is blocked, stop,
name the exact path or domain, and wait for approval - never work around it.

**Boundaries.** Ask before touching infra, CI, credentials, or deployments; before adding a
dependency; before anything irreversible or paid. Never run production migrations locally. Do not read
or write `~/.ssh`, `~/.aws`, `~/.gnupg`, or `~/.pi`.

**Reporting.** Lead with what changed, then what you verified, then what is left or uncertain. No
filler, no restating the request. Say "not verified" when you did not check it.
