#!/usr/bin/env bash
#
# Install this pi setup into an agent directory.
#
# Safe to re-run: files that differ are backed up as <name>.bak.<timestamp>, and settings.json is
# MERGED - keys you already set (defaultModel, defaultProvider, ...) survive, while this repo's keys
# win where they overlap.
#
# The agent directory is $PI_CODING_AGENT_DIR, or ~/.pi/agent when that is unset. That is what lets
# test-bundle.sh install into a scratch directory without touching your real setup.
set -uo pipefail

# --------------------------------------------------------------------------------------
# configuration
# --------------------------------------------------------------------------------------

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"

DRY_RUN=0
SKILL_ONLY=0
SHOW_HELP=0
WARNINGS=0
ERRORS=0

# --------------------------------------------------------------------------------------
# output
# --------------------------------------------------------------------------------------

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }
ok() { printf '   ok   %s\n' "$*"; }

# Something to look at but not a failed install (a missing optional tool, say).
warn() {
  printf '   warn %s\n' "$*"
  WARNINGS=$((WARNINGS + 1))
}

# Something that makes the install not work as intended.
problem() {
  printf '   FAIL %s\n' "$*"
  ERRORS=$((ERRORS + 1))
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Install this pi setup into an agent directory.

  ./install.sh               apply the full setup
  ./install.sh --skill-only  install/update only herdr-subagents
  ./install.sh --dry-run     show what would change, touch nothing
  ./install.sh --help        this text

Reads the agent directory from $PI_CODING_AGENT_DIR (default ~/.pi/agent).
USAGE
}

# --------------------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

# Run a command, or print it when --dry-run is set.
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '   [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

# Copy a file into the agent dir, backing up whatever was there first.
install_file() { # <source> <target>
  local source="$1" target="$2"
  if [ -f "$target" ]; then
    if diff -q "$source" "$target" >/dev/null 2>&1; then
      note "unchanged: $target"
      return
    fi
    run cp "$target" "$target.bak.$(date +%Y%m%d%H%M%S)"
    note "backed up the existing $(basename "$target")"
  fi
  run cp "$source" "$target"
}

is_valid_json() { python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1; }

file_size() { wc -c <"$1" | tr -d ' '; }

# --------------------------------------------------------------------------------------
# steps
# --------------------------------------------------------------------------------------

preflight() {
  step "Preflight"

  have python3 || die "python3 is required by this installer."

  if [ "$SKILL_ONLY" = 1 ]; then
    note "mode:      herdr-subagents skill only"
    note "python3:   $(python3 --version)"
    note "agent dir: $AGENT_DIR"
    return
  fi

  have pi || die "pi is not on PATH. Install it first:
       npm install -g --ignore-scripts @earendil-works/pi-coding-agent"

  note "pi:        $(pi --version)  ($(command -v pi))"
  if have node; then note "node:      $(node --version)"; else warn "node is not on PATH"; fi
  if have rg; then
    note "ripgrep:   $(rg --version | head -1)"
  else
    note "ripgrep:   not installed (optional)"
  fi
  note "python3:   $(python3 --version)"
  note "agent dir: $AGENT_DIR"
}

create_directories() {
  step "Directories"
  run mkdir -p "$AGENT_DIR/skills" "$AGENT_DIR/prompts" "$AGENT_DIR/extensions"
  ok "$AGENT_DIR"
}

merge_settings() {
  step "settings.json (merged, never overwritten)"

  if [ -f "$AGENT_DIR/settings.json" ]; then
    run cp -n "$AGENT_DIR/settings.json" "$AGENT_DIR/settings.json.orig"
  else
    note "no existing settings.json"
  fi

  if [ "$DRY_RUN" = 1 ]; then
    note "[dry-run] would merge config/settings.json into $AGENT_DIR/settings.json"
    return
  fi

  python3 "$REPO_DIR/lib/merge-settings.py" "$AGENT_DIR/settings.json" \
    "$REPO_DIR/config/settings.json" ||
    problem "settings merge failed - your settings.json was left as it was"
}

install_agents_md() {
  step "Global AGENTS.md (the working agreement)"

  local source="$REPO_DIR/config/AGENTS.md"

  install_file "$source" "$AGENT_DIR/AGENTS.md"
  ok "$AGENT_DIR/AGENTS.md  ($(file_size "$source") bytes)"

  note "the lean variant is $(file_size "$REPO_DIR/config/AGENTS.lean.md") bytes: config/AGENTS.lean.md"
}

install_plan_template() {
  step "Plan prompt template"
  install_file "$REPO_DIR/prompts/plan.md" "$AGENT_DIR/prompts/plan.md"
  ok "/plan - 0 prompt tokens until it is used"
}

install_brave_skill() {
  step "brave-search skill"
  run mkdir -p "$AGENT_DIR/skills/brave-search"
  install_file "$REPO_DIR/skills/brave-search/SKILL.md" "$AGENT_DIR/skills/brave-search/SKILL.md"
  install_file "$REPO_DIR/skills/brave-search/brave.mjs" "$AGENT_DIR/skills/brave-search/brave.mjs"
  run chmod +x "$AGENT_DIR/skills/brave-search/brave.mjs"
  ok "$AGENT_DIR/skills/brave-search/"
  note "needs a key before first use: pbpaste | node $AGENT_DIR/skills/brave-search/brave.mjs setkey"
}

install_herdr_subagents_skill() {
  step "herdr-subagents skill (user-invoked only, 0 prompt tokens)"
  run mkdir -p "$AGENT_DIR/skills/herdr-subagents"
  install_file "$REPO_DIR/skills/herdr-subagents/SKILL.md" \
    "$AGENT_DIR/skills/herdr-subagents/SKILL.md"
  ok "$AGENT_DIR/skills/herdr-subagents/SKILL.md"
}

verify_herdr_subagents_skill() {
  local target="$AGENT_DIR/skills/herdr-subagents/SKILL.md"
  [ -f "$target" ] || {
    problem "skills/herdr-subagents/SKILL.md is missing"
    return
  }
  python3 "$REPO_DIR/lib/make-skill-manual.py" "$target" --check >/dev/null ||
    problem "herdr-subagents is not user-invoked (it must have zero steady-state prompt cost)"
}

verify_installation() {
  step "Verify"

  # A dry run writes nothing, so there is nothing to verify - checking would report every file as
  # missing and exit non-zero.
  if [ "$DRY_RUN" = 1 ]; then
    note "[dry-run] skipped: nothing was written"
    return
  fi

  local file
  for file in AGENTS.md prompts/plan.md skills/brave-search/brave.mjs; do
    [ -f "$AGENT_DIR/$file" ] || problem "$file is missing"
  done

  is_valid_json "$AGENT_DIR/settings.json" || problem "$AGENT_DIR/settings.json is not valid JSON"
  verify_herdr_subagents_skill

  [ "$ERRORS" = 0 ] && ok "all files present and valid"
}

verify_skill_only_installation() {
  step "Verify"
  if [ "$DRY_RUN" = 1 ]; then
    note "[dry-run] skipped: nothing was written"
    return
  fi
  verify_herdr_subagents_skill
  [ "$ERRORS" = 0 ] && ok "herdr-subagents is present and user-invoked"
}

report_context_cost() {
  step "Measured context cost"
  [ "$DRY_RUN" = 1 ] && return
  python3 "$REPO_DIR/tools/context-cost.py" "$AGENT_DIR" "$REPO_DIR"
}

print_next_steps() {
  cat <<NEXT

== Manual steps that remain (not scriptable)
   1. Authenticate pi:            pi   then   /login        (or export your provider API key)
   2. Save model + thinking:      /model then Ctrl+S ,  /thinking then Ctrl+S
   3. Brave key:                  pbpaste | node $AGENT_DIR/skills/brave-search/brave.mjs setkey
   4. Start a project:            cd /path/to/project && pi
      - approve the project-trust prompt once, or run /trust
      - copy the project templates in and fill in the commands:
          cp $REPO_DIR/templates/project/AGENTS.md /path/to/project/AGENTS.md
          cp $REPO_DIR/templates/project/TODO.md   /path/to/project/TODO.md
   5. Herdr (for subagents):      brew install herdr && herdr
      - Herdr -> Settings -> Integrations -> install the Pi integration
      - verify with: herdr integration status
      - invoke from Pi with: /skill:herdr-subagents

== Next
   ./test-bundle.sh          self-test: what pi assembles and what it costs
   tools/measure.sh <name>   measure any other package before adopting it
   DESIGN.md                 why these choices, the numbers, and what was left out
NEXT

  if [ "$WARNINGS" != 0 ] || [ "$ERRORS" != 0 ]; then
    say ""
    say "$ERRORS failure(s), $WARNINGS warning(s) - see the FAIL and warn lines above."
  fi
}

print_skill_only_next_steps() {
  cat <<NEXT

== Installed
   /skill:herdr-subagents
   - ephemeral mode: pi --no-session, capture result, close the child pane
   - persistent mode: named Pi session, leave the child pane open for follow-ups

   Requires Pi to be running inside Herdr with the Pi integration installed.
NEXT
}

# --------------------------------------------------------------------------------------
# entry point
# --------------------------------------------------------------------------------------

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --skill-only) SKILL_ONLY=1 ;;
      -h | --help) SHOW_HELP=1 ;;
      *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  if [ "$SHOW_HELP" = 1 ]; then
    usage
    exit 0
  fi

  preflight

  if [ "$SKILL_ONLY" = 1 ]; then
    install_herdr_subagents_skill
    verify_skill_only_installation
    print_skill_only_next_steps
    [ "$ERRORS" = 0 ] || exit 2
    return
  fi

  create_directories
  merge_settings
  install_agents_md
  install_plan_template
  install_brave_skill
  install_herdr_subagents_skill
  verify_installation
  report_context_cost
  print_next_steps

  [ "$ERRORS" = 0 ] || exit 2
}

main "$@"
