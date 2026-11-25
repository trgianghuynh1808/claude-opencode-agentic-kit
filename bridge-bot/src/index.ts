import { Bot, InlineKeyboard, InputFile, type Context } from "grammy";
import { promises as fs } from "node:fs";
import path from "node:path";
import net from "node:net";
import { execFile } from "node:child_process";

// ---------- config ----------
const BOT_TOKEN = process.env.BOT_TOKEN ?? "";
const ADMIN_USER_ID = Number(process.env.ADMIN_USER_ID ?? "");
const CHAT_ID = Number(process.env.TELEGRAM_CHAT_ID ?? "");
const ROOMS_FILE = path.resolve(process.env.ROOMS_FILE ?? "rooms.json");
const POLL_MS = Number(process.env.POLL_MS ?? "2000");
const MAX_ATTEMPTS = 3;
const COMMANDS = new Set(["auto", "status", "stop", "resume", "ship", "health"]);

if (!BOT_TOKEN) {
  console.error("Set BOT_TOKEN (see .env.example).");
  process.exit(1);
}
// Discovery mode: without ADMIN_USER_ID/TELEGRAM_CHAT_ID the bot only replies with the ids to copy into .env.
const DISCOVERY = !ADMIN_USER_ID || !CHAT_ID || !Number.isFinite(ADMIN_USER_ID) || !Number.isFinite(CHAT_ID);

interface Room { topicId: number; name: string; path: string }
type Role = "manager" | "techlead" | "dev";
interface OutboxMessage { text?: string; images?: string[]; requires?: string; from?: Role }

const ROLE_LABEL: Record<Role, string> = { manager: "🧭 Manager", techlead: "🛠 Tech Lead", dev: "⌨️ Senior Dev" };

// ---------- helpers ----------
async function loadRooms(): Promise<Room[]> {
  try {
    const data = JSON.parse(await fs.readFile(ROOMS_FILE, "utf8"));
    return Array.isArray(data.rooms) ? data.rooms : [];
  } catch (err) {
    console.error(`Cannot read ${ROOMS_FILE}:`, (err as Error).message);
    return [];
  }
}

async function writeAtomic(file: string, content: string): Promise<void> {
  await fs.mkdir(path.dirname(file), { recursive: true });
  const tmp = `${file}.tmp`;
  await fs.writeFile(tmp, content);
  await fs.rename(tmp, file);
}

async function writeInbox(room: Room, payload: Record<string, unknown>): Promise<string> {
  const ts = Date.now();
  const name = `${ts}-${Math.random().toString(36).slice(2, 6)}.json`;
  await writeAtomic(path.join(room.path, ".agents", "inbox", name), JSON.stringify({ ts, ...payload }, null, 2));
  return name;
}

// Inbox files waiting for the Manager: when one lands in processed/ or failed/, react on the user's message.
// In memory only: after a bridge restart the 👀 stays on messages that were still pending.
const pendingReactions = new Map<string, { room: Room; messageId: number }>();
type Emoji = Parameters<typeof bot.api.setMessageReaction>[2] extends infer R ? R extends Array<{ emoji: infer E }> ? E : never : never;

async function react(messageId: number, emoji: string): Promise<void> {
  await bot.api
    .setMessageReaction(CHAT_ID, messageId, [{ type: "emoji", emoji: emoji as Emoji }])
    .catch((err) => console.error("reaction failed:", (err as Error).message));
}

async function pollReactions(): Promise<void> {
  for (const [key, { room, messageId }] of pendingReactions) {
    const inbox = path.join(room.path, ".agents", "inbox");
    const name = path.basename(key);
    const exists = (dir: string) => fs.stat(path.join(inbox, dir, name)).then(() => true, () => false);
    if (await exists("processed")) { await react(messageId, "👍"); pendingReactions.delete(key); }
    else if (await exists("failed")) { await react(messageId, "👎"); pendingReactions.delete(key); }
  }
}

function isAdmin(ctx: Context): boolean {
  return ctx.from?.id === ADMIN_USER_ID && ctx.chat?.id === CHAT_ID;
}

function chunk(text: string, size = 4000): string[] {
  const out: string[] = [];
  for (let i = 0; i < text.length; i += size) out.push(text.slice(i, i + size));
  return out.length ? out : [""];
}

/** Resolve an image path from an outbox file; it must stay inside the room directory. */
function safeImage(room: Room, rel: string): string | null {
  const abs = path.resolve(room.path, rel);
  return abs.startsWith(path.resolve(room.path) + path.sep) ? abs : null;
}


// ---------- /health: deterministic checks, no Claude call ----------
const run = (cmd: string, args: string[], cwd?: string) =>
  new Promise<{ ok: boolean; out: string }>((resolve) =>
    execFile(cmd, args, { cwd, timeout: 8000 }, (err, stdout, stderr) =>
      resolve({ ok: !err, out: (stdout || stderr || String(err?.message ?? "")).trim().split("\n")[0] })));

async function pidAlive(file: string): Promise<number | null> {
  try {
    const pid = Number((await fs.readFile(file, "utf8")).trim());
    if (!pid) return null;
    process.kill(pid, 0);
    return pid;
  } catch { return null; }
}

const portOpen = (port: number) =>
  new Promise<boolean>((resolve) => {
    const sock = net.connect({ port, host: "127.0.0.1", timeout: 1500 });
    sock.once("connect", () => { sock.destroy(); resolve(true); });
    sock.once("error", () => resolve(false));
    sock.once("timeout", () => { sock.destroy(); resolve(false); });
  });

async function readEnv(file: string): Promise<Record<string, string>> {
  const out: Record<string, string> = {};
  try {
    for (const line of (await fs.readFile(file, "utf8")).split("\n")) {
      const m = line.match(/^([A-Z_]+)="?([^"]*)"?\s*$/);
      if (m) out[m[1]] = m[2];
    }
  } catch { /* no room.env */ }
  return out;
}

async function health(room: Room): Promise<string> {
  const ag = path.join(room.path, ".agents");
  const env = await readEnv(path.join(ag, "room.env"));
  const lines: string[] = [];
  const problems: string[] = [];
  const ok = (m: string) => lines.push(`✅ ${m}`);
  const bad = (m: string, why: string) => { lines.push(`❌ ${m}`); problems.push(why); };
  const warn = (m: string) => lines.push(`⚠️ ${m}`);

  ok("Bridge (đang trả lời bạn)");

  for (const [role, token, label] of [["techlead", process.env.BOT_TOKEN_TECHLEAD, "Bot Tech Lead"], ["dev", process.env.BOT_TOKEN_DEV, "Bot Senior Dev"]] as const) {
    if (!token) { warn(`${label}: dùng bot chính (chưa có token riêng)`); continue; }
    try { const me = await roleApis[role].getMe(); ok(`${label}: @${me.username}`); }
    catch (e) { warn(`${label}: token lỗi (${(e as Error).message}) — tin của vai này sẽ không gửi được`); }
  }

  const mgr = await pidAlive(path.join(ag, "manager.lock"));
  mgr ? ok(`Manager daemon (pid ${mgr})`) : bad("Manager daemon không chạy", "Manager daemon (agent-room.sh start)");
  const wat = await pidAlive(path.join(ag, "watcher.pid"));
  wat ? ok(`Senior Dev watcher / OpenCode (pid ${wat})`) : bad("Senior Dev watcher không chạy", "watcher OpenCode (agent-room.sh start)");

  const cl = await run("claude", ["--version"]);
  cl.ok ? ok(`claude ${cl.out}`) : bad("claude CLI không chạy được", "claude CLI");
  const oc = await run("opencode", ["--version"]);
  oc.ok ? ok(`opencode ${oc.out}`) : bad("opencode CLI không chạy được", "opencode CLI");

  const br = await run("git", ["rev-parse", "--abbrev-ref", "HEAD"], room.path);
  const dirty = await run("git", ["status", "--porcelain"], room.path);
  const n = dirty.out ? (await run("sh", ["-c", "git status --porcelain | wc -l"], room.path)).out.trim() : "0";
  if (!br.ok) bad("Không phải git repo", "git repo");
  else if (n !== "0") warn(`Git: nhánh ${br.out}, ${n} file chưa commit — hand-off sẽ bị chặn`), problems.push("cây git dơ");
  else ok(`Git: nhánh ${br.out}, sạch`);

  const port = Number(env.APP_PORT);
  if (port) (await portOpen(port)) ? ok(`Dev server :${port}`) : warn(`Dev server :${port} chưa chạy (chỉ cần khi Verify trên trình duyệt)`);

  lines.push("", `AUTO_MODE=${env.AUTO_MODE ?? "?"} · nhánh nền ${env.STAGING_BRANCH ?? "staging"}`);
  lines.push(problems.length ? `❌ Chưa sẵn sàng: ${problems.join(", ")}` : "✅ Sẵn sàng nhận task");
  return `🩺 Health · ${room.name}\n${lines.join("\n")}`;
}

// ---------- inbound: Telegram -> .agents/inbox ----------
const bot = new Bot(BOT_TOKEN);

// Optional extra identities. They only send (never poll); without a token the role falls back to the main bot.
const roleApis: Record<Role, Bot["api"]> = {
  manager: bot.api,
  techlead: process.env.BOT_TOKEN_TECHLEAD ? new Bot(process.env.BOT_TOKEN_TECHLEAD).api : bot.api,
  dev: process.env.BOT_TOKEN_DEV ? new Bot(process.env.BOT_TOKEN_DEV).api : bot.api,
};

if (DISCOVERY) {
  bot.on("message", async (ctx) => {
    const info = `ADMIN_USER_ID=${ctx.from?.id}\nTELEGRAM_CHAT_ID=${ctx.chat.id}\nTopic ID (message_thread_id)=${ctx.message.message_thread_id ?? "none (General)"}`;
    console.log(info);
    await ctx.reply(info, { message_thread_id: ctx.message.message_thread_id });
  });
}

bot.on("message:text", async (ctx) => {
  if (DISCOVERY) return;
  if (!isAdmin(ctx)) {
    console.warn(`Ignored message: from.id=${ctx.from?.id} chat.id=${ctx.chat?.id} (expected ADMIN_USER_ID=${ADMIN_USER_ID}, TELEGRAM_CHAT_ID=${CHAT_ID})`);
    return;
  }
  const topicId = ctx.message.message_thread_id;
  if (topicId === undefined) {
    await ctx.reply("Hãy nhắn trong một Topic của project (General không có phòng).");
    return;
  }
  const room = (await loadRooms()).find((r) => r.topicId === topicId);
  if (!room) {
    await ctx.reply(`Topic ${topicId} chưa đăng ký. Chạy scripts/agent-room.sh init --topic ${topicId} --port <PORT> trong project.`);
    return;
  }

  const text = ctx.message.text;
  const m = text.match(/^\/([a-z_]+)(?:@\w+)?(?:\s+([\s\S]*))?$/i);
  const command = m && COMMANDS.has(m[1].toLowerCase()) ? `/${m[1].toLowerCase()}` : null;
  if (command === "/health") {
    await ctx.reply(await health(room), { message_thread_id: topicId });
    return;
  }
  if (m && !command) {
    await ctx.reply("Lệnh hợp lệ: /auto <checklist>, /status, /stop, /resume, /ship, /health");
    return;
  }
  if (command === "/auto" && !m?.[2]?.trim()) {
    await ctx.reply("Cách dùng: /auto <checklist> (mỗi dòng một việc).");
    return;
  }

  const file = await writeInbox(room, { from: ctx.from?.id, command, args: command ? (m?.[2] ?? "").trim() : "", text });
  pendingReactions.set(`${room.path}/${file}`, { room, messageId: ctx.message.message_id });
  await react(ctx.message.message_id, "👀");
});

bot.on("callback_query:data", async (ctx) => {
  if (ctx.from.id !== ADMIN_USER_ID) return void (await ctx.answerCallbackQuery());
  const [action, topic] = ctx.callbackQuery.data.split(":");
  const room = (await loadRooms()).find((r) => r.topicId === Number(topic));
  if (!room || (action !== "ship" && action !== "keep")) return void (await ctx.answerCallbackQuery("Không hợp lệ"));
  await writeInbox(room, { from: ctx.from.id, command: action === "ship" ? "/ship" : "/stop", args: "", text: "" });
  await ctx.answerCallbackQuery(action === "ship" ? "Đã gửi /ship" : "Đã giữ lại");
  await ctx.editMessageReplyMarkup({ reply_markup: undefined }).catch(() => undefined);
});

// ---------- outbound: .agents/outbox -> Telegram ----------
const attempts = new Map<string, number>();

async function sendOutbox(room: Room, msg: OutboxMessage): Promise<void> {
  // Ship buttons are answered by the main bot, so a message that needs approval always comes from the manager.
  const role: Role = msg.requires ? "manager" : (msg.from && msg.from in ROLE_LABEL ? msg.from : "manager");
  const api = roleApis[role];
  const opts = { message_thread_id: room.topicId } as const;
  const title = `${ROLE_LABEL[role]} · ${room.name}`;
  const images = (msg.images ?? []).map((p) => safeImage(room, p)).filter((p): p is string => p !== null);
  const existing: string[] = [];
  for (const p of images) if (await fs.stat(p).then((s) => s.isFile()).catch(() => false)) existing.push(p);

  const keyboard = msg.requires === "APPROVE_SHIP"
    ? new InlineKeyboard().text("✅ Ship", `ship:${room.topicId}`).text("⏸ Giữ lại", `keep:${room.topicId}`)
    : undefined;

  const parts = chunk(`${title}\n${msg.text ?? ""}`);
  for (let i = 0; i < parts.length; i++) {
    const last = i === parts.length - 1 && existing.length === 0;
    await api.sendMessage(CHAT_ID, parts[i], { ...opts, ...(last && keyboard ? { reply_markup: keyboard } : {}) });
  }
  if (existing.length === 1) {
    await api.sendPhoto(CHAT_ID, new InputFile(existing[0]), { ...opts, ...(keyboard ? { reply_markup: keyboard } : {}) });
  } else if (existing.length > 1) {
    for (let i = 0; i < existing.length; i += 10) {
      await api.sendMediaGroup(CHAT_ID, existing.slice(i, i + 10).map((p) => ({ type: "photo" as const, media: new InputFile(p) })), opts);
    }
    if (keyboard) await api.sendMessage(CHAT_ID, "Duyệt ship?", { ...opts, reply_markup: keyboard });
  }
}

async function pollRoom(room: Room): Promise<void> {
  const dir = path.join(room.path, ".agents", "outbox");
  let names: string[];
  try { names = (await fs.readdir(dir)).filter((n) => n.endsWith(".json")).sort(); } catch { return; }
  for (const name of names) {
    const file = path.join(dir, name);
    try {
      const msg = JSON.parse(await fs.readFile(file, "utf8")) as OutboxMessage;
      await sendOutbox(room, msg);
      await fs.mkdir(path.join(dir, "sent"), { recursive: true });
      await fs.rename(file, path.join(dir, "sent", name));
      attempts.delete(file);
    } catch (err) {
      const n = (attempts.get(file) ?? 0) + 1;
      attempts.set(file, n);
      console.error(`[${room.name}] send ${name} failed (${n}/${MAX_ATTEMPTS}):`, (err as Error).message);
      if (n >= MAX_ATTEMPTS) {
        await fs.mkdir(path.join(dir, "failed"), { recursive: true });
        await fs.rename(file, path.join(dir, "failed", name)).catch(() => undefined);
        attempts.delete(file);
      }
      break; // keep order: retry this file next tick before sending later ones
    }
  }
}

let polling = false;
if (!DISCOVERY) setInterval(async () => {
  if (polling) return;
  polling = true;
  try {
    for (const room of await loadRooms()) await pollRoom(room);
    await pollReactions();
  } finally { polling = false; }
}, POLL_MS);

bot.catch((err) => console.error("bot error:", err.message));

// Register the command menu shown when typing "/" (only the main bot receives commands).
if (!DISCOVERY) {
  const menu = [
    { command: "auto", description: "Giao việc: /auto <checklist>, mỗi dòng một task" },
    { command: "status", description: "Xem board và tiến độ" },
    { command: "health", description: "Kiểm tra mọi agent có đang chạy không" },
    { command: "stop", description: "Tắt AUTO_MODE, dừng nhận task mới" },
    { command: "resume", description: "Chạy tiếp sau khi dừng hoặc bị kẹt" },
    { command: "ship", description: "Merge staging vào main và push" },
  ];
  for (const scope of [{ type: "default" as const }, { type: "all_group_chats" as const }, { type: "chat" as const, chat_id: CHAT_ID }]) {
    bot.api.setMyCommands(menu, { scope }).catch((err) => console.error("setMyCommands failed:", (err as Error).message));
  }
}
console.log(`ADMIN_USER_ID=${ADMIN_USER_ID} TELEGRAM_CHAT_ID=${CHAT_ID}`);
console.log(`Identities: manager=main, techlead=${process.env.BOT_TOKEN_TECHLEAD ? "own bot" : "main bot (label)"}, dev=${process.env.BOT_TOKEN_DEV ? "own bot" : "main bot (label)"}`);
console.log(DISCOVERY ? "Discovery mode: send any message in the group/Topic to get the ids." : `Bridge bot up. Rooms file: ${ROOMS_FILE}`);
bot.start().catch((err) => {
  console.error("Bridge stopped:", (err as Error).message);
  process.exit(1);
});
