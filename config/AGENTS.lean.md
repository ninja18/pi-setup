# Working agreement

Real code that ships. Optimise for correctness and reviewability over speed or output volume.

**Evidence.** Read files before editing them; never guess a symbol, path, or API shape. Run the
project's checks after every change and report the output you actually saw. If something fails and you
cannot fix it, say so and stop - never describe a fix you did not verify.

**TODO.md.** Durable project backlog, never an implementation checklist: read it first, update only when
project state changes (not for implementation steps), keep one `[~]`, preserve unfinished entries, and
move completed entries under `## Done`.

**Complex task files.** After an approved `/plan`, use `.pi/tasks/<YYYY-MM-DD>-<slug>-<unique-id>.md` only for
3+ checkable steps, several components, or likely resumption. Use a session ID or UUID; never overwrite.
Record the goal and approved plan title. Locally ignore `.pi/tasks/` in Git's `.git/info/exclude`.
Turn the plan into 3-7 checked outcomes; keep one `[~]`, update at step boundaries. On resumption, list
`.pi/tasks/`, read the file matching this goal/plan, and ask if ambiguous. Delete only that file after
final validation. Update `TODO.md` separately only if project-level state changes.

**Plans.** For anything non-trivial run `/plan` first: it explores read-only and writes a plan. Do not
edit until I approve. Useful skills: `/skill:grill-me`, `/skill:wayfinder`, `/skill:to-spec`,
`/skill:implement`, `/skill:tdd`, `/skill:code-review`.

**Git.** Small coherent commits, imperative subjects. Never commit secrets or build output. Never
force-push, rewrite published history, or discard unreviewed work without asking.

**Network.** Say which URL or domain you need and why in the same message as the attempt. Use
`/skill:brave-search` for web search (do not scrape with raw `curl`).

**Boundaries.** Ask before touching infra, CI, credentials, or deployments; before adding a
dependency; before anything irreversible or paid. Never run production migrations locally. Do not read
or write `~/.ssh`, `~/.aws`, `~/.gnupg`, or `~/.pi`.

**herdr panes.** Separate processes with your full user rights, outside pi's control. Never use
`herdr pane run` / `send-text` for destructive commands unless I ask; prefer starting `pi` in a pane.

**Reporting.** Lead with what changed, then what you verified, then what is left or uncertain. No
filler, no restating the request. Say "not verified" when you did not check it.
