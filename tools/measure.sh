#!/usr/bin/env bash
# Measure one pi configuration: run pi in an isolated agent dir with the ctx-audit harness attached
# and capture everything that goes into the prefill.
#
#   tools/measure.sh <scenario> [workdir]
#
# Layout (override the root with PI_CTX_AUDIT_HOME, default ~/pi-audit):
#   $PI_CTX_AUDIT_HOME/scenarios/<scenario>/   agent dir: settings.json, npm/, skills/, ...
#   $PI_CTX_AUDIT_HOME/out/<scenario>/         dumps + run.log
#
# Typical use:
#   tools/measure.sh baseline
#   PI_CODING_AGENT_DIR=~/pi-audit/scenarios/todo pi install npm:@juicesharp/rpiv-todo
#   tools/measure.sh todo
#   tools/analyze.py
#
# No API key is needed: session_start fires before the first model call, so the dump is written even
# though the run then fails at the auth check.
set -u
# Homebrew first (Apple silicon and Intel). pi and node must be on PATH; run this from a login shell
# if they are managed by a version manager such as nvm, mise or asdf.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SCEN="${1:?usage: measure.sh <scenario> [workdir]}"
ROOT="${PI_CTX_AUDIT_HOME:-$HOME/pi-audit}"
HERE="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$ROOT/scenarios/$SCEN"
WORK="${2:-$ROOT/workdir}"
OUT="$ROOT/out/$SCEN"

mkdir -p "$AGENT_DIR/extensions" "$OUT" "$WORK"
cp -f "$HERE/ctx-audit.ts" "$AGENT_DIR/extensions/ctx-audit.ts"
[ -f "$AGENT_DIR/settings.json" ] || echo '{}' > "$AGENT_DIR/settings.json"

cd "$WORK" || exit 1
PI_CODING_AGENT_DIR="$AGENT_DIR" \
PI_CTX_AUDIT_DIR="$OUT" \
PI_OFFLINE=1 \
PI_SKIP_VERSION_CHECK=1 \
PI_TELEMETRY=0 \
timeout 120 pi -p "noop" >"$OUT/run.log" 2>&1
RC=$?
CHARS=$(wc -c < "$OUT/system-prompt.session-start.txt" 2>/dev/null || echo 0)
echo "scenario=$SCEN exit=$RC prompt_chars=$CHARS"
if [ "$CHARS" = "0" ]; then
  echo "no dump written - check $OUT/run.log"
fi
