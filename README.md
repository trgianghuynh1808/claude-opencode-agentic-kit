# claude-opencode-agentic-kit

> **Claude plans, verifies, reviews and ships. OpenCode codes. You approve the plan — the rest runs on autopilot.**

A small kit (a few bash scripts plus instruction files for the agents) that splits coding work between two agents:

- **Claude Code** (Claude Pro/Max plan): the thinking work — planning, reviewing, getting unstuck.
- **OpenCode** (e.g. the OpenCode Go plan): the token-heavy work — writing code, running tests, checking the feature in a real browser.

The goal: **make your Claude quota last several times longer**, while Claude still controls quality at the start (the plan) and the end (the review).

Optional: **[multi-room mode](#multi-room-mode-telegram--manager)** runs this unattended for several projects at once, controlled from Telegram Topics
(a Manager that is mostly plain code, a Tech Lead on Claude, OpenCode as the developer), with progress reports, a ship approval step and per-call usage tracking.

> **Language note:** the scripts print messages in Vietnamese, and a few conventions use Vietnamese words:
> difficulty labels `[dễ]` = easy, `[vừa]` = medium, `[khó]` = hard; task-file sections such as
> `Mục tiêu` (Goals), `Ngữ cảnh` (Context), `Trạng thái hiện tại` (Current status),
> `Đã thử mà không được` (Tried, didn't work), `Số liệu` (Metrics). Keep these exact strings — the scripts look for them.

---

## Table of contents

- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [First-time project setup](#first-time-project-setup)
- [Daily use](#daily-use)
- [The task file](#the-task-file)
- [Difficulty labels, models and escalation](#difficulty-labels-models-and-escalation)
- [Browser verification](#browser-verification)
- [Branches, review and ship](#branches-review-and-ship)
- [Configuration](#configuration)
- [Logs and timing](#logs-and-timing)
- [Troubleshooting](#troubleshooting)
- [Multi-room mode (Telegram + Manager)](#multi-room-mode-telegram--manager)
- [Repository layout](#repository-layout)

---

## How it works

```mermaid
flowchart TD
    subgraph YOU["You"]
        U([Describe a task])
        A{Approve the plan?}
        X(["🔔 Needs you"])
    end

    subgraph CLAUDE["Claude Code — plans, verifies, reviews, ships"]
        P[Plan in plan mode]
        H["Branch task/slug + task file + commit<br/>scripts/handoff.sh"]
        WT["Wait: scripts/wait-task.sh"]
        V["Verify in the browser<br/>depth = Verify mode"]
        RV[Review the diff]
        D{"VERIFY: PASS, checks pass,<br/>no blocking issue?"}
        S["Ship: squash into 1 commit → push → 🔔"]
        FC{"Fewer than 2<br/>fix cycles so far?"}
        F["Fix cycle: append Fix steps<br/>commit plan(fix-n) → handoff.sh"]
    end

    subgraph OPENCODE["OpenCode — implements"]
        W["watch-tasks.sh → run-task.sh"]
        R["Run a group of steps<br/>model chosen by label / folder"]
        T{Step done?}
        E{Stronger model left?}
    end

    U --> P --> A
    A -- revise --> P
    A -- approve --> H --> W --> R --> T
    T -- "yes, more steps" --> R
    T -- no --> E
    E -- yes --> R
    E -- "no: stuck" --> WT
    T -- "all steps done" --> WT
    WT -- "still running" --> WT
    WT -- done --> V --> RV --> D
    D -- yes --> S
    D -- no --> FC
    WT -- stuck --> FC
    FC -- yes --> F --> W
    FC -- no --> X
```

Say **"manual"** when requesting a task and Claude stops right after the hand-off instead (you then type `verify`, `review`, `ship` yourself).

The two agents never talk to each other directly. **All context lives in the repo:**

| File | Role |
|---|---|
| `AGENTS.md` | Stable project knowledge: architecture, commands, conventions, testing rules. Every agent reads it. |
| `CLAUDE.md` | `@AGENTS.md` plus Claude-only instructions: plan format, hand-off, review, ship. |
| `.agents/tasks/<task>.md` | One task's plan, context, test cases, status, test results and verification. |
| `.agents/queue/*.job` | The "mailbox" Claude uses to hand work to OpenCode (`scripts/handoff.sh`). |
| `.agents/status/*.status` | Task state written by the watcher (`queued → running → done / stuck`), read by `scripts/wait-task.sh`. |
| Git | One commit per step on branch `task/<slug>`; shipping squashes them into one commit. |

---

## Requirements

- macOS or Linux, `bash`, `git` (desktop notifications are macOS-only)
- [Claude Code](https://code.claude.com/docs/en/setup) signed in with a Claude plan (Pro/Max)
- [OpenCode](https://opencode.ai) with a model provider connected via `/connect` (e.g. OpenCode Go)
- Node.js + [Playwright Test](https://playwright.dev) for e2e tests
- [`playwright-cli`](https://playwright.dev/docs/getting-started-cli) for the Verify phase: `npm install -g @playwright/cli@latest`
- A terminal you can split (iTerm2, Zed, tmux...)

---

## Installation

```bash
git clone https://github.com/<you>/claude-opencode-agentic-kit.git
cd claude-opencode-agentic-kit
./install.sh /path/to/your-project
```

The installer:

- **always updates** everything in `scripts/` (re-run it to upgrade the kit);
- **creates only if missing** `CLAUDE.md`, `AGENTS.md`, `.agents/config.sh`, `.agents/tasks/_TEMPLATE.md` (use `--force` to overwrite);
- adds `.agents/queue/`, `.agents/status/`, `.agents/run.log`, `test-results/`, `playwright-report/` to `.gitignore`.

> Upgrading an existing project? The installer never overwrites `CLAUDE.md` / `AGENTS.md`, so newer template sections
> (e.g. **Documentation Rules**, which makes agents re-check the README and docs after every change) must be copied over by hand.

> Your project already has a `CLAUDE.md`? The installer leaves it alone. Copy the **Handoff to OpenCode**
> section from `template/CLAUDE.md` to the end of your file, and add `@AGENTS.md` at the top.

---

## First-time project setup

**1. Edit `.agents/config.sh`** — models per label, the dev URL for Verify, and what the agent runs after each step. See [Configuration](#configuration).

**2. Fill in `AGENTS.md`.** Open OpenCode in the project and paste the prompt from [`prompts/generate-agents-md.md`](prompts/generate-agents-md.md). Then read it and fix it by hand — every agent reads this file in every session, so it is worth 10 minutes.

**3. Playwright Test** (if you don't have it yet):

```bash
npm init playwright@latest   # TypeScript, tests folder, no GitHub Actions, install browsers
rm -f tests/example.spec.ts && rm -rf tests-examples
```

Then adjust `playwright.config.ts` following [`examples/playwright.config.ts`](examples/playwright.config.ts). The JSON reporter writing `test-results/results.json` is required.

**4. (Recommended) A test hook.** An object such as `window.__APP__`, enabled only with `?test=1`, that lets tests read and set app state instead of clicking through a long chain of screens. You can have Claude build it as your first task. Document how to use it on the "Test hook" line in `AGENTS.md`.

**5. Commit:**

```bash
git add -A && git commit -m "chore: add claude-opencode-agentic-kit"
```

**6. Check that Claude reads AGENTS.md:** run `claude` and ask *"What is the codebase map of this project?"*.

---

## Daily use

Split your terminal in two, both panes in the project folder:

| Left pane | Right pane |
|---|---|
| `scripts/watch-tasks.sh` | `claude` → `/model` pick Sonnet → Shift+Tab to **plan mode** |

> Tip: keep `npm run dev` running in a third pane — Playwright reuses the server, so every step is much faster.

1. **Right pane:** describe the task (templates in [`prompts/plan-task.md`](prompts/plan-task.md)). Use Claude's auto-accept/auto mode so it can run commands on its own after you approve.
2. **Approve the plan.** From here on everything is automatic (**Autopilot**, defined in `CLAUDE.md`):
   - Claude creates the branch, writes and commits the task file, and hands it off with `scripts/handoff.sh`.
   - The left pane runs the steps with OpenCode and shows a compact summary:

     ```
     ▶ Bước 1–2/5  [vừa] glm-5.3
       1. client/src/ui/OrdersPanel.ts → recipeSteps: ...
         ← Edit client/src/ui/OrdersPanel.ts
       ● feat(orders): show container line last
        client/src/ui/OrdersPanel.ts | 6 +++---
       ✓ Bước 1 xong
     ```

     (`Bước` = step, `xong` = done.)
   - Meanwhile Claude waits with `scripts/wait-task.sh` (it returns every ~9 minutes and Claude calls it again).
   - When OpenCode is done, Claude **verifies** in the browser, **reviews** the diff, and if everything passes **ships** (squash → push) and sends a 🔔 notification.
   - If Verify/review finds blocking problems, or OpenCode gets stuck, Claude runs a **fix cycle**: it appends `Fix:` steps to the same task file, commits `plan(fix-n): …`, hands it back to OpenCode and waits again.
   - After **2 fix cycles** without success, Claude stops and notifies you ("Cần bạn ⛔" = needs you).
3. Want to stay in control for one task? Say **"manual"** when you request it: Claude stops after the hand-off and you drive the rest (`review`, `ship`).

You can interrupt Claude at any time; it then follows your instructions instead of the loop.

To run without the watcher: `scripts/run-task.sh .agents/tasks/<file>.md` (it resumes from the first unchecked step).

---

## The task file

Template: [`template/.agents/tasks/_TEMPLATE.md`](template/.agents/tasks/_TEMPLATE.md). Claude writes it, OpenCode keeps it updated.

```markdown
# Task: Move the bowl/plate/cup line to the end of the recipe

## Mục tiêu                       ← Goals
## Quyết định đã chốt             ← Decisions made
## Ngữ cảnh                       ← Context: files/functions/types Claude already found, so OpenCode doesn't re-explore
## Plan
- [ ] 1. [dễ] client/src/ui/OrdersPanel.ts → recipeSteps: ...
- [ ] 2. [vừa] tests/orders-panel.spec.ts: write T1–T2
## Test cases
- [ ] T1. Container line is last — .part-into is the final step — tests/orders-panel.spec.ts   (max 3)
      Setup: ... · Steps: 1. ... 2. ... · Assert: ...   ← spelled out step by step by Claude
## Trạng thái hiện tại             ← Current status
## Test status                    ← per test: PASS / FAIL / not written yet
## Verify                         ← filled by the Verify phase; last line VERIFY: PASS|FAIL
(top of file) Verify mode: light  ← none | light | full
## Đã thử mà không được           ← what was tried and failed, so the next agent doesn't repeat it
## Số liệu                        ← metrics (time, quota)
```

The script detects steps with the pattern `- [ ] N. [label] ...` — keep that exact format.

---

## Difficulty labels, models and escalation

| Label | Meaning (Claude assigns it when planning) | Default model |
|---|---|---|
| `[dễ]` easy | one file, mechanical change | `MODELS[0]` |
| `[vừa]` medium | a few files, following existing patterns | `MODELS[1]` |
| `[khó]` hard | new design, crosses several layers, tricky state/sync logic | `MODELS[2]` |

- **Batching:** consecutive steps with the same label run in **one** OpenCode session (up to `BATCH_MAX`), so the agent doesn't re-read the context for every step.
- **Session reuse:** from the second run on, the script uses `opencode run --continue`, so the next model still sees what the previous one read and did (`REUSE_SESSION=0` to disable).
- **Escalation:** a step still unchecked after a run is retried on its own with the next model up (levels whose model is the same as the one that just failed are skipped). Stuck at `[khó]` → stop and hand over to Claude.
- **Per-folder models:** with `MEDIUM_RULES`, `[vừa]` steps can use different models depending on the folder of the first file path in the step line, so start each step with its main file path. A `tests/` prefix lets the steps that write specs use their own model (the planning rules tell Claude to start such steps with the spec path and label them `[vừa]`).
- **Fresh sessions:** with `FRESH_RULES` (e.g. `("tests/")`), steps whose first path matches run in a new session instead of `--continue`, so a long session's context doesn't slow every later turn. Use it for steps that don't need the earlier steps' history because the plan already carries the context.
- **Quota guard:** at most `MAX_RUNS` OpenCode invocations per task.

The script picks the model by reading `[dễ]`/`[vừa]`/`[khó]` in the plan line — the models themselves don't "know" about labels. Change models in `.agents/config.sh`.

---

## Browser verification

Once every step is checked, the feature is checked in a real browser with `playwright-cli` — by Claude in Autopilot (default), or by OpenCode with `VERIFY_MODEL` (must accept images) if `DEFAULT_VERIFY_AGENT="opencode"`.
How deep it goes is set by the `Verify mode:` line at the top of the task file (Claude picks it when planning):

| Mode | When | What the agent does |
|---|---|---|
| `none` | refactors, text/config changes, nothing user-visible | skips Verify |
| `light` (default) | normal UI / feature changes | runs the suite once; opens the browser **only** for test cases a spec can't check (visual/layout), one screenshot each; no new scenarios; writes a spec only to reproduce a bug it found |
| `full` | new user flows, multi-user/sync logic, risky changes | also tries up to 2 important edge scenarios and adds specs for unchecked ones (max 3 new tests) |

Every mode records results in `## Verify` and ends with `VERIFY: PASS` or `VERIFY: FAIL`. The agent never changes app code.

Keeping tests lean is what keeps runs fast. `CLAUDE.md` tells Claude to plan **at most 3 test cases per task**, to name the **exact test command** in each step (e.g. `npx playwright test tests/orders.spec.ts -g "T1"`), and the executor is told to run only that command and not to invent extra tests.

**Who verifies.** By default (`DEFAULT_VERIFY_AGENT="claude"`) the script stops after the code steps and Claude verifies and reviews in one go — browser screenshots are expensive, and this keeps them off your OpenCode quota. Set `"opencode"` to have OpenCode verify right after coding (Claude then skips its own Verify when it sees `VERIFY: PASS`).

Override the mode for one run: `VERIFY_MODE=full scripts/run-task.sh ...` · Skip Verify for one run: `VERIFY=0 scripts/run-task.sh ...`

**Two rules every OpenCode step and Verify prompt carries** (in `run-task.sh`, so `kit upgrade` rolls them out; the Tech Lead gets the same in the daemon prompt and the AUTO_MODE section of `CLAUDE.md`). They come from a real run where a 22-minute test step killed the developer's dev server and then spent about 11 minutes rediscovering selectors:

- **Never kill a process you did not start.** `lsof` and `ps` are for looking. If the server on a port does not fit (for example it has no `ADMIN_TOKEN`), the step does not kill it: it records the port, PID and reason in "Đã thử mà không được", leaves the step unticked and stops, so the Tech Lead decides. Projects should give their e2e tests dedicated ports with `reuseExistingServer: false` (the new `template/AGENTS.md` says so) so tests never depend on or disturb a dev server.
- **Selector hand-off.** A step that adds or changes UI ends by writing one `Selectors: #id, .class (file)` line to "Trạng thái hiện tại". A later test step (which runs in a fresh OpenCode session) reads that line before grepping the code, instead of rediscovering the selectors. The Tech Lead is told not to invent selectors for UI the plan itself creates and to point the test step at that line.
`tools/test-run-task-prompt.sh` checks that the prompts carry both rules.

E2e tests run **headless** (no window). To watch them: `npx playwright test --ui` (step-by-step timeline with screenshots) or `--headed`; with the example config, `HEADED=1` shows the browser in the automated flow too.

---

## Branches, review and ship

```
main ──●──────────────────────────────●  feat(orders): show container line last
        \                            ↑ ship: squash into 1 commit + push
         task/orders-container-last ─●─●─●─●  (plan, each step, verify)
```

- Claude creates `task/<slug>` before committing the plan. If `run-task.sh` is started while on `main`, it switches to `task/<file-name>` itself.
- `review`: Claude reads the task file and `git diff main...HEAD`, reports bugs, deviations from the plan and missing tests, and says whether it is ready to ship.
- `ship`: squash-merge into `main`, one Conventional Commit, push, delete the branch. If the push is rejected, Claude stops and tells you — **it never force-pushes**.

Claude's full instructions are in [`template/CLAUDE.md`](template/CLAUDE.md). Example phrases: [`prompts/review-and-ship.md`](prompts/review-and-ship.md).

---

## Configuration

`.agents/config.sh` (sourced by `run-task.sh`):

| Variable | Meaning |
|---|---|
| `MODELS=(easy medium hard)` | Model per label, as `provider/model` (see `opencode models`) |
| `MEDIUM_RULES=("prefix=model" ...)` | Optional: pick the `[vừa]` model by the folder of the first file a step names (e.g. `client/` → stronger model, `server/` → cheaper model). Unmatched steps use `MODELS[1]`. |
| `FRESH_RULES=("prefix" ...)` | Optional: steps whose first path matches a prefix (e.g. `tests/`) start a fresh OpenCode session instead of `--continue`. |
| `DEFAULT_VERIFY_MODEL` | Model for Verify when `DEFAULT_VERIFY_AGENT="opencode"` (must accept images) |
| `DEFAULT_VERIFY_URL` | App URL in dev, may include `?test=1` |
| `DEFAULT_CHECK_HINT` | What the agent runs after each step, written as an instruction |
| `DEFAULT_VERIFY_HINT` | Extra guidance for Verify (e.g. "always open 2 sessions") |
| `DEFAULT_VERIFY_AGENT` | `claude` (default: Claude verifies and reviews in Autopilot) or `opencode` (OpenCode verifies right after coding) |
| `BATCH_MAX` | Max same-label steps per run |
| `MAX_RUNS` | Max OpenCode invocations per task |

Environment variables to override a single run:

| Variable | Default | Effect |
|---|---|---|
| `VERBOSE=1` | 0 | Print OpenCode's full raw output |
| `ACTIONS=0` | 1 | Hide action lines (file edits, commands), show commits only |
| `ACTION_REGEX=...` | | Pattern for action lines, if OpenCode prints them in another format |
| `REUSE_SESSION=0` | 1 | A fresh OpenCode session for every step group |
| `BATCH_MAX=1` | 4 | Exactly one step per run |
| `AUTOPILOT=1` | 0 | Only changes the final message: "Claude will verify on its own" instead of the manual "open Claude → /clear → type verify" hint. `watch-tasks.sh` sets it automatically. |
| `MAX_RUNS=30` | 20 | Raise the limit for big tasks |
| `VERIFY=0` | 1 | Skip Verify |
| `VERIFY_MODE=full` | from task file, else `light` | Force Verify depth: `none` / `light` / `full` |
| `VERIFY_AGENT=opencode` | `claude` | Let OpenCode verify right after coding for this run |
| `VERIFY_MODEL`, `VERIFY_URL` | | Override the config values |

Example OpenCode subagents (optional, the scripts don't need them): [`examples/opencode-agents/`](examples/opencode-agents) — copy into `.opencode/agents/`.

---

## Logs and timing

- The screen shows a summary only; **the full output** goes to `.agents/run.log`, each line stamped with the clock time and seconds since the run started:

  ```
  === 2026-11-21 18:30:02 · bước 1–2 · opencode-go/glm-5.3 ===
  18:30:41 +39s │ ← Edit client/src/ui/OrdersPanel.ts
  18:30:42 +40s │ $ npx playwright test tests/orders-panel.spec.ts
  ```

- Follow live: `tail -f .agents/run.log` · browse later: `less -R .agents/run.log`
- **Find what is slow:**

  ```bash
  scripts/log-gaps.sh        # latest run
  scripts/log-gaps.sh 5      # last 5 runs (a whole task)
  ```

  Prints the duration of each run and the longest gaps, together with what was happening right before each one (running tests? type check? the model thinking?).

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Working tree đang có thay đổi chưa commit` (uncommitted changes) | The script only runs on a clean tree, so every step can be rolled back. Commit or stash first. Make sure `.agents/queue/` is ignored. |
| `This OpenCode Go model is hosted outside Europe and the United States` | Your OpenCode account is region-restricted. Console → Settings → Privacy → Regions → Global, or switch to US/EU-hosted models in `config.sh`. |
| The left pane hangs on the first step | `opencode run` may be waiting for a permission. See `opencode run --help` / OpenCode's permission settings. |
| Odd results when switching models mid-task | Try `REUSE_SESSION=0`. |
| The script continues the wrong session | `--continue` resumes the most recent session in the project — don't run interactive `opencode` in the same repo while the script runs (use a git worktree). |
| No `← Edit` / `$ ...` lines on screen | OpenCode prints actions in a different format. Check `grep -nE "Edit|Write|Bash" .agents/run.log`, then set `ACTION_REGEX`. |
| Steps feel slow even though little is happening | Check `scripts/log-gaps.sh` first: if the gaps sit in the model turns (not in tests or type checks), it is per-turn model latency, which varies a lot with the time of day and with session length. The levers are fewer turns: a plan with precise context and step-by-step test descriptions (so the executor does not explore), and short sessions. |
| Every step is slow in the test phase | Keep `npm run dev` running (`reuseExistingServer: true`). Confirm with `scripts/log-gaps.sh`. |
| `claude: command not found` | Install the Claude Code CLI ([guide](https://code.claude.com/docs/en/setup)) and add `~/.local/bin` to `PATH`. |
| iTerm dims the inactive pane | Settings → Appearance → Dimming → uncheck "Dim inactive split panes". |
| Running two tasks in parallel | One `git worktree` per task, one watcher per worktree. |
| Claude says the task is still `queued` / watcher not running | Start `scripts/watch-tasks.sh` in the left pane; Claude retries the wait. |
| `no such column: project_id` from `opencode` as soon as a task starts (seen with OpenCode 1.19.x) | It can happen in a repo that has a remote named `origin`. Rename the remote (e.g. `git remote rename origin github`), then use it in the Ship step (`git push github main`) — `template/CLAUDE.md` says `origin`, adjust it in your project's `CLAUDE.md`. |
| Claude keeps asking for permission during Autopilot | Switch Claude Code to auto-accept / auto mode (Shift+Tab) after approving the plan, or allow `scripts/*`, `git` and `npx playwright` in its permission settings. |

**Privacy:** a provider's free or "contributor" models may store your data — don't use them with company code. Check your provider's privacy settings.

---

## Multi-room mode (Telegram + Manager)

Optional. Turns the 2-agent kit into three tiers that run unattended, for several projects at once, controlled from Telegram.

| Tier | Agent | Runs as | Job |
|---|---|---|---|
| Manager | Code first, Claude only for judgement | `scripts/room-ops.py` (bash/Python, no AI); `claude -p` with `.agents/MANAGER.md` only when needed | Splits `/auto` into tasks, checks and approves plans (guardrails), reports, ships on `/ship`. Calls Claude only for plans the automatic check is unsure about |
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

### Flow in AUTO_MODE

1. `/auto <checklist>` → one task per line (bullets and numbers are stripped), written as `[pending]` on `board.md`; `staging` is created from `main`. Set `AUTO_SPLIT="claude"` in `room.env` to let Claude split a free-form request instead.
2. For each task, the daemon runs one step at a time (state lives on `board.md`):

   | State | Who acts | Next state |
   |---|---|---|
   | `pending` | Tech Lead (Claude) writes the plan on branch `task/<slug>` (no hand-off yet) | `plan_ready` |
   | `plan_ready` | Code checks the plan: `OK` → approved and handed off, `BLOCK` → blocked, `REVIEW` → Claude Manager decides | `in_progress` (or `BLOCKED`) |
   | `in_progress` | The daemon itself waits for OpenCode (reads `.agents/status`); when it is `done` or `stuck`, Tech Lead (Claude) verifies, reviews, fixes (max `MAX_FIX_CYCLES`) and squash-merges into `staging` | `done` |

   Plan checks (`room-ops.py check-plan`): **BLOCK** = no steps, touches `.env`, `DROP`/`TRUNCATE`/`DELETE FROM`. **REVIEW** = more than 8 steps, a step without a difficulty label, secrets/credentials, migrations, CI/deploy config, lockfiles, `rm -rf`, no concrete test command. Anything else is approved without calling Claude.
   The plan check does not compare the plan with the task title (that needs judgement); keep tasks small and check the plan in the log if a task is risky.

3. All tasks done → phase `AWAITING_SHIP_APPROVAL`; you get the evidence and then the approval card, all built by code:
   - for each task that has verification pictures, a `📸 T05 · title` message from the Tech Lead with **that task's own pictures only** (the ones captured while it was verified: recorded in its time window, or named `task-NN-*.png`); a task with no pictures sends none;
   - the approval card with the **Ship** button: tasks (each saying how many pictures are above, or that Verify was skipped / nothing was captured), and the commits not yet on `main`. Pictures from earlier work or other tasks are never attached.
4. `/ship` merges `staging` into `main` and pushes. Nothing reaches `main` without it.

**Fresh context per call.** Every `claude -p` call is a new process with an empty context window. State is passed through files
(`board.md`, the task file, git, `CLAUDE.md`/`AGENTS.md`), never through memory, so anything the next step needs must be written there.
OpenCode is different: it continues one session across the steps of a task (see `FRESH_RULES`).

**Safety**
- The daemon never loops on a stuck state: the same task/state twice without progress turns AUTO_MODE off and tells you (`/resume` to retry).
- Guardrails block plans that touch `.env`/secrets/CI config, destructive migrations, or drift from the task.
- Only `ADMIN_USER_ID` in `TELEGRAM_CHAT_ID` is obeyed; screenshots are only sent from inside the room directory.
- The daemon runs `claude -p ... --dangerously-skip-permissions` (override with `CLAUDE_FLAGS`). The Manager's "no application code" rule is a prompt instruction, not enforced by the system. Run rooms only on projects and machines you trust.
- Quota: see [Claude quota](#claude-quota) below.

### First-time setup (once per machine)

1. **Telegram:** create a bot with @BotFather and turn **Group Privacy** off (Bot Settings). Create a Supergroup, enable **Topics**, add the bot as admin
   (with *Manage Topics*), and create one Topic per project.
2. **Bridge bot:** `cp bridge-bot/.env.example bridge-bot/.env` and fill `BOT_TOKEN`. Leave `ADMIN_USER_ID` and `TELEGRAM_CHAT_ID` empty,
   run `bridge-bot/bridge.sh start`, and send any message in a Topic: the bot (discovery mode) replies with `ADMIN_USER_ID`, `TELEGRAM_CHAT_ID` and the Topic ID.
   Put the two ids in `.env`, then `bridge-bot/bridge.sh stop && bridge-bot/bridge.sh start`.
   `.env` format: one `KEY=value` per line, no quotes, no spaces, no trailing comments.

### Role identities (optional: one bot per role)

Messages in a Topic come from three roles. Progress is read from the task file, the board and git by the daemon (`room-ops.py progress`),
so it needs no extra Claude calls and works even if an agent forgets to report:

| Role | Reports |
|---|---|
| `🧭 Manager` | Replies to commands, plan approval or block, the ship report with the **Ship** button |
| `🛠 Tech Lead` | `▶` when each of its calls starts, `📋` plan summary (steps, tests, Verify mode), `🔎` Verify PASS/FAIL with the Verify notes and up to 3 new screenshots, `🔁` each fix cycle, `🎉` merged into `staging` |
| `⌨️ Senior Dev` | `▶` start; **one message per finished step**, in three sections: **Mô tả** (step, difficulty `dễ`/`vừa`/`khó` always shown, model used, step text), **Commit** (each commit with a link to it on GitHub) and **Kết quả test** (tests whose result changed during the step); `↗` a retry of a step with a stronger model; `⛔` when a step still fails on the strongest model; done or stuck (`watch-tasks.sh`) |

The `↗` and `⛔` messages come from `run-task.sh` itself (it knows the model and the retries); the per-step report is derived from the task file and git by the daemon (`room-ops.py progress`). It relies on the task file keeping the template shape: ticked `- [x] N.` steps, `T1: PASS|FAIL` lines under `Test status`, a `## Verify` section ending with `VERIFY: PASS|FAIL`.
A step is reported once, after its task file has been quiet for a few seconds, so a commit or a test result that comes a moment after the checkbox still lands in the same message; a lone commit or test result waits for the next finished step, and anything left when OpenCode is done is sent once as "Phần còn lại". There is no "starting step" message.
**Commit links.** They open on GitHub only if the commit is there, so when it reports a step the daemon pushes the task branch to `origin` **once per reported step** (never per commit or per check; it never asks for a password and gives up for 10 minutes after a failure) and deletes that remote branch when you `/ship`. Set `COMMIT_LINKS="false"` in `.agents/room.env` to turn this off (no push, no links; commits show as plain hashes). Only GitHub remotes get links. `tools/test-step-report.sh` covers it.
Reported state is kept in `.agents/progress/<slug>.json` (git-ignored); if the daemon restarts in the middle of a task it continues from the current state instead of replaying old steps.
**Telegram rate limit.** Telegram allows about 20 messages a minute per bot per group, shared by all Topics, and answers `429` with `retry_after` seconds when it is exceeded. The bridge waits exactly that long and sends again; the wait is kept **per bot**, so every room using a bot that was told to wait waits too. A wait longer than `MAX_RETRY_AFTER_S` (default 120) is not slept off and the outbox poller's own retry count applies. Ordering is kept: each room sends one message at a time.

Messages are produced as `.agents/outbox/*.json` with a `"from"` field (`manager` | `techlead` | `dev`; default `manager`).

**Tone and format.** Messages are written in a friendly, relaxed Vietnamese ("mình" / "bạn", light emoji), split into short sections, with lists for tasks and steps.
Producers write plain text with a tiny markdown subset (`**bold**`, `` `code` ``, `- ` bullets, `# ` headings) and the bridge converts it to Telegram HTML
(`bridge-bot/src/format.ts`): everything else is escaped, so stray `<`, `>` or `&` are safe, long messages are split at line boundaries, and if Telegram still
rejects the markup the raw text is sent instead, so a message is never lost. Step texts are trimmed at a word boundary without leaving a dangling backtick.
Claude-written messages follow the same style (it is part of the daemon prompt and `.agents/MANAGER.md`). `cd bridge-bot && npm test` checks the converter.

By default all three use the main bot and only the label differs. For separate identities (own name and avatar), create two more bots in BotFather,
add them to the group as ordinary members (admin is not needed: they only send, and Group Privacy does not matter), and set `BOT_TOKEN_TECHLEAD` and `BOT_TOKEN_DEV` in `bridge-bot/.env`. They only send: commands, reactions and the Ship button
stay on the main bot, so a message that needs approval is always sent by the Manager. The startup log shows which identity each role uses.

### The `kit` command (add, upgrade, status)

One command replaces the manual steps. Put it on your PATH once (any folder in your PATH works):

```bash
ln -s ~/Documents/projects/claude-opencode-kit/kit ~/.local/bin/kit
```

| Command | What it does |
|---|---|
| `kit new <name> --port 3001 --topic 12` | **New project from scratch**: creates `~/Documents/projects/<name>` (`KIT_PROJECTS_DIR`), `git init` on `main`, `.gitignore`, `README.md`, first commit, a **public** GitHub repo with `gh` (asks you to confirm first; `--private`, or `--no-github` for local only), then everything `kit add` does. `--template "npm create vite@latest . -- --template vanilla-ts"` runs your scaffolding command in the empty folder first |
| `kit add <path> --port 3001 --topic 12` | **Existing project** (including one on the old two-agent install; its `CLAUDE.md` and `config.sh` are kept): checks the prerequisites (git repo with a commit, clean tree, `claude`, `opencode`, `tmux`/`pm2`, `bridge-bot/.env`), installs the kit, creates the room and registers the Topic, adds or refreshes the AUTO_MODE section of an existing `CLAUDE.md` (the rest is kept), commits, starts the room (and the bridge if needed) and shows its status |
| `kit upgrade [name]` | Updates the kit in every registered room (or one). A room is skipped, with the reason, when it is busy (AUTO_MODE on, OpenCode running, a task in progress) or its git tree is dirty. An idle running room is stopped, updated, committed and started again; a stopped room stays stopped. The bridge is restarted once at the end (`--no-bridge` to skip) |
| `kit status` | One table: every room, running or not, AUTO_MODE, the task in progress and the kit version it runs (flagged when behind) |
| `kit scan [folder]` | Scans your projects folder (default `~/Documents/projects`) for every project that carries kit files, registered or not, with its kit version and the command to fix it: a legacy install with no room gets a `kit add …` hint. `kit status --all` shows the same list under the rooms table |
| `kit remove <name>` | Stops a room and removes it from the bridge; the project files are left alone |

Common flags: `--agents` asks Claude once to **draft `AGENTS.md`** from the repo (committed separately as `docs: draft AGENTS.md (review before use)`: read it before the first task),
`--no-start` only prepares the room, `--yes` answers the confirmation. Without `--topic`, `kit` explains how to get one and asks for it; without `--port` it guesses from `package.json`.

The only manual steps left for a new project: create the Topic in Telegram and read its id (type `/status` in the new Topic: the bot answers `Topic N chưa có phòng nào`),
review `AGENTS.md`, and set up Playwright if the project should verify in the browser. Then, in the Topic: `/health`, then `/auto <task>`.
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

### Create a room from Telegram (`/newroom`)

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

### Daily use

```bash
cd /path/to/project
scripts/agent-room.sh start     # starts the bridge if needed, then the room (tmux or pm2)
npm run dev                     # only when a task verifies in the browser; must listen on APP_PORT
```

Then chat in the project's Topic. `scripts/agent-room.sh stop` stops the room; `bridge-bot/bridge.sh stop` stops the shared bridge
(`agent-room.sh stop` does not touch it). `status` on either script shows what is running.

### Telegram commands

The bot reacts on your message instead of replying: 👀 = written to the room's inbox, 👍 = the Manager handled it, 👎 = the Manager failed (the file is in `.agents/inbox/failed/`).
The reaction state is kept in memory, so after a bridge restart a message that was still pending keeps its 👀.

| Command | Effect |
|---|---|
| `/auto <checklist>` | One item per line; turns AUTO_MODE on. Plain text without a command gets a canned reply (no Claude call) |
| `/status` | Board summary |
| `/stop` | AUTO_MODE off, phase IDLE |
| `/resume` | Continue after a stop, a stuck task or a BLOCKED task |
| `/usage [days]` | Claude: tokens, turns and list-price cost per role plus the last 5 calls (from `.agents/logs/usage.log`). OpenCode: sessions, tokens and cost per model from `opencode stats` for this project. Default today / last 24 h, `/usage 7` for a week |
| `/plan <question>` | **Plan mode**: ask about the project, analyse an idea, get a plan; Tech Lead reads the code and the Manager sends you one summary. Read-only: no task, no branch, no commit, nothing is changed (see [Plan mode](#plan-mode-plan-ask-without-creating-tasks)) |
| `/health` | Liveness check of the room, answered by the bridge itself (no Claude call, works even if the Manager is dead): bridge, role bots (`getMe`), Manager daemon, OpenCode watcher, `claude` and `opencode` CLIs, git branch and clean tree, dev server port. Ends with *Sẵn sàng* or the list of what is missing |
| `/ship` | Merge `staging` → `main` and push (only in `AWAITING_SHIP_APPROVAL`), then tidy up (below); also the **Ship** button |
| `/newroom <name> <port> [private] [local] [agents]` | Create a Topic `project-<name>` and a whole room (see [Create a room from Telegram](#create-a-room-from-telegram-newroom)); usable in any Topic, even General |

**Pre-flight.** Before it starts a task, the daemon checks that the OpenCode watcher is alive (`.agents/watcher.pid`). If not, it turns AUTO_MODE off and tells you, instead of leaving the hand-off stuck in `queued`. Run `/health` before `/auto` to see everything at once.

**Clean-up after `/ship`** (code, no AI; a failure here never undoes the ship, and the result is appended to the ship reply as `🧹 Đã dọn: …`):
- `.agents/status/*` and `.agents/progress/*` of every shipped task are deleted.
- Verification screenshots move to `.agents/screenshots/archive/<date-time>/`; only the 3 newest batches are kept (archived images are never attached to reports).
- The board keeps the newest `KEEP_SHIPPED` (default 5) shipped tasks; older ones are removed and noted in the Activity Log. Numbering keeps going because the newest task always stays.
- Files in `inbox/processed`, `inbox/failed`, `outbox/sent`, `outbox/failed` older than 7 days are deleted.
- Task plan files in `.agents/tasks/` are kept: they are part of the repository history.

Fresh context is automatic: every Tech Lead call is a new `claude -p` process (no `/clear` needed), and OpenCode only continues a session between step groups of the same task.

### Plan mode (`/plan`): ask without creating tasks

`/auto` turns your text into tasks and starts coding. When you only want information, an opinion or a plan, use:

```
/plan Project này đang có những màn hình nào, và thêm chức năng upload ảnh thì động tới file nào?
```

Only two agents work, together, and you get **one summary message**:

1. The Manager acknowledges the question and hands it to the Tech Lead.
2. The Tech Lead (Claude) reads the repo (`AGENTS.md`, `CLAUDE.md`, the board and whatever code it needs) and writes a technical analysis with file paths, risks and what it is unsure about.
3. The Manager (Claude, no tools) merges that with the board into a friendly message: short answer, **Góc nhìn Tech Lead**, and, when there is a concrete way to do it, ready-to-copy `/auto …` lines (only suggestions, nothing is started).

**It cannot change anything.** The Tech Lead runs with `--tools "Read,Grep,Glob"`: it has no tool that can write a file or run a command (a test asked Claude to create and delete files on purpose and it could not), and `--dangerously-skip-permissions` is not used. The Manager step has no tools at all. No OpenCode, no task, no branch, no commit.
It runs in the background, so the room keeps answering `/status` and keeps working on tasks meanwhile; one question at a time (a second `/plan` gets a polite "wait"). A question costs two Claude calls (turn caps: `MAX_TURNS_PLAN` for the reading, `MAX_TURNS_MANAGER` for the summary; models from `MODEL_TECHLEAD` / `MODEL_MANAGER`) and shows up in `/usage` as `plan: tìm hiểu` and `plan: tổng hợp`.
If the Tech Lead fails you are told; if only the Manager fails you get the Tech Lead's analysis as it is. Every question, analysis and answer is kept in `.agents/plan/` (git-ignored), and the run log is `.agents/logs/plan.log`.
`tools/test-plan-mode.sh` is the regression test (fake `claude`, checks the tool restriction, the background behaviour and the failure paths).

### Watching a room

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

### `.agents/room.env`

`PROJECT_NAME`, `TELEGRAM_TOPIC_ID`, `APP_PORT`, `PLAYWRIGHT_BASE_URL`, `AUTO_MODE`, `STAGING_BRANCH`, `MAIN_BRANCH`, `MAX_FIX_CYCLES`,
`MODEL_MANAGER`, `MODEL_TECHLEAD`, `MAX_TURNS_MANAGER`, `MAX_TURNS_TECHLEAD`, `MAX_TURNS_PLAN` (40), `COMMIT_LINKS` (`true`), `AUTO_SPLIT` (`lines`|`claude`), `CHAT_WITH_CLAUDE` (`false`|`true`), `KEEP_SHIPPED` (5).
Rooms created before these keys existed use the defaults above; add the keys by hand if you want to change them.
`run-task.sh` reads it via `scripts/room-env.sh`: Verify takes `DEFAULT_VERIFY_URL` and replaces its port with `APP_PORT`, and task branches are cut from the
staging branch. Without a `room.env` everything behaves as in the single-project mode.

### Claude quota

A task costs about two Claude calls (Tech Lead plan, Tech Lead verify/review/merge), plus one more per fix cycle; OpenCode does the heavy coding.
Verify stays with Claude (`DEFAULT_VERIFY_AGENT="claude"`), so keep `Verify mode: light` unless a task needs `full`. What keeps the cost down:

- **Mechanical work is code, not AI:** `/status`, `/stop`, `/resume`, `/ship`, `/usage`, plain-text replies, `/auto` splitting, plan checks, the ship report. A room with nothing to do costs nothing.
- **The daemon waits for OpenCode**, not Claude: Tech Lead is called again only when OpenCode is `done` or `stuck`, with a fresh context.
- **Model per role** in `.agents/room.env`: `MODEL_MANAGER`, `MODEL_TECHLEAD` (`haiku`, `sonnet`, `opus` or a full id; empty = the CLI default).
- **Turn cap per call:** `MAX_TURNS_MANAGER` (20), `MAX_TURNS_TECHLEAD` (150); a call that hits it fails instead of running on.
- **Measure:** every Claude call is appended to `.agents/logs/usage.log` (JSON lines: role, label, model, turns, tokens, cost). `/usage` summarizes it and adds OpenCode's numbers from `opencode stats` (per project and per model; it also counts runs you start by hand and cannot split them per task). Dollar figures are API list prices, useful to compare steps, not your subscription quota.
- `CHAT_WITH_CLAUDE="true"` lets Claude answer plain text (costs quota); the default replies with a canned help text.

### Troubleshooting (multi-room)

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

## Repository layout

```
claude-opencode-agentic-kit/
├── kit                             # CLI: new | add | upgrade | status | remove (see "The kit command")
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
│   ├── room-ops.py                 # multi-room: deterministic commands, plan checks, ship, usage log (no AI)
│   ├── wait-task.sh                # Claude waits for OpenCode (done / stuck / running)
│   └── notify.sh                   # desktop notification
├── tools/                          # kit maintenance only (not installed into projects)
│   ├── sync-knowledge.sh           # bundle the kit into kit-source.md for a Claude Project
│   ├── kit-lib.py                  # helpers of the kit command (registry, CLAUDE.md patch, status table)
│   ├── test-kit.sh                 # regression test of the kit command
│   ├── test-plan-mode.sh           # regression test of /plan (read-only Q&A)
│   ├── test-step-report.sh         # one Dev message per step, commit links, push once per step
│   ├── test-run-task-prompt.sh     # checks the OpenCode prompts carry the process-safety and selector rules
│   └── test-daemon-prompts.sh      # regression test: every prompt the daemon builds is non-empty
├── template/                       # files copied into your project
│   ├── CLAUDE.md
│   ├── AGENTS.md
│   └── .agents/
│       ├── config.sh
│       └── tasks/_TEMPLATE.md
├── bridge-bot/                     # Telegram Topics <-> .agents/inbox & outbox (Node/TypeScript, grammy)
│   ├── bridge.sh                   # start | stop | status | logs (tmux or pm2)
│   ├── src/format.ts               # light markdown -> Telegram HTML, line-based chunking
│   ├── src/ratelimit.ts            # 429 guard: waits retry_after, shared per bot
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

## License

MIT
