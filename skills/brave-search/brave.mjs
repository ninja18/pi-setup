#!/usr/bin/env node
/**
 * brave-search — Brave Search API + plain page fetch, no dependencies.
 *
 *   brave.mjs search "query" [--count 10] [--freshness pd|pw|pm|py] [--country IN] [--json]
 *   brave.mjs fetch <url> [--max-chars 12000]
 *   brave.mjs keyinfo
 *   brave.mjs setkey            # reads the key from stdin, stores it, prints nothing back
 *
 * Key lookup order:
 *   1. $BRAVE_API_KEY
 *   2. ~/.config/brave-search/api_key   (file mode 0600 recommended)
 *   3. macOS Keychain: security find-generic-password -s brave-search-api -w
 *
 * The key is never echoed, never logged, and never included in error output.
 */
import { execFileSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const KEYCHAIN_SERVICE = "brave-search-api";
const KEY_FILE = join(homedir(), ".config", "brave-search", "api_key");
const API = "https://api.search.brave.com/res/v1/web/search";

function getKey() {
	if (process.env.BRAVE_API_KEY?.trim()) return { key: process.env.BRAVE_API_KEY.trim(), source: "env BRAVE_API_KEY" };
	if (existsSync(KEY_FILE)) {
		const k = readFileSync(KEY_FILE, "utf8").trim();
		if (k) return { key: k, source: KEY_FILE };
	}
	if (process.platform === "darwin") {
		try {
			const k = execFileSync("security", ["find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"], {
				encoding: "utf8",
				stdio: ["ignore", "pipe", "ignore"],
			}).trim();
			if (k) return { key: k, source: `macOS Keychain (${KEYCHAIN_SERVICE})` };
		} catch {
			/* not stored in the keychain — fall through */
		}
	}
	return null;
}

function fail(msg, hint) {
	console.error(`error: ${msg}`);
	if (hint) console.error(`hint: ${hint}`);
	process.exit(1);
}

function parseArgs(argv) {
	const out = { positional: [], flags: {} };
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		if (a.startsWith("--")) {
			const eq = a.indexOf("=");
			if (eq > -1) out.flags[a.slice(2, eq)] = a.slice(eq + 1);
			else if (argv[i + 1] && !argv[i + 1].startsWith("--")) out.flags[a.slice(2)] = argv[++i];
			else out.flags[a.slice(2)] = true;
		} else out.positional.push(a);
	}
	return out;
}

async function readStdin() {
	const chunks = [];
	for await (const c of process.stdin) chunks.push(c);
	return Buffer.concat(chunks).toString("utf8").trim();
}

function storeKey(key) {
	if (process.platform === "darwin") {
		try {
			execFileSync("security", ["add-generic-password", "-U", "-a", process.env.USER || "user", "-s", KEYCHAIN_SERVICE, "-w", key], {
				stdio: ["ignore", "ignore", "pipe"],
			});
			console.log("stored: macOS Keychain (" + KEYCHAIN_SERVICE + ")");
			return;
		} catch (err) {
			console.log("keychain store failed, falling back to a 0600 file");
		}
	}
	mkdirSync(dirname(KEY_FILE), { recursive: true });
	writeFileSync(KEY_FILE, key + "\n", { mode: 0o600 });
	chmodSync(KEY_FILE, 0o600);
	console.log("stored: " + KEY_FILE + " (mode 0600)");
}

async function search(query, flags) {
	const found = getKey();
	if (!found) {
		fail(
			"no Brave Search API key configured",
			"run `node ~/.pi/agent/skills/brave-search/brave.mjs setkey` and paste the key on stdin, or export BRAVE_API_KEY. Get a key at https://api-dashboard.search.brave.com/",
		);
	}
	const params = new URLSearchParams({ q: query });
	if (flags.count) params.set("count", String(Math.min(Number(flags.count) || 10, 20)));
	if (flags.freshness) params.set("freshness", String(flags.freshness));
	if (flags.country) params.set("country", String(flags.country));

	let res;
	try {
		res = await fetch(`${API}?${params}`, {
			headers: {
				accept: "application/json",
				"x-subscription-token": found.key,
			},
		});
	} catch (err) {
		fail(
			`request failed: ${err?.cause?.code || err.message}`,
			"check the network and that api.search.brave.com resolves (DNS, VPN, proxy)",
		);
	}
	if (!res.ok) {
		// Brave reports an invalid token as 422 SUBSCRIPTION_TOKEN_INVALID, not 401.
		let detail = "";
		try {
			const body = await res.json();
			detail = body?.error?.detail || body?.error?.code || "";
		} catch {
			/* body was not JSON */
		}
		const code = String(detail).toUpperCase();
		if (res.status === 401 || code.includes("SUBSCRIPTION_TOKEN_INVALID") || code.includes("TOKEN")) {
			fail(`Brave rejected the subscription token (HTTP ${res.status}${detail ? `: ${detail}` : ""})`, `check the key from ${found.source} - regenerate at https://api-dashboard.search.brave.com/`);
		}
		if (res.status === 429) fail("rate limit or monthly quota reached (429)", "wait, or raise your Brave plan");
		if (res.status === 422) fail(`Brave rejected a query parameter (422${detail ? `: ${detail}` : ""})`, "check --count (1-20), --freshness (pd|pw|pm|py), --country (2-letter code)");
		fail(`Brave returned HTTP ${res.status}${detail ? `: ${detail}` : ""}`);
	}

	const data = await res.json();
	if (flags.json) {
		console.log(JSON.stringify(data, null, 2));
		return;
	}
	const results = data?.web?.results ?? [];
	console.log(`# ${query}  (${results.length} results, key from ${found.source})`);
	if (data?.web?.infobox?.description) console.log(`\ninfobox: ${data.web.infobox.description}`);
	for (const [i, r] of results.entries()) {
		console.log(`\n${i + 1}. ${r.title}\n   ${r.url}\n   ${r.age ? r.age + " · " : ""}${(r.description || "").replace(/\s+/g, " ").trim()}`);
		for (const s of (r.extra_snippets || []).slice(0, 2)) console.log(`   - ${s.replace(/\s+/g, " ").trim()}`);
	}
	if (data?.web?.results?.length === 0) console.log("\n(no web results; try different wording or a news vertical)");
}

function htmlToText(html) {
	const withoutHead = html
		.replace(/<script[\s\S]*?<\/script>/gi, " ")
		.replace(/<style[\s\S]*?<\/style>/gi, " ")
		.replace(/<noscript[\s\S]*?<\/noscript>/gi, " ")
		.replace(/<svg[\s\S]*?<\/svg>/gi, " ")
		.replace(/<!--[\s\S]*?-->/g, " ");
	const title = (html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] || "").replace(/\s+/g, " ").trim();
	const main = withoutHead.match(/<(main|article)[^>]*>([\s\S]*?)<\/\1>/i)?.[2] || withoutHead;
	const text = main
		.replace(/<\/(p|div|section|li|h[1-6]|tr|pre|blockquote)>/gi, "\n")
		.replace(/<br\s*\/?>/gi, "\n")
		.replace(/<li[^>]*>/gi, "- ")
		.replace(/<[^>]+>/g, " ")
		.replace(/&nbsp;/g, " ")
		.replace(/&amp;/g, "&")
		.replace(/&lt;/g, "<")
		.replace(/&gt;/g, ">")
		.replace(/&quot;/g, '"')
		.replace(/&#39;/g, "'")
		.replace(/[ \t]+/g, " ")
		.replace(/\n\s*\n\s*\n+/g, "\n\n")
		.trim();
	return { title, text };
}

async function fetchPage(url, flags) {
	const max = Number(flags["max-chars"] || 12000);
	let res;
	try {
		res = await fetch(url, {
			headers: {
				accept: "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
				"user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Safari/605.1.15",
			},
			redirect: "follow",
		});
	} catch (err) {
		fail(
			`fetch failed: ${err?.cause?.code || err.message}`,
			"check the network and that the host resolves (DNS, VPN, proxy)",
		);
	}
	if (!res.ok) fail(`HTTP ${res.status} for ${url}`);
	const type = res.headers.get("content-type") || "";
	const body = await res.text();
	if (type.includes("json")) {
		console.log(`# ${url}\n\n${body.slice(0, max)}`);
		return;
	}
	const { title, text } = htmlToText(body);
	console.log(`# ${title || url}\n${url}\n`);
	console.log(text.length > max ? `${text.slice(0, max)}\n\n[truncated: ${text.length - max} more characters]` : text);
}

const argv = process.argv.slice(2);
const cmd = argv.shift();
const { positional, flags } = parseArgs(argv);

if (cmd === "search") {
	if (!positional.length) fail("usage: brave.mjs search \"query\" [--count 10] [--freshness pw] [--country IN]");
	await search(positional.join(" "), flags);
} else if (cmd === "fetch") {
	if (!positional.length) fail("usage: brave.mjs fetch <url> [--max-chars 12000]");
	await fetchPage(positional[0], flags);
} else if (cmd === "setkey") {
	const key = await readStdin();
	if (!key) fail("no key on stdin", "pipe the key in: pbpaste | node brave.mjs setkey");
	if (!/^[A-Za-z0-9_-]{16,}$/.test(key)) fail("that does not look like a Brave subscription token");
	storeKey(key);
} else if (cmd === "keyinfo") {
	const found = getKey();
	console.log(found ? `key: present (from ${found.source})` : "key: not configured");
} else {
	console.error("usage: brave.mjs <search|fetch|setkey|keyinfo> [...]");
	process.exit(cmd ? 1 : 0);
}
