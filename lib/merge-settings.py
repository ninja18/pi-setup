#!/usr/bin/env python3
"""Merge bundle settings into an existing pi settings.json without losing existing keys.

Usage: merge-settings.py <target-settings.json> <bundle.json> [<bundle.json> ...]

Rules:
  - Keys from the bundles win, in the order given (they are the values this setup deliberately chose).
  - Everything else already in the target is preserved (defaultModel, defaultProvider, ...).
  - `packages` is a union across all bundles and the target, bundles first, deduplicated. That is what
    lets a package bundle live in its own file and only be merged when it is wanted.
  - The original file is copied to <target>.bak.<timestamp> when it changes.
"""
import json
import os
import shutil
import sys
import time

if len(sys.argv) < 3:
    print("usage: merge-settings.py <target-settings.json> <bundle.json> [<bundle.json> ...]")
    sys.exit(1)

target = sys.argv[1]
bundle_paths = sys.argv[2:]

new = {}
packages = []
for path in bundle_paths:
    try:
        bundle = json.load(open(path, encoding="utf-8"))
    except Exception as exc:
        print(f"  ! {path} is not readable JSON ({exc})")
        sys.exit(2)
    packages += bundle.get("packages") or []
    new = {**new, **bundle}

cur = {}
if os.path.exists(target):
    try:
        cur = json.load(open(target, encoding="utf-8"))
    except Exception as exc:
        print(f"  ! existing {target} is not valid JSON ({exc}); leaving it alone")
        sys.exit(2)

merged = {**cur, **new}
all_packages = list(dict.fromkeys(packages + (cur.get("packages") or [])))
if all_packages:
    merged["packages"] = all_packages

added = {k: v for k, v in merged.items() if k not in cur or cur[k] != v}
if not added:
    print("  = settings already up to date")
    sys.exit(0)

if os.path.exists(target):
    backup = f"{target}.bak.{time.strftime('%Y%m%d%H%M%S')}"
    shutil.copy2(target, backup)
    print(f"  backed up -> {backup}")

os.makedirs(os.path.dirname(target), exist_ok=True)
with open(target, "w", encoding="utf-8") as fh:
    json.dump(merged, fh, indent=2)
    fh.write("\n")
for k, v in added.items():
    print(f"  set {k} = {json.dumps(v)}")
