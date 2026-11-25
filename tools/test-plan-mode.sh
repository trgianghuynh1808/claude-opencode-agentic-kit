#!/usr/bin/env bash
# Hồi quy cho chế độ /plan của daemon: dùng `claude` giả, thư mục tạm, không bật phòng thật.
#   tools/test-plan-mode.sh
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"; [[ -n "${DPID:-}" ]] && kill "$DPID" 2>/dev/null' EXIT
mkdir -p "$T/bin"

# claude giả: ghi lại từng đối số, trả JSON khác nhau cho Tech Lead và Manager. Điều khiển bằng file: fail-tl, fail-mgr, STUB_SLEEP.
cat > "$T/bin/claude" <<'STUB'
#!/usr/bin/env bash
n=$(( $(cat "$KT/count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$KT/count"
printf '%s\n' "$@" > "$KT/call-$n.args"
prompt="$2"
if [[ "$prompt" == *"CHẾ ĐỘ PLAN: chỉ đọc"* ]]; then
  sleep "${STUB_SLEEP:-3}"
  [[ -f "$KT/fail-tl" ]] && exit 1
  result="TL_FINDINGS_MARKER: màn hình nằm ở client/src/ui/"
elif [[ "$prompt" == *"Bạn là Manager (PM)"* ]]; then
  [[ -f "$KT/fail-mgr" ]] && exit 1
  result="**Trả lời** FINAL_ANSWER_MARKER"
else
  result="ok"
fi
python3 -c 'import json,sys; print(json.dumps({"type":"result","subtype":"success","is_error":False,"result":sys.argv[1],"num_turns":2,"total_cost_usd":0.01,"usage":{}}))' "$result"
STUB
chmod +x "$T/bin/claude"
export KT="$T" PATH="$T/bin:$PATH" AGENT_ROOMS_FILE="$T/rooms.json"

P="$T/proj"; mkdir -p "$P"; git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm init
"$KIT/install.sh" "$P" >/dev/null 2>&1; (cd "$P" && scripts/agent-room.sh init --topic 5 --port 4000 >/dev/null); git -C "$P" add -A; git -C "$P" commit -qm kit
cd "$P"

fail=0
check() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }
inbox() { printf '%s' "$1" > ".agents/inbox/$2.json"; }
texts() { find .agents/outbox -maxdepth 1 -name '*.json' | sort | while read -r f; do python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("["+d["from"]+"] "+d["text"].replace("\n"," | "))' "$f"; done; }
wait_for() { local i; for i in $(seq 1 "${2:-60}"); do eval "$1" && return 0; sleep 0.5; done; return 1; }
start() { POLL=1 scripts/manager-loop.sh >/dev/null 2>&1 & DPID=$!; }

BEFORE_BOARD="$(cat .agents/board.md)"; BEFORE_HEAD="$(git rev-parse HEAD)"; BEFORE_BRANCHES="$(git branch | wc -l)"
start

echo "empty /plan:"
inbox '{"command":"/plan","args":""}' e1
wait_for '[[ -f .agents/inbox/processed/e1.json ]]'
check "answers with usage and calls no Claude" '[[ ! -f "$KT/call-1.args" ]] && texts | grep -q "Cách dùng: .*/plan"'

echo "a question:"
rm -f "$KT/count"; find .agents/outbox -maxdepth 1 -name '*.json' -delete
inbox '{"command":"/plan","args":"Project này có mấy màn hình?"}' q1
wait_for '[[ -f "$KT/call-1.args" ]]' 40
inbox '{"command":"/status"}' s1        # arrives while the Tech Lead is still reading
inbox '{"command":"/plan","args":"câu hỏi thứ hai"}' q2
wait_for 'texts | grep -q FINAL_ANSWER_MARKER' 80
OUT="$(texts)"
check "tells the user the question was received (Manager)"   'grep -q "^\[manager\] Mình nhận câu hỏi rồi" <<<"$OUT"'
check "Tech Lead announces it is reading"                   'grep -q "^\[techlead\] Mình bắt đầu đọc repo" <<<"$OUT"'
check "/status is answered while the plan runs (background)" 'grep -n "Tình hình dự án" <<<"$OUT" | head -1 | cut -d: -f1 | { read -r a; b=$(grep -n FINAL_ANSWER_MARKER <<<"$OUT" | head -1 | cut -d: -f1); (( a < b )); }'
check "a second /plan while one is running is refused"      'grep -q "đang xử lý một câu hỏi khác" <<<"$OUT"'
check "the final answer comes from the Manager"             'grep -q "^\[manager\] \*\*Trả lời\*\* FINAL_ANSWER_MARKER" <<<"$OUT"'
check "exactly two Claude calls (Tech Lead, then Manager)"  '[[ "$(cat "$KT/count")" == 2 ]]'
TL="$(cat "$KT/call-1.args")"; MG="$(cat "$KT/call-2.args")"
check "Tech Lead gets the question"                         'grep -q "Project này có mấy màn hình?" <<<"$TL"'
check "Tech Lead is limited to Read, Grep, Glob"            'grep -qx -- "--tools" <<<"$TL" && grep -qx "Read,Grep,Glob" <<<"$TL"'
check "Tech Lead does NOT get --dangerously-skip-permissions" '! grep -q "dangerously" <<<"$TL"'
check "Manager gets the Tech Lead findings"                 'grep -q "TL_FINDINGS_MARKER" <<<"$MG"'
check "Manager gets the board status"                       'grep -q "Tình hình dự án" <<<"$MG"'
check "Manager has no tools at all"                         'grep -qx -- "--tools" <<<"$MG" && ! grep -q "dangerously" <<<"$MG" && [[ "$(grep -A1 -x -- "--tools" "$KT/call-2.args" | tail -1)" == "" ]]'
check "usage.log has both calls"                            'grep -q "plan: tìm hiểu" .agents/logs/usage.log && grep -q "plan: tổng hợp" .agents/logs/usage.log'
check "question, findings and answer are archived"          '[[ -n "$(ls .agents/plan/*.question.md 2>/dev/null)" && -n "$(ls .agents/plan/*.findings.md 2>/dev/null)" && -n "$(ls .agents/plan/*.answer.md 2>/dev/null)" ]]'
check "plan.pid is cleaned up"                              'wait_for "[[ ! -f .agents/plan.pid ]]" 10'
check "no task was created"                                 '[[ "$(grep -c "^- \[.\] \`T" .agents/board.md)" == 0 ]]'
check "the repo is untouched (no commit, no branch, clean tree)" '[[ "$(git rev-parse HEAD)" == "$BEFORE_HEAD" && "$(git branch | wc -l)" == "$BEFORE_BRANCHES" && -z "$(git status --porcelain)" ]]'

echo "failure paths:"
touch "$KT/fail-tl"; rm -f "$KT/count"; find .agents/outbox -maxdepth 1 -name '*.json' -delete
inbox '{"command":"/plan","args":"hỏi khi Tech Lead lỗi"}' f1
wait_for 'texts | grep -q "Tech Lead tìm hiểu bị lỗi"' 40
check "Tech Lead failure is reported and the Manager is not called" 'texts | grep -q "Tech Lead tìm hiểu bị lỗi" && [[ "$(cat "$KT/count")" == 1 ]]'
rm -f "$KT/fail-tl"; touch "$KT/fail-mgr"; rm -f "$KT/count"; find .agents/outbox -maxdepth 1 -name '*.json' -delete
wait_for '[[ ! -f .agents/plan.pid ]]' 20
inbox '{"command":"/plan","args":"hỏi khi Manager lỗi"}' f2
wait_for 'texts | grep -q TL_FINDINGS_MARKER' 60
check "Manager failure still delivers the Tech Lead findings" 'texts | grep -q "TL_FINDINGS_MARKER" && texts | grep -q "nguyên phân tích của Tech Lead"'

[[ $fail == 0 ]] && echo "OK" || { echo "FAILED"; exit 1; }
