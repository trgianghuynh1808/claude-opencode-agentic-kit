# Multi-room mode (Telegram + Manager)

> Unattended rooms controlled from Telegram: the flow and states, setup, bot identities, the `kit` command, `/newroom`.

Optional. Turns the 2-agent kit into three tiers that run unattended, for several projects at once, controlled from Telegram.

| Tier | Agent | Runs as | Job |
|---|---|---|---|
| Manager | Code first, Claude only for judgement | `scripts/room-ops.py` (bash/Python, no AI); `claude -p` with `.agents/MANAGER.md` only when needed | Splits `/task` into tasks, checks and approves plans (guardrails), holds risky ones for you, reports, ships on `/ship`. Calls Claude only for free-form chat (off by default) and `/plan` |
| Tech Lead | Claude Code | `claude -p` (headless), `CLAUDE.md` section AUTO_MODE | Plans, verifies, reviews, squash-merges into `staging` |
| Senior Dev | OpenCode | `watch-tasks.sh` → `run-task.sh` | Implements and runs tests, as in the single-project mode |

`scripts/manager-loop.sh` is plain bash, not an AI: it reads the state on `board.md` and decides what to do. Everything mechanical runs in code (`scripts/room-ops.py`), so an idle or routine room costs no Claude quota.

Each project is a **room**: its own `.agents/room.env` (port, topic, branches), its own daemons (tmux/pm2), its own Telegram **Topic**.
One **bridge bot** (`bridge-bot/`) connects a Telegram Supergroup (Topics enabled) to all rooms through files:
Telegram message → `.agents/inbox/*.json`; Manager report/screenshots → `.agents/outbox/*.json` → Telegram.

```
Telegram Topic #a ─┐                          ┌─ Room A: manager-loop + watch-tasks (port 3001)
Telegram Topic #b ─┼─► bridge-bot ◄─ files ─►┤
                                              └─ Room B: manager-loop + watch-tasks (port 3002)
```

## Flow in AUTO_MODE

1. `/task <checklist>` (old name `/auto` still works) → one task per line (bullets and numbers are stripped), written as `[pending]` on `board.md`; `staging` is created from `main`. It also starts the work. `/automode on|off` only decides whether plans are approved automatically or by you; shipping always needs you. Set `AUTO_SPLIT="claude"` in `room.env` to let Claude split a free-form request instead.
2. For each task, the daemon runs one step at a time (state lives on `board.md`):

   | State | Who acts | Next state |
   |---|---|---|
   | `pending` | Tech Lead (Claude) writes the plan on branch `task/<slug>` (no hand-off yet). If context is missing it asks a question instead | `plan_ready` (or `needs_info`) |
   | `plan_ready` | Code checks the plan and sends the **plan card**. `PLAN_APPROVAL=auto`: `OK`/`REVIEW` → approved and handed off, `CRITICAL` → held, `BLOCK` → blocked. `ask`: always held | `in_progress`, `awaiting_plan`, or `BLOCKED` |
   | `awaiting_plan` | You: ✅ Duyệt / ✏️ Sửa plan / ❌ Hủy (or `/approve`, `/revise`, `/reject`). Costs nothing while it waits | `in_progress` (or `approved` if another task is running), `revise`, `cancelled` |
   | `needs_info` | You answer with `/revise Tn <information>` | `pending` (plan is made again) |
   | `revise` | Tech Lead edits the plan according to your feedback (`plan(rev-N)` commit), a new card is sent | `plan_ready` |
   | `approved` | Waits its turn; the daemon hands it off when nothing else is running | `in_progress` |
   | `in_progress` | The daemon itself waits for OpenCode (reads `.agents/status`); when it is `done` or `stuck`, Tech Lead (Claude) verifies, reviews, fixes (max `MAX_FIX_CYCLES`) and squash-merges into `staging` | `done` |

   The daemon works in this order: the task already running → plans you approved → new tasks. With `PLAN_APPROVAL=auto`, tasks waiting on you (`awaiting_plan`, `needs_info`, `BLOCKED`) are passed over so the queue keeps moving.

   Plan checks (`room-ops.py check-plan`): **BLOCK** = no steps, touches `.env`, `DROP`/`TRUNCATE`/`DELETE FROM`. **CRITICAL** = secrets/credentials, migrations, CI/deploy config, `rm -rf`. **REVIEW** = more than 8 steps, a step without a difficulty label, lockfiles, no concrete test command (approved with a note). Anything else is `OK`.
   The plan check does not compare the plan with the task title (that needs judgement); keep tasks small and check the plan in the log if a task is risky.

3. All tasks done → phase `AWAITING_SHIP_APPROVAL`; you get the evidence and then the approval card, all built by code:
   - for each task that has verification pictures, a `📸 T05 · title` message from the Tech Lead with **that task's own pictures only** (only files named `task-NN-*.png` or containing the task slug, whatever their timestamp); a task with no pictures sends none;
   - the approval card with the **Ship** button: tasks (each saying how many pictures are above, or that Verify was skipped / nothing was captured), and the commits not yet on `main`. Pictures from earlier work or other tasks are never attached.
4. `/ship` merges `staging` into `main` and pushes. Nothing reaches `main` without it. The merge commit names what is shipped (`Ship T10: <title>`, or `Ship 3 task: T08, T09, T10` with one line per task in the body).

**Fresh context per call.** Every `claude -p` call is a new process with an empty context window. State is passed through files
(`board.md`, the task file, git, `CLAUDE.md`/`AGENTS.md`), never through memory, so anything the next step needs must be written there.
OpenCode is different: it continues one session across the steps of a task (see `FRESH_RULES`).

**Safety**
- The daemon never loops on a stuck state: the same task/state twice without progress turns AUTO_MODE off and tells you (`/resume` to retry).
- Guardrails block plans that touch `.env`/secrets/CI config, destructive migrations, or drift from the task.
- Only `ADMIN_USER_ID` in `TELEGRAM_CHAT_ID` is obeyed; screenshots are only sent from inside the room directory.
- The daemon runs `claude -p ... --dangerously-skip-permissions` (override with `CLAUDE_FLAGS`). The Manager's "no application code" rule is a prompt instruction, not enforced by the system. Run rooms only on projects and machines you trust.
- Quota: see [Claude quota](operations.md#claude-quota) below.

## First-time setup (once per machine)

1. **Telegram:** create a bot with @BotFather and turn **Group Privacy** off (Bot Settings). Create a Supergroup, enable **Topics**, add the bot as admin
   (with *Manage Topics*), and create one Topic per project.
2. **Bridge bot:** `cp bridge-bot/.env.example bridge-bot/.env` and fill `BOT_TOKEN`. Leave `ADMIN_USER_ID` and `TELEGRAM_CHAT_ID` empty,
   run `bridge-bot/bridge.sh start`, and send any message in a Topic: the bot (discovery mode) replies with `ADMIN_USER_ID`, `TELEGRAM_CHAT_ID` and the Topic ID.
   Put the two ids in `.env`, then `bridge-bot/bridge.sh stop && bridge-bot/bridge.sh start`.
   `.env` format: one `KEY=value` per line, no quotes, no spaces, no trailing comments.

## Role identities (optional: one bot per role)

Messages in a Topic come from three roles. Progress is read from the task file, the board and git by the daemon (`room-ops.py progress`),
so it needs no extra Claude calls and works even if an agent forgets to report:

| Role | Reports |
|---|---|
| `🧭 Manager` | Replies to commands, plan approval or block, the ship report with the **Ship** button |
| `🛠 Tech Lead` | `▶` when it starts planning, `📋` plan summary (steps, tests, Verify mode), `🔁` each fix cycle, `🔎` a **failing** Verify at once (with notes and pictures, because a fix cycle follows), and **one report at the end of each task** (`🎉 T05 …`): **Verify** (result and the notes it wrote), **Merge** (the commit on `staging`, linked) and the verification pictures, attached once |
| `⌨️ Senior Dev` | `▶` task start; **when a step is done** (one message, no separate start message): `✅ Bước N/T xong` with the **Mô tả** (difficulty `dễ`/`vừa`/`khó` and what the step was), **Commit** (linked to GitHub) and **Kết quả test** (tests that changed result); `↗` a retry with a stronger model; `⛔` when a step still fails on the strongest model; done or stuck (`watch-tasks.sh`) |

The `↗` and `⛔` messages come from `run-task.sh` itself (it knows the model and the retries); the per-step report is derived from the task file and git by the daemon (`room-ops.py progress`). It relies on the task file keeping the template shape: ticked `- [x] N.` steps, `T1: PASS|FAIL` lines under `Test status`, a `## Verify` section ending with `VERIFY: PASS|FAIL`.
A step is reported once, after its task file has been quiet for a few seconds, so a commit or a test result that comes a moment after the checkbox still lands in the same message; a lone commit or test result waits for the next finished step, and anything left when OpenCode is done is sent once as "Phần còn lại".
**Commit links.** They open on GitHub only if the commit is there, so when it reports a step the daemon pushes the task branch to `origin` **once per reported step** (never per commit or per check; it never asks for a password and gives up for 10 minutes after a failure) and deletes that remote branch when you `/ship`. Set `COMMIT_LINKS="false"` in `.agents/room.env` to turn this off (no push, no links; commits show as plain hashes). Only GitHub remotes get links. `tools/test-step-report.sh` covers it.
Reported state is kept in `.agents/progress/<slug>.json` (git-ignored); if the daemon restarts in the middle of a task it continues from the current state instead of replaying old steps.
**Telegram rate limit.** Telegram allows about 20 messages a minute per bot per group, shared by all Topics, and answers `429` with `retry_after` seconds when it is exceeded. The bridge waits exactly that long and sends again; the wait is kept **per bot**, so every room using a bot that was told to wait waits too. A wait longer than `MAX_RETRY_AFTER_S` (default 120) is not slept off and the outbox poller's own retry count applies. Ordering is kept: each room sends one message at a time.

Reports are sent with Telegram link previews turned off, so a commit link does not add a big GitHub card.

Messages are produced as `.agents/outbox/*.json` with a `"from"` field (`manager` | `techlead` | `dev`; default `manager`).

**Tone and format.** Messages are written in a friendly, relaxed Vietnamese ("mình" / "bạn", light emoji), split into short sections, with lists for tasks and steps.
Producers write plain text with a tiny markdown subset (`**bold**`, `` `code` ``, `- ` bullets, `# ` headings) and the bridge converts it to Telegram HTML
(`bridge-bot/src/format.ts`): everything else is escaped, so stray `<`, `>` or `&` are safe, long messages are split at line boundaries, and if Telegram still
rejects the markup the raw text is sent instead, so a message is never lost. Step texts are trimmed at a word boundary without leaving a dangling backtick.
Claude-written messages follow the same style (it is part of the daemon prompt and `.agents/MANAGER.md`). `cd bridge-bot && npm test` checks the converter.

By default all three use the main bot and only the label differs. For separate identities (own name and avatar), create two more bots in BotFather,
add them to the group as ordinary members (admin is not needed: they only send, and Group Privacy does not matter), and set `BOT_TOKEN_TECHLEAD` and `BOT_TOKEN_DEV` in `bridge-bot/.env`. They only send: commands, reactions and the Ship button
stay on the main bot, so a message that needs approval is always sent by the Manager. The startup log shows which identity each role uses.

## The `kit` command (add, upgrade, status)

One command replaces the manual steps. Put it on your PATH once (any folder in your PATH works):

```bash
ln -s ~/Documents/projects/claude-opencode-kit/kit ~/.local/bin/kit
```

| Command | What it does |
|---|---|
| `kit new <name> --port 3001 --topic 12` | **New project from scratch**: creates `~/Documents/projects/<name>` (`KIT_PROJECTS_DIR`), `git init` on `main`, `.gitignore`, `README.md`, first commit, a **public** GitHub repo with `gh` (asks you to confirm first; `--private`, or `--no-github` for local only), then everything `kit add` does. `--template "npm create vite@latest . -- --template vanilla-ts"` runs your scaffolding command in the empty folder first |
| `kit add <path> --port 3001 --topic 12` | **Existing project** (including one on the old two-agent install; its `CLAUDE.md` and `config.sh` are kept): checks the prerequisites (git repo with a commit, clean tree, `claude`, `opencode`, `tmux`/`pm2`, `bridge-bot/.env`), installs the kit, creates the room and registers the Topic, adds or refreshes the AUTO_MODE section of an existing `CLAUDE.md` (the rest is kept), commits, starts the room (and the bridge if needed) and shows its status |
| `kit upgrade [name]` | Updates the kit in every registered room (or one). A room is skipped, with the reason, when it is busy (AUTO_MODE on, OpenCode running, a task in progress) or its git tree is dirty. An idle running room is stopped, updated, committed and started again; a stopped room stays stopped. The bridge is restarted once at the end (`--no-bridge` to skip) `KIT_UPGRADE_FORCE=1 kit upgrade` skips only tasks waiting for **you** (`needs_info`, `awaiting_plan`); a running room, a running OpenCode or a task in progress is always refused. A job cut off anyway (room stopped mid-run) is queued again when the watcher starts |
| `kit status` | One table: every room, running or not, AUTO_MODE, the task in progress and the kit version it runs (flagged when behind) |
| `kit scan [folder]` | Scans your projects folder (default `~/Documents/projects`) for every project that carries kit files, registered or not, with its kit version and the command to fix it: a legacy install with no room gets a `kit add …` hint. `kit status --all` shows the same list under the rooms table |
| `kit attach [name]` | Opens the room's tmux session (`room-<name>`); a part of the name is enough (`kit attach tea`), and no name is needed with a single room. Leave with `Ctrl+B` then `D`: typing `exit` or `Ctrl+C` in the pane stops the room. Rooms run by pm2 show their log instead |
| `kit logs [name]` | `tail -f` of the room's `.agents/logs/activity.log` (coloured by role); `Ctrl+C` only stops the viewing, never the room |
| `kit remove <name>` | Stops a room and removes it from the bridge; the project files are left alone |

Common flags: `--agents` asks Claude once to **draft `AGENTS.md`** from the repo (committed separately as `docs: draft AGENTS.md (review before use)`: read it before the first task),
`--no-start` only prepares the room, `--yes` answers the confirmation. Without `--topic`, `kit` explains how to get one and asks for it; without `--port` it guesses from `package.json`.

The only manual steps left for a new project: create the Topic in Telegram and read its id (type `/status` in the new Topic: the bot answers `Topic N chưa có phòng nào`),
review `AGENTS.md`, and set up Playwright if the project should verify in the browser. Then, in the Topic: `/health`, then `/task <task>`.
`tools/test-kit.sh` is the regression test of the command (temporary folders, fake `gh` and `claude`, nothing real is touched).

Under the hood `kit add` is `install.sh` + `agent-room.sh init` + the CLAUDE.md/room.env patch + commit + `agent-room.sh start`, so the individual scripts still work on their own:

```bash
./install.sh /path/to/project                                   # copy scripts, template, .agents/
cd /path/to/project
scripts/agent-room.sh init --topic <TOPIC_ID> --port <PORT>     # .agents/room.env, board.md, register the room
git add -A && git commit -m "chore: add agent room"
```

- `install.sh` never overwrites an existing `CLAUDE.md`; `kit` patches its AUTO_MODE section for you (by hand: copy the `## AUTO_MODE` section from `template/CLAUDE.md`).
- Verify uses `DEFAULT_VERIFY_URL` with its port replaced by `<PORT>` (so `?test=1` is kept). `rooms.json` lives in `<kit>/bridge-bot/` (override with `AGENT_ROOMS_FILE`, and set the same `ROOMS_FILE` for the bot); it is hot-reloaded. It is per machine and **git-ignored** (it holds local paths): `kit add`/`kit new` create it, `bridge-bot/rooms.example.json` shows the shape.
- After upgrading the kit, use `kit upgrade` (a dirty working tree blocks hand-off, so rooms must be committed).

## Create a room from Telegram (`/newroom`)

No terminal needed. In any Topic of the group (General works too) type:

```
/newroom tea-party 3001                 # existing folder ~/Documents/projects/tea-party -> adds a room to it; if the folder does not exist -> creates the project
/newroom my-app 5173 private agents     # new project, PRIVATE GitHub repo, Claude drafts AGENTS.md
/newroom my-app 5173 local              # new project, no GitHub repo
```

The bot answers with a card (Topic name, folder, port, whether a GitHub repo will be created, **PUBLIC** by default) and two buttons. After **✅ Tạo phòng** it:

1. Checks the project first (uncommitted files, no commit yet, `gh` not logged in, a room that already exists) and stops **before** creating anything.
2. Checks that the Tech Lead and Senior Dev bots are members of the group.
3. Creates the Topic **`project-<name>`**, posts the link where you typed the command, and a welcome inside the new Topic.
4. Runs `kit new` (or `kit add` for an existing folder) with the new Topic id: folder, git, GitHub repo, kit install, room registration, commit, start.
5. Lets **the three bots say hello in the new Topic**, each with its own name and avatar (Manager with the project info and next steps, Tech Lead, Senior Dev), then posts a `/health` report.

A Telegram Topic has no member list of its own: every bot that is in the group can post in every Topic. So "adding the bots to the Topic" means checking they are in the group and having each one speak there; if a role bot is missing from the group the card says so.

Requirements: Topics enabled, the main bot (ManagerBot) is an admin with **Manage Topics**, `gh auth login` done for new GitHub repos, and the other prerequisites of `kit add`. If `kit` fails after the Topic exists, the Topic stays and the bot posts the last lines of the output with the command to retry (`kit add … --topic <id>`).
Safety: only `ADMIN_USER_ID` can use it, names are restricted to letters, digits, `.`, `_`, `-` and always live under `KIT_PROJECTS_DIR`, `kit` is started without a shell and without stdin, only one room is built at a time, and the confirmation card expires after 10 minutes.
`npm test` (unit) and `npm run test:e2e` (the real bridge and the real `kit` against a fake Telegram API and a fake `gh`) in `bridge-bot/` cover it.

**Settings on the board.** The board header carries a block with the current settings (`Plan Approval`, `Commit Links`, `Auto Split`, `Chat With Claude`, `Manager Model`, `Tech Lead Model`, `Max Fix Cycles`, `Keep Shipped`, `Dev Port`) next to `Auto Mode` and `Current Phase`. `room.env` stays the source of truth: the block is rewritten from it on **every board write** and on every `/status`, so it also follows a hand edit of `room.env`. `/status` lists the same settings in plain words (and the dashboard pane shows the block). `tools/test-config.sh` covers it.
