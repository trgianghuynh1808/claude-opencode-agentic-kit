// End-to-end test of /newroom: the real bridge talks to a fake Telegram Bot API, and runs the real `kit` CLI
// (with --no-start, a fake `gh`, a temp projects folder and a temp rooms file). Nothing real is touched.
import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const BRIDGE = path.resolve(here, "..", "dist", "index.js");
const T = fs.mkdtempSync(path.join(os.tmpdir(), "newroom-e2e-"));
const PROJECTS = path.join(T, "projects");
const ROOMS = path.join(T, "rooms.json");
fs.mkdirSync(PROJECTS);
fs.mkdirSync(path.join(T, "bin"));
fs.writeFileSync(ROOMS, '{ "rooms": [] }');
fs.writeFileSync(path.join(T, "bin", "gh"), `#!/usr/bin/env bash
echo "gh $*" >> "${T}/gh.log"
case "$1 $2" in
  "auth status") exit 0 ;;
  "api user") echo tester; exit 0 ;;
  "repo create") git init -q --bare "${T}/remote-$3.git"; git remote add origin "${T}/remote-$3.git"; git push -q -u origin main; exit 0 ;;
esac
`, { mode: 0o755 });

const CHAT = -1001234567890;
const ADMIN = 1000;
const TOKENS = { "111:AAA": { id: 111, name: "ManagerBot" }, "222:BBB": { id: 222, name: "TechLeadBot" }, "333:CCC": { id: 333, name: "DevBot" } };

// ---------- fake Telegram ----------
const calls = [];
const updates = [];
let updateId = 1, messageId = 100, topicCounter = 777;
const send = (res, result) => { res.setHeader("content-type", "application/json"); res.end(JSON.stringify({ ok: true, result })); };
const server = http.createServer((req, res) => {
  let raw = "";
  req.on("data", (d) => (raw += d));
  req.on("end", async () => {
    const m = req.url.match(/^\/bot([^/]+)\/(\w+)/);
    const [, token, method] = m ?? [];
    const body = raw ? JSON.parse(raw) : {};
    if (method !== "getUpdates") calls.push({ token, method, body });
    switch (method) {
      case "getMe": return send(res, { id: TOKENS[token].id, is_bot: true, first_name: TOKENS[token].name, username: TOKENS[token].name });
      case "getUpdates": {
        const off = body.offset ?? 0;
        for (let i = 0; i < 8; i++) {
          const list = updates.filter((u) => u.update_id >= off);
          if (list.length) return send(res, list);
          await new Promise((r) => setTimeout(r, 100));
        }
        return send(res, []);
      }
      case "sendMessage": return send(res, { message_id: ++messageId, date: 0, chat: { id: CHAT, type: "supergroup" } });
      case "createForumTopic": return send(res, { message_thread_id: ++topicCounter, name: body.name });
      case "getChatMember": return send(res, { status: "member", user: { id: body.user_id, is_bot: true, first_name: "x" } });
      default: return send(res, true);
    }
  });
});

const user = (id) => ({ id, is_bot: false, first_name: "u" });
const say = (text, from = ADMIN, thread) => updates.push({
  update_id: updateId++,
  message: { message_id: ++messageId, date: 0, chat: { id: CHAT, type: "supergroup" }, from: user(from), text,
    entities: [{ type: "bot_command", offset: 0, length: text.split(/\s/)[0].length }], ...(thread ? { message_thread_id: thread, is_topic_message: true } : {}) },
});
const press = (data, from = ADMIN) => updates.push({
  update_id: updateId++,
  callback_query: { id: String(updateId), from: user(from), chat_instance: "x", data,
    message: { message_id: messageId, date: 0, chat: { id: CHAT, type: "supergroup" } } },
});
const waitFor = async (what, fn, ms = 60000) => {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) { const v = fn(); if (v) return v; await new Promise((r) => setTimeout(r, 150)); }
  throw new Error(`timeout waiting for: ${what}`);
};
const texts = () => calls.filter((c) => c.method === "sendMessage");
const findText = (re, extra = () => true) => texts().find((c) => re.test(c.body.text) && extra(c));

let bad = 0;
const check = (name, ok, extra = "") => { console.log(`${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : " " + extra}`); if (!ok) bad++; };

await new Promise((r) => server.listen(0, "127.0.0.1", r));
const apiRoot = `http://127.0.0.1:${server.address().port}`;
let bridgeLog = "";
const bridge = spawn(process.execPath, [BRIDGE], {
  env: { ...process.env, BOT_TOKEN: "111:AAA", BOT_TOKEN_TECHLEAD: "222:BBB", BOT_TOKEN_DEV: "333:CCC", ADMIN_USER_ID: String(ADMIN),
    TELEGRAM_CHAT_ID: String(CHAT), ROOMS_FILE: ROOMS, POLL_MS: "300", KIT_PROJECTS_DIR: PROJECTS, TELEGRAM_API_ROOT: apiRoot,
    KIT_EXTRA_ARGS: "--no-start", NEWROOM_HEALTH_DELAY_MS: "300", KT: T, PATH: `${path.join(T, "bin")}:${process.env.PATH}` },
  stdio: ["ignore", "pipe", "pipe"],
});
bridge.stdout.on("data", (d) => (bridgeLog += d));
bridge.stderr.on("data", (d) => (bridgeLog += d));

try {
  await waitFor("bridge up", () => bridgeLog.includes("Bridge bot up"), 15000);

  console.log("usage and validation:");
  say("/newroom");
  await waitFor("usage reply", () => findText(/Cách dùng/));
  check("no arguments -> usage", true);
  say("/newroom ../evil 3000");
  await waitFor("name rejected", () => findText(/Tên project chỉ gồm/));
  check("a path-like name is rejected", true);
  const before = calls.length;
  say("/newroom sneaky 3000", 999);   // not the admin
  await new Promise((r) => setTimeout(r, 1500));
  check("a non-admin is ignored", !calls.slice(before).some((c) => c.method === "sendMessage"));

  console.log("cancel:");
  say("/newroom cancel-me 4556");
  const card0 = await waitFor("confirmation card", () => findText(/cancel-me/, (c) => c.body.reply_markup));
  const data0 = JSON.parse(card0.body.reply_markup ? JSON.stringify(card0.body.reply_markup) : "{}").inline_keyboard[0][1].callback_data;
  press(data0);
  await new Promise((r) => setTimeout(r, 1500));
  check("pressing Huỷ creates no Topic", !calls.some((c) => c.method === "createForumTopic"));
  check("pressing Huỷ creates no folder", !fs.existsSync(path.join(PROJECTS, "cancel-me")));

  console.log("create a room:");
  say("/newroom tea-demo 4555");
  const card = await waitFor("confirmation card", () => findText(/tea-demo/, (c) => c.body.reply_markup));
  check("card names the topic project-tea-demo", /project-tea-demo/.test(card.body.text));
  check("card warns the GitHub repo will be PUBLIC", /PUBLIC/.test(card.body.text));
  const okData = card.body.reply_markup.inline_keyboard[0][0].callback_data;
  press(okData);

  const topic = await waitFor("createForumTopic", () => calls.find((c) => c.method === "createForumTopic"));
  check("topic is created with the project- prefix", topic.body.name === "project-tea-demo");
  check("topic uses an allowed icon colour", [7322096, 16766590, 13338331, 9367192, 16749490, 16478047].includes(topic.body.icon_color));
  const THREAD = 778;
  await waitFor("welcome in the new topic", () => findText(/Chào mừng đến phòng/, (c) => c.body.message_thread_id === THREAD));
  check("welcome message is posted inside the new topic", true);
  check("the link to the topic is posted where the command was typed", !!findText(/t\.me\/c\/1234567890\/778/));

  const health = await waitFor("health check", () => findText(/Health check/, (c) => c.body.message_thread_id === THREAD), 120000);
  check("final health check is posted in the topic", !!health);

  const inTopic = (re) => texts().find((c) => c.body.message_thread_id === THREAD && re.test(c.body.text));
  const hello = { manager: inTopic(/Manager<\/b>[\s\S]*đã sẵn sàng/), techlead: inTopic(/Tech Lead<\/b>[\s\S]*mình là/), dev: inTopic(/Senior Dev<\/b>[\s\S]*Mình lo viết code/) };
  await waitFor("all three hello messages", () => (hello.manager = inTopic(/Manager<\/b>[\s\S]*đã sẵn sàng/)) && (hello.techlead = inTopic(/Tech Lead<\/b>[\s\S]*mình là/)) && (hello.dev = inTopic(/Senior Dev<\/b>[\s\S]*Mình lo viết code/)), 30000);
  check("Manager says hello with its own bot", hello.manager.token === "111:AAA");
  check("Tech Lead says hello with its own bot", hello.techlead.token === "222:BBB");
  check("Senior Dev says hello with its own bot", hello.dev.token === "333:CCC");
  check("hello messages arrive in order manager, techlead, dev", texts().indexOf(hello.manager) < texts().indexOf(hello.techlead) && texts().indexOf(hello.techlead) < texts().indexOf(hello.dev));
  check("messages are sent as HTML", hello.manager.body.parse_mode === "HTML" && /<b>/.test(hello.manager.body.text));
  check("the Manager message carries the GitHub URL", /github\.com\/tester\/tea-demo/.test(hello.manager.body.text));

  const dir = path.join(PROJECTS, "tea-demo");
  check("project folder is a git repo", fs.existsSync(path.join(dir, ".git")));
  check("kit files are installed", fs.existsSync(path.join(dir, "scripts", "manager-loop.sh")) && fs.existsSync(path.join(dir, ".agents", "room.env")));
  const env = fs.readFileSync(path.join(dir, ".agents", "room.env"), "utf8");
  check("room.env has the new topic id and port", env.includes('TELEGRAM_TOPIC_ID="778"') && env.includes('APP_PORT="4555"'));
  const rooms = JSON.parse(fs.readFileSync(ROOMS, "utf8")).rooms;
  check("room is registered for the bridge", rooms.some((r) => r.topicId === 778 && r.name === "tea-demo"));
  check("GitHub repo was created PUBLIC", fs.readFileSync(path.join(T, "gh.log"), "utf8").includes("repo create tea-demo --public"));
  check("git tree is clean after setup", spawnSync("git", ["-C", dir, "status", "--porcelain"], { encoding: "utf8" }).stdout.trim() === "");

  console.log("existing project:");
  const run = (cmd, args, cwd) => spawnSync(cmd, args, { cwd, encoding: "utf8" });
  const mk = (name) => { const d = path.join(PROJECTS, name); fs.mkdirSync(d); run("git", ["init", "-q", "-b", "main"], d); run("git", ["config", "user.email", "t@t"], d); run("git", ["config", "user.name", "t"], d); fs.writeFileSync(path.join(d, "package.json"), "{}"); fs.writeFileSync(path.join(d, "CLAUDE.md"), "MY_OWN_RULES\n"); run("git", ["add", "-A"], d); run("git", ["commit", "-qm", "init"], d); return d; };
  const dirty = mk("dirty-app"); fs.appendFileSync(path.join(dirty, "package.json"), " ");
  const topicsBefore = calls.filter((c) => c.method === "createForumTopic").length;
  say("/newroom dirty-app 4600");
  await waitFor("dirty refusal", () => findText(/chưa commit nên mình chưa gắn phòng/));
  check("a project with uncommitted files is refused", true);
  check("...and no Topic is created for it", calls.filter((c) => c.method === "createForumTopic").length === topicsBefore);
  say("/newroom plain-dir 4601");
  const plain = path.join(PROJECTS, "plain-dir"); fs.mkdirSync(plain); fs.writeFileSync(path.join(plain, "a.txt"), "x");
  say("/newroom plain-dir 4601");
  await waitFor("not-a-repo refusal", () => findText(/chưa phải git repo/));
  check("a non-empty folder that is not a git repo is refused", true);

  const existing = mk("existing-app");
  say("/newroom existing-app 4602");
  const card2 = await waitFor("existing card", () => findText(/existing-app/, (c) => c.body.reply_markup && /đã có, mình gắn phòng/.test(c.body.text)));
  check("card says the project exists and will only get a room", !/GitHub/.test(card2.body.text));
  press(card2.body.reply_markup.inline_keyboard[0][0].callback_data);
  const T2 = 779;
  await waitFor("health for the existing project", () => findText(/Health check/, (c) => c.body.message_thread_id === T2), 120000);
  check("topic project-existing-app was created", calls.some((c) => c.method === "createForumTopic" && c.body.name === "project-existing-app"));
  check("the project's own CLAUDE.md text is kept", fs.readFileSync(path.join(existing, "CLAUDE.md"), "utf8").includes("MY_OWN_RULES"));
  check("the AUTO_MODE section was added", fs.readFileSync(path.join(existing, "CLAUDE.md"), "utf8").includes("## AUTO_MODE"));
  check("no GitHub repo was created for an existing project", !fs.readFileSync(path.join(T, "gh.log"), "utf8").includes("existing-app"));
  check("its room is registered with the new topic", JSON.parse(fs.readFileSync(ROOMS, "utf8")).rooms.some((r) => r.topicId === T2 && r.name === "existing-app"));
  await waitFor("all three hello messages for the second room", () => ["222:BBB", "333:CCC"].every((tok) => texts().some((c) => c.token === tok && c.body.message_thread_id === T2)), 30000);
  check("the three bots greeted the second room too", true);

  console.log("local project (no GitHub):");
  const ghCallsBefore = fs.readFileSync(path.join(T, "gh.log"), "utf8").split("\n").length;
  say("/newroom local-app 4603 local");
  const card3 = await waitFor("local card", () => findText(/local-app/, (c) => c.body.reply_markup));
  check("card says no GitHub repo will be created", /không tạo/.test(card3.body.text));
  press(card3.body.reply_markup.inline_keyboard[0][0].callback_data);
  await waitFor("health for the local project", () => findText(/Health check/, (c) => c.body.message_thread_id === 780), 120000);
  check("`local` creates no GitHub repo", fs.readFileSync(path.join(T, "gh.log"), "utf8").split("\n").length === ghCallsBefore);

  console.log("duplicates:");
  say("/newroom tea-demo 4557");
  await waitFor("duplicate reply", () => findText(/đã có phòng rồi/));
  check("a project that already has a room is refused", true);
} catch (e) {
  console.error("ERROR:", e.message);
  console.error("--- bridge log (tail) ---\n" + bridgeLog.split("\n").slice(-25).join("\n"));
  bad++;
} finally {
  bridge.kill("SIGTERM");
  server.close();
  fs.rmSync(T, { recursive: true, force: true });
}
console.log(bad ? "FAILED" : "OK");
process.exit(bad ? 1 : 0);
