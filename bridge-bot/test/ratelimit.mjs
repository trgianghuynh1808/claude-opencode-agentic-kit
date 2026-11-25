// The 429 guard against a fake Telegram: waits retry_after, shares the wait between concurrent sends, gives up on very long waits.
import http from "node:http";
import { Bot } from "grammy";
import { guardApi } from "../dist/ratelimit.js";

let bad = 0;
const check = (name, ok, extra = "") => { console.log(`${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : " " + extra}`); if (!ok) bad++; };

const hits = [];          // time of each sendMessage that reached the server
let mode = "once";        // once: first call 429 (retry 1s) then ok · long: always 429 with retry_after 999
const server = http.createServer((req, res) => {
  req.resume();
  req.on("end", () => {
    res.setHeader("content-type", "application/json");
    if (/getMe/.test(req.url)) return res.end(JSON.stringify({ ok: true, result: { id: 1, is_bot: true, first_name: "b", username: "b" } }));
    hits.push(Date.now());
    const limited = mode === "long" || (mode === "once" && hits.length === 1);
    if (limited) return res.end(JSON.stringify({ ok: false, error_code: 429, description: "Too Many Requests: retry after", parameters: { retry_after: mode === "long" ? 999 : 1 } }));
    res.end(JSON.stringify({ ok: true, result: { message_id: hits.length, date: 0, chat: { id: 1, type: "supergroup" } } }));
  });
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const mk = () => guardApi(new Bot("1:T", { client: { apiRoot: `http://127.0.0.1:${server.address().port}` } }).api, "test", 5);

// 1) a 429 is waited out and the message still goes through
let t0 = Date.now();
let r = await mk().sendMessage(1, "hi");
check("a 429 is retried after retry_after and succeeds", r.message_id === 2 && hits.length === 2 && Date.now() - t0 >= 1000);

// 2) two sends in a row on the same bot: the second does not hit the server while the bot is told to wait
hits.length = 0; mode = "once";
const api = mk();
t0 = Date.now();
const a = api.sendMessage(1, "A");
await new Promise((x) => setTimeout(x, 150));      // A has been rejected by now, the bot is blocked
const b = api.sendMessage(1, "B");
await Promise.all([a, b]);
check("while one bot is blocked, a second send waits too", hits.length === 3 && hits[2] - hits[0] >= 1000);

// 3) a wait longer than the cap is not slept off: the error reaches the caller quickly
hits.length = 0; mode = "long";
t0 = Date.now();
let err;
try { await mk().sendMessage(1, "x"); } catch (e) { err = e; }
check("a very long retry_after is returned to the caller without sleeping", err?.error_code === 429 && Date.now() - t0 < 1500 && hits.length === 1);

server.close();
process.exit(bad ? 1 : 0);
