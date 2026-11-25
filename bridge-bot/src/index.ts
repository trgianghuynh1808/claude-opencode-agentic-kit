import { Bot, InlineKeyboard, InputFile, type Context } from "grammy";
import { promises as fs } from "node:fs";
import path from "node:path";
import { chunk, toHtml } from "./format.js";
import { guardApi } from "./ratelimit.js";
import net from "node:net";
import os from "node:os";
import { fileURLToPath } from "node:url";
import { execFile, spawn } from "node:child_process";
import { kitArgs, nowNs, parseKitOutput, parseNewRoom, topicColor, topicLink, topicTitle, type NewRoomRequest } from "./newroom.js";

// ---------- config ----------
const BOT_TOKEN = process.env.BOT_TOKEN ?? "";
const ADMIN_USER_ID = Number(process.env.ADMIN_USER_ID ?? "");
const CHAT_ID = Number(process.env.TELEGRAM_CHAT_ID ?? "");
const ROOMS_FILE = path.resolve(process.env.ROOMS_FILE ?? "rooms.json");
const POLL_MS = Number(process.env.POLL_MS ?? "2000");
const MAX_ATTEMPTS = 3;
const COMMANDS = new Set(["auto", "status", "stop", "resume", "ship", "health", "usage", "newroom", "plan", "clear", "clearlog"]);
// /newroom runs the `kit` CLI that lives two folders above dist/. API_ROOT / KIT_EXTRA_ARGS exist for the end-to-end test (fake Telegram, --no-start).
const KIT_BIN = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "kit");
const PROJECTS_DIR = path.resolve(process.env.KIT_PROJECTS_DIR ?? path.join(os.homedir(), "Documents", "projects"));
const API_ROOT = process.env.TELEGRAM_API_ROOT;
const KIT_EXTRA_ARGS = (process.env.KIT_EXTRA_ARGS ?? "").split(/\s+/).filter(Boolean);
const botOptions = API_ROOT ? { client: { apiRoot: API_ROOT } } : undefined;

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
    // A missing file just means "no room yet" (rooms.json is per machine and git-ignored): stay quiet about that.
    if ((err as NodeJS.ErrnoException).code !== "ENOENT") console.error(`Cannot read ${ROOMS_FILE}:`, (err as Error).message);
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

const lastNotice = new Map<string, number>();

/** Tell the user about a problem that would otherwise only be printed to the console, at most once per `everyMs` per kind. */
async function notifyOnce(key: string, text: string, everyMs: number, threadId?: number): Promise<void> {
  if (Date.now() - (lastNotice.get(key) ?? 0) < everyMs) return;
  lastNotice.set(key, Date.now());
  await sendRich(bot.api, CHAT_ID, text, threadId !== undefined ? { message_thread_id: threadId } : {}).catch(() => undefined);
}

async function react(messageId: number, emoji: string, threadId?: number): Promise<void> {
  await bot.api
    .setMessageReaction(CHAT_ID, messageId, [{ type: "emoji", emoji: emoji as Emoji }])
    .catch(async (err) => {
      console.error("reaction failed:", (err as Error).message);
      await notifyOnce("reaction", "Mình không thả được reaction 👀 lên tin nhắn của bạn nên không báo được là đã nhận lệnh ⚠️\nLệnh vẫn được nhận bình thường. Có thể bot thiếu quyền trong group.", 6 * 3600_000, threadId);
    });
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

type SendOpts = Parameters<Bot["api"]["sendMessage"]>[2];

/** Send as HTML; if Telegram rejects the markup, resend the raw text so a message is never lost. */
async function sendRich(api: Bot["api"], chatId: number, text: string, opts: SendOpts = {}) {
  try {
    // link_preview_options: no big GitHub card under a report that already contains the commit link
    return await api.sendMessage(chatId, toHtml(text), { ...opts, parse_mode: "HTML", link_preview_options: { is_disabled: true } });
  } catch (err) {
    if (/parse entities|can't parse/i.test((err as Error).message)) return api.sendMessage(chatId, text, opts);
    throw err;
  }
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
  const infra: string[] = [];
  const agents: string[] = [];
  const tools: string[] = [];
  const problems: string[] = [];
  const ok = (arr: string[], m: string) => arr.push(`✅ ${m}`);
  const bad = (arr: string[], m: string, why: string) => { arr.push(`❌ ${m}`); problems.push(why); };
  const warn = (arr: string[], m: string) => arr.push(`⚠️ ${m}`);

  ok(infra, "Bridge đang online (đang nói chuyện với bạn nè)");
  for (const [role, token, label] of [["techlead", process.env.BOT_TOKEN_TECHLEAD, "Bot Tech Lead"], ["dev", process.env.BOT_TOKEN_DEV, "Bot Senior Dev"]] as const) {
    if (!token) { warn(infra, `${label}: đang dùng chung bot chính (chưa có token riêng)`); continue; }
    try { const me = await roleApis[role].getMe(); ok(infra, `${label}: @${me.username}`); }
    catch (e) { warn(infra, `${label}: token lỗi (${(e as Error).message}), tin của vai này sẽ không gửi được`); }
  }

  const mgr = await pidAlive(path.join(ag, "manager.lock"));
  mgr ? ok(agents, `Manager daemon (pid ${mgr})`) : bad(agents, "Manager daemon đang ngủ đông", "Manager daemon (chạy `scripts/agent-room.sh start`)");
  const wat = await pidAlive(path.join(ag, "watcher.pid"));
  wat ? ok(agents, `Senior Dev watcher / OpenCode (pid ${wat})`) : bad(agents, "Senior Dev watcher đang ngủ đông", "watcher OpenCode (chạy `scripts/agent-room.sh start`)");

  const cl = await run("claude", ["--version"]);
  cl.ok ? ok(tools, `claude ${cl.out}`) : bad(tools, "Không gọi được `claude` CLI", "claude CLI");
  const oc = await run("opencode", ["--version"]);
  oc.ok ? ok(tools, `opencode ${oc.out}`) : bad(tools, "Không gọi được `opencode` CLI", "opencode CLI");

  const br = await run("git", ["rev-parse", "--abbrev-ref", "HEAD"], room.path);
  const dirty = await run("git", ["status", "--porcelain"], room.path);
  const n = dirty.out ? (await run("sh", ["-c", "git status --porcelain | wc -l"], room.path)).out.trim() : "0";
  if (!br.ok) bad(tools, "Thư mục này không phải git repo", "git repo");
  else if (n !== "0") { warn(tools, `Git: nhánh \`${br.out}\`, còn ${n} file chưa commit (hand-off sẽ bị chặn)`); problems.push("cây git đang dơ"); }
  else ok(tools, `Git: nhánh \`${br.out}\`, sạch bong`);

  const port = Number(env.APP_PORT);
  if (port) (await portOpen(port)) ? ok(tools, `Dev server :${port} đang chạy`) : warn(tools, `Dev server :${port} chưa chạy (chỉ cần khi Verify trên trình duyệt)`);

  const verdict = problems.length
    ? `Chưa sẵn sàng đâu 😿 Còn thiếu: ${problems.join(", ")}`
    : "Mọi thứ ổn áp, sẵn sàng nhận việc nha! 🚀";
  return [
    `🩺 **Health check** · ${room.name}`,
    "", "**Hạ tầng**", ...infra,
    "", "**Các agent**", ...agents,
    "", "**Công cụ & dự án**", ...tools,
    "", `Chế độ tự động: **${env.AUTO_MODE === "true" ? "BẬT" : "TẮT"}** · nhánh nền \`${env.STAGING_BRANCH ?? "staging"}\``,
    "", verdict,
  ].join("\n");
}

// ---------- inbound: Telegram -> .agents/inbox ----------
const bot = new Bot(BOT_TOKEN, botOptions);

// Optional extra identities. They only send (never poll); without a token the role falls back to the main bot.
guardApi(bot.api, "manager");
const roleApis: Record<Role, Bot["api"]> = {
  manager: bot.api,
  techlead: process.env.BOT_TOKEN_TECHLEAD ? guardApi(new Bot(process.env.BOT_TOKEN_TECHLEAD, botOptions).api, "techlead") : bot.api,
  dev: process.env.BOT_TOKEN_DEV ? guardApi(new Bot(process.env.BOT_TOKEN_DEV, botOptions).api, "dev") : bot.api,
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
  const text = ctx.message.text;
  const m = text.match(/^\/([a-z_]+)(?:@\w+)?(?:\s+([\s\S]*))?$/i);
  const command = m && COMMANDS.has(m[1].toLowerCase()) ? `/${m[1].toLowerCase()}` : null;
  if (command === "/newroom") {   // works anywhere in the group, including General: it creates the Topic itself
    await handleNewRoom(ctx, (m?.[2] ?? "").trim());
    return;
  }
  if (topicId === undefined) {
    await sendRich(bot.api, ctx.chat.id, "Bạn nhắn trong **Topic của project** giúp mình nha 🙏 (khu General không có phòng nào hết). Muốn tạo phòng mới thì gõ `/newroom <tên-project> <port>` nhé.");
    return;
  }
  const room = (await loadRooms()).find((r) => r.topicId === topicId);
  if (!room) {
    await sendRich(bot.api, ctx.chat.id, `Topic **${topicId}** chưa có phòng nào hết 🏠\nTrong project, chạy giúp mình:\n\`scripts/agent-room.sh init --topic ${topicId} --port <PORT>\``, { message_thread_id: topicId });
    return;
  }

  if (command === "/clear") {   // irreversible by git (the board is not tracked), so ask first
    await askClear(ctx, room, topicId);
    return;
  }
  if (command === "/health") {
    await sendRich(bot.api, ctx.chat.id, await health(room), { message_thread_id: topicId });
    return;
  }
  if (m && !command) {
    await sendRich(bot.api, ctx.chat.id, "Mình chỉ hiểu mấy lệnh này thôi nha 😅\n- `/auto <việc cần làm>` · mỗi dòng một việc\n- `/status` · xem tiến độ\n- `/health` · kiểm tra các agent\n- `/usage` · xem mức dùng token\n- `/plan <câu hỏi>` · hỏi đáp, phân tích (chỉ đọc)\n- `/clear` · dọn board và trạng thái cũ\n- `/clearlog` · dọn log chạy\n- `/stop` · dừng lại\n- `/resume` · chạy tiếp\n- `/ship` · đưa lên main\n- `/newroom <tên> <port>` · tạo phòng mới", { message_thread_id: topicId });
    return;
  }
  if (command === "/plan" && !m?.[2]?.trim()) {
    await sendRich(bot.api, ctx.chat.id, "Bạn muốn hỏi gì về project nè? 🔍\nCách dùng: `/plan <câu hỏi>`. Mình và Tech Lead sẽ đọc code rồi tổng hợp gửi bạn, không sửa gì và không tạo task nào hết.", { message_thread_id: topicId });
    return;
  }
  if (command === "/auto" && !m?.[2]?.trim()) {
    await sendRich(bot.api, ctx.chat.id, "Bạn cho mình biết việc cần làm nhé 📝\nCách dùng: `/auto <việc cần làm>`, mỗi dòng một việc.", { message_thread_id: topicId });
    return;
  }

  const file = await writeInbox(room, { from: ctx.from?.id, command, args: command ? (m?.[2] ?? "").trim() : "", text });
  pendingReactions.set(`${room.path}/${file}`, { room, messageId: ctx.message.message_id });
  await react(ctx.message.message_id, "👀", topicId);
});

bot.on("callback_query:data", async (ctx) => {
  if (ctx.from.id !== ADMIN_USER_ID) return void (await ctx.answerCallbackQuery());
  if (ctx.callbackQuery.data.startsWith("nr:")) return void (await handleNewRoomButton(ctx));
  if (ctx.callbackQuery.data.startsWith("cl:")) return void (await handleClearButton(ctx));
  const [action, topic] = ctx.callbackQuery.data.split(":");
  const room = (await loadRooms()).find((r) => r.topicId === Number(topic));
  if (!room || (action !== "ship" && action !== "keep")) return void (await ctx.answerCallbackQuery("Không hợp lệ"));
  await writeInbox(room, { from: ctx.from.id, command: action === "ship" ? "/ship" : "/stop", args: "", text: "" });
  await ctx.answerCallbackQuery(action === "ship" ? "Đã gửi /ship" : "Đã giữ lại");
  await ctx.editMessageReplyMarkup({ reply_markup: undefined }).catch(() => undefined);
});

// ---------- /clear: confirmation card, then the daemon does the cleaning (idle rooms only) ----------
const pendingClears = new Map<string, { room: Room; expires: number }>();

async function askClear(ctx: Context, room: Room, topicId: number): Promise<void> {
  const board = await fs.readFile(path.join(room.path, ".agents", "board.md"), "utf8").catch(() => "");
  const open = (board.match(/^- \[ \] `T\d+`/gm) ?? []).length;
  const done = (board.match(/^- \[x\] `T\d+`/gm) ?? []).length;
  const id = Math.random().toString(36).slice(2, 8);
  pendingClears.set(id, { room, expires: Date.now() + 10 * 60_000 });
  const text = [
    `Mình sắp dọn phòng **${room.name}** nè 🧹`, "",
    "**Sẽ làm**",
    `- Reset board: gỡ ${open} task chưa xong và ${done} task đã xong (mình lưu bản sao board trước)`,
    "- Xóa trạng thái task cũ, tin nhắn cũ và các file hỏi đáp `/plan`", "",
    "**Không đụng tới:** cấu hình phòng, file plan trong git, ảnh, log và `usage.log`", "",
    "Nếu phòng đang bận thì mình sẽ từ chối. Bạn xác nhận nhé? 👇",
  ].join("\n");
  await sendRich(bot.api, ctx.chat!.id, text, { message_thread_id: topicId, reply_markup: new InlineKeyboard().text("✅ Dọn", `cl:ok:${id}`).text("❌ Huỷ", `cl:no:${id}`) });
}

async function handleClearButton(ctx: Context): Promise<void> {
  const [, action, id] = (ctx.callbackQuery?.data ?? "").split(":");
  const pending = pendingClears.get(id);
  await ctx.editMessageReplyMarkup({ reply_markup: undefined }).catch(() => undefined);
  pendingClears.delete(id);
  if (!pending || pending.expires < Date.now()) return void (await ctx.answerCallbackQuery("Yêu cầu đã hết hạn, bạn gõ lại /clear nha"));
  if (action !== "ok") return void (await ctx.answerCallbackQuery("Đã huỷ"));
  await writeInbox(pending.room, { from: ctx.from?.id, command: "/clear", args: "", text: "" });
  await ctx.answerCallbackQuery("Đã gửi /clear");
}

// ---------- /newroom: create a Topic, set the project up with `kit`, let the three bots say hello ----------
interface PendingRoom { req: NewRoomRequest; dir: string; existing: boolean; originThread?: number; expires: number }
const pendingRooms = new Map<string, PendingRoom>();
let creatingRoom = false;

async function handleNewRoom(ctx: Context, args: string): Promise<void> {
  const origin = ctx.message?.message_thread_id;
  const say = (text: string, extra: SendOpts = {}) =>
    sendRich(bot.api, ctx.chat!.id, text, { ...(origin !== undefined ? { message_thread_id: origin } : {}), ...extra });
  const parsed = parseNewRoom(args);
  if (!parsed.ok) return void (await say(parsed.error));
  const { req } = parsed;
  const dir = path.join(PROJECTS_DIR, req.name);

  if (creatingRoom) return void (await say("Mình đang dựng một phòng khác, bạn chờ xíu rồi gõ lại nha ⏳"));
  if ((await loadRooms()).some((r) => path.resolve(r.path) === dir)) {
    return void (await say(`Project **${req.name}** đã có phòng rồi nè 🏠 Gõ \`/status\` trong Topic của nó nhé.`));
  }
  const stat = await fs.stat(dir).catch(() => null);
  let existing = false;
  if (stat) {
    if (!stat.isDirectory()) return void (await say(`\`${dir}\` là một file, không phải thư mục 😅`));
    const isGit = await fs.stat(path.join(dir, ".git")).then(() => true, () => false);
    const empty = (await fs.readdir(dir)).length === 0;
    if (isGit) existing = true;
    else if (!empty) return void (await say(`Thư mục \`${dir}\` đã có file nhưng chưa phải git repo 🙈\nBạn \`git init\` và commit giúp mình rồi gõ lại nhé.`));
  }

  // Fail before creating the Topic: otherwise a problem in the project would leave an empty Topic behind.
  if (existing) {
    if (await fs.stat(path.join(dir, ".agents", "room.env")).then(() => true, () => false)) {
      return void (await say(`\`${req.name}\` đã là một phòng rồi nhưng chưa có trong sổ đăng ký bridge 🤔 Bạn chạy \`kit status --all\` để xem nhé.`));
    }
    if (!(await run("git", ["rev-parse", "HEAD"], dir)).ok) return void (await say(`Project **${req.name}** chưa có commit nào 🙈 Bạn commit một lần giúp mình rồi gõ lại nhé.`));
    if ((await run("git", ["status", "--porcelain"], dir)).out) {
      return void (await say(`Project **${req.name}** đang có file chưa commit nên mình chưa gắn phòng được ⚠️\nBạn commit hoặc stash giúp mình rồi gõ lại nhé.`));
    }
  } else if (!req.local && !(await run("gh", ["auth", "status"])).ok) {
    return void (await say("Mình chưa tạo được repo GitHub vì `gh` chưa đăng nhập 🔑\nBạn chạy `gh auth login` giúp mình, hoặc gõ lại kèm `local` để chỉ tạo project trên máy nhé."));
  }

  const id = Math.random().toString(36).slice(2, 8);
  pendingRooms.set(id, { req, dir, existing, originThread: origin, expires: Date.now() + 10 * 60_000 });
  const lines = [
    "Mình sắp tạo phòng mới nè 🏠", "",
    `**Topic:** \`${topicTitle(req.name)}\``,
    existing ? `**Project:** \`${dir}\` (đã có, mình gắn phòng vào)` : `**Project:** \`${dir}\` (tạo mới)`,
    `**Port dev server:** \`${req.port}\``,
  ];
  if (!existing) lines.push(req.local ? "- GitHub: không tạo (chỉ local)" : `- GitHub: tạo repo **${req.private ? "PRIVATE" : "PUBLIC"}** rồi push`);
  if (req.agents) lines.push("- Claude sẽ soạn nháp `AGENTS.md` (tốn một lần gọi Claude)");
  lines.push("", "Bạn xác nhận nhé? 👇");
  await say(lines.join("\n"), { reply_markup: new InlineKeyboard().text("✅ Tạo phòng", `nr:ok:${id}`).text("❌ Huỷ", `nr:no:${id}`) });
}

async function handleNewRoomButton(ctx: Context): Promise<void> {
  const [, action, id] = (ctx.callbackQuery?.data ?? "").split(":");
  const pending = pendingRooms.get(id);
  await ctx.editMessageReplyMarkup({ reply_markup: undefined }).catch(() => undefined);
  if (!pending || pending.expires < Date.now()) {
    pendingRooms.delete(id);
    return void (await ctx.answerCallbackQuery("Yêu cầu đã hết hạn, bạn gõ lại /newroom nha"));
  }
  pendingRooms.delete(id);
  if (action !== "ok") return void (await ctx.answerCallbackQuery("Đã huỷ"));
  await ctx.answerCallbackQuery("Đang tạo phòng…");
  void createRoom(pending);   // long-running: do not block the update loop
}

function runKit(args: string[]): Promise<{ code: number | null; out: string }> {
  return new Promise((resolve) => {
    // No shell and no stdin: `kit` runs non-interactively (--yes) and every argument comes from newroom.ts.
    const child = spawn(KIT_BIN, args, { env: { ...process.env, AGENT_ROOMS_FILE: ROOMS_FILE, AGENT_BRIDGE_UP: "1" }, stdio: ["ignore", "pipe", "pipe"] });
    let out = "";
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (out += d));
    const timer = setTimeout(() => child.kill("SIGTERM"), 20 * 60_000);
    child.on("close", (code) => { clearTimeout(timer); resolve({ code, out }); });
    child.on("error", (e) => { clearTimeout(timer); resolve({ code: -1, out: String(e) }); });
  });
}

/** Warnings for role bots that cannot post in the group (a Topic has no member list: any bot in the group can post in it). */
async function botsNotInGroup(): Promise<string[]> {
  const warns: string[] = [];
  for (const [role, token, label] of [["techlead", process.env.BOT_TOKEN_TECHLEAD, "Tech Lead"], ["dev", process.env.BOT_TOKEN_DEV, "Senior Dev"]] as const) {
    if (!token) continue;
    try {
      const me = await roleApis[role].getMe();
      const member = await bot.api.getChatMember(CHAT_ID, me.id);
      if (member.status === "left" || member.status === "kicked") warns.push(`Bot ${label} (@${me.username}) chưa ở trong group, bạn thêm nó vào giúp mình nhé`);
    } catch (e) {
      warns.push(`Mình không kiểm tra được bot ${label}: ${(e as Error).message}`);
    }
  }
  return warns;
}

async function writeRoomOutbox(room: Room, role: Role, text: string): Promise<void> {
  await writeAtomic(path.join(room.path, ".agents", "outbox", `${nowNs()}-${role}.json`), JSON.stringify({ from: role, text }));
}

async function createRoom(p: PendingRoom): Promise<void> {
  creatingRoom = true;
  const { req } = p;
  const title = topicTitle(req.name);
  const sayAt = (threadId: number | undefined, text: string) =>
    sendRich(bot.api, CHAT_ID, text, threadId !== undefined ? { message_thread_id: threadId } : {}).catch((e) => console.error("say failed:", (e as Error).message));
  try {
    const warns = await botsNotInGroup();

    let threadId: number;
    try {
      threadId = (await bot.api.createForumTopic(CHAT_ID, title, { icon_color: topicColor(req.name) })).message_thread_id;
    } catch (e) {
      await sayAt(p.originThread, `Mình chưa tạo được Topic 😢\n**Lý do:** ${(e as Error).message}\n\nBạn kiểm tra giúp mình: group đã bật **Topics** và ManagerBot là admin có quyền **Manage Topics** chưa nhé.`);
      return;
    }
    const link = topicLink(CHAT_ID, threadId);
    await sayAt(p.originThread, `Mình tạo Topic **${title}** rồi nè 🎉${link ? `\n${link}` : ""}`);
    await sayAt(threadId, `Chào mừng đến phòng **${title}** 🎉\nMình đang dựng project, chờ mình xíu nha ⏳ (có thể mất vài phút)`);
    if (warns.length) await sayAt(threadId, `⚠️ ${warns.join("\n⚠️ ")}`);

    const { code, out } = await runKit(kitArgs(req, p.existing, p.dir, threadId, KIT_EXTRA_ARGS));
    const { repoUrl, tail } = parseKitOutput(out);
    if (code !== 0) {
      console.error(`kit exited with ${code}:\n${out}`);
      await sayAt(threadId, `Ối, mình dựng phòng chưa xong 😢 (mã lỗi ${code})\n\n**Những dòng cuối**\n${tail.map((l) => `- ${l.slice(0, 160)}`).join("\n")}\n\nTopic này vẫn còn. Bạn xử lý xong có thể chạy lại:\n\`kit ${p.existing ? "add" : "new"} ${p.existing ? p.dir : req.name} --topic ${threadId} --port ${req.port}\``);
      return;
    }

    const room = (await loadRooms()).find((r) => r.topicId === threadId);
    if (!room) { await sayAt(threadId, "Dựng xong nhưng mình không thấy phòng trong sổ đăng ký 🤔 Bạn kiểm tra `kit status` giúp mình nhé."); return; }

    // The three bots say hello through the normal outbox, so each one speaks with its own identity and header.
    await writeRoomOutbox(room, "manager", [
      `Phòng **${title}** đã sẵn sàng! 🚀`, "",
      "**Thông tin**", `- Thư mục: \`${p.dir}\``, `- Port dev server: \`${req.port}\``,
      ...(repoUrl ? [`- Repo GitHub: ${repoUrl}`] : []), "",
      "**Bắt đầu thôi**", "- `/health` để kiểm tra các agent", "- `/auto <việc cần làm>` để giao việc, mỗi dòng một việc", "",
      req.agents ? "Mình đã nhờ Claude soạn nháp `AGENTS.md`, bạn đọc lại trước khi giao task đầu tiên nhé 📖" : "Nhớ điền `AGENTS.md` để các agent biết cách chạy app và test nha 📖",
    ].join("\n"));
    await writeRoomOutbox(room, "techlead", "Chào bạn, mình là **Tech Lead** 🛠\nMình sẽ lên plan, verify và review cho project này nha.");
    await writeRoomOutbox(room, "dev", "Hello! Mình là **Senior Dev** ⌨️\nMình lo viết code và chạy test. Rất vui được làm việc cùng bạn! 💪");
    await new Promise((r) => setTimeout(r, Number(process.env.NEWROOM_HEALTH_DELAY_MS ?? "6000")));   // let the daemon come up before checking it
    await sendRich(bot.api, CHAT_ID, await health(room), { message_thread_id: threadId });
  } catch (e) {
    console.error("createRoom failed:", e);
    await sayAt(p.originThread, `Mình gặp lỗi khi tạo phòng 😢 ${(e as Error).message}`);
  } finally {
    creatingRoom = false;
  }
}

// ---------- outbound: .agents/outbox -> Telegram ----------
const attempts = new Map<string, number>();

async function sendOutbox(room: Room, msg: OutboxMessage): Promise<void> {
  // Ship buttons are answered by the main bot, so a message that needs approval always comes from the manager.
  const role: Role = msg.requires ? "manager" : (msg.from && msg.from in ROLE_LABEL ? msg.from : "manager");
  const api = roleApis[role];
  const opts = { message_thread_id: room.topicId } as const;
  const title = `**${ROLE_LABEL[role]}** · ${room.name}\n`;
  const images = (msg.images ?? []).map((p) => safeImage(room, p)).filter((p): p is string => p !== null);
  const existing: string[] = [];
  for (const p of images) if (await fs.stat(p).then((s) => s.isFile()).catch(() => false)) existing.push(p);

  const keyboard = msg.requires === "APPROVE_SHIP"
    ? new InlineKeyboard().text("✅ Ship", `ship:${room.topicId}`).text("⏸ Giữ lại", `keep:${room.topicId}`)
    : undefined;

  const parts = chunk(`${title}\n${msg.text ?? ""}`);
  for (let i = 0; i < parts.length; i++) {
    const last = i === parts.length - 1 && existing.length === 0;
    await sendRich(api, CHAT_ID, parts[i], { ...opts, ...(last && keyboard ? { reply_markup: keyboard } : {}) });
  }
  if (existing.length === 1) {
    await api.sendPhoto(CHAT_ID, new InputFile(existing[0]), { ...opts, ...(keyboard ? { reply_markup: keyboard } : {}) });
  } else if (existing.length > 1) {
    for (let i = 0; i < existing.length; i += 10) {
      await api.sendMediaGroup(CHAT_ID, existing.slice(i, i + 10).map((p) => ({ type: "photo" as const, media: new InputFile(p) })), opts);
    }
    if (keyboard) await sendRich(api, CHAT_ID, "Bạn duyệt ship luôn chứ? 👇", { ...opts, reply_markup: keyboard });
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
        await notifyOnce(`outbox-failed:${room.name}`, `Mình không gửi được một tin của phòng **${room.name}** sau ${MAX_ATTEMPTS} lần thử nên đã bỏ vào \`.agents/outbox/failed/\` ⚠️\nBạn có thể đã thiếu một tin báo. Lý do: ${(err as Error).message.slice(0, 120)}`, 30 * 60_000, room.topicId);
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
    { command: "usage", description: "Token và chi phí Claude + OpenCode (/usage 7 = 7 ngày)" },
    { command: "stop", description: "Tắt AUTO_MODE, dừng nhận task mới" },
    { command: "resume", description: "Chạy tiếp sau khi dừng hoặc bị kẹt" },
    { command: "ship", description: "Merge staging vào main và push" },
    { command: "plan", description: "Hỏi đáp, phân tích project (chỉ đọc, không sửa gì)" },
    { command: "clear", description: "Dọn board và trạng thái cũ (có xác nhận)" },
    { command: "clearlog", description: "Dọn log chạy, giữ vài trăm dòng cuối" },
    { command: "newroom", description: "Tạo phòng mới: /newroom <tên> <port>" },
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
