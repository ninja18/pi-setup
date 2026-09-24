#!/usr/bin/env bash
#
# Self-test for this repo's configuration.
#
#   ./test-bundle.sh            run it, clean up afterwards
#   ./test-bundle.sh --keep     keep the scratch directory for inspection
#   ./test-bundle.sh --help     this text
#
# Installs the bundle into a scratch agent directory, runs pi against it with the context audit
# harness attached, and checks that everything that should be registered really is. No API key is
# required: session_start fires before the first model call, so the prompt is dumped and the run then
# stops at the auth check.
#
# Nothing outside the scratch directory is touched, except the Brave key file it creates and removes
# again to exercise the key-management path. Exits non-zero if any check fails.
set -uo pipefail

# --------------------------------------------------------------------------------------
# configuration
# --------------------------------------------------------------------------------------

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEEP_SCRATCH=0
SCRATCH=""
AGENT_DIR=""
SKILL_ONLY_AGENT_DIR=""
WORK_DIR=""
CHECKS=0
FAILURES=0

# --------------------------------------------------------------------------------------
# output
# --------------------------------------------------------------------------------------

section() { printf '\n########## %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }
info() { printf '   %-9s %s\n' "$1" "$2"; }

pass() {
  printf '   ok    %s\n' "$*"
  CHECKS=$((CHECKS + 1))
}

fail() {
  printf '   FAIL  %s\n' "$*"
  CHECKS=$((CHECKS + 1))
  FAILURES=$((FAILURES + 1))
}

usage() {
  cat <<'USAGE'
Self-test for this repo's configuration.

  ./test-bundle.sh            run it, clean up afterwards
  ./test-bundle.sh --keep     keep the scratch directory for inspection
  ./test-bundle.sh --help     this text

Needs pi, node and python3 on PATH. No API key required.
USAGE
}

# --------------------------------------------------------------------------------------
# lifecycle
# --------------------------------------------------------------------------------------

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --keep) KEEP_SCRATCH=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        printf 'error: unknown option: %s\n' "$1" >&2
        exit 1
        ;;
    esac
    shift
  done
}

setup_scratch() {
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/pi-setup-test.XXXXXX")"
  AGENT_DIR="$SCRATCH/agent"
  SKILL_ONLY_AGENT_DIR="$SCRATCH/skill-only-agent"
  WORK_DIR="$SCRATCH/work"
  mkdir -p "$AGENT_DIR" "$SKILL_ONLY_AGENT_DIR" "$WORK_DIR"
  cd "$SCRATCH" || exit 1 # never stand inside a directory this script deletes
  trap cleanup EXIT
}

cleanup() {
  if [ "$KEEP_SCRATCH" = 1 ]; then
    printf '\nscratch kept at %s\n' "$SCRATCH"
  else
    rm -rf "$SCRATCH"
  fi
}

finish() {
  section "summary"
  if [ "$FAILURES" = 0 ]; then
    printf '   %d/%d checks passed\n' "$CHECKS" "$CHECKS"
    exit 0
  fi
  printf '   %d of %d checks failed\n' "$FAILURES" "$CHECKS"
  exit 1
}

# --------------------------------------------------------------------------------------
# assertions
# --------------------------------------------------------------------------------------

assert_file() { # <path> <label>
  if [ -f "$1" ]; then
    pass "$2"
  else
    fail "$2 (missing: $1)"
  fi
}

assert_contains() { # <file> <needle> <label>
  if grep -qF -- "$2" "$1" 2>/dev/null; then
    pass "$2"
  else
    fail "$2 (not found in $(basename "$1"))"
  fi
}

assert_not_contains() { # <file> <needle> <label>
  if grep -qF -- "$2" "$1" 2>/dev/null; then
    fail "$3 (unexpected text found in $(basename "$1"))"
  else
    pass "$3"
  fi
}

# A dump records registered commands; this checks one is there, which is how we prove that an
# extension, skill or prompt template actually loaded.
assert_registered() { # <dump dir> <name> <label>
  if grep -qF -- "\"$2\"" "$1/commands.session-start.json" 2>/dev/null; then
    pass "$3"
  else
    fail "$3 (command $2 not registered)"
  fi
}

# --------------------------------------------------------------------------------------
# steps
# --------------------------------------------------------------------------------------

check_environment() {
  section "environment"
  local tool
  for tool in pi node python3; do
    if command -v "$tool" >/dev/null 2>&1; then
      info "$tool" "$("$tool" --version 2>&1 | head -1)"
    else
      info "$tool" "MISSING"
    fi
  done
  [ -z "${PI_CODING_AGENT_DIR:-}" ] ||
    note "note: PI_CODING_AGENT_DIR is set in your shell; this test overrides it for the scratch install"
}

# The installer must be safe to run without changing anything. It is pointed at the scratch agent
# directory as well, so a dry run can never inspect (or report on) your real one.
test_dry_run() {
  section "1. install.sh --dry-run"
  export PI_CODING_AGENT_DIR="$AGENT_DIR"
  if bash "$REPO_DIR/install.sh" --dry-run >"$SCRATCH/dry-run.log" 2>&1; then
    pass "dry run exits 0"
  else
    fail "dry run exited non-zero"
  fi
  if [ -n "$(ls -A "$AGENT_DIR" 2>/dev/null)" ]; then
    fail "dry run wrote files into the agent directory"
  else
    pass "dry run wrote nothing"
  fi
  sed -n '1,14p' "$SCRATCH/dry-run.log"
}

# Prove an existing setup can receive only the new skill, and that a second run is a no-op.
test_skill_only_install() {
  section "2. install.sh --skill-only"

  mkdir -p "$SKILL_ONLY_AGENT_DIR/prompts"
  printf '%s\n' 'existing agents file' >"$SKILL_ONLY_AGENT_DIR/AGENTS.md"
  printf '%s\n' '{"existing": true}' >"$SKILL_ONLY_AGENT_DIR/settings.json"
  printf '%s\n' 'existing prompt' >"$SKILL_ONLY_AGENT_DIR/prompts/plan.md"
  cp "$SKILL_ONLY_AGENT_DIR/AGENTS.md" "$SCRATCH/expected-AGENTS.md"
  cp "$SKILL_ONLY_AGENT_DIR/settings.json" "$SCRATCH/expected-settings.json"
  cp "$SKILL_ONLY_AGENT_DIR/prompts/plan.md" "$SCRATCH/expected-plan.md"

  if PI_CODING_AGENT_DIR="$SKILL_ONLY_AGENT_DIR" \
    bash "$REPO_DIR/install.sh" --skill-only --dry-run >"$SCRATCH/skill-only-dry.log" 2>&1; then
    pass "skill-only dry run exits 0"
  else
    fail "skill-only dry run exited non-zero"
  fi
  if [ ! -e "$SKILL_ONLY_AGENT_DIR/skills/herdr-subagents/SKILL.md" ]; then
    pass "skill-only dry run wrote nothing"
  else
    fail "skill-only dry run installed the skill"
  fi

  if PI_CODING_AGENT_DIR="$SKILL_ONLY_AGENT_DIR" \
    bash "$REPO_DIR/install.sh" --skill-only >"$SCRATCH/skill-only-first.log" 2>&1; then
    pass "skill-only install exits 0"
  else
    fail "skill-only install exited non-zero"
  fi

  assert_file "$SKILL_ONLY_AGENT_DIR/skills/herdr-subagents/SKILL.md" \
    "skill-only mode installed herdr-subagents"
  if cmp -s "$REPO_DIR/skills/herdr-subagents/SKILL.md" \
    "$SKILL_ONLY_AGENT_DIR/skills/herdr-subagents/SKILL.md"; then
    pass "installed skill matches the repository"
  else
    fail "installed skill differs from the repository"
  fi
  if cmp -s "$SCRATCH/expected-AGENTS.md" "$SKILL_ONLY_AGENT_DIR/AGENTS.md" && \
    cmp -s "$SCRATCH/expected-settings.json" "$SKILL_ONLY_AGENT_DIR/settings.json" && \
    cmp -s "$SCRATCH/expected-plan.md" "$SKILL_ONLY_AGENT_DIR/prompts/plan.md"; then
    pass "skill-only mode left the existing setup untouched"
  else
    fail "skill-only mode changed an unrelated setup file"
  fi

  local before after
  before="$(cksum "$SKILL_ONLY_AGENT_DIR/skills/herdr-subagents/SKILL.md")"
  if PI_CODING_AGENT_DIR="$SKILL_ONLY_AGENT_DIR" \
    bash "$REPO_DIR/install.sh" --skill-only >"$SCRATCH/skill-only-second.log" 2>&1; then
    pass "second skill-only install exits 0"
  else
    fail "second skill-only install exited non-zero"
  fi
  after="$(cksum "$SKILL_ONLY_AGENT_DIR/skills/herdr-subagents/SKILL.md")"
  if [ "$before" = "$after" ] && grep -qF "unchanged:" "$SCRATCH/skill-only-second.log"; then
    pass "second skill-only install is unchanged"
  else
    fail "second skill-only install was not a no-op"
  fi
  if ! compgen -G "$SKILL_ONLY_AGENT_DIR/skills/herdr-subagents/*.bak.*" >/dev/null; then
    pass "identical re-install created no backup"
  else
    fail "identical re-install created an unnecessary backup"
  fi
}

test_install() {
  section "3. install.sh"
  if bash "$REPO_DIR/install.sh" >"$SCRATCH/install.log" 2>&1; then
    pass "install exits 0"
  else
    fail "install exited non-zero (see $SCRATCH/install.log)"
  fi
  tail -12 "$SCRATCH/install.log"

  assert_file "$AGENT_DIR/AGENTS.md" "global AGENTS.md installed"
  assert_file "$AGENT_DIR/prompts/plan.md" "plan template installed"
  assert_file "$AGENT_DIR/skills/brave-search/brave.mjs" "brave-search script installed"
  assert_file "$AGENT_DIR/skills/herdr-subagents/SKILL.md" "herdr-subagents skill installed"

  assert_contains "$AGENT_DIR/skills/herdr-subagents/SKILL.md" "--no-session" \
    "ephemeral mode is documented"
  assert_contains "$AGENT_DIR/skills/herdr-subagents/SKILL.md" "Leave the pane open" \
    "persistent mode preserves the child pane"
  assert_contains "$AGENT_DIR/settings.json" "\"theme\"" "settings.json merged by default"
}

show_agent_dir() {
  section "4. resulting agent directory"
  printf '\n--- default install: %s\n' "$AGENT_DIR"
  find "$AGENT_DIR" -maxdepth 2 -not -path "*/npm/*" | sort
  printf '\n--- herdr-subagents frontmatter (must be user-invoked)\n'
  head -6 "$AGENT_DIR/skills/herdr-subagents/SKILL.md"
  printf '\n--- pi list\n'
  (cd "$SCRATCH" && PI_OFFLINE=1 pi list 2>&1 | tail -4)
}

# Remove a key this test created, from both places brave.mjs can read.
cleanup_brave_key() {
  rm -f "$HOME/.config/brave-search/api_key"
  rmdir "$HOME/.config/brave-search" 2>/dev/null
  if [ "$(uname -s)" = "Darwin" ]; then
    # Only reached when no key was configured beforehand, so this cannot delete a real one.
    security delete-generic-password -s brave-search-api >/dev/null 2>&1
  fi
}

# Exercises key lookup, storage and the auth-error path without a real key.
test_brave_script() {
  section "5. brave-search script"
  local script="$AGENT_DIR/skills/brave-search/brave.mjs"
  local output

  if node "$script" keyinfo >/dev/null 2>&1; then
    pass "keyinfo runs"
  else
    fail "keyinfo did not run"
  fi

  if node "$script" keyinfo 2>&1 | grep -q "present"; then
    note "a Brave key is already configured - skipping the storage tests so your key is untouched"
    return
  fi

  if echo "dummy-token-1234567890abcd" | node "$script" setkey | grep -q "stored"; then
    pass "setkey stores a key"
  else
    fail "setkey did not store a key"
  fi

  if node "$script" keyinfo 2>&1 | grep -q "present"; then
    pass "keyinfo finds the stored key"
  else
    fail "keyinfo did not find the stored key"
  fi

  # An invalid token must fail as an auth problem, which proves the endpoint and header are right.
  output="$(node "$script" search "test query" 2>&1 || true)"
  if printf '%s' "$output" | grep -qi "rejected the subscription token"; then
    pass "an invalid token is reported as an auth failure"
  else
    fail "an invalid token produced an unexpected result: $(printf '%s' "$output" | head -1)"
  fi
  note "script said: $(printf '%s' "$output" | head -1)"

  cleanup_brave_key
  if node "$script" keyinfo 2>&1 | grep -q "not configured"; then
    pass "test key removed again"
  else
    fail "test key was left behind - remove it with: security delete-generic-password -s brave-search-api"
  fi
}

# Attach the audit harness and the project templates, so the next dump shows the full configuration.
prepare_prompt_dump() { # <agent dir>
  cp "$REPO_DIR/tools/ctx-audit.ts" "$1/extensions/ctx-audit.ts"
  cp "$REPO_DIR/templates/project/AGENTS.md" "$WORK_DIR/AGENTS.md"
  cp "$REPO_DIR/templates/project/TODO.md" "$WORK_DIR/TODO.md"
  git init -q "$WORK_DIR" 2>/dev/null
}

# Run pi once against an agent dir and dump what it assembles.
dump_prompt() { # <agent dir> <out dir>
  (cd "$WORK_DIR" &&
    PI_CODING_AGENT_DIR="$1" PI_CTX_AUDIT_DIR="$2" PI_OFFLINE=1 PI_SKIP_VERSION_CHECK=1 \
      timeout 120 pi -p "noop" >"$2.log" 2>&1)
  # pi exits non-zero without credentials; the dump is written before that check.
  [ -f "$2/system-prompt.session-start.txt" ]
}

# Report the cost of a dump and assert the expected surfaces loaded.
report_dump() { # <out dir> <label> <agents variant marker>
  local out="$1" label="$2" marker="$3"

  printf '\n--- %s\n' "$label"
  (cd "$REPO_DIR" && python3 tools/analyze.py --out "$SCRATCH" --quiet "$(basename "$out")")

  assert_file "$out/system-prompt.session-start.txt" "$label: prompt dump written"
  assert_contains "$out/system-prompt.session-start.txt" "$marker" "$label: AGENTS.md content reached the prompt"
  assert_contains "$out/system-prompt.session-start.txt" "TODO.md" "$label: TODO convention reached the prompt"
  assert_registered "$out" "plan" "$label: /plan template registered"
  assert_registered "$out" "skill:brave-search" "$label: brave-search skill registered"
  assert_registered "$out" "skill:herdr-subagents" "$label: herdr-subagents skill registered"
  assert_not_contains "$out/system-prompt.session-start.txt" \
    "Run disposable or persistent Pi agents through Herdr." \
    "$label: herdr-subagents has zero steady-state prompt cost"
}

test_default_configuration() {
  section "6. what pi assembles"
  if dump_prompt "$AGENT_DIR" "$SCRATCH/out-default"; then
    report_dump "$SCRATCH/out-default" "default install" "working agreement"
  else
    fail "no prompt dump written (see $SCRATCH/out-default.log)"
    tail -5 "$SCRATCH/out-default.log" 2>/dev/null
  fi
}

test_lean_variant() {
  section "7. the lean AGENTS.md variant"
  cp "$REPO_DIR/config/AGENTS.lean.md" "$AGENT_DIR/AGENTS.md"
  if dump_prompt "$AGENT_DIR" "$SCRATCH/out-lean"; then
    report_dump "$SCRATCH/out-lean" "lean AGENTS.md" "Real code that ships"
  else
    fail "no prompt dump written for the lean variant"
  fi
}

# --------------------------------------------------------------------------------------
# entry point
# --------------------------------------------------------------------------------------

main() {
  parse_args "$@"
  setup_scratch

  check_environment
  test_dry_run
  test_skill_only_install
  test_install
  show_agent_dir
  test_brave_script
  prepare_prompt_dump "$AGENT_DIR"
  test_default_configuration
  test_lean_variant

  finish
}

main "$@"
