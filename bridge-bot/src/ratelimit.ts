import type { Bot } from "grammy";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * Telegram answers 429 with `retry_after` seconds when a bot sends too much to one chat (about 20 messages a minute per group,
 * shared by all its Topics). This waits that long and sends again. The "blocked until" time is kept per bot, so while one bot is
 * told to wait, every room using that bot waits too instead of making it worse. A wait longer than `maxWaitS` is not slept off:
 * the 429 is returned to the caller (the outbox poller keeps its own retry count).
 */
export function guardApi(api: Bot["api"], label: string, maxWaitS = Number(process.env.MAX_RETRY_AFTER_S ?? "120")): Bot["api"] {
  let blockedUntil = 0;
  api.config.use(async (prev, method, payload, signal) => {
    for (let attempt = 0; ; attempt++) {
      const wait = blockedUntil - Date.now();
      if (wait > 0) await sleep(wait);
      const res = await prev(method, payload, signal);
      if (res.ok || res.error_code !== 429 || attempt >= 4) return res;
      const secs = res.parameters?.retry_after ?? 5;
      if (secs > maxWaitS) return res;
      blockedUntil = Math.max(blockedUntil, Date.now() + secs * 1000 + 250);
      console.warn(`[${label}] Telegram asked to wait ${secs}s (429 on ${method}); waiting, then retrying`);
    }
  });
  return api;
}
