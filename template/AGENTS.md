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

- After each coding step, run the type/lint check and the e2e specs related to that step (see Commands). If there are no specs yet, rely on the type check and note it in the task file.
- When tests fail, read `test-results/results.json` first (the Playwright JSON reporter writes it).
- In "Test status", report every test case from the task file (T1, T2...) as PASS / FAIL / not written yet, not just an overall result.
- When a plan step writes a spec, tick the matching test case in "Test cases" once the spec exists.
- Only use `playwright-cli` (interactive browser tool, separate from `@playwright/test`) when a failure is visual and `results.json` is not enough, or during the Verify phase.
- After any browser testing, clean up: close the browser and stop any dev server you started.
- Use unique test data per run (e.g. usernames like `user-${Date.now()}`) so runs do not collide.
- Tests must never touch production data.
- Test hook: TODO (e.g. `window.__APP__` enabled with `?test=1` to read/set state). Until it exists, do not script long UI flows just to reach a screen.

## Verify Phase

- After all plan steps are done, a Verify agent checks the feature in a real browser with `playwright-cli`.
- It checks every item in "Mục tiêu" and "Test cases", records results in the task file's "## Verify" section with screenshot paths, and turns every checked scenario (PASS or FAIL) into a spec.
- The Verify agent must not change app code. Its last line in "## Verify" is exactly `VERIFY: PASS` or `VERIFY: FAIL`.

## Workflow Rules

- Every task has a file in `.agents/tasks/` (template: `_TEMPLATE.md`). Read it before starting work.
- Only modify files named in the task's plan. If another file must change, record the reason in the task file.
- Commit after each step with a clear message.
- Before finishing: tick the plan checkboxes and update "Trạng thái hiện tại" and "Test status" in the task file.
