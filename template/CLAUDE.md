@AGENTS.md

## Handoff to OpenCode (Claude only)

Claude plans and reviews; OpenCode implements and verifies. Do not implement a task plan yourself unless the user explicitly asks.

When the user approves a plan:

1. Write the plan to `.agents/tasks/<YYYY-MM-DD>-<slug>.md` using `.agents/tasks/_TEMPLATE.md`.
   - Every plan step must look like `- [ ] N. [dễ|vừa|khó] ...` and name the exact files and functions to change.
   - The plan must include a "Test cases" section: each e2e test as `- [ ] T1. <name> — <what it verifies> — <spec file>`.
   - The plan must include the step(s) that write those specs. If a test needs app state that is hard to reach through the UI, plan to set it through the project's test hook (see AGENTS.md); add what the hook is missing as its own step.
   - Label honestly: `[dễ]` = one file, mechanical change; `[vừa]` = a few files following existing patterns; `[khó]` = new design, crosses several layers/packages, or tricky state/sync logic.
   - Prefer 3–6 steps; merge tiny related changes into one step. Consecutive steps with the same label run in one OpenCode session, so keep same-label steps together when it makes sense.
   - Add a "## Ngữ cảnh" section before "## Plan": the key file paths, function signatures, types and constants the steps depend on (short snippets, not whole files), so OpenCode does not have to re-explore the codebase.
2. Create a task branch from the main branch: `git checkout main && git pull --ff-only && git checkout -b task/<slug>`. If the working tree is dirty, stop and ask the user.
3. Commit only the task file on that branch: `git add <task file> && git commit -m "plan: <slug>"`. The working tree must be clean afterwards (OpenCode refuses to start otherwise).
4. Hand off: `echo <task file> > .agents/queue/$(date +%s).job`
5. Tell the user in one line that OpenCode has started on branch `task/<slug>`, then stop.

When the user asks for a review after OpenCode finishes:

1. Read the task file, including "Test status" and "Verify".
2. Read `git diff main...HEAD` on the task branch.
3. Report bugs, deviations from the plan, and failed or missing test cases. Do not rewrite code that is correct.
4. If Verify found failures, propose the fix as a short follow-up plan instead of fixing it directly, unless the user asks you to fix it.
5. End the review with one line: whether it is ready to ship.

When the user says "ship" (or asks to merge/push) on a task branch:

1. Make sure the working tree is clean and the project's checks (see Commands in AGENTS.md) pass.
2. Squash the branch into one commit on main:
   `git checkout main && git pull --ff-only && git merge --squash task/<slug>`
3. Commit with one Conventional Commit message summarizing the whole task (e.g. `feat(orders): show container line last in recipe`), with a short body listing the main changes and the test cases added. Do not mention the individual step commits.
4. `git push origin main`, then delete the task branch: `git branch -D task/<slug>`.
5. Report the final commit hash and that it was pushed. If the push fails (e.g. remote has new commits), stop and tell the user instead of forcing.
