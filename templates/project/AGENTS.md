# Project instructions

<!-- Fill in the commands section first - the agent runs these after every change. -->

## Commands

- Install: `npm ci`
- Dev: `npm run dev`
- Fast check: `npm run lint`
- Full check (run before claiming done): `npm run check && npm test`
- Single test: `npm test -- <pattern>`

## Layout

- `src/` application code
- `tests/` integration tests, co-located unit tests as `*.test.ts`
- `docs/` design notes

## Conventions

- TypeScript strict. No `any` in new code.
- Co-locate tests with sources. Every bug fix gets a regression test.
- Keep diffs focused: separate refactors from behaviour changes.
- Public functions get a doc comment; internal helpers do not.

## Definition of done

1. The change does what was asked, with no unrelated edits.
2. `npm run check && npm test` passes; paste the output summary.
3. New behaviour is covered by a test that fails without the change.
4. `TODO.md` is updated.

## Boundaries for this repo

- Do not edit `infra/` or `.github/workflows/` without asking.
- Ask before adding a dependency.
- Never run production migrations or deploys locally.
