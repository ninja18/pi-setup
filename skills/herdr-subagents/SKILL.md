---
name: herdr-subagents
description: Run disposable or persistent Pi agents through Herdr.
disable-model-invocation: true
---

# Herdr subagents

Use Herdr panes as a small, on-demand orchestration layer for Pi. This skill has two modes:

- **Ephemeral (default):** run one task with `pi --no-session`, capture the answer, then close only the
  pane created for it.
- **Persistent:** create a named Pi session and leave its pane open so the user can continue the
  branched conversation later.

## Prerequisites

Before changing pane state, verify all of the following:

```bash
test "${HERDR_ENV:-}" = 1
command -v herdr
command -v pi
herdr integration status
```

If `HERDR_ENV` is not `1`, stop and tell the user to launch Pi inside Herdr. Do not control a
UI-focused Herdr session from outside a managed pane. The Pi integration should be installed so
Herdr can report authoritative lifecycle and native session metadata.

Inspect the installed command syntax before first use because Herdr evolves:

```bash
herdr agent
herdr pane
```

## Prepare the delegation

1. Choose a unique lowercase name matching `[a-z][a-z0-9_-]{0,31}` and confirm it is unused with
   `herdr agent list`.
2. Make the task self-contained. A child does not inherit this conversation, so include the goal,
   working directory, constraints, relevant file paths, and expected output.
3. For write tasks, checkpoint the repository first. Do not send multiple agents into the same files;
   use separate worktrees when parallel writers are necessary.
4. Inspect the current layout with `herdr pane layout --current`. Split right when the pane is wide;
   otherwise split down. Preserve the current directory and user focus:

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus
```

Read the new pane ID from `.result.pane.pane_id`. Record it; cleanup may target only that pane.

## Ephemeral mode

Use this mode unless the user asks to keep the child conversation.

1. Start Pi without session persistence:

```bash
herdr agent start <name> --kind pi --pane <pane-id> -- --no-session
```

2. Submit the self-contained task and wait for a settled state:

```bash
herdr agent prompt <name> "<task>" --wait --timeout 120000
```

3. Inspect the final state and capture the result before cleanup:

```bash
herdr agent get <name>
herdr agent read <name> --source recent-unwrapped --lines 200
```

If the agent is `blocked`, inspect the terminal and ask the user before answering any approval or
question. If the prompt times out or stalls, do not resend it blindly and do not close the pane: the
agent may still be working. Inspect it and return the pane ID to the user.

If the completed answer is missing from terminal scrollback, ask the child to write the complete
result to a temporary Markdown file, wait again, and read that file before cleanup.

4. After the result is captured successfully, close exactly the pane created in step 1:

```bash
herdr pane close <pane-id>
```

Confirm the child no longer appears in `herdr agent list`. Report the captured result, not the raw
terminal transcript.

## Persistent session mode

Use this mode when the user asks for a branch, follow-up conversation, persistent agent, or session
that must remain available.

1. Start Pi with normal session storage and a recognizable session name. Do **not** pass
   `--no-session`:

```bash
herdr agent start <name> --kind pi --pane <pane-id> -- --name "branch-<name>"
```

2. Prompt and read it using the same workflow:

```bash
herdr agent prompt <name> "<task>" --wait --timeout 120000
herdr agent get <name>
herdr agent read <name> --source recent-unwrapped --lines 200
```

3. Return the live agent name, pane ID, status, and the `agent_session` ID/path reported by
   `herdr agent get`.

4. **Leave the pane open.** Do not close, release, stop, or replace a persistent child after returning
   its first result. Continue the branch later with:

```bash
herdr agent prompt <name> "<follow-up>" --wait --timeout 120000
```

Only close its pane when the user explicitly asks to end that branch. Closing the pane ends the live
agent but does not delete Pi's saved session. If the live pane is lost, start a new Pi agent with
`--session <saved-session-id-or-path>` after creating a replacement pane.

## Parallel basic orchestration

For independent tasks, create one pane and unique agent name per task. Start and prompt all children
without `--wait`, then call `herdr agent wait <name> --timeout 120000` for each. Capture every result.
Close only completed ephemeral panes; leave every persistent pane open. Never treat one child's
completion as evidence that the others completed.

## Pitfalls

- A successful prompt submission is not proof of completion. Trust lifecycle state and read output.
- `idle` and `done` are both ready states; `blocked` requires user input; `unknown` is not success.
- A timeout does not prove the task was not delivered. Inspect before retrying.
- Reads do not focus panes. Keep background work on `--no-focus` unless the user requests otherwise.
- Use explicit agent names and pane IDs. Never close a pane merely because it is adjacent or focused.
- Ephemeral mode avoids Pi session-history clutter. Persistent mode creates it deliberately.

## Verification

An ephemeral delegation is complete only when its result is captured, its created pane is closed, and
its name is absent from `herdr agent list`.

A persistent delegation is complete only when its first result is captured and its live name, pane ID,
and Pi session reference are reported while the pane remains present in `herdr pane list`.
