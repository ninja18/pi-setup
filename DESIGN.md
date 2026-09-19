# Design notes

Why this configuration looks the way it does, what each decision cost, and what was deliberately
left out. Every number here was measured with the tooling in `tools/` — see
[Reproducing the numbers](#reproducing-the-numbers).

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

0. **Maintain Pi philosophy**. Add features to the developer's behaviour instead of context bloat.
1. **Files before extensions.** A rule in `AGENTS.md`, a convention in `TODO.md`, a template in
   `prompts/` costs a fixed, small number of tokens — or zero until invoked — and works in every
   harness that reads markdown. An extension costs a tool schema on every request forever.
2. **Progressive disclosure where possible.** Skills put only their name and description in the
   prompt; the body loads when the skill is used. `disable-model-invocation: true` removes even the
   description, leaving the skill callable by you via `/skill:<name>`.
3. **Zero-cost invocation paths win ties.** Prompt templates and user-invoked skills measure at
   exactly `+0`. Plan mode, by contrast, is a state machine that must be resident.
4. **Advice where you can, enforcement where advice fails.** Instructions in `AGENTS.md` handle
   ~90% of desired behaviour for a few hundred tokens. The remaining 10% — filesystem writes,
   network reach — has to be enforced outside the model, which is what the sandbox is for.
5. **Measure on your own machine.** Adoption numbers tell you a package is maintained; they tell you
   nothing about what it costs you. The harness in `tools/` answers that in a couple of minutes.

## How each choice was made

| Need                         | Options measured                                                                                                                                                                                     | Decision                                         | Why                                                                                                                                                                                                                                                                                                                                            |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Plan before editing          | Plannotator plan mode **+481** (browser approval gate, 2 tools) · `@narumitw/pi-plan-mode` **+478** · prompt template **+0** · mattpocock `grill-me`/`wayfinder`/`to-spec`/`implement` skills **+0** | `/plan` prompt template (+0), skills when wanted | A template costs nothing and produces the same artefact — a written plan you approve. Skills are already `disable-model-invocation: true`, so adopting them later is free too.                                                                                                                                                                 |
| Track multi-step work        | `@juicesharp/rpiv-todo` **+904** (tool schema 474 + 430 guidance) · `TODO.md` convention in `AGENTS.md` **+202**                                                                                     | `TODO.md` file                                   | 4.5× cheaper, survives new sessions and compaction, visible in git, works in any other agent you use.                                                                                                                                                                                                                                          |
| Delegate to subagents        | `pi-subagents` **+5918** · `pi-herdr-subagents` **+2118** · herdr's own skill **+0**                                                                                                                 | herdr skill, invoked on demand                   | herdr already gives real terminal panes and lifecycle state for pi; the skill is user-invoked, so it costs nothing until you ask for help with panes.                                                                                                                                                                                          |
| Web search + fetch           | `pi-web-access` **+2899** · `pi-mcp-adapter` + a Brave MCP server **+1077** · Brave skill + script **~+110**                                                                                         | skill + dependency-free script                   | You already pay for a search API. 26× cheaper than `pi-web-access`, no MCP server to keep running.                                                                                                                                                                                                                                             |
| Constrain writes and network | `pi-sandbox` **+0** · `@gotgenes/pi-permission-system` **+0** · container/VM (separate concern)                                                                                                      | `pi-sandbox`                                     | Both permission layers measure at zero prompt cost because they wrap `bash` and gate the file tools instead of registering new tools. `pi-sandbox` adds OS-level enforcement (macOS `sandbox-exec`) and a domain allowlist with interactive prompts. Read [Security model](#security-model-what-the-sandbox-is-and-is-not) before trusting it. |
| Instructions to the model    | One big `AGENTS.md` vs a leaner one                                                                                                                                                                  | Both shipped                                     | The full file is ~930 tokens/turn, the lean variant ~370. It is the single largest line item in the whole setup, so the choice belongs to you rather than to a default.                                                                                                                                                                        |

## Measurements

### Method

A small extension (`tools/ctx-audit.ts`) hooks `session_start` and writes four things to disk:

- `ctx.getSystemPrompt()` — the assembled system prompt, including active-tool snippets, guidelines,
  the skills catalogue, and any `AGENTS.md` content,
- `pi.getAllTools()` — every registered tool with its description and JSON schema,
- `pi.getActiveTools()` — the subset the model actually receives,
- `pi.getCommands()` — registered slash commands (proof that an extension, skill, or template
  actually loaded).

`session_start` fires **before** the first model call, so the whole thing works with no API key: start
pi in print mode, let it fail at the auth check, read the dump.

Rules that materially change the answer:

- **Tokens = `ceil(chars / 4)`** — pi's own estimator (`estimateTokens` in `core/compaction`). It is a
  consistent yardstick, not a provider-exact tokenizer; schema-heavy JSON usually tokenizes _better_
  than 4 chars/token, so treat the absolute extension costs as upper bounds.
- **Count active tools only.** A bare pi _registers_ eight tools and _activates_ four. Counting the
  registered set inflates every scenario.
- **Tool cost = name + description + `JSON.stringify(parameters)`.** Extension tools can be enormous:
  `pi-subagents`' tool is 4926 characters of description and 13810 of schema.
- **Skills cost only their name and description** in the prompt; bodies load on use.
- **Prompt templates and registered commands cost 0** until invoked.
- **Sandbox and permission extensions cost 0** prompt tokens.

### Results (pi 0.85.1, Linux aarch64)

Prefill = system prompt + active tool schemas. Absolute figures will differ slightly on macOS and
across pi releases; the _ratios_ are what matter.

| Configuration                                               | Prompt tok | Δ     | Tools  | Tool tok | Prefill   | vs bare    |
| ----------------------------------------------------------- | ---------- | ----- | ------ | -------- | --------- | ---------- |
| bare pi                                                     | 678        | 0     | 4      | 638      | **1316**  | —          |
| `pi-sandbox`                                                | 678        | 0     | 4      | 638      | **1316**  | **+0**     |
| `@gotgenes/pi-permission-system`                            | 678        | 0     | 4      | 638      | **1316**  | **+0**     |
| silent skills (`disable-model-invocation`)                  | 678        | 0     | 4      | 638      | **1316**  | **+0**     |
| `/plan` prompt template                                     | 678        | 0     | 4      | 638      | **1316**  | **+0**     |
| `TODO.md` + AGENTS.md convention                            | 880        | +202  | 4      | 638      | **1518**  | +202       |
| project `AGENTS.md`                                         | 945        | +267  | 4      | 638      | **1583**  | +267       |
| 6 mattpocock skills (2 model-invoked)                       | 1006       | +328  | 4      | 638      | **1644**  | +328       |
| `@narumitw/pi-plan-mode`                                    | 678        | 0     | 6      | 1116     | **1794**  | +478       |
| Plannotator plan mode                                       | 911        | +233  | 6      | 886      | **1797**  | +481       |
| `@juicesharp/rpiv-advisor`                                  | 1186       | +508  | 5      | 753      | **1939**  | +623       |
| `@juicesharp/rpiv-ask-user-question`                        | 1012       | +334  | 5      | 1565     | **2577**  | +1261      |
| `@juicesharp/rpiv-todo`                                     | 1108       | +430  | 5      | 1112     | **2220**  | +904       |
| `pi-mcp-adapter`                                            | 725        | +47   | 6      | 1668     | **2393**  | +1077      |
| `pi-lens` (lean, 6-tool allowlist)                          | 1193       | +515  | 6      | 1543     | **2736**  | +1420      |
| **this setup** (full AGENTS.md + project AGENTS.md + skill) | 2166       | +1488 | 4      | 638      | **2804**  | +1488      |
| **this setup** (lean AGENTS.md)                             | 1724       | +1046 | 4      | 638      | **2362**  | +1046      |
| all 38 mattpocock skills installed                          | 2319       | +1641 | 4      | 638      | **2957**  | +1641      |
| `pi-herdr-subagents`                                        | 1445       | +767  | 8      | 1989     | **3434**  | +2118      |
| `pi-lens` (`--exclude-tools`, 9 tools)                      | 1242       | +564  | 9      | 2516     | **3758**  | +2442      |
| `pi-web-access`                                             | 839        | +161  | 8      | 3376     | **4215**  | +2899      |
| `pi-lens` (default)                                         | 1374       | +696  | **17** | 5344     | **6718**  | +5402      |
| `pi-subagents`                                              | 1031       | +353  | 6      | 6203     | **7234**  | +5918      |
| "install everything" stack                                  | 2366       | +1688 | **26** | 14369    | **16735** | **+15419** |

`./test-bundle.sh` prints the exact figures for your machine — they move by a handful of tokens because
the working directory path is part of the system prompt (it reports ~2797 / ~2358 for the two
`AGENTS.md` variants from a `/tmp` scratch directory).

Reading the table:

- pi's floor is real, and it is easy to lose. Six packages took a comparable setup from ~1.3k to
  ~16.7k — 12× — of which only the sandbox was free.
- The cheap wins are files: `+202` for a `TODO.md` convention against `+904` for a todo tool.
- The expensive things are tool _schemas_, not features. `pi-subagents` and `pi-lens` are 11k tokens
  of schema between them.
- Cost is not quality. `pi-sandbox` is the second-most-valuable thing in this repo and measures at
  zero, because it wraps `bash` instead of adding tools.

## Why certain things were not added

Each of these is one command away. The point is that you should add them knowing the price.

### Plan-mode extensions (`@plannotator/pi-extension`, `@narumitw/pi-plan-mode`, …)

**+481 / +478 tokens, resident.** A plan-mode extension is a state machine: it holds phase state,
injects framing instructions, and reconfigures the active tool set. That is worth paying for if you
want a _hard gate_ — Plannotator restricts writes to the plan file, blocks destructive commands, and
refuses to execute until you approve in a browser UI with annotations. It is not worth paying for if
what you want is "a plan before we start", which the `/plan` template does for `+0`.

What you give up by using the template: the model _can_ ignore it, whereas a mode physically removes
the write tools. Start with the template; add Plannotator when you catch yourself wanting the gate.

### A todo extension (`@juicesharp/rpiv-todo`)

**+904 tokens.** Its advantages over a file are real: a live overlay, a dependency graph with cycle
detection, structured CRUD that survives `/reload` and compaction via branch replay. But a `TODO.md`
file costs `+202`, persists across sessions _and across agents_ (Claude Code, Codex, or a human
reading the repo all see the same file), and shows up in `git diff`. If you work in long single
sessions where compaction is a real risk, the extension earns its tokens; otherwise the file wins.

### `pi-lens` — the biggest single "no"

**+5402 tokens as shipped (17 active tools)**. What it does is genuinely good: LSP diagnostics on
every write/edit, impact-cascade diagnostics on affected files, linters and typecheckers, ast-grep and
tree-sitter rules, ranked `symbol_search`, 19 LSP navigation operations, plus guards — a read-guard
that blocks edits without a prior read, and a git-guard that holds commits while findings are open.
Those guards are the interesting part, because they are _enforcement_ in a way prompt text never is.

Why it is not in the default set anyway:

- It costs ~4× this entire setup, before it has found a single issue.
- Its documentation describes a dynamic-tooling mode (5 tools always active, situational tools
  activated on demand through a loader). On pi-lens 4.2.1 with pi 0.85.1, **all 13 tools activated** —
  check `/lens-tools` on your machine before assuming you get the lean path.
- Lazy-loading it yourself does **not** work: a `session_start` hook that calls `setActiveTools()`
  runs before pi-lens' own handler, so the tools come straight back (tested: still 17 active). The
  reliable levers are the CLI flags only:

  ```bash
  # 9 tools, +2442 — drops the situational tools
  pi --exclude-tools ast_grep_search,ast_grep_replace,ast_grep_outline,lsp_navigation,lens_diagnostic_mark,project_report,effective_config,pi_lens_activate_tools

  # 6 tools, +1420 — keeps diagnostics + symbol search, the highest-value surfaces
  alias pil='pi --tools read,bash,edit,write,lens_diagnostics,symbol_search'
  ```

- It needs language servers and linters present to do anything, so it is dead weight on a fresh repo
  with no toolchain yet.

Add it when the project has real code and you are in refactor or debugging loops — and add it through
the alias, not at full width. Then check whether it reduces round-trips enough to justify itself.

### `@juicesharp/rpiv-ask-user-question` — the closest call

**+1261 tokens** (927 of which is the `ask_user_question` schema; the rest is guidance text). The
feature is good: up to four questions in one dialog, typed options with descriptions, a free-text row
on every question, notes, a submit summary, markdown previews, and graceful removal in
non-interactive runs.

It is left out because it overlaps with two things already here: the `/plan` template ends with a
"Questions" section, and `AGENTS.md` says to stop and confirm anything spanning more than two files.
The unique value is _mid-execution_ — the agent hits an unforeseen fork halfway through implementing
and asks you with buttons instead of guessing. If that is the failure mode you actually feel, install
it (and consider `--exclude-tools ask_user_question` on approved-plan runs so you only pay when
exploring). You can trim the 334 tokens of guidance via
`~/.config/rpiv-ask-user-question/config.json`; you cannot trim the 927-token schema.

### `pi-web-access`

**+2899 tokens** for four tools (`web_search`, `fetch_content`, `source_check`, `get_search_content`).
Excellent coverage — Brave, Exa, Tavily, Kagi, SearXNG and more, plus GitHub, YouTube, PDFs and local
video. It is simply 26× the cost of the Brave skill + script for a search-API shape most people
already pay for. If you want `source_check`-style citations or YouTube/PDF support routinely, the
calculation changes.

### `pi-subagents`

**+5918 tokens** — the most expensive single addition measured, and only 4.5× pi's floor on its own.
The implementation is not the problem: it ships `scout`/`researcher`/`worker`/`reviewer`/`oracle`
roles, background children, a FleetView panel and a live inspector with transcript reading and
steering. The problem is that a delegation tool with that much configuration surface has a ~12 KB
description-plus-schema that is re-sent on every request whether or not you delegate. herdr gives you
visible panes for `+0`; use that until you specifically want scripted multi-agent workflows.

### MCP (`pi-mcp-adapter`)

**+1077 tokens of fixed cost**, which is cheaper than most single-purpose MCP-consuming extensions —
the adapter exposes one gateway tool and fetches server schemas on demand, so adding servers is
nearly free. It is excluded because nothing here requires MCP: one search API is cheaper as a skill,
and pi's own guidance is to prefer a script over a server when the surface is small. Add it if you
have a real MCP estate (Linear, Sentry, a database) to talk to.

## Security model: what the sandbox is and is not

**`pi-sandbox` is a guardrail against mistakes, not a security boundary.**

What it does:

- wraps `bash` (and your `!` commands) in macOS `sandbox-exec`, enforcing filesystem and network
  rules at the OS level for those subprocesses;
- intercepts the `read`, `write` and `edit` tools in-process against the same policy, because those
  tools run inside the Node process and cannot be covered by the OS sandbox;
- prompts you when a write reaches outside the project, when a read reaches outside the allow list,
  or when a command tries a domain that is not on the allow list;
- hard-blocks writes to `denyWrite` paths (`.env`, `*.pem`, `*.key`, credential directories) with no
  prompt, and refuses rather than silently allowing when a prompt times out.

What it is **not**:

- **Not a container, not a VM, not an OS-level isolation boundary.** It reduces blast radius; it does
  not contain a determined attacker who already has code execution as your user.
- **Not protection against extensions or skills.** pi extensions are TypeScript modules that run with
  the full permissions of the pi process. Installing a package is equivalent to running its author's
  code as yourself. Read what you install. This is why every package here is pinned and why the
  preference is scripts you can read.
- **Not protection against prompt injection.** Untrusted content in a repository — a README, a
  comment, a build log, a fetched page — can still ask the model to do things. The sandbox limits what
  those actions can reach; it does not make untrusted content trustworthy.
- **Not airtight even on its own terms.** On macOS the default config enables an unauthenticated SOCKS
  proxy so `git` over SSH works; while the sandbox is running, another local process that discovers
  that port can use it. The domain allow list still applies to it, but the surface exists. Likewise,
  anything you approve once is allowed for the rest of the session, so approvals are a real decision.
- **Not a substitute for git.** It will happily let the agent delete your uncommitted work inside the
  project directory. Checkpoint before you let it run; see the FAQ in the README.

pi itself ships no sandbox at all and its documentation is explicit that real isolation has to come
from the OS or a virtualization/container boundary. If that is what you need — untrusted
repositories, unattended automation, generated code you will not review — run the whole of `pi`
inside one:

- **Docker**: mount only the workspace (`-v "$PWD:/workspace"`), do _not_ mount the host
  `~/.pi/agent` (that exposes your credentials and sessions), pass the minimum credentials, and
  restrict the network.
- **Docker Sandboxes**: provider keys stay on the host and a proxy substitutes a sentinel on egress.
- **Gondolin**: host `pi`, tools routed into a local Linux micro-VM (QEMU; Node ≥ 23.6).
- **OpenShell**: policy-controlled sandbox with filesystem, process, network and credential controls.

The honest summary: the sandbox configuration in this repo is worth having, costs nothing in context,
and will stop an agent from wiping your home directory or `curl`-ing a payload with your credentials.
It is not a reason to run untrusted code.

## Reproducing the numbers

Everything above comes from `tools/`:

```bash
# 1. baseline: run pi in an isolated agent dir with the audit harness attached
tools/measure.sh baseline

# 2. add a candidate to that scenario's agent dir and measure again
PI_CODING_AGENT_DIR=~/pi-audit/scenarios/todo pi install npm:@juicesharp/rpiv-todo
tools/measure.sh todo

# 3. compare everything you have measured so far
tools/analyze.py
tools/analyze.py todo lens --detail      # selected scenarios, with per-tool breakdown
```

Dumps and run logs land in `$PI_CTX_AUDIT_HOME/out/<scenario>/` (default `~/pi-audit`). The whole
loop is offline-friendly: set `PI_OFFLINE=1` and nothing touches the network except your own
`pi install`.

`test-bundle.sh` does the whole thing for this repo's own configuration — install into a scratch
agent dir, dump the prompt, print the cost of the full and lean `AGENTS.md`, and confirm that the
sandbox extension actually loaded. It needs `pi`, `node` and `python3` on `PATH` and no API key,
because the dump happens before the auth check.
