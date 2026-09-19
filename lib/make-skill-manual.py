#!/usr/bin/env python3
"""Make an installed skill opt-in (user-invoked only) by adding disable-model-invocation: true.

Usage: make-skill-manual.py <SKILL.md> [--check]

Why: a model-invoked skill costs its name+description in the system prompt on every request. Setting
disable-model-invocation: true removes it from the prompt (0 tokens) and leaves it available as
/skill:<name>. Exits non-zero if the file does not look like a skill.
"""
import re
import sys

path = sys.argv[1]
check_only = "--check" in sys.argv
text = open(path, encoding="utf-8").read()

m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
if not m:
    print(f"error: {path} has no YAML frontmatter block")
    sys.exit(2)
fm = m.group(1)
if "name:" not in fm or "description:" not in fm:
    print(f"error: {path} frontmatter is missing name or description")
    sys.exit(2)
name = re.search(r"^name:\s*(.+)$", fm, re.M).group(1).strip()

if re.search(r"^disable-model-invocation:\s*true\s*$", fm, re.M):
    print(f"  = {name}: already user-invoked (0 prompt tokens)")
    sys.exit(0)
if check_only:
    print(f"  ! {name}: model-invoked, would be changed")
    sys.exit(1)

new_fm = fm + "\ndisable-model-invocation: true"
patched = text[: m.start(1)] + new_fm + text[m.end(1):]
open(path, "w", encoding="utf-8").write(patched)
print(f"  + {name}: now user-invoked (0 prompt tokens), invoke with /skill:{name}")
