// Pure helpers of the /newroom flow (no Telegram, no I/O), kept apart so they can be tested on their own.

export interface NewRoomRequest {
  name: string;      // project folder name under the projects dir, also the room name
  port: number;      // dev server port
  private: boolean;  // new project only: private GitHub repo (default is public)
  local: boolean;    // new project only: no GitHub repo
  agents: boolean;   // ask Claude to draft AGENTS.md
}

export type ParsedNewRoom = { ok: true; req: NewRoomRequest } | { ok: false; error: string };

export const NEWROOM_USAGE =
  "Cách dùng: `/newroom <tên-project> <port> [private] [local] [agents]`\n" +
  "- ví dụ: `/newroom tea-party 3001`\n" +
  "- `private`: repo GitHub riêng tư (mặc định public) · `local`: không tạo repo GitHub · `agents`: nhờ Claude soạn nháp AGENTS.md";

const NAME_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,60}$/;
const FLAGS = new Set(["private", "local", "agents"]);

export function parseNewRoom(args: string): ParsedNewRoom {
  const t = args.trim().split(/\s+/).filter(Boolean);
  if (t.length < 2) return { ok: false, error: `Mình cần tên project và port nha 📝\n${NEWROOM_USAGE}` };
  const [name, portStr, ...flags] = t;
  if (!NAME_RE.test(name)) {
    return { ok: false, error: "Tên project chỉ gồm chữ, số, `.`, `_` và `-` (tối đa 61 ký tự) nha 🙏" };
  }
  if (!/^\d+$/.test(portStr) || Number(portStr) < 1024 || Number(portStr) > 65535) {
    return { ok: false, error: "Port phải là số từ 1024 đến 65535 nha 🙏" };
  }
  for (const f of flags) {
    if (!FLAGS.has(f.toLowerCase())) return { ok: false, error: `Mình chưa hiểu \`${f}\` 😅\n${NEWROOM_USAGE}` };
  }
  const has = (f: string) => flags.some((x) => x.toLowerCase() === f);
  if (has("private") && has("local")) return { ok: false, error: "`private` và `local` không đi cùng nhau được nha: chọn một thôi 🙏" };
  return { ok: true, req: { name, port: Number(portStr), private: has("private"), local: has("local"), agents: has("agents") } };
}

/** Telegram Topic title: every project room is named project-<name>. */
export const topicTitle = (name: string): string => `project-${name}`;

/** Arguments for the `kit` CLI. Only arguments built here are ever passed (no shell), so names cannot inject anything. */
export function kitArgs(req: NewRoomRequest, existing: boolean, dir: string, topicId: number, extra: string[] = []): string[] {
  const args = existing ? ["add", dir] : ["new", req.name];
  args.push("--topic", String(topicId), "--port", String(req.port), "--yes");
  if (!existing) {
    if (req.local) args.push("--no-github");
    else if (req.private) args.push("--private");
  }
  if (req.agents) args.push("--agents");
  return [...args, ...extra];
}

// The only colours Telegram accepts for a forum topic icon.
const TOPIC_COLORS = [7322096, 16766590, 13338331, 9367192, 16749490, 16478047] as const;
export type TopicColor = (typeof TOPIC_COLORS)[number];
export function topicColor(name: string): TopicColor {
  let h = 0;
  for (const c of name) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return TOPIC_COLORS[h % TOPIC_COLORS.length];
}

// eslint-disable-next-line no-control-regex
const ANSI = /\x1b\[[0-9;?]*[A-Za-z]/g;

/** Clean `kit` output: strip colours, pick out the GitHub URL, keep the last lines for error reports. */
export function parseKitOutput(out: string): { repoUrl?: string; tail: string[] } {
  const clean = out.replace(ANSI, "");
  const repo = clean.match(/Repo GitHub: (https:\/\/github\.com\/\S+)/);
  const lines = clean.split("\n").map((l) => l.trimEnd()).filter(Boolean);
  return { repoUrl: repo?.[1], tail: lines.slice(-12) };
}

/** t.me link to a topic of a supergroup (chat ids look like -100<digits>). */
export function topicLink(chatId: number, threadId: number): string | undefined {
  const s = String(chatId);
  return s.startsWith("-100") ? `https://t.me/c/${s.slice(4)}/${threadId}` : undefined;
}

/** Epoch nanoseconds as a 19-digit string, the same file-name scheme as room-ops.py so the poller keeps the order. */
export function nowNs(): string {
  return (BigInt(Date.now()) * 1_000_000n + (process.hrtime.bigint() % 1_000_000n)).toString();
}
