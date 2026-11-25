import { toHtml, chunk } from "../dist/format.js";
const cases = [
  ["**Plan** xong rồi nè 📋", "<b>Plan</b> xong rồi nè 📋"],
  ["- bước **1** `a.ts`", "• bước <b>1</b> <code>a.ts</code>"],
  ["  - lồng nhau", "  • lồng nhau"],
  ["## Tiêu đề", "<b>Tiêu đề</b>"],
  ["a < b & c > d", "a &lt; b &amp; c &gt; d"],
  ["`x <y> **z**`", "<code>x &lt;y&gt; **z**</code>"],
  ["dấu ` lẻ loi", "dấu ` lẻ loi"],
  ["**chưa đóng", "**chưa đóng"],
  ["1. giữ nguyên số", "1. giữ nguyên số"],
  ["**a** và **b**", "<b>a</b> và <b>b</b>"],
  ["**Nhánh `staging`** xong", "Nhánh <code>staging</code> xong"],
  ["- [abc1234](https://github.com/o/r/commit/abc1234) fix a & b", '• <a href="https://github.com/o/r/commit/abc1234">abc1234</a> fix a &amp; b'],
  ["[x](javascript:alert(1))", "[x](javascript:alert(1))"],
];
let bad = 0;
for (const [i, want] of cases) { const got = toHtml(i); const ok = got === want; if (!ok) bad++; console.log(ok ? "ok  " : "FAIL", JSON.stringify(i), ok ? "" : `-> ${got}`); }
const long = Array.from({ length: 400 }, (_, i) => `dòng ${i} **đậm**`).join("\n");
const parts = chunk(long);
const intact = parts.every((p) => (p.match(/\*\*/g) ?? []).length % 2 === 0);
console.log(parts.length > 1 && intact && parts.every((p) => p.length <= 3500) ? "ok   chunk: " + parts.length + " phần, tag không bị cắt" : "FAIL chunk");
if (!intact) bad++;
process.exit(bad ? 1 : 0);
