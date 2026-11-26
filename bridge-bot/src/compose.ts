// Pure helpers for "type a command, then fill in the rest": which commands need text, the ForceReply prompt for each,
// and the store that remembers which prompt message (and which pictures) a reply belongs to.

export interface PromptSpec {
  /** Message shown when the command arrives without text. */
  ask: string;
  /** Greyed hint inside the reply box. */
  placeholder: string;
  /** Whether pictures can be attached to this command. */
  images: boolean;
}

export const NEEDS_TEXT: Record<string, PromptSpec> = {
  "/task": {
    ask: "Bạn muốn giao việc gì nè? 📝\n**Trả lời tin nhắn này** bằng mô tả, mỗi dòng một việc. Muốn làm rõ hơn thì đính kèm ảnh (chụp màn hình, mockup) ngay trong câu trả lời 📎",
    placeholder: "Mỗi dòng một việc cần làm",
    images: true,
  },
  "/plan": {
    ask: "Bạn muốn hỏi gì về project nè? 🔍\n**Trả lời tin nhắn này** bằng câu hỏi. Mình và Tech Lead sẽ đọc code rồi tổng hợp, không sửa gì và không tạo task nào hết.",
    placeholder: "Câu hỏi về project",
    images: false,
  },
  "/revise": {
    ask: "Bạn muốn sửa gì ở plan nè? ✏️\n**Trả lời tin nhắn này** bằng góp ý. Có ảnh minh hoạ thì đính kèm luôn nhé 📎",
    placeholder: "Góp ý cho plan",
    images: true,
  },
};
// /auto is the old name of /task
NEEDS_TEXT["/auto"] = NEEDS_TEXT["/task"];

export function canAttachImages(command: string | null): boolean {
  return !!command && !!NEEDS_TEXT[command]?.images;
}

export const MAX_IMAGES = 5;
export const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
export const PROMPT_TTL_MS = 30 * 60 * 1000;

export interface ImageRef {
  fileId: string;
  ext: string;
  size?: number;
}

export interface PendingPrompt {
  command: string;
  topicId: number;
  images: ImageRef[];
  expires: number;
}

export class PromptStore {
  private items = new Map<number, PendingPrompt>();
  constructor(private now: () => number = Date.now) {}

  add(messageId: number, p: Omit<PendingPrompt, "expires">): void {
    this.sweep();
    this.items.set(messageId, { ...p, expires: this.now() + PROMPT_TTL_MS });
  }

  /** Take the prompt a reply points at (one-shot); null when unknown, expired or from another topic. */
  take(replyToId: number | undefined, topicId: number | undefined): PendingPrompt | null {
    if (replyToId === undefined) return null;
    const p = this.items.get(replyToId);
    if (!p) return null;
    if (p.expires < this.now() || p.topicId !== topicId) return null;
    this.items.delete(replyToId);
    return p;
  }

  private sweep(): void {
    const t = this.now();
    for (const [k, v] of this.items) if (v.expires < t) this.items.delete(k);
  }
}

/** `/task@bot args` → { command: "/task", args } for known commands; command is null otherwise (plain text or unknown). */
export function parseSlash(text: string, known: Set<string>): { isSlash: boolean; command: string | null; args: string } {
  const m = text.match(/^\/([a-z_]+)(?:@\w+)?(?:\s+([\s\S]*))?$/i);
  if (!m) return { isSlash: false, command: null, args: "" };
  const name = m[1].toLowerCase();
  return { isSlash: true, command: known.has(name) ? `/${name}` : null, args: (m[2] ?? "").trim() };
}

export function imageExt(mime?: string, fileName?: string): string | null {
  const byName = fileName?.match(/\.(png|jpe?g|webp|gif)$/i)?.[1]?.toLowerCase();
  if (byName) return byName === "jpeg" ? "jpg" : byName;
  const byMime = mime?.match(/^image\/(png|jpeg|webp|gif)$/i)?.[1]?.toLowerCase();
  if (byMime) return byMime === "jpeg" ? "jpg" : byMime;
  return null;
}
