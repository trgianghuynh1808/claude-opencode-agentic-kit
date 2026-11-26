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
    ask: "Bạn muốn giao việc gì nè? 📝\n**Tin nhắn kế tiếp của bạn** sẽ là nội dung việc, mỗi dòng một việc. Muốn làm rõ hơn thì gửi kèm ảnh (chụp màn hình, mockup): gửi ảnh trước hay cùng lúc với mô tả đều được 📎",
    placeholder: "Mỗi dòng một việc cần làm",
    images: true,
  },
  "/plan": {
    ask: "Bạn muốn hỏi gì về project nè? 🔍\n**Tin nhắn kế tiếp của bạn** sẽ là câu hỏi. Mình và Tech Lead sẽ đọc code rồi tổng hợp, không sửa gì và không tạo task nào hết.",
    placeholder: "Câu hỏi về project",
    images: false,
  },
  "/revise": {
    ask: "Bạn muốn sửa gì ở plan nè? ✏️\n**Tin nhắn kế tiếp của bạn** sẽ là góp ý. Có ảnh minh hoạ thì gửi kèm luôn nhé 📎",
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
  created: number;
}

/** A plain message (not a Telegram reply) still answers the prompt when it comes this soon after it. */
export const IMPLICIT_TTL_MS = 10 * 60 * 1000;

export class PromptStore {
  private byMessage = new Map<number, PendingPrompt>();
  private byTopic = new Map<number, number>();   // topic -> message id of its latest prompt
  constructor(private now: () => number = Date.now) {}

  add(messageId: number, p: Omit<PendingPrompt, "created">): void {
    this.sweep();
    this.byMessage.set(messageId, { ...p, created: this.now() });
    this.byTopic.set(p.topicId, messageId);
  }

  /** The prompt a message answers: the one it replies to, else the latest of its topic if still fresh. Does not consume it. */
  find(replyToId: number | undefined, topicId: number | undefined): { id: number; prompt: PendingPrompt } | null {
    if (topicId === undefined) return null;
    const t = this.now();
    if (replyToId !== undefined) {
      const p = this.byMessage.get(replyToId);
      if (p && p.topicId === topicId && t - p.created <= PROMPT_TTL_MS) return { id: replyToId, prompt: p };
    }
    const id = this.byTopic.get(topicId);
    const p = id === undefined ? undefined : this.byMessage.get(id);
    return id !== undefined && p && t - p.created <= IMPLICIT_TTL_MS ? { id, prompt: p } : null;
  }

  /** Same as find, and the prompt is used up. */
  take(replyToId: number | undefined, topicId: number | undefined): PendingPrompt | null {
    const f = this.find(replyToId, topicId);
    if (!f) return null;
    this.forget(f.id);
    return f.prompt;
  }

  /** Drop the pending prompt of a topic (the user typed another command instead). */
  clearTopic(topicId: number | undefined): void {
    const id = topicId === undefined ? undefined : this.byTopic.get(topicId);
    if (id !== undefined) this.forget(id);
  }

  private forget(id: number): void {
    const p = this.byMessage.get(id);
    this.byMessage.delete(id);
    if (p && this.byTopic.get(p.topicId) === id) this.byTopic.delete(p.topicId);
  }

  private sweep(): void {
    const t = this.now();
    for (const [k, v] of this.byMessage) if (t - v.created > PROMPT_TTL_MS) this.forget(k);
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
