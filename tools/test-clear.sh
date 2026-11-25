#!/usr/bin/env bash
# Hồi quy cho /clear và /clearlog (room-ops.py): từ chối khi phòng bận, dọn khi rảnh, giữ bản sao board và số task, giữ usage.log.
#   tools/test-clear.sh
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
cmd() { printf '%s' "{\"command\":\"$1\",\"args\":\"${2:-}\"}" > .agents/inbox/c.json; python3 scripts/room-ops.py inbox .agents/inbox/c.json >/dev/null; rm -f .agents/inbox/c.json
        python3 -c 'import json,sys,glob; f=sorted(glob.glob(".agents/outbox/*.json"))[-1]; print(json.load(open(f))["text"])'; }

python3 - <<'PY'
p='.agents/board.md'; s=open(p).read()
t="".join(f"- [x] `T0{i}` [shipped] Task {i} (slug: `task-0{i}-t{i}`)\n" for i in (1,2,3))
open(p,'w').write(s.replace("## Checklist & Tasks\n","## Checklist & Tasks\n\n"+t,1))
PY
mkdir -p .agents/tasks .agents/status .agents/progress .agents/plan .agents/inbox/processed .agents/outbox/sent .agents/logs
for i in 1 2 3; do echo "# t" > .agents/tasks/2026-01-01-task-0$i-t$i.md; echo "done 1" > .agents/status/2026-01-01-task-0$i-t$i.status; echo '{}' > .agents/progress/task-0$i-t$i.json; done
echo x > .agents/inbox/processed/old.json; echo x > .agents/outbox/sent/old.json; echo q > .agents/plan/1.question.md; touch .agents/manager.sig
git add -A .agents/tasks; git commit -qm plans

echo "busy room:"
sed -i.bak 's/^AUTO_MODE=.*/AUTO_MODE="true"/' .agents/room.env; rm -f .agents/room.env.bak
R="$(cmd /clear)"
check "/clear is refused while AUTO_MODE is on"          'grep -q "đang bận" <<<"$R" && grep -q "T01" .agents/board.md && [[ -f .agents/status/2026-01-01-task-01-t1.status ]]'
R="$(cmd /clearlog)"
check "/clearlog is refused too"                         'grep -q "đang bận" <<<"$R"'
sed -i.bak 's/^AUTO_MODE=.*/AUTO_MODE="false"/' .agents/room.env; rm -f .agents/room.env.bak
echo "running 1" > .agents/status/2026-01-01-task-03-t3.status
R="$(cmd /clear)"
check "/clear is refused while OpenCode is running"      'grep -q "OpenCode đang chạy" <<<"$R"'
echo "done 1" > .agents/status/2026-01-01-task-03-t3.status

echo "/clear on an idle room:"
R="$(cmd /clear)"
check "reply says it is done and names the archive"      'grep -q "Dọn dẹp xong" <<<"$R" && grep -q "board-archive" <<<"$R"'
check "the old board is archived"                        'grep -q "T03" .agents/board-archive/*.md'
check "the board is empty, IDLE and AUTO off"            '! grep -q "^- \[.\] \`T" .agents/board.md && grep -q "Current Phase:\*\* IDLE" .agents/board.md && grep -q "Auto Mode:\*\* OFF" .agents/board.md'
check "per-task state and old messages are gone"         '[[ -z "$(ls .agents/status .agents/progress .agents/plan .agents/inbox/processed .agents/outbox/sent 2>/dev/null | grep -v ":" | grep .)" ]] && [[ ! -f .agents/manager.sig ]]'
check "plan files (tracked) and room.env are untouched"  '[[ "$(ls .agents/tasks/*task-0*.md | wc -l | tr -d " ")" == 3 ]] && grep -q "TELEGRAM_TOPIC_ID" .agents/room.env'
printf '%s' '{"command":"/auto","args":"Việc mới"}' > .agents/inbox/a.json; python3 scripts/room-ops.py inbox .agents/inbox/a.json >/dev/null
check "numbering continues after the clear (T04, not T01)" 'grep -q "\`T04\` \[pending\] Việc mới" .agents/board.md'
sed -i.bak 's/^AUTO_MODE=.*/AUTO_MODE="false"/' .agents/room.env; rm -f .agents/room.env.bak
python3 - <<'PY'
import re
p='.agents/board.md'; s=open(p).read(); open(p,'w').write(re.sub(r"- \[ \] `T04` \[pending\]","- [x] `T04` [shipped]",s))
PY

echo "/clearlog:"
seq 1 1000 > .agents/run.log; seq 1 500 > .agents/logs/activity.log; seq 1 50 > .agents/logs/usage.log
R="$(cmd /clearlog)"
check "run.log and other logs keep their last 200 lines" '[[ "$(wc -l < .agents/run.log | tr -d " ")" == 200 && "$(tail -1 .agents/run.log)" == 1000 && "$(wc -l < .agents/logs/activity.log | tr -d " ")" == 200 ]]'
check "usage.log is left alone"                          '[[ "$(wc -l < .agents/logs/usage.log | tr -d " ")" == 50 ]]'
check "the reply reports what was freed"                 'grep -q "Giải phóng" <<<"$R" && grep -q "usage.log" <<<"$R"'
R="$(cmd /clearlog 0)"
check "/clearlog 0 empties the logs"                     '[[ ! -s .agents/run.log && ! -s .agents/logs/activity.log && "$(wc -l < .agents/logs/usage.log | tr -d " ")" == 50 ]]'

[[ $fail == 0 ]] && echo "OK" || { echo "FAILED"; exit 1; }
