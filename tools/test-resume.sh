#!/usr/bin/env bash
# Regression for /resume (room-ops.py): plain /resume, /resume T03 on one BLOCKED task while the room runs, notes, wrong states.
#   tools/test-resume.sh
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export AGENT_ROOMS_FILE="$T/rooms.json"
P="$T/proj"; mkdir -p "$P"; git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm init
"$KIT/install.sh" "$P" >/dev/null 2>&1; (cd "$P" && scripts/agent-room.sh init --topic 5 --port 4000 >/dev/null)
git -C "$P" add -A; git -C "$P" commit -qm kit; git -C "$P" branch staging; git -C "$P" checkout -q staging
cd "$P"
fail=0
check() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }
cmd() { rm -f .agents/outbox/*.json; printf '%s' "{\"command\":\"$1\",\"args\":\"${2:-}\"}" > .agents/inbox/c.json; python3 scripts/room-ops.py inbox .agents/inbox/c.json >/dev/null; rm -f .agents/inbox/c.json
        python3 -c 'import json,glob; fs=sorted(glob.glob(".agents/outbox/*.json")); print(json.load(open(fs[-1]))["text"] if fs else "")'; }
auto() { sed -i.bak "s/^AUTO_MODE=.*/AUTO_MODE=\"$1\"/" .agents/room.env; rm -f .agents/room.env.bak; }
state() { grep -o "\`$1\` \[[a-zA-Z_]*\]" .agents/board.md | grep -o "\[.*\]"; }
board() {   # T03 blocked, T04 in progress, T05 needs_info, T06 awaiting_plan
python3 - <<'PY'
import re
p='.agents/board.md'; s=open(p).read()
s=re.sub(r"- \[.\] `T0\d`.*\n","",s)
t=("- [ ] `T03` [BLOCKED] Task 3 (slug: `task-03-t3`)\n- [ ] `T04` [in_progress] Task 4 (slug: `task-04-t4`)\n"
   "- [ ] `T05` [needs_info] Task 5 (slug: `task-05-t5`)\n- [ ] `T06` [awaiting_plan] Task 6 (slug: `task-06-t6`)\n")
open(p,'w').write(s.replace("## Checklist & Tasks\n","## Checklist & Tasks\n\n"+t,1))
PY
}
mkdir -p .agents/outbox .agents/inbox .agents/notices .agents/plan-feedback

echo "room running, one task BLOCKED:"
board; auto true; touch .agents/notices/skip-T03-BLOCKED .agents/manager.sig
R="$(cmd /resume T03)"
check "/resume T03 unblocks only T03"            '[[ "$(state T03)" == "[pending]" && "$(state T04)" == "[in_progress]" && "$(state T05)" == "[needs_info]" ]]'
check "reply says it queues behind T04"          'grep -q "T03" <<<"$R" && grep -q "T04" <<<"$R"'
check "skip notice and guard counter cleared"    '[[ ! -f .agents/notices/skip-T03-BLOCKED && ! -f .agents/manager.sig ]]'
check "room stays on"                            'grep -q "^AUTO_MODE=\"true\"" .agents/room.env'

echo "note goes to the Tech Lead:"
board; R="$(cmd /resume "T03 dùng Supabase thay vì D1")"
check "note saved like a /revise note"           'grep -q "dùng Supabase thay vì D1" .agents/plan-feedback/task-03-t3.md && grep -q "ghi chú" <<<"$R"'

echo "plain /resume while running:"
board; R="$(cmd /resume)"
check "retries the blocked task, not 'already running'" '[[ "$(state T03)" == "[pending]" ]] && ! grep -q "chạy sẵn rồi mà" <<<"$R" && grep -q "T03" <<<"$R"'
R="$(cmd /resume)"
check "nothing blocked + running -> already running"    'grep -q "chạy sẵn rồi mà" <<<"$R"'

echo "wrong states and ids:"
board; R="$(cmd /resume T04)"
check "task that is not blocked is left alone"   '[[ "$(state T04)" == "[in_progress]" ]] && grep -q "không bị chặn" <<<"$R"'
R="$(cmd /resume T05)"
check "needs_info points to /revise"             'grep -q "/revise T05" <<<"$R" && [[ "$(state T05)" == "[needs_info]" ]]'
R="$(cmd /resume T06)"
check "awaiting_plan points to /approve"         'grep -q "/approve" <<<"$R"'
R="$(cmd /resume T99)"
check "unknown id is reported"                   'grep -q "không thấy task" <<<"$R"'

echo "room stopped:"
board; auto false
R="$(cmd /resume)"
check "plain /resume turns the room on and unblocks" 'grep -q "^AUTO_MODE=\"true\"" .agents/room.env && [[ "$(state T03)" == "[pending]" ]]'
board; auto false
R="$(cmd /resume T03)"
check "/resume T03 on a stopped room also turns it on" 'grep -q "^AUTO_MODE=\"true\"" .agents/room.env && [[ "$(state T03)" == "[pending]" ]]'

echo "task-id lookup (used by the watcher's messages):"
board
check "task-id maps a task file to its id"       '[[ "$(python3 scripts/room-ops.py task-id .agents/tasks/2026-01-01-task-03-t3.md)" == "T03" ]]'
check "task-id maps a bare slug too"             '[[ "$(python3 scripts/room-ops.py task-id task-04-t4)" == "T04" ]]'
check "unknown slug -> empty"                    '[[ -z "$(python3 scripts/room-ops.py task-id task-99-nope)" ]]'
exit $fail
