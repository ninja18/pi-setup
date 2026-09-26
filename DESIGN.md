# Design notes

Why this configuration looks the way it does, what each decision cost, and what was deliberately
left out. Every number here was measured with the tooling in `tools/` — see
[Measuring your own setup](#measuring-your-own-setup).

## The problem

pi is a deliberately small agent: four built-in tools (`read`, `bash`, `edit`, `write`), no plan mode,
no todo list, no subagents, no permission popups, no sandbox. The pitch is that a frontier model does
not need thousands of tokens of scaffolding explaining what a coding agent is.

Measured floor on pi 0.85.1: **1316 tokens of prefill** — the system prompt (678) plus the schemas of
the four active tools (638). That is what you pay before you have typed anything, on every request.

The trouble is that everything you add is _also_ paid on every request. A single popular subagent
extension adds **+5918 tokens** of tool schema — four and a half times pi's entire floor — and gets
re-sent whether or not you delegate anything that day. Packages are usually evaluated on "does this
help?" and almost never on "what does it cost per turn, forever?".

So the design goal was: **get the behavioural rails, without paying for tool schemas that sit idle.**

## Principles

1. **Keep Pi small and maintainable.** Add conventions before new resident tools or another
   extension to maintain.
2. **Prefer files when they suffice.** `AGENTS.md` costs instruction tokens; `TODO.md` and
   `.pi/tasks/` are read when needed. Prompt templates and user-invoked skills avoid tool-schema
   cost until used.
3. **Load capabilities on demand.** Skill descriptions can appear in the prompt, while skill
   bodies load only when used; `disable-model-invocation: true` removes even that description.
4. **Separate advice from enforcement.** `AGENTS.md` guides the model but cannot constrain
   filesystem or network access. This setup does not claim to provide an OS boundary; see
   [No sandbox layer](#no-sandbox-layer-why-pi-sandbox-is-not-included).
5. **Measure on your own machine.** Compare active prompt and tool costs, not just the features
   a package offers; use the harness in `tools/`.

## How each choice was made

| Need | Choice here | Extensions considered | Reason |
| ---- | ----------- | --------------------- | ------ |
| Plan before editing | `/plan` template | `@plannotator/pi-extension`, `@narumitw/pi-plan-mode` | A plan without always-active mode tools; no enforced write gate. |
| Track work | `TODO.md` backlog + ignored `.pi/tasks/` | `@juicesharp/rpiv-todo` | Project state and approved plans survive sessions without a todo extension. |
| Delegate | User-invoked Herdr skill | `pi-subagents`, `pi-herdr-subagents`, `pi-herdsman` | Disposable or persistent children without resident orchestration tools. |
| Search + fetch | Brave skill + script | `pi-web-access`, `pi-mcp-adapter` | One search API without an MCP server or resident search tools. |
| Control writes/network | No sandbox shipped | `pi-sandbox`, `@gotgenes/pi-permission-system` | The evaluated guardrail impaired ordinary work and did not enforce its domain list. |
| Instructions | Default and lean `AGENTS.md` | — | Choose detail or a lower fixed instruction cost. |

*These are evaluated alternatives, not part of the default setup. See
[Why certain things were not added](#why-certain-things-were-not-added) for the main extension trade-offs;
[Herdsman](#pi-herdsman-evaluation-pi-0871) and the [sandbox decision](#no-sandbox-layer-why-pi-sandbox-is-not-included)
are covered separately.* See [prefill measurements](#prefill-comparison) for the costs.

## Measurements

### Method

Measurements capture Pi's assembled prompt and **active** tool schemas before the first model
call, without an API key. Prefill is their combined cost using Pi's `ceil(chars / 4)` estimator,
not an exact provider token count. Each delta is compared with a bare Pi run in the same environment;
paths and Pi versions can change absolute totals. Skills contribute descriptions until invoked;
registered commands and templates add nothing until used. Wrappers such as permission and sandbox
extensions add no tool schema. See [`tools/ctx-audit.ts`](tools/ctx-audit.ts) and
[Measuring your own setup](#measuring-your-own-setup) for the procedure.

### Prefill comparison

Current bundle totals were measured offline on macOS; extension rows are historical Linux aarch64
measurements. **Compare deltas only within each group**: the two bare Pi baselines differ, and neither
the old bundle measurements nor extension deltas should be added to the current totals. Re-run
`./test-bundle.sh` for the current configuration on your machine.

| Configuration                                               | Prompt tok | Δ     | Tools  | Tool tok | Prefill   | vs bare    |
| ----------------------------------------------------------- | ---------- | ----- | ------ | -------- | --------- | ---------- |
| **Current bundle (Pi 0.86.1)**                              | —          | —     | —      | —        | —         | —          |
| bare pi                                                     | —          | —     | 4      | —        | **1304**  | —          |
| **this setup**, default                                     | —          | —     | 4      | —        | **3451**  | +2147      |
| **this setup**, lean `AGENTS.md`                            | —          | —     | 4      | —        | **2987**  | +1683      |
| **Historical extension comparison (Pi 0.85.1)**             | —          | —     | —      | —        | —         | —          |
| bare pi                                                     | 678        | 0     | 4      | 638      | **1316**  | —          |
| `@gotgenes/pi-permission-system`                            | 678        | 0     | 4      | 638      | **1316**  | **+0**     |
| silent skills (`disable-model-invocation`)                  | 678        | 0     | 4      | 638      | **1316**  | **+0**     |
| `/plan` prompt template                                     | 678        | 0     | 4      | 638      | **1316**  | **+0**     |
| `TODO.md` AGENTS.md convention (historical)                  | 880        | +202  | 4      | 638      | **1518**  | +202       |
| project `AGENTS.md`                                         | 945        | +267  | 4      | 638      | **1583**  | +267       |
| 6 mattpocock skills (2 model-invoked)                       | 1006       | +328  | 4      | 638      | **1644**  | +328       |
| `@narumitw/pi-plan-mode`                                    | 678        | 0     | 6      | 1116     | **1794**  | +478       |
| Plannotator plan mode                                       | 911        | +233  | 6      | 886      | **1797**  | +481       |
| `@juicesharp/rpiv-advisor`                                  | 1186       | +508  | 5      | 753      | **1939**  | +623       |
| `@juicesharp/rpiv-ask-user-question`                        | 1012       | +334  | 5      | 1565     | **2577**  | +1261      |
| `@juicesharp/rpiv-todo`                                     | 1108       | +430  | 5      | 1112     | **2220**  | +904       |
| `pi-mcp-adapter`                                            | 725        | +47   | 6      | 1668     | **2393**  | +1077      |
| `pi-lens` (lean, 6-tool allowlist)                          | 1193       | +515  | 6      | 1543     | **2736**  | +1420      |
| all 38 mattpocock skills installed                          | 2319       | +1641 | 4      | 638      | **2957**  | +1641      |
| `pi-herdr-subagents`                                        | 1445       | +767  | 8      | 1989     | **3434**  | +2118      |
| `pi-lens` (`--exclude-tools`, 9 tools)                      | 1242       | +564  | 9      | 2516     | **3758**  | +2442      |
| `pi-web-access`                                             | 839        | +161  | 8      | 3376     | **4215**  | +2899      |
| `pi-lens` (default)                                         | 1374       | +696  | **17** | 5344     | **6718**  | +5402      |
| `pi-subagents`                                              | 1031       | +353  | 6      | 6203     | **7234**  | +5918      |
| "install everything" stack                                  | 2366       | +1688 | **26** | 14369    | **16735** | **+15419** |

The `TODO.md` convention and project `AGENTS.md` rows describe older instruction text, **not**
this setup's current cost. The "install everything" stack reached 26 active tools; its exact package
manifest was not retained in this repo, so the figure is historical, not a reproducible benchmark
for a typical installation. A `.pi/tasks/` file is read on demand and adds no steady-state content.
Resident tool schemas account for much of the extension cost, but zero-token wrappers still need a
behavioural evaluation: see [No sandbox layer](#no-sandbox-layer-why-pi-sandbox-is-not-included).

### `pi-herdsman` evaluation (Pi 0.87.1)

`pi-herdsman@0.14.2` was measured separately because it declares Pi compatibility only for
`>=0.87.0 <0.88.0`; mixing those numbers into the Pi 0.85.1 table would imply a comparison the tool
does not support.

| Scenario | Prefill | Change |
| --- | ---: | ---: |
| compatible Pi baseline | **3129** | — |
| baseline + `pi-herdsman` | **5472** | **+2343 / +74.9%** |

The increase came from orchestration instructions plus five always-active coordination tools:
`agent`, `chief`, `peer`, `staff`, and `ask_owner`. The lifecycle test confirmed that a completed
managed child pane is cleaned up, while the child's Pi session is intentionally retained for later
continuation. Pane cleanup therefore does not prevent session-history accumulation.

That trade is reasonable when nested delegation, peer messaging, steering, supervision, recovery,
and managed-assignment semantics are routine. It is not reasonable for this setup's usual need:
start an independent child, collect its answer, and clean it up — or deliberately keep one named
branch alive for follow-up prompts.

The bundled `herdr-subagents` skill implements those two paths directly:

- **ephemeral:** start Pi with `--no-session`, capture the result, then close the created pane;
- **persistent:** start a named normal Pi session, report its pane/session identifiers, and leave the
  pane open until the user explicitly ends the branch.

The skill has `disable-model-invocation: true`, so its steady-state prefill cost is **0**. It gives up
the broader Herdsman protocol deliberately rather than reimplementing it in markdown.

## Why certain things were not added

Each of these is one command away. The point is that you should add them knowing the price.

### Plan-mode extensions (`@plannotator/pi-extension`, `@narumitw/pi-plan-mode`, …)

- **Cost:** +481 tokens (Plannotator) or +478 (`pi-plan-mode`), resident.
- **Offers:** A stateful plan mode; Plannotator also blocks writes outside the plan and requires
  browser approval with annotations.
- **Here:** The `/plan` prompt template (+0) produces a plan for user approval.
- **Trade-off:** A model can ignore a template; a mode can remove write tools. Use Plannotator
  when you need an enforced gate.

### A todo extension (`@juicesharp/rpiv-todo`)

- **Cost:** +904 tokens, resident.
- **Offers:** A live overlay, dependency graph with cycle detection, and structured CRUD with
  `/reload` and compaction replay.
- **Here:** `TODO.md` holds the project backlog; locally ignored `.pi/tasks/` checklists track
  approved complex plans across sessions, then are deleted after validation.
- **Trade-off:** Files have no live UI, dependency graph, or automatic branch replay; use the
  extension if those are worth its permanent schema cost.

### `pi-lens` — the biggest single "no"

- **Cost:** +5402 tokens as shipped (17 active tools); +2442 with 9 tools or +1420 with a
  6-tool allowlist.
- **Offers:** LSP and cascade diagnostics, linters, ast-grep, ranked symbol search, navigation,
  and read/commit guards that actually enforce their rules.
- **Here:** Project checks, targeted code search, and review; no resident diagnostics extension.
- **Trade-off:** No automatic diagnostics or enforced guards. Add `pi-lens` when it saves enough
  debugging time, but install language servers first and limit the active tools.

Do not assume its advertised dynamic loading reduces cost: with pi-lens 4.2.1 and Pi 0.85.1, all
13 tools activated. A tested `session_start` attempt to deactivate tools was undone by pi-lens's
handler (still 17 active). Check `/lens-tools`; CLI flags worked:

```bash
# 9 tools, +2442 — drops the situational tools
pi --exclude-tools ast_grep_search,ast_grep_replace,ast_grep_outline,lsp_navigation,lens_diagnostic_mark,project_report,effective_config,pi_lens_activate_tools

# 6 tools, +1420 — keeps diagnostics + symbol search
alias pil='pi --tools read,bash,edit,write,lens_diagnostics,symbol_search'
```

### `@juicesharp/rpiv-ask-user-question` — the closest call

- **Cost:** +1261 tokens (927 schema + 334 guidance).
- **Offers:** Up to four questions per dialog, typed choices, free text, notes, and markdown previews;
  removes itself gracefully in non-interactive runs.
- **Here:** `/plan` ends with questions, and `AGENTS.md` requires confirmation before broad changes.
- **Trade-off:** No button-driven questions at an unexpected mid-task fork. Install it if that matters;
  exclude its tool on approved-plan runs to avoid the schema cost then. Guidance can be trimmed via
  `~/.config/rpiv-ask-user-question/config.json`, but the schema cannot.

### `pi-web-access`

- **Cost:** +2899 tokens for four active tools.
- **Offers:** Search and fetching across multiple providers, source checking, GitHub, YouTube, PDFs,
  and local video.
- **Here:** The Brave skill and script (~+110 tokens) cover web search and fetching on demand.
- **Trade-off:** No built-in source checking or specialized media support. Use `pi-web-access` if
  those are routine needs.

### `pi-subagents`

- **Cost:** +5918 tokens, the largest single addition measured.
- **Offers:** `scout`/`researcher`/`worker`/`reviewer`/`oracle` roles, background children,
  FleetView, and live transcript inspection and steering.
- **Here:** The user-invoked Herdr skill (+0 steady-state) offers visible ephemeral or persistent
  Pi children.
- **Trade-off:** No scripted multi-agent roles or FleetView. Adopt `pi-subagents` if those
  workflows justify its always-active delegation schema.

### MCP (`pi-mcp-adapter`)

- **Cost:** +1077 tokens of fixed gateway-tool cost; server schemas load on demand.
- **Offers:** One adapter for multiple MCP services, such as Linear, Sentry, and databases.
- **Here:** A skill and script handle the one search API needed by this setup.
- **Trade-off:** No general MCP access. Add the adapter if you actually use several MCP servers.

## No sandbox layer: why pi-sandbox is not included

`pi-sandbox` was installed, used on real work, then removed. It wraps `bash` and `!` calls in
macOS `sandbox-exec`, intercepts `read`/`write`/`edit`, prompts for access outside the project, and
hard-blocks `denyWrite` paths such as `.env`, `*.pem`, and credentials. At **+0 prompt tokens**, it
worked as a guardrail against mistakes. These failures outweighed that benefit:

- **Process lifecycle (no config fix):** each `bash` call runs in a different sandbox. Signals
  work only within `same-sandbox`; a server started in one call cannot be stopped in the next,
  even by the same user. Start and stop it in one call or give lifecycle to the application.
- **GUI and permissions (no practical config fix):** macOS blocks window-server, WebKit,
  `cfprefsd`, audio, and `tccd` mach services. TCC microphone consent is not a sandbox config
  key. An agent building or driving a GUI cannot exercise the app inside the sandbox.
- **Silent or misleading failures:** mach-service and unix-socket denials do not prompt. Setuid
  tools such as `ps`, `top`, and `sudo` cannot run. The extension mistakes some exec refusals
  for blocked writes and suggests adding `/bin/ps` to `allowWrite`, which cannot fix them.
- **Toolchain tax:** `cargo` needed registry/cache access, Go needed checksum-db writes, and
  clang's module cache broke Objective-C module builds (including Tauri/Swift) without
  `CLANG_MODULE_CACHE_PATH`. `xcrun` logged a cache error on every link. Each fix added
  per-toolchain knowledge unrelated to the task.
- **Network policy (deciding failure):** in pi-sandbox 0.6.8, `allowedDomains` acted as a
  pre-approval list, not an enforced allowlist. Unlisted hosts returned HTTP 200 over both
  HTTP and SOCKS proxies, even with hostnames assembled at runtime; direct DNS failed, but
  proxy traffic was not rejected. That is unsafe to trust as a security boundary.
- **Pane escape:** Herdr panes run outside Pi's subprocess sandbox. Allowing its control socket
  lets sandboxed code invoke unsandboxed pane commands; starting Pi in a pane only protects
  that child's own Pi tool calls.

See [SANDBOX-FAILURE-MODES.md](SANDBOX-FAILURE-MODES.md) for the generated Seatbelt rules,
reproductions, configuration levers, and version-specific caveats.

**What replaces it:** no OS-level guardrail. Checkpoint with git before delegating, inspect diffs,
commit small, use worktrees for larger jobs, and treat outside content as untrusted. `AGENTS.md` is
advice; git is undo, not isolation. `@gotgenes/pi-permission-system` (+0 tokens) can gate tools and
commands in-process against model mistakes, but cannot contain a determined agent.

**For real isolation:** Pi itself has no sandbox; run all of Pi inside an OS/container/VM boundary
for untrusted repositories or unattended work. This setup does not ship one:

- **Docker:** mount only the workspace (`-v "$PWD:/workspace"`); never mount host `~/.pi/agent`
  (credentials and sessions). Minimize credentials and restrict network access.
- **Docker Sandboxes:** provider keys remain on the host; a proxy substitutes a sentinel on egress.
- **Gondolin:** host Pi with tools routed to a local Linux micro-VM (QEMU; Node ≥ 23.6).
- **OpenShell:** policy-controlled filesystem, process, network, and credential access.

## Measuring your own setup

**This setup:** `./test-bundle.sh` installs into a scratch agent directory, asserts what loads,
and prints costs for both `AGENTS.md` variants. It needs `pi`, `node`, and `python3`; prompt dumps
need no provider key. The full test also inspects the Brave key store and may temporarily store a
dummy key and request `api.search.brave.com` (see [README](README.md#verify-it-works)).

**An extension:** measure a bare Pi scenario and the candidate in separate agent directories:

```bash
tools/measure.sh baseline
PI_CODING_AGENT_DIR=~/pi-audit/scenarios/todo pi install npm:@juicesharp/rpiv-todo
tools/measure.sh todo
tools/analyze.py baseline todo --detail
```

`pi install` can access the network; `tools/measure.sh` sets `PI_OFFLINE=1` for its Pi run and
needs no provider key. Dumps and logs land in `$PI_CTX_AUDIT_HOME/out/<scenario>/` (default
`~/pi-audit`); see [`tools/ctx-audit.ts`](tools/ctx-audit.ts) for the capture procedure.
