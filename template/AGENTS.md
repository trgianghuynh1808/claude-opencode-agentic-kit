# AGENTS.md

Guidelines for coding agents working in this repo.
<!-- Generate the project-specific sections with prompts/generate-agents-md.md, then review them by hand.
     Keep the "Testing Rules", "Verify Phase" and "Workflow Rules" sections: the scripts depend on them. -->

## Project Overview

TODO: what the app is, who uses it, main stack.

## Architecture

TODO: how the parts talk to each other (HTTP, WebSocket...), ports, where state lives.

## Codebase Map

TODO: main folders and files, one line each, plus the main flow.

## Commands

```bash
# TODO: fill in the real commands
npm install
npm run dev          # dev server
npm run typecheck    # or lint / build check
npx playwright test  # e2e tests
```

## Code Conventions

TODO: language/style rules taken from the existing code.

## Testing Rules

- After each coding step, run the type/lint check and only the test command named in that step (see Commands). Do not run the whole suite per step, and do not design or add tests the plan does not ask for. If there are no specs yet, rely on the type check and note it in the task file.
- When tests fail, read `test-results/results.json` first (the Playwright JSON reporter writes it).
- In "Test status", report every test case from the task file (T1, T2...) as PASS / FAIL / not written yet, not just an overall result.
- When a plan step writes a spec, tick the matching test case in "Test cases" once the spec exists.
- Only use `playwright-cli` (interactive browser tool, separate from `@playwright/test`) when a failure is visual and `results.json` is not enough, or during the Verify phase.
- After any browser testing, clean up: close the browser and stop any dev server you started.
- Never kill, restart or stop a process you did not start, including a dev server on the user's ports (`lsof` and `ps` are for looking only). If a server on the test port does not fit (for example a missing env var such as `ADMIN_TOKEN`), do not kill it: record the port, PID and reason in "Đã thử mà không được", leave the step unticked and stop. Prefer dedicated test ports with `reuseExistingServer: false`, so tests never depend on or disturb a dev server.
- Notes for the approver: when something should be known before approving (a deviation from the plan, something left untested, a known bug or `test.fail`, a follow-up), write a line starting with `Lưu ý:` in "Trạng thái hiện tại". Only such lines (and "Đã thử mà không được") are relayed to the user, so never use the marker for reminders to agents or maintainers.
- A step that adds or changes UI ends by writing one `Selectors:` line to "Trạng thái hiện tại" (ids, classes, data-* and the file holding them). A later test step reads that line before grepping the code.
- Use unique test data per run (e.g. usernames like `user-${Date.now()}`) so runs do not collide.
- Tests must never touch production data.
- Test hook: TODO (e.g. `window.__APP__` enabled with `?test=1` to read/set state). Until it exists, do not script long UI flows just to reach a screen.

## Verify Phase

- After all plan steps are done, a Verify agent checks the feature in a real browser with `playwright-cli`, at the level set by the task file's `Verify mode:` line (`none` / `light` / `full`).
- `light`: run the suite once, open the browser only for test cases a spec cannot check (visual/layout), no new scenarios; write a spec only to reproduce a bug found.
- `full`: also try up to 2 important edge scenarios and add specs for unchecked scenarios (max 3 new tests).
- Results go in the task file's "## Verify" section with screenshot paths.
- The Verify agent must not change app code. Its last line in "## Verify" is exactly `VERIFY: PASS` or `VERIFY: FAIL`.

## Workflow Rules

- Every task has a file in `.agents/tasks/` (template: `_TEMPLATE.md`). Read it before starting work.
- Only modify files named in the task's plan. If another file must change, record the reason in the task file.
- Commit after each step with a clear message.
- Before finishing: tick the plan checkboxes and update "Trạng thái hiện tại" and "Test status" in the task file.

## Documentation Rules

After finishing anything new (feature, behavior change, API or config change, env var, script, folder or dependency change), double-check the project docs and update whatever is now out of date, in the same task:
- `README.md`: features, architecture/diagrams, API, environment variables, scripts, project structure, tech stack. Compare it against the code, not against memory.
- Any other spec/design doc that describes the changed behavior.
- `AGENTS.md`: Architecture, Codebase Map, Commands, conventions.
- Remove statements that are no longer true instead of adding a note next to them.
- If nothing needs changing, say so in the task file's "Trạng thái hiện tại" (e.g. "Docs checked: no change needed").

