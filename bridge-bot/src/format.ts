// Message formatting helpers (kept free of Telegram/bot code so they can be tested on their own).

/** Split at line boundaries so formatting tags never get cut in half. */
export function chunk(text: string, size = 3500): string[] {
  const out: string[] = [];
  let cur = "";
  for (const line of text.split("\n")) {
    if (cur && cur.length + line.length + 1 > size) { out.push(cur); cur = ""; }
    cur += (cur ? "\n" : "") + line;
    while (cur.length > size) { out.push(cur.slice(0, size)); cur = cur.slice(size); }
  }
  out.push(cur);
  return out;
}

const escapeHtml = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

/**
 * Light markdown -> Telegram HTML. Producers (shell, Python, Claude) write plain text with:
 *   **bold**, `code`, "- item" / "* item" bullets, "# heading". Everything else is escaped, so stray < or & are safe.
 */
export function toHtml(text: string): string {
  return text.split("\n").map((raw) => {
    let line = escapeHtml(raw);
    const heading = line.match(/^#{1,3}\s+(.*)$/);
    if (heading) return `<b>${heading[1]}</b>`;
    line = line.replace(/^(\s*)[-*]\s+/, "$1• ");
    const codes: string[] = [];
    line = line.replace(/`([^`\n]+)`/g, (_m, c: string) => { codes.push(c); return `\u0000${codes.length - 1}\u0000`; });
    // Telegram may reject <code> nested inside <b>, so a bold span that contains code is rendered without the bold.
    line = line.replace(/\*\*([^*\n]+)\*\*/g, (_m, inner: string) => (inner.includes("\u0000") ? inner : `<b>${inner}</b>`));
    line = line.replace(/\[([^\]\n]+)\]\((https?:\/\/[^\s)"<>]+)\)/g, '<a href="$2">$1</a>');   // [text](url)
    return line.replace(/\u0000(\d+)\u0000/g, (_m, i: string) => `<code>${codes[Number(i)]}</code>`);
  }).join("\n");
}

