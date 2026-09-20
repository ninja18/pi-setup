# Sandbox failure modes

> **Status: removed.** This file is the evidence behind the decision in
> [DESIGN.md](DESIGN.md#no-sandbox-layer-why-pi-sandbox-is-not-included) to drop `pi-sandbox` from this
> repo. It is kept for the rule-level detail and the reproductions. Read every "_Shipped:_" note, and
> everything in §7, as "what the last shipped config contained" rather than as current advice.

Reference notes for `config/sandbox.json` (`npm:pi-sandbox`). Written after a debugging session
against **pi-sandbox 0.6.8 / @carderne/sandbox-runtime 0.0.72 / pi 0.85.1 on macOS 26.6.2**. Every
failure below was reproduced and pinned to a rule in the Seatbelt profile that pi-sandbox actually
generates — rule text was read out of the generated profile, not inferred. See [Caveats](#6-caveats).

If something "doesn't work" under the sandbox it is almost always one of two things, and they have
different fixes. Start here.

## 1. Two kinds of denial

|                           | A. exec-time refusal                                                          | B. operation-time refusal                                                                                        |
| ------------------------- | ----------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Symptom                   | `<shell>: /bin/ps: Operation not permitted` (exit 126)                        | the program runs, then fails: `EPERM`, `Connection Invalid`, `service not found`                                 |
| Cause                     | the binary is **setuid**, and Seatbelt refuses privileged exec                | an SBPL rule denies a syscall                                                                                    |
| Examples                  | `ps`, `top`, `sudo`, `su`, `login`, `newgrp`, `crontab`, `at`/`atq`/`atrm`/`batch` | `kill` across tool calls, `pgrep`, GUI apps, local sockets, writes outside `allowWrite`                          |
| Config lever              | **none** — no SBPL operation grants setuid exec                               | some; see [levers](#4-config-levers)                                                                             |
| Workaround                | run it outside the sandbox, or use a non-setuid equivalent                     | depends on the rule                                                                                              |

How to tell them apart when the message is unhelpful:

- exit code 126 with a path before `Operation not permitted` → exec refusal;
- anything that starts and prints its own error → operation refusal;
- `kill` is a shell builtin, so it never execs: an EPERM from `kill` is always a rule, never setuid.

## 2. What the profile actually says

The profile is generated per `bash` call (`sandbox-exec -p <profile> <shell> -c <cmd>`), so **each
tool call is its own sandbox instance**. The fixed, non-configurable core:

```
(deny default (with message "<log-tag>"))
(allow process-exec)
(allow process-fork)
(allow process-info*       (target same-sandbox))
(allow signal              (target same-sandbox))
(allow mach-priv-task-port (target same-sandbox))
(allow user-preference-read)
(allow mach-lookup (global-name "<~15 fixed services>"))
(allow sysctl-read (…fixed name list incl. prefixes kern.proc.all, kern.proc.pid., machdep.cpu.))
(allow system-socket (require-all (socket-domain AF_SYSTEM) (socket-protocol 2)))
; network: bind/inbound (local ip "*:*") when allowLocalBinding,
;          outbound (remote ip "localhost:*"), plus the proxy ports;
;          unix-socket rules only when allowUnixSockets/allowAllUnixSockets is set
; reads:   (allow file-read*) → (deny file-read* (subpath <denyRead>)) → (allow file-read* (subpath <allowRead|allowWrite>))
; writes:  (allow file-write* (subpath <allowWrite>)) → (deny file-write* (subpath <denyWrite>)) + move-blocking denies
```

Everything those lines do not allow is denied — including `mach-lookup` for any service outside the
fixed list, and every `unix-socket` path unless you opt in.

Four consequences that surprise people:

- **`(target same-sandbox)` is per tool call.** One `sandbox-exec` per `bash` invocation means the
  process you started in call N is out of reach in call N+1.
- **Writes are deny-by-default; reads are allow-by-default except `denyRead`.** This is a write
  guardrail plus a network allowlist, not read confidentiality.
- **`denyWrite` beats `allowWrite`.** Seatbelt is last-match-wins and the runtime emits allow rules
  first, so "allow a directory, carve out the dangerous bits inside it" works — e.g.
  `allowWrite: ["~/.cargo"]` + `denyWrite: ["~/.cargo/bin", "~/.cargo/config.toml"]`.
- **pi-sandbox always sets `enableWeakerNetworkIsolation: true`**, which appends
  `com.apple.trustd.agent` and `com.apple.SystemConfiguration.configd` to the mach list. The runtime's
  own docs call `trustd.agent` a potential data-exfiltration vector; it is on all the time here.

## 3. Failure catalogue

### 3.1 setuid binaries cannot be executed (`ps`, `top`, `sudo`, `crontab`, …)

_Symptom:_ `bash: /bin/ps: Operation not permitted`, exit 126. `/bin/ps` is `-rwsr-xr-x root wheel`.

_Evidence:_ `python3` `subprocess.run(["/bin/ps", …])` → `OSError errno=1`. Same for `crontab`,
`atq`, `newgrp`, `top`, `sudo`. Non-setuid system binaries that are equally restricted/compressed
(`cc`, `xcrun`, `sysctl`, `lsof`, `htop`) exec fine, so the distinguishing feature is the setuid bit.
A non-setuid copy of the binary gets past exec but is then killed/returns nothing — not a workaround.

_Verdict:_ incident of sandboxing, not a policy rule; **no config lever**. The setuid inventory is
small and mostly privilege/process-inspection tools (`ps`, `top`, `sudo`, `su`, `login`, `newgrp`,
`crontab`, `at`/`atq`/`atrm`/`batch`, `quota`, `traceroute`). Agents rarely need any of them: they
need their **own** processes and ports, which `lsof` covers (see [3.9](#39-things-that-do-work-do-not-over-relax-to-fix-a-non-problem)).
`sudo` being refused is arguably a feature.

### 3.2 `pgrep` / `pkill` — the `sysmond` lookup

_Symptom:_ `sysmon request failed with error: sysmond service not found`, exit 3.

_Evidence:_ `bootstrap_look_up` from inside the sandbox returns `1100` for `com.apple.sysmond` and
`com.apple.system.libinfo.mach`, and `0` for services in the fixed list. A definitely nonexistent
name also returns `1100`, i.e. the denial happens before name resolution.

_Lever:_ `network.allowMachLookup: ["com.apple.sysmond", "com.apple.system.libinfo.mach"]`.

_Risk:_ low mechanically, but it exposes the whole user process table and `argv` (tokens, paths) to
sandboxed commands. Note that `kern.proc.all` is already in the sysctl allowlist, so pid enumeration
works without it.

_Shipped:_ both services are allow-listed in the default config. **`pkill` still fails** — it is
`pgrep` plus a signal, and signals cross only within one tool call
([3.5](#35-signals-only-cross-within-one-tool-call--kill-across-calls)). Expect `pgrep` to list and
`pkill` to refuse.

### 3.3 mach-lookup allowlist — everything GUI, audio, WebKit and TCC

Measured with `bootstrap_look_up` (`0` = allowlisted, `1100` = denied):

| Service | Result |
| --- | --- |
| `com.apple.system.notification_center`, `…opendirectoryd.libinfo`, `…distributed_notifications@Uv3`, `com.apple.SecurityServer` | 0 |
| `com.apple.hiservices-xpcservice` (HIServices / AppKit) | 1100 |
| `com.apple.windowserver.active`, `com.apple.WindowServer`, `com.apple.SkyLight`, `com.apple.CARenderServer`, `com.apple.CoreDisplay` | 1100 |
| `com.apple.appkit.xpc.openAndSavePanelService`, `com.apple.axserver` | 1100 |
| `com.apple.cfprefsd.daemon`, `com.apple.lsd` | 1100 |
| `com.apple.WebKit.WebContent` | 1100 |
| `com.apple.tccd` (TCC) | 1100 |
| `com.apple.audio.audiohald`, `com.apple.audio.AudioComponentRegistrar`, `com.apple.coreaudio.avfaudio` | 1100 |

_Interpretation:_ a GUI app cannot get started (first wall: `hiservices-xpcservice`, which surfaces
as a hang with `Connection Invalid` in `run()` before `setup()`), and allowing the window server
alone does not finish the job: a WKWebView app also needs WebKit XPC, `cfprefsd`, `lsd`, IOKit,
LaunchServices and writes under `~/Library/Application Support/<bundle>`. Microphone capture needs
`com.apple.tccd`, and TCC consent is not a sandbox config key at all.

_Verdict:_ **not a config problem to solve.** Run GUI apps outside the sandbox (`!` with
`sandboxUserShell: false`, `Alt+S`, `/sandbox-disable`, or `--no-sandbox`). `allowBrowserProcess:
true` is the only realistic lever and it grants `(allow mach*)` (see [4](#4-config-levers)).

### 3.4 Unix sockets — local daemons and control sockets

_Symptom:_ connecting to a local daemon or control socket fails with `EPERM` (errno 1), with **no
prompt** — the profile contains no unix-socket rules unless configured.

_Evidence:_ `socket(AF_UNIX, SOCK_STREAM)` succeeds; `connect()` to
`~/.config/herdr/herdr.sock` (a mode-0600 control socket) → `errno=1`.

_Lever:_ `network.allowUnixSockets: ["/absolute/path.sock"]` → emits
`(allow network-bind (local unix-socket (subpath …)))` and
`(allow network-outbound (remote unix-socket (subpath …)))`; or `allowAllUnixSockets: true`. macOS
only; ignored on Linux (seccomp cannot filter by path).

_Risk:_ depends entirely on what the socket can do. `allowAllUnixSockets` also exposes Docker,
the SSH agent, 1Password and every other local daemon. A control socket for an orchestrator or
terminal multiplexer is worse than it looks: see [3.10](#310-herdr-panes-what-is-and-is-not-sandboxed).

_Shipped:_ herdr's two sockets (`herdr.sock`, `herdr-client.sock`) are allow-listed in the default
config with the consequence above accepted deliberately — see [7](#7-what-the-last-shipped-config-contained-and-why). `~` is
expanded, so the entries stay portable. Only `bind` and `outbound` for those two exact paths are
allowed; every other daemon socket is still refused.

### 3.5 Signals only cross within one tool call — `kill` across calls

_Evidence:_ `/bin/kill` is `-rwxr-xr-x` (**not** setuid) and `kill` is a shell builtin, so no exec is
involved. Same binary, same user, only the target differs:

| Test | Result |
| --- | --- |
| `sleep 25 & p=$!; /bin/kill -0 $p; /bin/kill -TERM $p` — same `bash` call | `rc=0`, `rc=0` |
| start `sleep` in one call, then `/bin/kill -0 <pid>` / `-TERM <pid>` from the next call | `Operation not permitted`, `rc=1`, target still alive |

_Cause:_ `(allow signal (target same-sandbox))` plus one sandbox per tool call.

_Verdict:_ **no config lever** (no `signal` key exists in pi-sandbox or the runtime schema; the rule
is a literal string in `macos-sandbox-utils.js`). Consequences: an agent can start a server but
never stop it in a later call, and can never signal anything it did not start — including a process
your app launched. Design around it: start and stop within one call, or let the application own
process lifecycle. (Timeouts still work: pi kills the process group from its own unsandboxed Node
process, which never passes through Seatbelt.)

### 3.6 Writes outside the allow list

_Symptom:_ bash gets `EPERM`; the `write`/`edit` tools get a prompt instead.

_Evidence:_ `~/.cargo/registry/index`, `~/.cargo/registry/cache`, `~/.cargo/git` → `EPERM`;
`~/Library/Caches` → OK. The file tools prompt for any path outside `allowRead`/`allowWrite`
(`~/Documents` is not in either, so vault/notes paths prompt every time). Note the asymmetry: the
`read` tool prompts when outside `allowRead`, while **bash reads are unrestricted except `denyRead`**.

_Lever:_ `allowWrite` (implies read) plus `denyWrite` carve-outs.

### 3.7 `$TMPDIR` is redirected, `DARWIN_USER_*` is not

_Evidence:_ inside bash, `TMPDIR=/tmp/claude`, and `/tmp/claude` is writable — the runtime sets that
env var for the child and allow-lists the path by default, so tools that honour `TMPDIR` are fine.
Tools that use `confstr(_CS_DARWIN_USER_TEMP_DIR / _CACHE_DIR)` are not: writes to
`$(getconf DARWIN_USER_TEMP_DIR)` and `$(getconf DARWIN_USER_CACHE_DIR)` → `EPERM`.

_Real failure_ (clang module cache, breaks ObjC/module builds — Rust `cc` crate, Tauri, Swift
interop):

```
error: unable to open output file
  '$DARWIN_USER_CACHE_DIR/clang/ModuleCache/<hash>/_DarwinFoundation2-<hash>.pcm': 'Operation not permitted'
fatal error: could not build module '_DarwinFoundation2'
```

_Levers:_ the portable fix is not a sandbox change: `CLANG_MODULE_CACHE_PATH=~/Library/Caches/clang`
(already writable), or per-project through cargo's `[env]` table with `relative = true`. `allowWrite`
cannot express it portably: `C` and `T` sit behind a per-user hash, and the runtime strips a trailing
`/**` (`removeTrailingGlobSuffix`), so `/private/var/folders/*/*/C/**` degrades to the regex
`^/private/var/folders/[^/]*/[^/]*/C$` — which matches the directory itself but not the files inside
it. The only config route is the literal `$(getconf DARWIN_USER_CACHE_DIR)` for this machine, which
the runtime canonicalises to `/private/var/folders/…`.

### 3.8 Sysctl: the library works, the CLI does not

_Evidence:_ `sysctlbyname("kern.ostype" | "hw.ncpu" | "kern.osversion" | "machdep.cpu.brand_string")`
all succeed; the `sysctl(8)` CLI fails with `sysctl: sysctl fmt -1 1024 1: Operation not permitted`
even for allowlisted names; `netstat -an -p tcp | grep -c LISTEN` → `0`.

_Hypothesis (unconfirmed):_ the CLI resolves names by walking the sysctl tree, which trips a read
that is not on the fixed list. Either way, do not read "sysctl is broken" as "sysctl-read is not
allowed" — the allowlist works.

### 3.9 Things that do work (do not over-relax to fix a non-problem)

- `lsof -nP -iTCP -sTCP:LISTEN` → full `COMMAND PID USER … NAME` list of listeners, **including
  processes started outside the sandbox**. This answers "what is on port N / is the server up" and is
  the practical replacement for `ps`/`pgrep`. (Mechanism not determined; `kern.proc.all` is allowed.)
- `curl http://127.0.0.1:<port>` → loopback TCP is allowed while `allowLocalBinding` is on.
- `htop` (Homebrew, non-setuid) — unlike setuid `top`.
- `git`, `node`, `python3`, `cargo`, `cc`, `xcrun`, `nc`, `rg`.
- `proc_listpids` via `kern.proc.all` returns every pid, while `proc_pidinfo` on other processes
  returns nothing — that difference is the `process-info* (target same-sandbox)` rule.

### 3.10 herdr panes: what is and is not sandboxed

- herdr has **no sandbox option**: `herdr --help`, `herdr pane --help` (`run`, `send-text`,
  `send-keys`, …), `herdr agent --help`, and `config.toml` contain no such flag or key.
- The only sandbox in the picture is applied by pi to its own `bash` executions. A pane is created by
  the herdr **server** and runs your `$SHELL`; nothing in that process tree ever had a profile
  attached, so `pane run`, `send-text` and `send-keys` execute **unsandboxed**.
- A **`pi` process** started in a pane is different: it applies the same global config to its own
  tool calls (pi-sandbox: "parent agents and subagents have separate sandbox managers"), so
  subagents are contained **as long as what you start is `pi`**, not a shell command.
- So allowing the herdr socket means the socket is an unsandboxed execution channel for anything that
  can reach it — including code running inside your sandbox. The shipped config allows the two
  sockets deliberately; see [7](#7-what-the-last-shipped-config-contained-and-why) for the trade and how to undo it.
- `AGENTS.md` cannot change this. It is advice to the model: it cannot grant a socket the OS refuses,
  and it cannot constrain a pane shell. A convention ("always `agent start pi`, never raw
  `pane run`") reduces accidents and does not survive prompt injection.

### 3.11 Exec denials are misreported as write denials (pi-sandbox bug)

pi-sandbox scans bash output for `(?:/bin/bash|bash|sh): (?:line \d: )?(\/[^\s:]+): Operation not
permitted` and treats the captured path as a blocked write, then offers to add it to `allowWrite`.
An exec refusal such as `/bin/bash: /bin/ps: Operation not permitted` therefore produces a prompt
suggesting `/bin/ps` be added to `allowWrite` — which cannot work, because the refusal is the setuid
exec rule. Observed consequence in the wild: a project `.pi/sandbox.json` containing exactly
`{"filesystem": {"allowWrite": ["/bin/ps"]}}`. Delete entries like that; grep for them.

Related gap: `mach-lookup` and unix-socket denials have **no prompt path at all** (only domains,
reads and writes are prompted), so those failures arrive as silent `EPERM` and can only be fixed by
editing config and restarting the session.

## 4. Config levers

| Key | Effect | Notes |
| --- | --- | --- |
| `filesystem.allowWrite` | `(allow file-write* (subpath …))`; implies read | arrays **union** global+project config, so a project file can only widen, never narrow |
| `filesystem.denyWrite` | hard deny, beats `allowWrite`, never prompted | the right place for `~/.cargo/bin`, `~/.cargo/config.toml` |
| `filesystem.allowRead` / `denyRead` | read rules for the file tools and bash | `denyRead` is not a hard block for the file tools (granting a read prompt overrides it) |
| `network.allowMachLookup` | `(allow mach-lookup (global-name …))`, trailing `*` allowed | per service; the fix for XPC clients |
| `network.allowUnixSockets` | `(allow network-{bind,outbound} … unix-socket (subpath …))` | macOS only |
| `network.allowAllUnixSockets` | every unix socket | also exposes Docker/SSH agent/keychain sockets |
| `network.allowedDomains` / `deniedDomains` | proxy allowlist / hard deny | |
| `allowBrowserProcess` | `(allow mach*)`, `(allow process-info*)`, `(allow iokit-open)`, `(allow ipc-posix-shm*)` | large hammer; the documented route to a window-server-capable process |
| `allowPty` | `(allow pseudo-tty)` + `/dev/ttys*` | off by default; pi's bash tool does not allocate a pty |
| `allowAppleEvents` | `appleevent-send`, `lsopen`, events/LaunchServices services | removes code-execution isolation (can launch apps unsandboxed) |
| `sandboxUserShell` | whether `!` commands are wrapped | `false` = a human escape hatch while the model's `bash` stays sandboxed |
| `permissionPromptTimeoutSeconds` | prompt timeout; `0` waits forever | a timeout never grants |

**No lever exists for:** setuid exec; `(allow signal|process-info*|mach-priv-task-port (target
same-sandbox))`; the fixed mach-list core (only additions); the fixed sysctl list; TCC.

Operational: config is read at session start. A change needs a pi restart, or `/sandbox-disable` →
`/sandbox-enable`.

## 5. Diagnostic recipes

```bash
# exec refusal vs operation refusal, with an errno and no shell noise
python3 -c "import subprocess
try: print('rc', subprocess.run(['/bin/ps','-p','1']).returncode)
except OSError as e: print('errno', e.errno, e.strerror)"

# is a Mach service reachable? 0 = allowlisted, 1100 = denied
python3 -c "import ctypes
L=ctypes.CDLL('/usr/lib/libSystem.B.dylib'); bp=ctypes.c_uint.in_dll(L,'bootstrap_port')
L.bootstrap_look_up.argtypes=[ctypes.c_uint,ctypes.c_char_p,ctypes.POINTER(ctypes.c_uint)]
p=ctypes.c_uint(0); print(L.bootstrap_look_up(bp,'com.apple.hiservices-xpcservice',ctypes.byref(p)))"

# what is listening (works inside the sandbox)
lsof -nP -iTCP -sTCP:LISTEN

# write probe: print the errno for a path instead of triggering a prompt
python3 -c "import os
p=os.path.expanduser('~/.cargo/registry/.probe')
try: open(p,'w').write('x'); os.unlink(p); print('writable')
except OSError as e: print('errno',e.errno,e.strerror)"
```

Print the exact profile pi-sandbox generates (pure computation, safe anywhere). The import path is
the pi agent npm dir; adjust it if you set `PI_CODING_AGENT_DIR`:

```bash
node --input-type=module -e "
import { wrapCommandWithSandboxMacOS } from '$HOME/.pi/agent/npm/node_modules/@carderne/sandbox-runtime/dist/sandbox/macos-sandbox-utils.js';
console.log(wrapCommandWithSandboxMacOS({ command:'true', needsNetworkRestriction:true,
  httpProxyPort:41234, socksProxyPort:41235, allowLocalBinding:true,
  readConfig:{denyOnly:[],allowWithinDeny:[]},
  writeConfig:{allowOnly:['/tmp'],denyWithinAllow:[]} }))"
```

The profile is the `-p` argument, single-quoted for the shell: `bash -c 'set -- '"$(…)"'; printf
"%s\n" "$@"'` prints each argument on its own line.

Two diagnostic caveats:

- `log show` refuses to run inside the sandbox (`log: Cannot run while sandboxed`), so read violation
  logs from an unsandboxed terminal.
- You **cannot** validate a relaxation from inside a sandboxed session: a nested `sandbox-exec` fails
  with `sandbox-exec: sandbox_apply: Operation not permitted`, and nested profiles could only ever
  intersect anyway. Restart pi with the change instead.

## 6. Caveats

- Verified on macOS 26.6.2, pi-sandbox 0.6.8, `@carderne/sandbox-runtime` 0.0.72, pi 0.85.1. The rule
  text lives in that runtime's `dist/sandbox/macos-sandbox-utils.js` and the config schema in
  `sandbox-config.js`; if the pins move, re-derive rather than trusting this file.
- Linux (bubblewrap/seccomp) differs substantially: `allowUnixSockets` is ignored, globs in
  `allowWrite` are skipped, and process/`kill` semantics are not the same.
- Hypotheses are marked as such: the `sysctl(8)`/`netstat` cause, and why `lsof` works despite
  `process-info*` being same-sandbox-restricted.
- "No lever" means "no key in pi-sandbox's config surface, and the runtime emits no rule for it" —
  not a statement about the full expressiveness of SBPL.

## 7. What the last shipped config contained, and why

The last shipped `config/sandbox.json` reflected the analysis above (that file is no longer in the
repo). One rule governed every addition:

> Allow caches and registries. Never allow anything that puts an executable on `PATH`, replaces a
> toolchain, or holds a credential.

### Added

| Entry | Why | Guard |
| --- | --- | --- |
| `network.allowMachLookup: [com.apple.sysmond, com.apple.system.libinfo.mach]` | `pgrep` is an ordinary diagnostic tool, and without it the failure is a silent `EPERM`. `pkill` still fails — it needs `signal` ([3.5](#35-signals-only-cross-within-one-tool-call--kill-across-calls)). | read-only; exposes the user process table and `argv` |
| domains: crates.io, Go, PyPI, Maven, Gradle, RubyGems | a registry that is not allow-listed is refused with a 403 and no prompt | proxy-scoped, one domain at a time |
| `~/.cargo` | Rust registry index, `.crate` cache, git checkouts, build state | `~/.cargo/bin`, `config.toml`, `config` and `credentials.toml` are in `denyWrite` |
| `~/go/pkg/mod`, `~/Library/pnpm/store`, `~/.bun/install/cache`, `~/.yarn/berry/cache`, `~/.m2/repository`, `~/.gradle/caches` | package stores that live outside `~/.cache` and `~/Library/Caches` | caches only — the sibling `bin`/`tools` directories are not allowed |
| `network.allowUnixSockets: [~/.config/herdr/herdr.sock, ~/.config/herdr/herdr-client.sock]` | lets the agent create panes and start subagents itself | **the one deliberate containment hole** — see below |

Python needed nothing: pip, uv and poetry caches already sit under `~/.cache` and `~/Library/Caches`.

### Deliberately left alone

- **GUI apps** ([3.3](#33-mach-lookup-allowlist--everything-gui-audio-webkit-and-tcc)) — the only
  lever is `allowBrowserProcess: true` (`(allow mach*)`), and TCC for a microphone is not a config key.
- **Signals across tool calls** ([3.5](#35-signals-only-cross-within-one-tool-call--kill-across-calls)) —
  no config key exists.
- **`~/.rustup`, `~/.pyenv`, `~/.local/bin`, `~/.local/share/uv`, `~/.gem`** — these put executables on
  or near `PATH`, and a writable `~/.rustup` means a replaceable `rustc`. Installing into them is a
  deliberate action that should prompt.

### The accepted hole: herdr's sockets

Allowing the socket is what makes agent-created panes possible, and it means anything that can reach
the socket — including code inside the sandbox — can run **unsandboxed** commands in a pane, because
panes are children of the herdr server and never inherit a profile
([3.10](#310-herdr-panes-what-is-and-is-not-sandboxed)). This is accepted, not overlooked:

- the config allows those two exact paths, never `allowAllUnixSockets`;
- `config/AGENTS.sandbox.md` tells the model to start `pi` in a pane and to keep destructive work out
  of `pane run`/`send-text`;
- to undo it, delete the `allowUnixSockets` block and restart pi — you lose agent-created panes and
  regain containment.

### Operational notes

- Config is read at session start: restart pi, or `/sandbox-disable` → `/sandbox-enable`.
- A project `.pi/sandbox.json` can only **widen** the arrays, never narrow them.
- `install.sh` **replaces** `~/.pi/agent/sandbox.json` (with a timestamped backup), so additions made
  by hand do not survive the next run. Fold anything worth keeping into `config/sandbox.json`.

### Still open

- **Working directories.** Vaults and shared directories still prompt on write; add them explicitly
  once the paths are settled.
- **`kill`** deserves a line in the security-model section of DESIGN.md (app-owned lifecycle is the
  design, not agent-owned).
- **Prompt-bug artefacts.** Grep your configs for `allowWrite` entries naming a setuid binary — such as
  the `/bin/ps` entry this analysis found in a project `.pi/sandbox.json`.
