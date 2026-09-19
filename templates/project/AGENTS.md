# Project instructions

<!--
Fill in the Commands section first - it is the one thing the agent cannot infer, and it is what the
"definition of done" below refers to. Delete the sections that do not apply to this project.
-->

## Commands

| Task                                           | Command                                                   |
| ---------------------------------------------- | --------------------------------------------------------- |
| Install dependencies                           | `<e.g. npm ci / uv sync / go mod download / cargo fetch>` |
| Build                                          | `<...>`                                                   |
| Run all checks (required before claiming done) | `<e.g. make check>`                                       |
| Test everything                                | `<...>`                                                   |
| Test one thing                                 | `<...>`                                                   |
| Run the app                                    | `<...>`                                                   |

If a check needs a specific environment (a database, a container, an env var), say so here and note
what the agent should do when it is unavailable - skip it, or stop and ask.

## Layout

- `<path>/` - what lives here
- `<path>/` - what lives here

Keep this short. The agent can read the tree; this is for the parts that are not obvious.

## Conventions

- Match the surrounding code: naming, error handling, logging, and test structure.
- Keep diffs focused. Separate refactors from behaviour changes.
- Every bug fix gets a regression test at the level the bug was found.
- Document public interfaces; leave internal helpers undocumented unless the logic is subtle.
- If you are unsure whether something is a convention or an accident, ask instead of guessing.

## Definition of done

1. The change does what was asked, with no unrelated edits.
2. The full check command above passes; paste the output summary, not a claim.
3. New behaviour is covered by a test that fails without the change.
4. Public interfaces and user-facing docs are updated if they changed.
5. `TODO.md` is updated.

## Boundaries for this repository

- Do not edit `<CI config, infra, release scripts>` without asking.
- Ask before adding a dependency, changing a lockfile, or altering the build.
- Never run migrations, deploys, or anything that touches production or paid resources locally.
- Never commit secrets, credentials, or generated artefacts.
