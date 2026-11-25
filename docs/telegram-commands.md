# Telegram commands and approvals

> Every command, the plan approval card, auto approval, notes, the ship card, plan mode.

## Daily use

```bash
cd /path/to/project
scripts/agent-room.sh start     # starts the bridge if needed, then the room (tmux or pm2)
npm run dev                     # only when a task verifies in the browser; must listen on APP_PORT
```

Then chat in the project's Topic. `scripts/agent-room.sh stop` stops the room; `bridge-bot/bridge.sh stop` stops the shared bridge
(`agent-room.sh stop` does not touch it). `status` on either script shows what is running.

## Telegram commands

The bot reacts on your message instead of replying: 👀 = written to the room's inbox, 👍 = the Manager handled it, 👎 = the Manager failed (the file is in `.agents/inbox/failed/`).
The reaction state is kept in memory, so after a bridge restart a message that was still pending keeps its 👀.

| Command | Effect |
|---|---|
| `/task <checklist>` | One item per line; adds the tasks **and starts working** (it also resumes after a `/stop`). `/auto` is the old name. Plain text without a command gets a canned reply (no Claude call) |
| `/status` | Board summary |
| `/stop` | AUTO_MODE off, phase IDLE |
| `/resume` | Continue after a stop, a stuck task or a BLOCKED task |
| `/usage [days]` | Claude: tokens, turns and list-price cost per role plus the last 5 calls (from `.agents/logs/usage.log`). OpenCode: sessions, tokens and cost per model from `opencode stats` for this project. Default today / last 24 h, `/usage 7` for a week |
| `/automode on\|off` | **Who approves plans.** `on` (default): a plan that passes the automatic check goes straight to OpenCode; you are asked only for risky plans. `off`: every plan comes to you as a card first. **It never stops the work**: planning, coding, Verify and merging into `staging` carry on, and **shipping always needs you**. With no argument it reports the mode and whether the room is running or paused. Same switch as `/config approval auto\|ask` |
| `/config` · `/config <key> <value>` | Show or change the settings that decide how the room behaves, from chat. Keys: `approval` (`ask`\|`auto`), `links` (`on`\|`off`), `split` (`lines`\|`claude`), `chat` (`on`\|`off`), `model_manager`, `model_techlead` (`haiku`, `sonnet`, `opus`, an id, or `default`), `fix_cycles` (1 to 5), `keep_shipped` (0 to 50). Values are validated; ports, topic ids and branches **cannot** be changed from chat. Effective from the next step, logged in the board's Activity Log |
| `/approve [Tn]` · `/revise <feedback>` · `/reject [Tn]` | Answer the **plan card** (below) without the buttons: approve the plan waiting for you, ask the Tech Lead to change it, or cancel the task. `Tn` is optional when only one plan is waiting |
| `/plan <question>` | **Plan mode**: ask about the project, analyse an idea, get a plan; Tech Lead reads the code and the Manager sends you one summary. Read-only: no task, no branch, no commit, nothing is changed (see [Plan mode](#plan-mode-plan-ask-without-creating-tasks)) |
| `/clear` | Housekeeping (asks you to confirm with two buttons, idle rooms only): archives the board to `.agents/board-archive/` (newest 10 kept) and resets it, and deletes per-task state (`status`, `progress`, `queue`), old `inbox`/`outbox` messages, `/plan` Q&A files and `manager.sig`. Task numbers keep going (the next number is computed from the board, the plan files and the `task/*` branches, so branch and plan names are never reused). **Never touched:** `room.env`, plan files in git, screenshots, logs, `usage.log` |
| `/clearlog [n]` | Truncates `.agents/run.log` and `.agents/logs/*` to their last `n` lines (default 200, `0` empties them); `usage.log` is kept. Idle rooms only. The logs grow forever otherwise (`run.log` of one project reached 3.6 MB) |
| `/health` | Liveness check of the room, answered by the bridge itself (no Claude call, works even if the Manager is dead): bridge, role bots (`getMe`), the three agents each named with what runs it (Manager = the daemon, Tech Lead = Claude Code `claude -p` called by the Manager, with its model and last call, Senior Dev = the OpenCode watcher),  `claude` and `opencode` CLIs, git branch and clean tree, dev server port. Ends with *Sẵn sàng* or the list of what is missing |
| `/ship` | Merge `staging` → `main` (commit message names the shipped tasks) and push (only in `AWAITING_SHIP_APPROVAL`), then tidy up (below); also the **Ship** button. It refuses while the working tree has uncommitted files |
| `/newroom <name> <port> [private] [local] [agents]` | Create a Topic `project-<name>` and a whole room (see [Create a room from Telegram](multi-room.md#create-a-room-from-telegram-newroom)); usable in any Topic, even General |

**Pre-flight.** Before it starts a task, the daemon checks that the OpenCode watcher is alive (`.agents/watcher.pid`). If not, it turns AUTO_MODE off and tells you, instead of leaving the hand-off stuck in `queued`. Run `/health` before `/task` to see everything at once.

**Clean-up after `/ship`** (code, no AI; a failure here never undoes the ship, and the result is appended to the ship reply as `🧹 Đã dọn: …`):
- `.agents/status/*` and `.agents/progress/*` of every shipped task are deleted.
- Verification screenshots move to `.agents/screenshots/archive/<date-time>/`; only the 3 newest batches are kept (archived images are never attached to reports).
- The board keeps the newest `KEEP_SHIPPED` (default 5) shipped tasks; older ones are removed and noted in the Activity Log. Numbering keeps going because the newest task always stays.
- Files in `inbox/processed`, `inbox/failed`, `outbox/sent`, `outbox/failed` older than 7 days are deleted.
- Task plan files in `.agents/tasks/` are kept: they are part of the repository history.

Fresh context is automatic: every Tech Lead call is a new `claude -p` process (no `/clear` needed), and OpenCode only continues a session between step groups of the same task.

**Auto approval (default, `PLAN_APPROVAL="auto"`).** A plan that passes the automatic check goes straight to OpenCode, with no question asked. The queue **never stops for one task**: three situations pass that task over, tell you once, and carry on with the next one in the list:
- **Serious risk** (secrets or keys, migrations, CI/deploy files, `rm -rf`): the plan is **held** and you get the plan card with the buttons. Approve it any time; if another task is running it is queued as `approved` and starts right after.
- **Missing context**: the Tech Lead sets the task to `needs_info` and asks its question (in chat). Answer with `/revise Tn <information>` and the plan is made again, or `/reject Tn`.
- **Blocked** (touches `.env`, deletes data, stuck after the fix cycles): the task is `BLOCKED`, the room stays on; `/resume` tries it again.
Softer doubts (more than 8 steps, a lockfile, no test command) are approved with a note for you. With `PLAN_APPROVAL="ask"` every plan waits for you (card below) and the queue waits too. The daemon always finishes the running task first, then approved plans, then new tasks.

**Two separate switches.** *Automatic mode* (`/automode`) only decides who approves plans. *Running or paused* is `/stop` and `/resume` (or an automatic pause when something is stuck). Turning automatic mode off therefore never makes the room stop: it just asks you at the plan and at the ship. `/task` (formerly `/auto`, the old name still works) adds tasks and starts the work.

**Plan approval card.** When the Tech Lead has written a plan, you get **one card with the whole plan**: goals and decisions made, every step with its difficulty (and how many of each), the test cases (names only), the files it will touch, the Verify mode and what the automatic check found. Three buttons: **✅ Duyệt** (the plan is committed as `APPROVED_BY_USER` and handed to OpenCode), **✏️ Sửa plan** (type `/revise <góp ý>`: the Tech Lead edits the plan on its branch according to your feedback, committed as `plan(rev-N)`, and you get a new card) and **❌ Hủy** (the task is cancelled; its branch is kept). While it waits, the task is in state `awaiting_plan` and **nothing costs anything** (no Claude call, no OpenCode). A plan the automatic check **blocks** (for example it touches `.env`) gets the same card without buttons and is blocked as before. Set `PLAN_APPROVAL="auto"` in `.agents/room.env` for the previous hands-off behaviour (same card, no buttons, the daemon checks and approves by itself). `tools/test-plan-approval.sh` covers it.

**Notes for the approver (`Lưu ý`).** The agents are told to write a line starting with `Lưu ý:` (or `Cảnh báo:`) in "Trạng thái hiện tại" (or in an optional `## Lưu ý` section of the task file) whenever the approver should know something: a deviation from the plan, something left untested or tested less than the goal, a known bug (even a test marked `test.fail`), a follow-up, a non-blocking review finding. The daemon relays only explicit markers, plus the "Đã thử mà không được" section; nothing is guessed. They appear as a **Lưu ý** section in the Dev step report (new notes only, riding along with the next finished step), in the Tech Lead's end-of-task report (all notes of the task) and in the ship approval card ("Lưu ý cần xem trước khi duyệt", and `⚠️ N lưu ý` on the task line).

**What the ship approval card also tells you.** A dry-run merge (`git merge-tree`, needs git 2.38+) says whether `/ship` will conflict and on which files, and mentions commits that exist on `main` but not on `staging`; each task shows its fix cycles and model escalations; and the Claude cost of the batch (calls labelled with the task ids, API list price, OpenCode not included).

**Problems are not silent.** Things that used to be only logged are now told to you, once per interval so they never spam: the daemon turning AUTO_MODE off because of an unknown task state, a message the bridge gave up on (moved to `outbox/failed/`), a failing progress report, a failed `git push` for commit links (so you know why links are missing), and a failing 👀 reaction. When the Manager (Claude) approves a plan that the automatic check doubted, you get a line saying why it looked closer.

**One Tech Lead report per task.** A passing Verify is not announced on its own: it waits for the merge and goes out in the single `🎉` report together with the merge commit and the pictures (a Verify that fails is told immediately). The pictures are sent only once: the ship approval then does not send them again, it just says "📸 N ảnh trong báo cáo T05 ở trên" next to the task. There is no separate "verify + review" start message either, because the Dev's "Code xong hết rồi nè" already is the hand-off signal. For the merge link to open, the daemon also pushes `staging` once per finished task (same `COMMIT_LINKS` switch). `tools/test-techlead-report.sh` covers it.

## Plan mode (`/plan`): ask without creating tasks

`/task` turns your text into tasks and starts the coding. When you only want information, an opinion or a plan, use:

```
/plan Project này đang có những màn hình nào, và thêm chức năng upload ảnh thì động tới file nào?
```

Only two agents work, together, and you get **one summary message**:

1. The Manager acknowledges the question and hands it to the Tech Lead.
2. The Tech Lead (Claude) reads the repo (`AGENTS.md`, `CLAUDE.md`, the board and whatever code it needs) and writes a technical analysis with file paths, risks and what it is unsure about.
3. The Manager (Claude, no tools) merges that with the board into a friendly message: short answer, **Góc nhìn Tech Lead**, and, when there is a concrete way to do it, ready-to-copy `/task …` lines (only suggestions, nothing is started).

**It cannot change anything.** The Tech Lead runs with `--tools "Read,Grep,Glob"`: it has no tool that can write a file or run a command (a test asked Claude to create and delete files on purpose and it could not), and `--dangerously-skip-permissions` is not used. The Manager step has no tools at all. No OpenCode, no task, no branch, no commit.
It runs in the background, so the room keeps answering `/status` and keeps working on tasks meanwhile; one question at a time (a second `/plan` gets a polite "wait"). A question costs two Claude calls (turn caps: `MAX_TURNS_PLAN` for the reading, `MAX_TURNS_MANAGER` for the summary; models from `MODEL_TECHLEAD` / `MODEL_MANAGER`) and shows up in `/usage` as `plan: tìm hiểu` and `plan: tổng hợp`.
If the Tech Lead fails you are told; if only the Manager fails you get the Tech Lead's analysis as it is. Every question, analysis and answer is kept in `.agents/plan/` (git-ignored), and the run log is `.agents/logs/plan.log`.
`tools/test-plan-mode.sh` is the regression test (fake `claude`, checks the tool restriction, the background behaviour and the failure paths).
