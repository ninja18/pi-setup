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

1. **Maintain Pi philosophy**. Add features to the developer's behaviour instead of context bloat.
2. **Easier to maintain**. Pi is customisable, but this setup aims to make it rare that you comeback and tweak settings often.
3. **Files before extensions.** A rule in `AGENTS.md`, a convention in `TODO.md`, a template in
   `prompts/` costs a fixed, small number of tokens — or zero until invoked — and works in every
   harness that reads markdown. An extension costs a tool schema on every request forever.
4. **Progressive disclosure where possible.** Skills put only their name and description in the
   prompt; the body loads when the skill is used. `disable-model-invocation: true` removes even the
   description, leaving the skill callable by you via `/skill:<name>`.
5. **Zero-cost invocation paths win ties.** Prompt templates and user-invoked skills measure at
   exactly `+0`. Plan mode, by contrast, is a state machine that must be resident.
6. **Advice where you can, enforcement where advice fails.** Instructions in `AGENTS.md` handle
   ~90% of desired behaviour for a few hundred tokens. The remaining 10% — filesystem writes,
   network reach — has to be enforced outside the model, and no layer we have measured earns its keep
   yet: see [No sandbox layer](#no-sandbox-layer-why-pi-sandbox-is-not-included).
7. **Measure on your own machine.** Adoption numbers tell you a package is maintained; they tell you
   nothing about what it costs you. The harness in `tools/` answers that in a couple of minutes.

## How each choice was made

| Need                         | Options measured                                                                                                                                                                                     | Decision                                         | Why                                                                                                                                                                                                                                                                                                                                            |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Plan before editing          | Plannotator plan mode **+481** (browser approval gate, 2 tools) · `@narumitw/pi-plan-mode` **+478** · prompt template **+0** · mattpocock `grill-me`/`wayfinder`/`to-spec`/`implement` skills **+0** | `/plan` prompt template (+0), skills when wanted | A template costs nothing and produces the same artefact — a written plan you approve. Skills are already `disable-model-invocation: true`, so adopting them later is free too.                                                                                                                                                                 |
| Track multi-step work        | `@juicesharp/rpiv-todo` **+904** (tool schema 474 + 430 guidance) · `TODO.md` convention in `AGENTS.md` **+202**                                                                                     | `TODO.md` file                                   | 4.5× cheaper, survives new sessions and compaction, visible in git, works in any other agent you use.                                                                                                                                                                                                                                          |
| Delegate to subagents        | `pi-subagents` **+5918** · `pi-herdr-subagents` **+2118** · herdr's own skill **+0**                                                                                                                 | herdr skill, invoked on demand                   | herdr already gives real terminal panes and lifecycle state for pi; the skill is user-invoked, so it costs nothing until you ask for help with panes.                                                                                                                                                                                          |
| Web search + fetch           | `pi-web-access` **+2899** · `pi-mcp-adapter` + a Brave MCP server **+1077** · Brave skill + script **~+110**                                                                                         | skill + dependency-free script                   | You already pay for a search API. 26× cheaper than `pi-web-access`, no MCP server to keep running.                                                                                                                                                                                                                                             |
| Constrain writes and network | `pi-sandbox` **+0** · `@gotgenes/pi-permission-system` **+0** · container/VM (separate concern)                                                                                                      | **nothing** — measured, then rejected               | Both cost zero prompt tokens because they wrap `bash` and gate the file tools instead of registering new tools. `pi-sandbox` was installed and used for real work before being removed: the failures it produces cannot be configured away, and making toolchains build inside it needed per-toolchain workarounds. See [No sandbox layer](#no-sandbox-layer-why-pi-sandbox-is-not-included).                                                                             |
| Instructions to the model    | One big `AGENTS.md` vs a leaner one                                                                                                                                                                  | Both shipped                                     | The full file is ~910 tokens/turn, the lean variant ~480. It is the single largest line item in the whole setup, so the choice belongs to you rather than to a default.                                                                                                                                                                        |

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
- **Permission and sandbox extensions cost 0** prompt tokens: they wrap `bash` and gate the file
  tools instead of registering new tools.

### Results (pi 0.85.1)

Prefill = system prompt + active tool schemas. Absolute figures differ across platforms and pi
releases by a few tokens, because the working-directory path is part of the system prompt, so the
_ratios_ are what matter. The extension and package rows were measured on Linux aarch64; the two
`this setup` rows were re-measured on macOS on 2026-09-21 with `./test-bundle.sh`.

| Configuration                                               | Prompt tok | Δ     | Tools  | Tool tok | Prefill   | vs bare    |
| ----------------------------------------------------------- | ---------- | ----- | ------ | -------- | --------- | ---------- |
| bare pi                                                     | 678        | 0     | 4      | 638      | **1316**  | —          |
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
| **this setup**, default (`AGENTS.md` + project template + skill) | 2525   | +1847 | 4      | 638      | **3163**  | +1847      |
| **this setup**, lean `AGENTS.md`                            | 2098       | +1420 | 4      | 638      | **2736**  | +1420      |
| all 38 mattpocock skills installed                          | 2319       | +1641 | 4      | 638      | **2957**  | +1641      |
| `pi-herdr-subagents`                                        | 1445       | +767  | 8      | 1989     | **3434**  | +2118      |
| `pi-lens` (`--exclude-tools`, 9 tools)                      | 1242       | +564  | 9      | 2516     | **3758**  | +2442      |
| `pi-web-access`                                             | 839        | +161  | 8      | 3376     | **4215**  | +2899      |
| `pi-lens` (default)                                         | 1374       | +696  | **17** | 5344     | **6718**  | +5402      |
| `pi-subagents`                                              | 1031       | +353  | 6      | 6203     | **7234**  | +5918      |
| "install everything" stack                                  | 2366       | +1688 | **26** | 14369    | **16735** | **+15419** |

`./test-bundle.sh` prints the exact figures for your machine for both shapes of this setup — default
and lean `AGENTS.md` — as ~3163 / ~2736 from a `$TMPDIR` scratch directory.

One note on these two rows: they were re-measured twice on macOS. First after the project `AGENTS.md`
template was rewritten to be language-agnostic rather than Node/TypeScript flavoured: **2804 / 2362** →
**3049 / 2665** (that template is part of the prompt, and grew from **+267** to **+512** tokens). Then
after the herdr pane guidance was added to the global `AGENTS.md`, and with the sandbox gone: →
**3163 / 2736**. Part of that last move is the scratch directory path, which is part of the prompt —
re-running `./test-bundle.sh` gives your own figures. The other rows in this table were measured
without the project template, so their deltas are unaffected.

Reading the table:

- pi's floor is real, and it is easy to lose. A handful of packages took a comparable setup from
  ~1.3k to ~16.7k — 12×. The free ones were the ones that shipped files, templates or wrappers rather
  than tool schemas.
- The cheap wins are files: `+202` for a `TODO.md` convention against `+904` for a todo tool.
- The expensive things are tool _schemas_, not features. `pi-subagents` and `pi-lens` are 11k tokens
  of schema between them.
- Cost is not quality, and free is not free. The cheapest layers are the ones that wrap `bash` or
  ship markdown rather than tool schemas — which is why a guardrail looks like a bargain, and why
  `pi-sandbox` still had to be judged on its behaviour and removed.

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

## No sandbox layer: why pi-sandbox is not included

`pi-sandbox` was installed, used on real work, and removed. It is a well-built extension: it wraps
`bash` (and your `!` commands) in a macOS `sandbox-exec` profile, intercepts `read`, `write` and `edit`
in-process against the same policy, prompts for writes and reads outside the project, and hard-blocks
`denyWrite` paths (`.env`, `*.pem`, credential files) with no prompt. It costs **+0** prompt tokens.
As a guardrail against mistakes, it worked.

It is not in this repo because the cost is paid constantly, in the wrong place, on ordinary work.
Three classes of failure could not be fixed at all:

- **A process cannot be signalled from a later tool call.** Each `bash` call gets its own profile and
  signals are allowed only within `same-sandbox`, so an agent can start a server and never stop it —
  `Operation not permitted`, even though it is the same user and the same process it started. No
  config key exists. In real use this was the failure that bit hardest, and the workaround (start and
  stop inside one tool call, or hand lifecycle to the application) is a discipline the sandbox imposes
  on every long-running command.
- **GUI apps, audio, the microphone and TCC do not work.** The window server, WebKit, `cfprefsd` and
  `tccd` are not on the mach-lookup allowlist, and TCC consent is not a config key. On a project that
  builds or drives a GUI — the case that prompted this evaluation — the agent cannot touch the thing
  being built.
- **Some denials arrive with no prompt at all.** mach-service and unix-socket denials are silent, and
  the extension misreads exec refusals as blocked writes, offering to add something like `/bin/ps` to
  `allowWrite`, which cannot work.

Worse than the hard failures was the tax on ordinary tools. Making the toolchains this repo actually
uses run inside the sandbox needed per-toolchain workarounds: `cargo` could not reach its registry or
cache, Go could not write its checksum database, clang could not write its module cache (so builds of
anything Objective-C — a Tauri or Swift target — fail unless `CLANG_MODULE_CACHE_PATH` is pointed
somewhere else), and `xcrun` printed a cache error on every link. Each has a fix, and each fix is
environment knowledge unrelated to the task at hand — bought for a layer its own documentation calls a
guardrail rather than a boundary.

The deciding measurement was the network policy. `allowedDomains` reads like an allowlist, but on
pi-sandbox 0.6.8 it behaves as a pre-approval list: requesting hosts that are not in it still returned
200, over both the HTTP and the SOCKS proxy, including when the hostnames were built at runtime so no
command scan could have approved them. Traffic is funnelled through the local proxy — direct DNS fails
— but nothing rejects an unlisted host. A security-shaped control that does not enforce is worse than
no control, because it gets trusted.

Every denial is catalogued with the generated Seatbelt rules and the reproductions in
[SANDBOX-FAILURE-MODES.md](SANDBOX-FAILURE-MODES.md), kept as the evidence for this decision.

What replaced it: nothing at the OS layer. The guardrail is process — checkpoint with git before
delegating, read the diff rather than the summary, commit small, isolate bigger jobs in a worktree, and
treat anything that arrives from outside the repository as untrusted input. If you want enforcement
short of a container, `@gotgenes/pi-permission-system` (**+0** tokens) gates `read`, `write`, `edit` and
commands in-process: no OS layer, so none of the failure classes above, and it is enforcement against a
confused model rather than a determined one.

pi itself ships no sandbox at all and its documentation is explicit that real isolation has to come
from the OS or a virtualization/container boundary. If that is what you need — untrusted
repositories, unattended automation, generated code you will not review — run the whole of `pi`
inside one (this repo does not ship a container path; the improvements list in the README tracks it):

- **Docker**: mount only the workspace (`-v "$PWD:/workspace"`), do _not_ mount the host
  `~/.pi/agent` (that exposes your credentials and sessions), pass the minimum credentials, and
  restrict the network.
- **Docker Sandboxes**: provider keys stay on the host and a proxy substitutes a sentinel on egress.
- **Gondolin**: host `pi`, tools routed into a local Linux micro-VM (QEMU; Node ≥ 23.6).
- **OpenShell**: policy-controlled sandbox with filesystem, process, network and credential controls.

The honest summary: this setup has no OS-level guardrail, and the one it had could not be made to work
on ordinary toolchains. The substitution is process — checkpoint before delegating, read the diff,
commit small, isolate the rest — and if you need a line that holds against a determined agent, put a
container under pi rather than a profile around its subprocesses. `AGENTS.md` is advice; git is the
undo.

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

For this repo's own configuration, `./test-bundle.sh` does the same thing in a scratch agent
directory (no API key, nothing of yours touched) and prints the numbers for both shapes: default and
the lean `AGENTS.md`.

Dumps and run logs land in `$PI_CTX_AUDIT_HOME/out/<scenario>/` (default `~/pi-audit`). The whole
loop is offline-friendly: set `PI_OFFLINE=1` and nothing touches the network except your own
`pi install`.

`test-bundle.sh` does the whole thing for this repo's own configuration — install into a scratch
agent dir, dump the prompt, print the cost of the full and lean `AGENTS.md`, and confirm that no
sandbox layer is loaded. It needs `pi`, `node` and `python3` on `PATH` and no API key,
because the dump happens before the auth check.
