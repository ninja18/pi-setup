/**
 * ctx-audit — measures what pi actually puts in the model's context.
 *
 * Copy into an agent dir's extensions/ (install.sh does this for the bundle's self-test), or load it
 * for a single run with `pi -e tools/ctx-audit.ts`. On session_start it writes:
 *
 *   system-prompt.session-start.txt   the assembled system prompt
 *   tools.session-start.json          every registered tool: description + JSON schema
 *   active-tools.session-start.json   the subset the model actually receives
 *   commands.session-start.json       registered slash commands (proof an extension/skill loaded)
 *   meta.session-start.json           cwd and mode
 *
 * Output goes to $PI_CTX_AUDIT_DIR, or ./ctx-audit-out when unset. session_start fires before the
 * first model call, so this works with no API key: run `pi -p "noop"`, let it fail at the auth check,
 * then read the dump.
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export default function (pi) {
	const dump = async (ctx, tag) => {
		const dir = process.env.PI_CTX_AUDIT_DIR || join(process.cwd(), "ctx-audit-out");
		mkdirSync(dir, { recursive: true });

		let prompt = "";
		try {
			prompt = ctx.getSystemPrompt();
		} catch (err) {
			prompt = `ERROR: ${String(err)}`;
		}

		let tools = [];
		try {
			tools = pi.getAllTools();
		} catch (err) {
			tools = [{ error: String(err) }];
		}

		let commands = [];
		try {
			commands = pi.getCommands();
		} catch (err) {
			commands = [{ error: String(err) }];
		}

		writeFileSync(join(dir, `system-prompt.${tag}.txt`), prompt);
		writeFileSync(join(dir, `tools.${tag}.json`), JSON.stringify(tools, null, 2));
		writeFileSync(join(dir, `active-tools.${tag}.json`), JSON.stringify(pi.getActiveTools(), null, 2));
		writeFileSync(join(dir, `commands.${tag}.json`), JSON.stringify(commands, null, 2));
		writeFileSync(join(dir, `meta.${tag}.json`), JSON.stringify({ cwd: ctx.cwd, mode: ctx.mode }, null, 2));
	};

	pi.on("session_start", async (_event, ctx) => {
		await dump(ctx, "session-start");
	});

	// Re-dump mid-session after changing tools or config: /ctx-audit
	pi.registerCommand("ctx-audit", {
		description: "Dump the current system prompt, tools and commands for context auditing",
		handler: async (_args, ctx) => {
			await dump(ctx, "on-demand");
		},
	});
}
