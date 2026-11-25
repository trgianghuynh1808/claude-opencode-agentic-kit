import { Bot, InlineKeyboard, InputFile, type Context } from "grammy";
import { promises as fs } from "node:fs";
import path from "node:path";

// ---------- config ----------
const BOT_TOKEN = process.env.BOT_TOKEN ?? "";
const ADMIN_USER_ID = Number(process.env.ADMIN_USER_ID ?? "");
const CHAT_ID = Number(process.env.TELEGRAM_CHAT_ID ?? "");
const ROOMS_FILE = path.resolve(process.env.ROOMS_FILE ?? "rooms.json");
const POLL_MS = Number(process.env.POLL_MS ?? "2000");
const MAX_ATTEMPTS = 3;
const COMMANDS = new Set(["auto", "status", "stop", "resume", "ship"]);

if (!BOT_TOKEN || !Number.isFinite(ADMIN_USER_ID) || !Number.isFinite(CHAT_ID)) {
  console.error("Set BOT_TOKEN, ADMIN_USER_ID and TELEGRAM_CHAT_ID (see .env.example).");
  process.exit(1);
}

interface Room { topicId: number; name: string; path: string }
interface OutboxMessage { text?: string; images?: string[]; requires?: string }

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

async function writeInbox(room: Room, payload: Record<string, unknown>): Promise<void> {
  const ts = Date.now();
  const file = path.join(room.path, ".agents", "inbox", `${ts}-${Math.random().toString(36).slice(2, 6)}.json`);
  await writeAtomic(file, JSON.stringify({ ts, ...payload }, null, 2));
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

// ---------- inbound: Telegram -> .agents/inbox ----------
const bot = new Bot(BOT_TOKEN);

bot.on("message:text", async (ctx) => {
  if (!isAdmin(ctx)) return;
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
  if (m && !command) {
    await ctx.reply("Lệnh hợp lệ: /auto <checklist>, /status, /stop, /resume, /ship");
    return;
  }
  if (command === "/auto" && !m?.[2]?.trim()) {
    await ctx.reply("Cách dùng: /auto <checklist> (mỗi dòng một việc).");
    return;
  }

  await writeInbox(room, { from: ctx.from?.id, command, args: command ? (m?.[2] ?? "").trim() : "", text });
  await ctx.reply(`📥 ${room.name}: đã nhận ${command ?? "tin nhắn"}.`, { message_thread_id: topicId });
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
  const opts = { message_thread_id: room.topicId } as const;
  const title = `📌 ${room.name}`;
  const images = (msg.images ?? []).map((p) => safeImage(room, p)).filter((p): p is string => p !== null);
  const existing: string[] = [];
  for (const p of images) if (await fs.stat(p).then((s) => s.isFile()).catch(() => false)) existing.push(p);

  const keyboard = msg.requires === "APPROVE_SHIP"
    ? new InlineKeyboard().text("✅ Ship", `ship:${room.topicId}`).text("⏸ Giữ lại", `keep:${room.topicId}`)
    : undefined;

  const parts = chunk(`${title}\n${msg.text ?? ""}`);
  for (let i = 0; i < parts.length; i++) {
    const last = i === parts.length - 1 && existing.length === 0;
    await bot.api.sendMessage(CHAT_ID, parts[i], { ...opts, ...(last && keyboard ? { reply_markup: keyboard } : {}) });
  }
  if (existing.length === 1) {
    await bot.api.sendPhoto(CHAT_ID, new InputFile(existing[0]), { ...opts, ...(keyboard ? { reply_markup: keyboard } : {}) });
  } else if (existing.length > 1) {
    for (let i = 0; i < existing.length; i += 10) {
      await bot.api.sendMediaGroup(CHAT_ID, existing.slice(i, i + 10).map((p) => ({ type: "photo" as const, media: new InputFile(p) })), opts);
    }
    if (keyboard) await bot.api.sendMessage(CHAT_ID, "Duyệt ship?", { ...opts, reply_markup: keyboard });
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
setInterval(async () => {
  if (polling) return;
  polling = true;
  try { for (const room of await loadRooms()) await pollRoom(room); } finally { polling = false; }
}, POLL_MS);

bot.catch((err) => console.error("bot error:", err.message));
console.log(`Bridge bot up. Rooms file: ${ROOMS_FILE}`);
void bot.start();
