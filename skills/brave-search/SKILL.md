---
name: brave-search
description: Web search and page fetching through the Brave Search API. Use when the task needs current information, external documentation, library versions, error messages, or any fact that is not in the repository - searching the web, checking docs, finding a source URL, or fetching a page as readable text.
---

# Brave search

Search the web and fetch pages as text, without any MCP server. The script is dependency-free Node.

```bash
S=~/.pi/agent/skills/brave-search/brave.mjs

node $S search "typescript 5.9 breaking changes"          # 5-20 results with snippets
node $S search "postgres partial index" --count 10 --json # raw API payload
node $S search "node 24 release notes" --freshness pm     # pd|pw|pm|py
node $S fetch https://nodejs.org/en/blog                   # readable text of a page
node $S fetch https://api.github.com/repos/nodejs/node     # JSON bodies pass through
node $S keyinfo                                            # where the key comes from (never prints it)
```

## Setup (once)

```bash
pbpaste | node ~/.pi/agent/skills/brave-search/brave.mjs setkey
```

That stores the subscription token in the macOS Keychain (service `brave-search-api`), or in
`~/.config/brave-search/api_key` with mode 0600 where no Keychain is available. Lookup order:
`$BRAVE_API_KEY`, then that file, then the Keychain. The token is never printed, logged, or included
in error output. Create a key at https://api-dashboard.search.brave.com/.

## How to use it well

- Search first, fetch second. Use `search` to find URLs and `fetch` only for the one or two pages you
  actually need - each fetch costs context.
- Prefer primary sources: official docs, the project's repository, the changelog, the RFC. Prefer a
  recent result over a stale one; check the `age` field before trusting a version number.
- When you use a result, cite it: give the URL in your answer.
- If a search returns nothing useful, reword once. Do not loop on the same query.
- In a sandboxed session only allow-listed domains are reachable (`api.search.brave.com` is on the
  list). If a fetch of another host is blocked, say which host you need and wait for approval.

## Limits

- Brave's index, not Google's. For very niche queries, try different wording before concluding the
  information does not exist.
- `fetch` returns server-rendered HTML as text. JavaScript-only pages come back mostly empty; if that
  happens, look for an API endpoint, a `llms.txt`, a raw file, or a docs page for the same content.
- The free tier is rate-limited; if you hit 429, stop searching and work with what you have.
