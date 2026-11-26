# Developing the kit

> Repository layout and the tools used to work on the kit itself.

## Repository layout

```
claude-opencode-agentic-kit/
├── kit                             # CLI: new | add | upgrade | status | scan | remove | attach | logs (see "The kit command")
├── install.sh                      # install/upgrade the kit in a project
├── scripts/
│   ├── run-task.sh                 # run a task's steps + Verify
│   ├── watch-tasks.sh              # wait for jobs from Claude via .agents/queue
│   ├── log-gaps.sh                 # find slow spots in run.log
│   ├── handoff.sh                  # Claude → OpenCode: queue a task
│   ├── room-env.sh                 # load .agents/room.env (port, URL, branches)
│   ├── manager-loop.sh             # multi-room: daemon (inbox, board state machine, waits for OpenCode, calls Claude only when needed)
│   ├── agent-room.sh               # multi-room: init | start | stop | status for a project room
│   ├── board-view.sh               # multi-room: board pane of the tmux dashboard (redraws only on change)
│   ├── room-ops.py                 # multi-room: deterministic commands, plan checks, ship (with timing), usage/tools log, /resume (no AI)
│   ├── wait-task.sh                # Claude waits for OpenCode (done / stuck / running)
│   └── notify.sh                   # desktop notification
├── tools/                          # kit maintenance only (not installed into projects)
│   ├── sync-knowledge.sh           # bundle the kit into kit-source.md for a Claude Project
│   ├── kit-lib.py                  # helpers of the kit command (registry, CLAUDE.md patch, status table)
│   ├── test-kit.sh                 # regression test of the kit command
│   ├── test-plan-mode.sh           # regression test of /plan (read-only Q&A)
│   ├── test-clear.sh               # regression test of /clear and /clearlog
│   ├── test-finalize-shots.sh      # per-task pictures in the ship report
│   ├── test-step-report.sh         # one Dev message per step, commit links, push once per step
│   ├── test-techlead-report.sh     # one Tech Lead report per task, pictures sent once
│   ├── test-notes.sh               # Lưu ý, ship-card checks, review notes, non-silent notices
│   ├── test-plan-approval.sh       # plan card, /approve /revise /reject, auto mode, daemon waiting
│   ├── test-config.sh              # /automode, /config, settings block on the board
│   ├── test-inbox-images.sh        # /task and /revise with pictures through the inbox
│   ├── test-attachments.py         # attach_images: only inbox/files, only images
│   ├── test-watcher-requeue.sh     # a cut-off .job.running is queued again when the watcher starts
│   ├── test-inbox-readonly.sh      # /status and /usage answered during a Claude call, other commands stay queued
│   ├── test-resume.sh              # /resume and /resume T03 (one blocked task, even while running)
│   ├── test-ship-timeline.py       # per-phase timing block of the ship message
│   ├── test-claude-result.py       # usage.log row and tools.log from Claude's stream-json output
│   ├── test-room-ops-shots.py      # a task's own screenshots only (task-NN-* / slug)
│   ├── test-ship-leftover-plan.py  # /ship commits a board task's leftover plan file on staging, leaves orphans
│   ├── test-check-plan-env.py      # the plan check blocks real .env edits, not plans that only mention .env
│   ├── test-leftover-report.py     # leftover step report: only sections with content, notes never sent alone
│   ├── test-run-task-prompt.sh     # checks the OpenCode prompts carry the process-safety and selector rules
│   └── test-daemon-prompts.sh      # regression test: every prompt the daemon builds is non-empty
├── template/                       # files copied into your project
│   ├── CLAUDE.md
│   ├── AGENTS.md
│   └── .agents/
│       ├── config.sh
│       └── tasks/_TEMPLATE.md
├── assets/avatars/                 # cute avatars for the three bots (for BotFather /setuserpic)
├── bridge-bot/                     # Telegram Topics <-> .agents/inbox & outbox (Node/TypeScript, grammy)
│   ├── bridge.sh                   # start | stop | status | logs (tmux or pm2)
│   ├── src/format.ts               # light markdown -> Telegram HTML, line-based chunking
│   ├── src/ratelimit.ts            # 429 guard: waits retry_after, shared per bot
│   ├── src/compose.ts              # reply prompts for commands without text, pending-prompt store, image types (pure, tested)
│   ├── src/newroom.ts              # /newroom: argument validation, kit arguments, topic naming (pure, tested)
│   ├── test/                       # unit tests + e2e-newroom.mjs (fake Telegram API)
│   └── .env.example
├── prompts/                        # prompt templates (Vietnamese)
│   ├── MANAGER.md                  # Manager prompt for judgement calls only (installed to .agents/MANAGER.md)
│   ├── generate-agents-md.md
│   ├── plan-task.md
│   └── review-and-ship.md
└── examples/
    ├── playwright.config.ts
    └── opencode-agents/            # sample subagents (optional)
```

`tools/sync-knowledge.sh` is for working **on** the kit. It bundles the tracked files (plus new, not-ignored ones)
into one `kit-source.md` — a file tree, then each script/template in its own code block — and copies it to the
knowledge folder of a Claude Project, so the Project always sees the current source:

```bash
tools/sync-knowledge.sh ~/path/to/project-files   # first run: the folder is remembered in .git/
tools/sync-knowledge.sh                           # after that
tools/sync-knowledge.sh --dry-run                 # only report whether anything changed
```

Which files are embedded and in what order is set by `EXCLUDE` and `ORDER` at the top of the script.
The file is not rewritten when only the date would change.
