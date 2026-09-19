#!/usr/bin/env python3
"""Summarise ctx-audit dumps: what each pi configuration costs per request.

    tools/analyze.py                     # every scenario found under $PI_CTX_AUDIT_HOME/out
    tools/analyze.py baseline todo lens  # selected scenarios
    PI_CTX_AUDIT_HOME=/tmp/x tools/analyze.py

Methodology (see DESIGN.md for why these rules matter):

  tokens   = ceil(chars / 4), pi's own estimator (estimateTokens in core/compaction)
  prompt   = the assembled system prompt, which already includes the one-line snippets for active
             tools, tools' prompt guidelines, the skills catalogue and any AGENTS.md content
  tools    = ACTIVE tools only (a bare pi registers 8 files and activates 4 - counting the registered
             set inflates every scenario), each costed as name + description + JSON schema
  prefill  = prompt + active tool schemas; this is what is re-sent on every request
"""
import argparse
import json
import math
import os
import sys


def tok(chars: int) -> int:
    return math.ceil(chars / 4)


def tool_cost(t: dict) -> dict:
    name = t.get("name", "?")
    desc = t.get("description") or ""
    schema = json.dumps(t.get("parameters") or {}, separators=(",", ":"))
    return {
        "name": name,
        "desc_chars": len(desc),
        "schema_chars": len(schema),
        "total_chars": len(name) + len(desc) + len(schema),
        "tokens": tok(len(name) + len(desc) + len(schema)),
    }


def analyze(out_root: str, scen: str) -> dict:
    d = os.path.join(out_root, scen)
    res = {"scenario": scen, "system_prompt_tokens": None, "tool_total_tokens": None}

    prompt_path = os.path.join(d, "system-prompt.session-start.txt")
    if os.path.exists(prompt_path):
        text = open(prompt_path, encoding="utf-8").read()
        res["system_prompt_chars"] = len(text)
        res["system_prompt_tokens"] = tok(len(text))

    def load(name, default):
        p = os.path.join(d, name)
        try:
            return json.load(open(p, encoding="utf-8"))
        except Exception:
            return default

    active = set(load("active-tools.session-start.json", []))
    all_tools = load("tools.session-start.json", [])
    per = [tool_cost(t) for t in all_tools if isinstance(t, dict) and t.get("name") in active]
    res["active_tool_count"] = len(per)
    res["registered_tool_count"] = len([t for t in all_tools if isinstance(t, dict) and t.get("name")])
    res["tool_total_chars"] = sum(x["total_chars"] for x in per)
    res["tool_total_tokens"] = sum(x["tokens"] for x in per)
    res["tools"] = sorted(per, key=lambda x: -x["tokens"])
    res["active_tools"] = sorted(active)
    res["commands"] = [c.get("name") for c in load("commands.session-start.json", []) if isinstance(c, dict)]

    if res["system_prompt_tokens"] is not None:
        res["prefill_tokens"] = res["system_prompt_tokens"] + res["tool_total_tokens"]
    return res


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("scenarios", nargs="*", help="scenario names (default: everything measured)")
    ap.add_argument("--out", default=os.path.join(os.environ.get("PI_CTX_AUDIT_HOME", os.path.expanduser("~/pi-audit")), "out"))
    ap.add_argument("--json", action="store_true", help="print the raw JSON instead of tables")
    ap.add_argument("--detail", action="store_true", help="always print the per-tool breakdown")
    ap.add_argument("--quiet", action="store_true", help="summary table only, no per-tool detail")
    args = ap.parse_args()

    if not os.path.isdir(args.out):
        print(f"no measurements at {args.out} - run tools/measure.sh <scenario> first", file=sys.stderr)
        return 1

    scens = args.scenarios or sorted(d for d in os.listdir(args.out) if os.path.isdir(os.path.join(args.out, d)))
    rows = [analyze(args.out, s) for s in scens]

    if args.json:
        print(json.dumps(rows, indent=2))
        return 0

    base = next((r for r in rows if r["scenario"] == "baseline"), None)
    print(f"{'scenario':<16}{'prompt tok':>11}{'tools':>7}{'tool tok':>10}{'prefill':>9}{'vs bare':>9}")
    for r in rows:
        delta = ""
        if base and base.get("prefill_tokens") and r.get("prefill_tokens"):
            delta = f"{r['prefill_tokens'] - base['prefill_tokens']:+d}"
        print(
            f"{r['scenario']:<16}{str(r['system_prompt_tokens']):>11}{str(r['active_tool_count']):>7}"
            f"{str(r['tool_total_tokens']):>10}{str(r.get('prefill_tokens')):>9}{delta:>9}"
        )

    for r in rows:
        if args.quiet:
            continue
        if args.detail or r["scenario"] != "baseline":
            print(f"\n--- {r['scenario']}  (prefill {r.get('prefill_tokens')} tokens)")
            print(f"    active tools: {', '.join(r['active_tools']) or '(none)'}")
            ext = [c for c in r["commands"] if c]
            if ext:
                print(f"    commands: {', '.join(sorted(ext))}")
            for t in r["tools"][:10]:
                print(f"      {t['name']:<30}{t['tokens']:>6}   (desc {t['desc_chars']}, schema {t['schema_chars']})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
