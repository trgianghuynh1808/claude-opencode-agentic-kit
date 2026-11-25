# claude-opencode-agentic-kit

> **Claude plans, verifies, reviews and ships. OpenCode codes. You approve the plan — the rest runs on autopilot.**

A small kit (a few bash scripts plus instruction files for the agents) that splits coding work between two agents:

- **Claude Code** (Claude Pro/Max plan): the thinking work — planning, reviewing, getting unstuck.
- **OpenCode** (e.g. the OpenCode Go plan): the token-heavy work — writing code, running tests, checking the feature in a real browser.

The goal: **make your Claude quota last several times longer**, while Claude still controls quality at the start (the plan) and the end (the review).

Optional: **[multi-room mode](docs/multi-room.md#multi-room-mode-telegram--manager)** runs this unattended for several projects at once, controlled from Telegram Topics
(a Manager that is mostly plain code, a Tech Lead on Claude, OpenCode as the developer), with progress reports, a ship approval step and per-call usage tracking.

> **Language note:** the scripts print messages in Vietnamese, and a few conventions use Vietnamese words:
> difficulty labels `[dễ]` = easy, `[vừa]` = medium, `[khó]` = hard; task-file sections such as
> `Mục tiêu` (Goals), `Ý tưởng` (Idea), `Lưu ý` (Notes), `Ngữ cảnh` (Context), `Trạng thái hiện tại` (Current status),
> `Đã thử mà không được` (Tried, didn't work), `Số liệu` (Metrics). Keep these exact strings — the scripts look for them.

## Table of contents

- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [First-time project setup](#first-time-project-setup)
- [Documentation](#documentation) (single-project mode, multi-room mode, Telegram commands, operating a room, developing the kit)
- [License](#license)

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

**1. Edit `.agents/config.sh`** — models per label, the dev URL for Verify, and what the agent runs after each step. See [Configuration](docs/single-project.md#configuration).

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

## Documentation

| Guide | What is in it |
|---|---|
| [Single-project mode](docs/single-project.md) | Two terminals (Claude + OpenCode): daily use, the task file, difficulty labels and models, browser verification, branches and ship, configuration, logs, troubleshooting |
| [Multi-room mode](docs/multi-room.md) | Unattended rooms from Telegram: the flow and task states, first-time setup, bot identities, the `kit` command, `/newroom` |
| [Telegram commands and approvals](docs/telegram-commands.md) | Every command, the plan approval card, auto approval, notes for the approver, the ship card, `/plan` mode |
| [Operating a room](docs/operations.md) | Watching a room, `room.env`, Claude quota, troubleshooting |
| [Developing the kit](docs/development.md) | Repository layout, tests, `sync-knowledge.sh` |

Start here: [How it works](#how-it-works) → [Installation](#installation) → [First-time project setup](#first-time-project-setup), then pick the mode you want.

## License

MIT
