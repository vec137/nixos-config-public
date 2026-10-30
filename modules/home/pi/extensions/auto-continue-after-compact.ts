/**
 * auto-continue-after-compact.ts
 *
 * После компакта (авто-компакт по порогу контекста или ручной /compact)
 * pi останавливается и ждёт ввода. Эта extension сама отправляет агенту
 * сообщение-продолжение, чтобы работа шла дальше без нажатий.
 *
 * Положить в ~/.pi/agent/extensions/ (глобально) или .pi/extensions/ (проект).
 * Отключить на время: /toggle-auto-continue
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const CONTINUE_PROMPT =
	"Context was just compacted. Resume the task from the compaction summary: " +
	"pick the next unfinished step and continue working. " +
	"If everything asked for is already done, say so briefly and stop.";

const MAX_CHAINED_CONTINUES = 3; // защита от цикла compact -> continue -> compact

export default function (pi: ExtensionAPI) {
	let enabled = true;
	let compactPending = false;
	let chained = 0;

	pi.on("session_before_compact", () => {
		compactPending = true;
	});

	pi.on("session_compact", () => {
		if (!compactPending || !enabled) return;
		compactPending = false;
		if (chained >= MAX_CHAINED_CONTINUES) return;
		chained++;

		// Откладываем: session_compact приходит внутри цикла компакта,
		// новый промпт должен стартовать уже после того, как стек развернётся.
		setTimeout(() => {
			try {
				pi.sendUserMessage(CONTINUE_PROMPT, { deliverAs: "followUp" });
			} catch {
				/* агент мог уйти в другую сессию */
			}
		}, 0);
	});

	// Пользователь что-то набрал -> цепочка продолжений сброшена
	pi.on("input", (event) => {
		if (event.source === "interactive") chained = 0;
	});

	pi.registerCommand("toggle-auto-continue", {
		description: "Вкл/выкл авто-продолжение после компакта",
		handler: async (_args, ctx) => {
			enabled = !enabled;
			chained = 0;
			await ctx.ui.notify(`auto-continue after compact: ${enabled ? "on" : "off"}`, "info");
		},
	});
}
