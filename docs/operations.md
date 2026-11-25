# Operating a room

> Watching a room (tmux, logs), `room.env`, Claude quota, troubleshooting.

## Watching a room

With tmux, `agent-room.sh start` opens session `room-<name>`:

```
window dashboard                      window manager
┌─────────────────┬─────────────────┐ (the daemon itself)
│ board.md        │ OpenCode        │
│ (updates on     │ watcher         │
│  change)        │                 │
├─────────────────┤                 │
│ merged log      │                 │
└─────────────────┴─────────────────┘
```

`tmux ls` lists sessions (`agent-bridge`, `room-<name>`); `tmux attach -t room-<name>`; `Ctrl+B` then `0`/`1` switches window,
`Ctrl+B` then `D` detaches without stopping anything. Mouse is on.

Logs in `.agents/logs/` (progress messages are not logged, they go straight to Telegram): `activity.log` (merged, timestamped, coloured by role), `manager.log` / `techlead.log` (full output of each call), `plan.log` (/plan jobs), `usage.log` (tokens and cost per call), `ops.log` (code errors).
`claude -p` prints only when a call finishes, so the log can stay quiet for minutes while Claude works. While OpenCode codes, the daemon is waiting and the log is quiet by design.

## `.agents/room.env`

`PROJECT_NAME`, `TELEGRAM_TOPIC_ID`, `APP_PORT`, `PLAYWRIGHT_BASE_URL`, `AUTO_MODE`, `STAGING_BRANCH`, `MAIN_BRANCH`, `MAX_FIX_CYCLES`,
`MODEL_MANAGER`, `MODEL_TECHLEAD`, `MAX_TURNS_MANAGER`, `MAX_TURNS_TECHLEAD`, `MAX_TURNS_PLAN` (40), `PLAN_APPROVAL` (`auto`|`ask`, default `auto`), `COMMIT_LINKS` (`true`), `AUTO_SPLIT` (`lines`|`claude`), `CHAT_WITH_CLAUDE` (`false`|`true`), `KEEP_SHIPPED` (5).
Rooms created before these keys existed use the defaults above (`kit upgrade` adds the missing keys). Most of them can be changed from chat with `/config` and are mirrored in the board header, see `/status`. Runtime folders: `.agents/plan-feedback/` (your `/revise` notes and the Tech Lead's questions), `.agents/progress/`, `.agents/notices/`.
`run-task.sh` reads it via `scripts/room-env.sh`: Verify takes `DEFAULT_VERIFY_URL` and replaces its port with `APP_PORT`, and task branches are cut from the
staging branch. Without a `room.env` everything behaves as in the single-project mode.

## Claude quota

A task costs about two Claude calls (Tech Lead plan, Tech Lead verify/review/merge), plus one more per fix cycle; OpenCode does the heavy coding.
Verify stays with Claude (`DEFAULT_VERIFY_AGENT="claude"`), so keep `Verify mode: light` unless a task needs `full`. What keeps the cost down:

- **Mechanical work is code, not AI:** `/status`, `/stop`, `/resume`, `/ship`, `/usage`, plain-text replies, `/task` splitting, plan checks, the ship report. A room with nothing to do costs nothing.
- **The daemon waits for OpenCode**, not Claude: Tech Lead is called again only when OpenCode is `done` or `stuck`, with a fresh context.
- **Model per role** in `.agents/room.env`: `MODEL_MANAGER`, `MODEL_TECHLEAD` (`haiku`, `sonnet`, `opus` or a full id; empty = the CLI default).
- **Turn cap per call:** `MAX_TURNS_MANAGER` (20), `MAX_TURNS_TECHLEAD` (150); a call that hits it fails instead of running on.
- **Measure:** every Claude call is appended to `.agents/logs/usage.log` (JSON lines: role, label, model, turns, tokens, cost). `/usage` summarizes it and adds OpenCode's numbers from `opencode stats` (per project and per model; it also counts runs you start by hand and cannot split them per task). Dollar figures are API list prices, useful to compare steps, not your subscription quota.
- `CHAT_WITH_CLAUDE="true"` lets Claude answer plain text (costs quota); the default replies with a canned help text.

## Troubleshooting (multi-room)

| Symptom | Cause / fix |
|---|---|
| Bot is silent | The bridge prints `Ignored message: from.id=… chat.id=…` when ids differ from `.env`; fix `.env` (group ids start with `-100`) |
| Bot starts in discovery mode | `ADMIN_USER_ID` or `TELEGRAM_CHAT_ID` is empty or malformed (quotes, spaces, comments) |
| `Topic N chưa đăng ký` | No room uses this Topic yet: run `agent-room.sh init --topic N --port <PORT>` in the project |
| Message stays on 👀, no report | The bridge wrote it but the room is not handling it: `agent-room.sh status`, is `claude` installed? |
| No 👀 at all | The bridge ignored the message (see `Ignored message` above) or the bot cannot react: check `reaction failed:` in `bridge-bot/bridge.sh logs` |
| Two bridges, Telegram error 409 | Another bridge process is running (an old terminal); stop it, keep only `bridge.sh` |
| `Working tree chưa sạch` on hand-off | Something in the project is uncommitted; commit it, then `/resume`. `.agents/board.md` and `.agents/room.env` are runtime state and must be git-ignored (`install.sh` does this and untracks them if an older install committed them) |
| Room stops itself | A task was stuck or BLOCKED; read `.agents/logs/` and the board, then `/resume` or `/stop` |
| `command not found: agent-room.sh` | Run it from the project root as `scripts/agent-room.sh` |
