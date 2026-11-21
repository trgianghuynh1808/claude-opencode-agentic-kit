---
description: Debug visual failures from screenshots / image diffs. Not for logic errors.
mode: subagent
model: opencode-go/gemini-4-argon
permissions:
  - action: edit
    resource: "*"
    effect: deny
---
Read test-results/results.json and the failure screenshots/diffs. Use playwright-cli if needed.
Do NOT edit code. Return only: root cause, suspected files, proposed fix.
