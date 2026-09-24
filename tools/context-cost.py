#!/usr/bin/env python3
"""Print the context cost of the files an install put in place.

    tools/context-cost.py <agent-dir> <repo-dir>

Used by install.sh after a successful install, and useful on its own to see what a change to
AGENTS.md or a skill actually costs. Sizes are converted with pi's own estimator, ceil(chars / 4).
"""
import math
import os
import sys


def tokens(path: str) -> int:
    return math.ceil(os.path.getsize(path) / 4) if os.path.exists(path) else 0


def row(label: str, path: str, note: str) -> None:
    if os.path.exists(path):
        print(f"   {label:<26}{tokens(path):>6} tokens  {note}")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    agent, repo = sys.argv[1], sys.argv[2]

    print("   paid on every request:")
    row("global AGENTS.md", f"{agent}/AGENTS.md", "the one line item worth watching")
    row("  lean variant would be", f"{repo}/config/AGENTS.lean.md",
        "swap in: cp config/AGENTS.lean.md ~/.pi/agent/AGENTS.md")
    print("   free until used:")
    row("brave-search skill", f"{agent}/skills/brave-search/SKILL.md",
        "only its description is in the prompt; the body loads on use")
    row("herdr-subagents skill", f"{agent}/skills/herdr-subagents/SKILL.md",
        "user-invoked: 0 in the prompt, body loads on /skill:herdr-subagents")
    row("plan template", f"{agent}/prompts/plan.md", "0 in the prompt, expands on /plan")
    print("   measured end to end with: ./test-bundle.sh")
    return 0


if __name__ == "__main__":
    sys.exit(main())
