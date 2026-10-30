/**
 * session-namer — ручные и «агентские» имена сессий.
 *
 * Встроенное в pi:
 *   /name <имя>                 задать имя вручную
 *   Ctrl+R в /resume / pi -r    переименовать в списке сессий
 *
 * Это расширение добавляет:
 *   name_session                инструмент, который вызывает сама модель (агент сам называет сессию)
 *   /autoname [подсказка]       попросить модель придумать имя по диалогу и применить его
 *   pi --auto-name              автоименование после первого хода (если имя ещё не задано)
 *
 * Дешёвую модель для нейминга можно задать явно: PI_NAMER_MODEL="provider/modelId"
 * (например PI_NAMER_MODEL="google/gemini-2.5-flash"), иначе используется текущая модель сессии.
 */

import { complete } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const MAX_NAME_CHARS = 64;

function cleanName(raw: string): string {
	return raw
		.replace(/^[\s"'`“”«]+|[\s"'`“”«»]+$/g, "")
		.replace(/^(name|session name|имя)\s*[:—-]\s*/i, "")
		.replace(/\s+/g, " ")
		.replace(/[.!?]+$/g, "")
		.slice(0, MAX_NAME_CHARS)
		.trim();
}

/** Краткая выжимка из первых пользовательских сообщений — дешёвый вход для нейминга. */
function conversationDigest(ctx: ExtensionContext, maxChars = 1600): string {
	const parts: string[] = [];
	let total = 0;
	for (const entry of ctx.sessionManager.getBranch() as Array<any>) {
		if (entry.type !== "message") continue;
		const msg = entry.message;
		if (!msg || msg.role === "toolResult") continue;
		const text = Array.isArray(msg.content)
			? msg.content
					.filter((c: any) => c.type === "text")
					.map((c: any) => c.text)
					.join(" ")
			: typeof msg.content === "string"
				? msg.content
				: "";
		const trimmed = text.trim();
		if (!trimmed || trimmed.startsWith("/")) continue;
		const snippet = trimmed.slice(0, 400);
		parts.push(`${msg.role}: ${snippet}`);
		total += snippet.length;
		if (total >= maxChars) break;
	}
	return parts.join("\n---\n").slice(0, maxChars);
}

async function generateName(pi: ExtensionAPI, ctx: ExtensionContext, hint: string): Promise<string | undefined> {
	const env = process.env.PI_NAMER_MODEL;
	let model = ctx.model;
	if (env) {
		const [provider, ...rest] = env.split("/");
		const found = ctx.modelRegistry.find(provider, rest.join("/"));
		if (found) model = found;
	}
	if (!model) return undefined;

	const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
	if (!auth.ok || !auth.apiKey) {
		ctx.ui.notify(`Нет ключа для ${model.provider}/${model.id}: ${auth.ok ? "пустой ключ" : auth.error}`, "warning");
		return undefined;
	}

	const digest = conversationDigest(ctx);
	if (!digest) return undefined;

	const prompt = `Придумай короткое имя (3–6 слов, ${MAX_NAME_CHARS} символов максимум) для этой рабочей сессии.
Формат: одна строка, без кавычек, без точки в конце, без префикса "Name:". Язык — язык запроса пользователя.
Суть диалога:
${digest}
${hint ? `Дополнительная подсказка пользователя: ${hint}` : ""}`;

	const response = await complete(
		model,
		{ messages: [{ role: "user", content: [{ type: "text", text: prompt }], timestamp: Date.now() }] },
		{ apiKey: auth.apiKey, headers: auth.headers, maxTokens: 64, signal: ctx.signal },
	);

	const text = response.content
		.filter((c): c is { type: "text"; text: string } => c.type === "text")
		.map((c) => c.text)
		.join("\n");
	return cleanName(text);
}

export default function (pi: ExtensionAPI) {
	// 1. Инструмент для самой модели: агент сам называет сессию.
	pi.registerTool({
		name: "name_session",
		label: "Name session",
		description: "Set the display name of the current session (shown in /resume and the footer).",
		promptSnippet: "Set the current session's display name",
		promptGuidelines: [
			"Use name_session once near the start of a task to give the session a short descriptive name (3-6 words), and again if the task changes scope.",
			"Use name_session instead of /name; never ask the user to name the session for you.",
		],
		parameters: Type.Object({
			name: Type.String({ description: "Short session name, 3-6 words" }),
		}),
		async execute(_id, params, _signal, _onUpdate, ctx) {
			const name = cleanName(params.name);
			if (!name) return { content: [{ type: "text", text: "Empty name, ignored" }], details: {} };
			pi.setSessionName(name);
			return { content: [{ type: "text", text: `Session named: ${name}` }], details: { name } };
		},
	});

	// 2. Ручной запуск генерации имени.
	pi.registerCommand("autoname", {
		description: "Generate and apply a session name from the conversation (optional hint)",
		handler: async (args, ctx) => {
			const old = pi.getSessionName();
			const name = await generateName(pi, ctx, args.trim());
			if (!name) {
				ctx.ui.notify("Не удалось сгенерировать имя (нет диалога / нет модели или ключа)", "warning");
				return;
			}
			pi.setSessionName(name);
			ctx.ui.notify(`Сессия: ${old ? `${old} → ` : ""}${name}`, "info");
		},
	});

	// 3. Автоименование: pi --auto-name
	pi.registerFlag("auto-name", { description: "Name the session automatically after the first turn", type: "boolean", default: false });

	let named = false;
	pi.on("session_start", () => {
		named = false;
	});
	pi.on("agent_end", async (_event, ctx) => {
		if (!pi.getFlag("auto-name") || named) return;
		if (pi.getSessionName()) {
			named = true;
			return;
		}
		const name = await generateName(pi, ctx, "");
		if (name) {
			pi.setSessionName(name);
			named = true;
			ctx.ui.notify(`Сессия названа: ${name}`, "info");
		}
	});
}
