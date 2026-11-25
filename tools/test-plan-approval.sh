#!/usr/bin/env bash
# Hồi quy: thẻ duyệt plan đầy đủ (nút Duyệt / Sửa plan / Hủy), /approve /revise /reject, chế độ auto, plan bị chặn, daemon chờ và sửa plan.
#   tools/test-plan-approval.sh
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"; [[ -n "${DPID:-}" ]] && kill "$DPID" 2>/dev/null' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/claude" <<'STUB'
#!/usr/bin/env bash
n=$(( $(cat "$KT/count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$KT/count"; printf '%s' "$2" > "$KT/prompt-$n.txt"
python3 -c 'import json; print(json.dumps({"type":"result","subtype":"success","is_error":False,"result":"ok","num_turns":1,"total_cost_usd":0.01,"usage":{}}))'
STUB
chmod +x "$T/bin/claude"
export KT="$T" PATH="$T/bin:$PATH" AGENT_ROOMS_FILE="$T/rooms.json"
P="$T/proj"; mkdir -p "$P"; git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm init
"$KIT/install.sh" "$P" >/dev/null 2>&1; (cd "$P" && scripts/agent-room.sh init --topic 5 --port 4000 >/dev/null); git -C "$P" add -A; git -C "$P" commit -qm kit
git -C "$P" branch staging; cd "$P"; git checkout -q staging
sed -i.bak 's/^PLAN_APPROVAL=.*/PLAN_APPROVAL="ask"/' .agents/room.env; rm -f .agents/room.env.bak
fail=0
check() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }
OPS() { python3 scripts/room-ops.py "$@"; }
field() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2],""))' "$1" "$2"; }
msgs() { find .agents/outbox -maxdepth 1 -name '*.json' | sort; }
alltext() { for f in $(msgs); do echo "[$(field "$f" from)|$(field "$f" requires)|$(field "$f" task)]"; field "$f" text; echo "=====MSG====="; done; }
clearbox() { find .agents/outbox -maxdepth 1 -name '*.json' -delete; }
cmd() { printf '%s' "{\"command\":\"$1\",\"args\":\"${2:-}\"}" > .agents/inbox/c.json; OPS inbox .agents/inbox/c.json >/dev/null; rm -f .agents/inbox/c.json; }
state() { grep -oE "\`$1\` \[[A-Za-z_]+\]" .agents/board.md | head -1 | sed -E 's/.*\[(.*)\]/\1/'; }
board() { python3 - "$@" <<'PY'
import sys
p='.agents/board.md'; s=open(p).read()
t="".join(f"- [ ] `{i}` [{st}] Thêm upload ảnh {i} (slug: `{sl}`)\n" for i,st,sl in zip(sys.argv[1::3],sys.argv[2::3],sys.argv[3::3]))
open(p,'w').write(s.replace("## Checklist & Tasks\n","## Checklist & Tasks\n\n"+t,1))
PY
}
mkplan() { mkdir -p .agents/tasks; cat > ".agents/tasks/2026-01-01-$1.md" <<PLAN
# Task: Thêm upload ảnh
Verify mode: light
## Mục tiêu
- Cho phép tải ảnh raw lên portal
- Phân tích ra từng món
## Quyết định đã chốt
- Dùng canvas để cắt ảnh
## Ngữ cảnh
- Dài dòng, không đưa vào thẻ
## Plan
- [ ] 1. [khó] \`shared/src/customDecor.ts\` (mới) → kiểu dữ liệu $2
- [ ] 2. [vừa] \`server/portal/index.html\` → thêm section "Nội thất tuỳ chỉnh"
- [ ] 3. [dễ] \`README.md\` → mô tả
## Test cases
- [ ] T1. Upload — kiểm tra upload — tests/c.spec.ts
  - Setup: không hiện trong thẻ
- [ ] T2. Phân tích — kiểm tra phân tích — tests/c.spec.ts
PLAN
}

echo "the card (PLAN_APPROVAL=ask):"
board T01 plan_ready task-01-up
git checkout -q -b task/task-01-up; mkplan task-01-up ""; git add -A; git commit -qm "plan: task-01-up"
OPS progress task-01-up >/dev/null
M="$(alltext)"
check "ONE message, from the Manager, with the approval buttons flag" '[[ "$(grep -c "=====MSG=====" <<<"$M")" == 1 ]] && grep -q "^\[manager|APPROVE_PLAN|T01\]" <<<"$M"'
check "it shows the goals and the decisions"            'grep -q "\*\*Mục tiêu\*\*" <<<"$M" && grep -q "Cho phép tải ảnh raw" <<<"$M" && grep -q "\*\*Quyết định đã chốt\*\*" <<<"$M" && grep -q "Dùng canvas" <<<"$M"'
check "every step with its difficulty and the mix"      'grep -q "Các bước\*\* (3 · 1 khó · 1 vừa · 1 dễ)" <<<"$M" && grep -q "1\. \*\*khó\*\* ·" <<<"$M" && grep -q "3\. \*\*dễ\*\* ·" <<<"$M"'
check "the test cases (names only), the files, the Verify mode" 'grep -q "Test case\*\* (2)" <<<"$M" && grep -q "T1 · Upload" <<<"$M" && ! grep -q "không hiện trong thẻ" <<<"$M" && grep -q "File sẽ động tới" <<<"$M" && grep -q "\`server/portal/index.html\`" <<<"$M" && grep -q "Verify:\*\* light" <<<"$M"'
check "the automatic check result and how to answer"    'grep -q "Kiểm tra tự động" <<<"$M" && grep -q "/approve" <<<"$M" && grep -q "/revise" <<<"$M"'
check "the task now waits for the user"                 '[[ "$(state T01)" == awaiting_plan ]] && grep -q "AWAITING_PLAN_APPROVAL" .agents/board.md'
clearbox; OPS progress task-01-up >/dev/null
check "the card is not sent twice"                      '[[ -z "$(msgs)" ]]'
cmd /status; check "/status says it waits for you"      'grep -q "chờ bạn duyệt plan" <<<"$(alltext)"'; clearbox

echo "/revise:"
cmd /revise "tách bước 1 thành hai bước nhỏ hơn"
check "state becomes revise and the feedback is kept"   '[[ "$(state T01)" == revise ]] && grep -q "tách bước 1" .agents/plan-feedback/task-01-up.md'
clearbox
mkplan task-01-up "(đã sửa)"; git add -A; git commit -qm "plan(rev-1): task-01-up"
sed -i.bak 's/`T01` \[revise\]/`T01` [plan_ready]/' .agents/board.md; rm -f .agents/board.md.bak
OPS progress task-01-up >/dev/null
check "the revised plan gets a new card"                'grep -q "^\[manager|APPROVE_PLAN|T01\]" <<<"$(alltext)" && grep -q "đã sửa" <<<"$(alltext)" && [[ "$(state T01)" == awaiting_plan ]]'

echo "/approve:"
clearbox; cmd /approve T01
check "the task is handed to OpenCode"                  '[[ "$(state T01)" == in_progress ]] && ls .agents/queue/*.job >/dev/null 2>&1'
check "the plan records WHO approved"                   'grep -q "APPROVED_BY_USER" .agents/tasks/*task-01-up.md'
check "exactly one message, saying you approved"        '[[ "$(msgs | wc -l | tr -d " ")" == 1 ]] && grep -q "Bạn đã duyệt plan" <<<"$(alltext)"'
clearbox; cmd /approve
check "nothing waiting: a polite answer"                'grep -q "Không có plan nào đang chờ" <<<"$(alltext)"'

echo "/reject:"
clearbox; git checkout -q staging; board T02 awaiting_plan task-02-no
cmd /reject T02
check "the task is cancelled and counts as finished"    '[[ "$(state T02)" == cancelled ]] && grep -q "\[x\] \`T02\`" .agents/board.md && grep -q "đã hủy\|Đã hủy" <<<"$(alltext)"'

echo "auto mode and blocked plans:"
clearbox; sed -i.bak 's/^PLAN_APPROVAL=.*/PLAN_APPROVAL="auto"/' .agents/room.env; rm -f .agents/room.env.bak
board T03 plan_ready task-03-auto; git checkout -q -b task/task-03-auto; mkplan task-03-auto ""; git add -A; git commit -qm "plan: task-03-auto"
OPS progress task-03-auto >/dev/null
check "auto: same card from the Tech Lead, no buttons, state untouched" 'grep -q "^\[techlead||\]" <<<"$(alltext)" && grep -q "tự duyệt" <<<"$(alltext)" && [[ "$(state T03)" == plan_ready ]]'
clearbox; sed -i.bak 's/^PLAN_APPROVAL=.*/PLAN_APPROVAL="ask"/' .agents/room.env; rm -f .agents/room.env.bak
board T04 plan_ready task-04-env; git checkout -q -b task/task-04-env; mkplan task-04-env ""; sed -i.bak 's#`README.md` → mô tả#`.env` → đổi key#' .agents/tasks/*task-04-env.md; rm -f .agents/tasks/*.bak; git add -A; git commit -qm "plan: task-04-env"
OPS progress task-04-env >/dev/null
check "a blocked plan gets no buttons and is left to the daemon to block" 'grep -q "^\[techlead||\]" <<<"$(alltext)" && grep -q "chặn plan này" <<<"$(alltext)" && [[ "$(state T04)" == plan_ready ]]'


echo "auto mode (default): critical plans are held, soft doubts are not:"
git checkout -q staging; python3 - <<'PY'
import re
p='.agents/board.md'; s=open(p).read()
s=re.sub(r"^- \[ \] `T0[1-9]`.*\n","",s,flags=re.M); open(p,'w').write(s)
PY
clearbox; sed -i.bak 's/^PLAN_APPROVAL=.*/PLAN_APPROVAL="auto"/' .agents/room.env; rm -f .agents/room.env.bak
board T06 plan_ready task-06-mig; git checkout -q -b task/task-06-mig; mkplan task-06-mig ""; sed -i.bak 's#`README.md` → mô tả#`db/001.sql` → migration mới#' .agents/tasks/*task-06-mig.md; rm -f .agents/tasks/*.bak; git add -A; git commit -qm "plan: task-06-mig"
[[ "$(OPS check-plan task-06-mig)" == CRITICAL:* ]] && echo "  ✓ check-plan: a migration is CRITICAL" || { echo "  ✗ check-plan: migration should be CRITICAL"; fail=1; }
OPS progress task-06-mig >/dev/null
check "a critical plan is held with the buttons and says why"   '[[ "$(state T06)" == awaiting_plan ]] && grep -q "^\[manager|APPROVE_PLAN|T06\]" <<<"$(alltext)" && grep -q "giữ lại chờ bạn duyệt" <<<"$(alltext)" && grep -q "rủi ro nghiêm trọng" <<<"$(alltext)"'
git checkout -q staging; board T07 pending task-07-next
check "the queue is not stuck: the next task is picked (held one skipped)" '[[ "$(bash -c "BOARD=.agents/board.md PLAN_APPROVAL=auto; $(sed -n "/^board_line() {/,/^state_of()/p" scripts/manager-loop.sh | sed "\$d"); board_line")" == *T07* ]]'
check "in ask mode the same board waits on the held task"       '[[ "$(bash -c "BOARD=.agents/board.md PLAN_APPROVAL=ask; $(sed -n "/^board_line() {/,/^state_of()/p" scripts/manager-loop.sh | sed "\$d"); board_line")" == *T06* ]]'
sed -i.bak 's/`T07` \[pending\]/`T07` [in_progress]/' .agents/board.md; rm -f .agents/board.md.bak
clearbox; cmd /approve T06
check "approving a held plan while another task runs queues it (no hand-off yet)" '[[ "$(state T06)" == approved ]] && grep -q "xong sẽ làm tới" <<<"$(alltext)" && ! ls .agents/queue/*task-06* >/dev/null 2>&1'
check "a running task is picked before an approved one"         '[[ "$(bash -c "BOARD=.agents/board.md PLAN_APPROVAL=auto; $(sed -n "/^board_line() {/,/^state_of()/p" scripts/manager-loop.sh | sed "\$d"); board_line")" == *T07* ]]'
sed -i.bak 's/`T07` \[in_progress\]/`T07` [done]/; s/^- \[ \] `T07`/- [x] `T07`/' .agents/board.md; rm -f .agents/board.md.bak
check "...and once it is finished the approved one is next"     '[[ "$(bash -c "BOARD=.agents/board.md PLAN_APPROVAL=auto; $(sed -n "/^board_line() {/,/^state_of()/p" scripts/manager-loop.sh | sed "\$d"); board_line")" == *T06* ]]'

echo "missing context and blocked tasks:"
clearbox; board T08 needs_info task-08-q; board T09 BLOCKED task-09-b
mkdir -p .agents/plan-feedback; printf -- '- Ảnh nào là ảnh gốc?\n' > .agents/plan-feedback/task-08-q.question.md
OPS skipped-notice; OPS skipped-notice
A="$(alltext)"
check "each skipped task is announced once, with the question"  '[[ "$(grep -c "thiếu ngữ cảnh" <<<"$A")" == 1 && "$(grep -c "đang bị chặn" <<<"$A")" == 1 ]] && grep -q "Ảnh nào là ảnh gốc" <<<"$A" && grep -q "/revise T08" <<<"$A"'
clearbox; cmd /revise "T08 ảnh gốc là file raw.png"
check "answering turns needs_info back into pending, feedback kept" '[[ "$(state T08)" == pending ]] && grep -q "raw.png" .agents/plan-feedback/task-08-q.md'
check "/task is an alias of /auto"                              'cmd /task "Việc từ lệnh task" ; grep -q "Việc từ lệnh task" .agents/board.md'
cmd /automode on; check "a blocked plan in auto mode lets the queue go on"        'OPS block T09 "thử nghiệm" >/dev/null; grep -q "chuyển sang" <<<"$(alltext)" && grep -q "AUTO_MODE=\"true\"" .agents/room.env'

echo "the daemon:"
git checkout -q staging; python3 - <<'PY'
import re
p='.agents/board.md'; s=open(p).read()
s=re.sub(r"^- \[ \] `T0[34]`.*\n","",s,flags=re.M); s=re.sub(r"^- \[ \] `T01`.*\n","",s,flags=re.M)
open(p,'w').write(s)
PY
board T05 awaiting_plan task-05-w
sed -i.bak 's/^AUTO_MODE=.*/AUTO_MODE="true"/' .agents/room.env; rm -f .agents/room.env.bak
sleep 300 & echo $! > .agents/watcher.pid; disown
rm -f "$KT/count"; POLL=1 scripts/manager-loop.sh >/dev/null 2>&1 & DPID=$!; disown
sleep 4
check "a task waiting for your approval costs nothing (no Claude call)" '[[ ! -f "$KT/count" ]]'
mkdir -p .agents/plan-feedback; echo "## Góp ý
FEEDBACK_MARKER đổi bước 2" > .agents/plan-feedback/task-05-w.md
sed -i.bak 's/`T05` \[awaiting_plan\]/`T05` [revise]/' .agents/board.md; rm -f .agents/board.md.bak
for i in $(seq 1 20); do [[ -f "$KT/prompt-1.txt" ]] && break; sleep 0.5; done
PR="$(cat "$KT/prompt-1.txt" 2>/dev/null)"
check "a revise request sends the Tech Lead the feedback file" '[[ "$PR" == *"YÊU CẦU SỬA"* && "$PR" == *".agents/plan-feedback/task-05-w.md"* && "$PR" == *"plan(rev-N)"* ]]'
check "...and forbids handing off before you approve"    '[[ "$PR" == *"KHÔNG chạy scripts/handoff.sh"* ]]'
kill "$DPID" 2>/dev/null; kill "$(cat .agents/watcher.pid)" 2>/dev/null

[[ $fail == 0 ]] && echo "OK" || { echo "FAILED"; exit 1; }
