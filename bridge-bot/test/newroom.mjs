import { kitArgs, nowNs, parseKitOutput, parseNewRoom, topicColor, topicLink, topicTitle } from "../dist/newroom.js";

let bad = 0;
const check = (name, ok, extra = "") => { console.log(`${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : " " + extra}`); if (!ok) bad++; };
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// --- parseNewRoom
let r = parseNewRoom("tea-party 3001");
check("parses name and port", r.ok && r.req.name === "tea-party" && r.req.port === 3001 && !r.req.private && !r.req.local && !r.req.agents);
r = parseNewRoom("my.app_2 5173 private agents");
check("parses flags", r.ok && r.req.private && r.req.agents && !r.req.local);
r = parseNewRoom("  spaced   3000   LOCAL ");
check("flags are case-insensitive, spaces are tolerated", r.ok && r.req.local && r.req.name === "spaced");
check("needs a port", !parseNewRoom("only-name").ok);
check("needs a name", !parseNewRoom("").ok);
check("rejects a path separator", !parseNewRoom("../etc 3000").ok && !parseNewRoom("a/b 3000").ok);
check("rejects shell characters", !parseNewRoom("a;rm 3000").ok && !parseNewRoom("a$(x) 3000").ok && !parseNewRoom("a`b` 3000").ok);
check("rejects a leading dash (would look like a flag)", !parseNewRoom("-rf 3000").ok);
check("rejects spaces inside a name via extra token", !parseNewRoom("my app 3000").ok);
check("rejects ports out of range", !parseNewRoom("a 80").ok && !parseNewRoom("a 70000").ok && !parseNewRoom("a abc").ok);
check("rejects unknown flags", !parseNewRoom("a 3000 --force").ok && !parseNewRoom("a 3000 yolo").ok);
check("private and local conflict", !parseNewRoom("a 3000 private local").ok);

// --- topic title
check("topic is named project-<name>", topicTitle("tea-party") === "project-tea-party");

// --- kit arguments
const req = (o = {}) => ({ name: "app", port: 3001, private: false, local: false, agents: false, ...o });
check("new project args", same(kitArgs(req(), false, "/p/app", 9), ["new", "app", "--topic", "9", "--port", "3001", "--yes"]));
check("existing project args use the path", same(kitArgs(req(), true, "/p/app", 9), ["add", "/p/app", "--topic", "9", "--port", "3001", "--yes"]));
check("private repo flag", kitArgs(req({ private: true }), false, "/p/app", 9).includes("--private"));
check("local flag", kitArgs(req({ local: true }), false, "/p/app", 9).includes("--no-github"));
check("repo flags are ignored for an existing project", !kitArgs(req({ private: true, local: true }), true, "/p/app", 9).some((a) => a === "--private" || a === "--no-github"));
check("agents flag", kitArgs(req({ agents: true }), false, "/p/app", 9).includes("--agents"));
check("extra args are appended", same(kitArgs(req(), false, "/p/app", 9, ["--no-start"]).slice(-1), ["--no-start"]));
check("every arg is a plain string without shell syntax", kitArgs(req({ name: "a.b_c-d" }), false, "/p/a.b_c-d", 9).every((a) => !/[;&|$`\s]/.test(a)));

// --- colours, links, output, names
check("icon colour is one of Telegram's six", [7322096, 16766590, 13338331, 9367192, 16749490, 16478047].includes(topicColor("tea-party")));
check("icon colour is stable per name", topicColor("x") === topicColor("x"));
check("t.me link for a supergroup", topicLink(-1005817211080, 6) === "https://t.me/c/5817211080/6");
check("no link for a basic group", topicLink(-12345, 6) === undefined);
const out = parseKitOutput("\x1b[32m  ✓\x1b[0m Repo GitHub: https://github.com/u/app (public)\nline2\n\n");
check("kit output: strips colours and finds the repo URL", out.repoUrl === "https://github.com/u/app" && out.tail.every((l) => !l.includes("\x1b")));
check("kit output: keeps only the last 12 lines", parseKitOutput(Array.from({ length: 40 }, (_, i) => `l${i}`).join("\n")).tail.length === 12);
const a = nowNs(), b = nowNs();
check("nowNs is 19 digits and monotonic", /^\d{19}$/.test(a) && BigInt(b) >= BigInt(a));

process.exit(bad ? 1 : 0);
