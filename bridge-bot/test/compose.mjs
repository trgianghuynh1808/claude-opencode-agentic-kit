// Compose helpers: which commands ask for text, the one-shot prompt store, slash parsing, image types.
import { NEEDS_TEXT, PromptStore, canAttachImages, imageExt, parseSlash, PROMPT_TTL_MS, IMPLICIT_TTL_MS } from "../dist/compose.js";

let bad = 0;
const check = (name, ok) => { console.log(`${ok ? "ok  " : "FAIL"} ${name}`); if (!ok) bad++; };
const known = new Set(["task", "auto", "plan", "revise", "status"]);

check("/task, /auto, /plan, /revise ask for text", ["/task", "/auto", "/plan", "/revise"].every((c) => NEEDS_TEXT[c]?.ask && NEEDS_TEXT[c]?.placeholder));
check("/status needs no text", !NEEDS_TEXT["/status"]);
check("pictures allowed for /task and /revise, not /plan", canAttachImages("/task") && canAttachImages("/auto") && canAttachImages("/revise") && !canAttachImages("/plan") && !canAttachImages(null));

let p = parseSlash("/task@my_bot làm A\nlàm B", known);
check("parse: command, bot suffix and multi-line args", p.command === "/task" && p.args === "làm A\nlàm B");
p = parseSlash("/task", known);
check("parse: command without text", p.command === "/task" && p.args === "" && p.isSlash);
p = parseSlash("/nope abc", known);
check("parse: unknown command is slash but not a command", p.isSlash && p.command === null);
p = parseSlash("xin chào", known);
check("parse: plain text", !p.isSlash && p.command === null);

let t = 1000;
const store = new PromptStore(() => t);
store.add(10, { command: "/task", topicId: 6, images: [{ fileId: "f", ext: "jpg" }] });
check("a reply in the same topic takes the prompt, once", store.take(10, 6)?.images.length === 1 && store.take(10, 6) === null);
store.add(11, { command: "/revise T03", topicId: 6, images: [] });
check("another topic does not take it", store.take(11, 7) === null && store.find(undefined, 7) === null);
check("a plain message (no reply link) answers the latest prompt of its topic", store.take(undefined, 6)?.command === "/revise T03");
store.add(12, { command: "/task", topicId: 6, images: [] });
store.add(13, { command: "/plan", topicId: 6, images: [] });
check("the latest prompt of a topic wins", store.take(undefined, 6)?.command === "/plan");
store.clearTopic(6);
check("clearTopic drops the pending prompt", store.find(undefined, 6) === null);
store.add(14, { command: "/task", topicId: 6, images: [] });
t += IMPLICIT_TTL_MS + 1;
check("after 10 min a plain message no longer answers, an explicit reply still does", store.find(undefined, 6) === null && store.find(14, 6)?.id === 14);
t += PROMPT_TTL_MS;
check("an expired prompt is gone", store.take(14, 6) === null);
check("no reply target and no prompt → null", store.take(undefined, 6) === null);

check("image types", imageExt("image/jpeg") === "jpg" && imageExt(undefined, "a.PNG") === "png" && imageExt("image/webp") === "webp" && imageExt("application/pdf") === null);

process.exit(bad ? 1 : 0);
