#!/usr/bin/env bash
# Regression: a job left as .job.running by a cut-off watcher is queued again and run when the watcher starts.
#   tools/test-watcher-requeue.sh
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts" "$T/.agents/queue" "$T/.agents/status" "$T/.agents/tasks"
cp "$KIT/scripts/watch-tasks.sh" "$T/scripts/"
printf '#!/usr/bin/env bash\necho ran "$1" >> .agents/ran.txt\n' > "$T/scripts/run-task.sh"; chmod +x "$T"/scripts/*.sh
echo ".agents/tasks/t.md" > "$T/.agents/queue/111.job.running"; touch "$T/.agents/tasks/t.md"
cd "$T"; bash scripts/watch-tasks.sh > out.txt 2>&1 & pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -f .agents/ran.txt ]] && break; sleep 1; done
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
fail=0
check() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }
check "stale .job.running is re-queued and the task runs" 'grep -q "ran .agents/tasks/t.md" .agents/ran.txt 2>/dev/null'
check "the queue is empty afterwards" '[[ -z "$(ls .agents/queue)" ]]'
check "the watcher says it re-queued the job" 'grep -q "↻" out.txt'
exit $fail
