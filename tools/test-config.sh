#!/usr/bin/env bash
# Hồi quy: /automode on|off, /config (xem, đổi, từ chối giá trị xấu), khối cấu hình trên board đồng bộ với room.env, /status hiện cấu hình.
#   tools/test-config.sh
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export AGENT_ROOMS_FILE="$T/rooms.json"
P="$T/proj"; mkdir -p "$P"; git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm init
"$KIT/install.sh" "$P" >/dev/null 2>&1; (cd "$P" && scripts/agent-room.sh init --topic 5 --port 4321 >/dev/null); sed -i.bak 's/^PLAN_APPROVAL=.*/PLAN_APPROVAL="ask"/' "$P/.agents/room.env"; rm -f "$P/.agents/room.env.bak"; git -C "$P" add -A; git -C "$P" commit -qm kit
git -C "$P" branch staging; cd "$P"; git checkout -q staging
fail=0
check() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["text"])' "$1"; }
cmd() { python3 - "$1" "${*:2}" > .agents/inbox/c.json <<'PY'
import json,sys; print(json.dumps({"command": sys.argv[1], "args": sys.argv[2]}))
PY
  python3 scripts/room-ops.py inbox .agents/inbox/c.json >/dev/null; rm -f .agents/inbox/c.json
  field "$(find .agents/outbox -maxdepth 1 -name '*.json' | sort | tail -1)"; }
envval() { sed -nE "s/^$1=\"?([^\"]*)\"?$/\1/p" .agents/room.env | head -1; }

echo "the board shows the settings:"
cmd /status >/dev/null
check "the board header has the settings block (written on the first /status)" 'grep -q "^- \*\*Plan Approval:\*\* ask" .agents/board.md && grep -q "^- \*\*Commit Links:\*\* ON" .agents/board.md && grep -q "^- \*\*Dev Port:\*\* 4321" .agents/board.md'
check "the block sits under the header, before the task list"   '[[ "$(grep -n "Plan Approval" .agents/board.md | cut -d: -f1)" -lt "$(grep -n "## Checklist" .agents/board.md | cut -d: -f1)" ]]'
S="$(cmd /status)"
check "/status lists the settings in plain words"               'grep -q "Duyệt plan: \*\*bạn duyệt plan\*\*" <<<"$S" && grep -q "Link commit: \*\*bật\*\*" <<<"$S" && grep -q "Cổng dev: \*\*4321\*\*" <<<"$S" && grep -q "Model Manager\|Model Manager" <<<"$S"'

echo "/automode:"
R="$(cmd /automode)"
check "without an argument it reports the state"                'grep -q "đang \*\*TẮT\*\*" <<<"$R"'
R="$(cmd /automode on)"
check "on: AUTO_MODE true in room.env and ON on the board"      '[[ "$(envval AUTO_MODE)" == true ]] && grep -q "Auto Mode:\*\* ON" .agents/board.md && grep -q "bật chế độ tự động" <<<"$R"'
check "on with an empty board says what to do next"             'grep -q "Board đang trống" <<<"$R"'
check "on without a running watcher warns about it"             'grep -q "watcher" <<<"$R"'
R="$(cmd /automode on)"
check "on again is harmless"                                    'grep -q "đang bật rồi" <<<"$R"'
R="$(cmd /automode off)"
check "off: AUTO_MODE false everywhere"                         '[[ "$(envval AUTO_MODE)" == false ]] && grep -q "Auto Mode:\*\* OFF" .agents/board.md'
python3 - <<'PY'
p='.agents/board.md'; s=open(p).read()
t="- [ ] `T01` [pending] Việc một (slug: `task-01-a`)\n- [ ] `T02` [BLOCKED] Việc hai (slug: `task-02-b`)\n"
open(p,'w').write(s.replace("## Checklist & Tasks\n","## Checklist & Tasks\n\n"+t,1))
PY
R="$(cmd /automode on)"
check "on with waiting tasks counts them and flags BLOCKED ones" 'grep -q "2 việc" <<<"$R" && grep -q "1 task đang BLOCKED" <<<"$R" && grep -q "Current Phase:\*\* RUNNING" .agents/board.md'
cmd /automode off >/dev/null

echo "/config:"
R="$(cmd /config)"
check "listing shows every setting with its meaning"            'grep -q "approval" <<<"$R" && grep -q "links" <<<"$R" && grep -q "model_techlead" <<<"$R" && grep -q "ask = luôn chờ" <<<"$R"'
R="$(cmd /config approval auto)"
check "changing approval updates room.env, the board and the log" '[[ "$(envval PLAN_APPROVAL)" == auto ]] && grep -q "Plan Approval:\*\* auto" .agents/board.md && grep -q "/config approval" .agents/board.md && grep -q "ask → \*\*auto\*\*" <<<"$R"'
S="$(cmd /status)"
check "/status shows the new value"                             'grep -q "Duyệt plan: \*\*tự duyệt\*\*" <<<"$S"'
cmd /config links off >/dev/null
check "booleans accept on/off words"                            '[[ "$(envval COMMIT_LINKS)" == false ]] && grep -q "Commit Links:\*\* OFF" .agents/board.md'
cmd /config model_techlead sonnet >/dev/null; cmd /config manager_model haiku >/dev/null
check "models: a name is stored, the board shows it"            '[[ "$(envval MODEL_TECHLEAD)" == sonnet ]] && grep -q "Tech Lead Model:\*\* sonnet" .agents/board.md'
cmd /config model_techlead default >/dev/null
check "default clears the model"                                '[[ -z "$(envval MODEL_TECHLEAD)" ]] && grep -q "Tech Lead Model:\*\* default" .agents/board.md'
cmd /config fix_cycles 3 >/dev/null
check "numbers are accepted inside their range"                 '[[ "$(envval MAX_FIX_CYCLES)" == 3 ]]'
R="$(cmd /config fix_cycles 99)"
check "...and refused outside it"                               'grep -q "không hợp lệ" <<<"$R" && [[ "$(envval MAX_FIX_CYCLES)" == 3 ]]'
R="$(cmd /config approval maybe)"
check "a wrong value is refused and the options are named"      'grep -q "không hợp lệ" <<<"$R" && grep -q "ask" <<<"$R" && [[ "$(envval PLAN_APPROVAL)" == auto ]]'
R="$(cmd /config APP_PORT 1)"; R2="$(cmd /config TELEGRAM_TOPIC_ID 9)"; R3="$(cmd /config STAGING_BRANCH main)"
check "ports, ids and branches cannot be changed from chat"     'grep -q "không đổi được" <<<"$R$R2$R3" && [[ "$(envval APP_PORT)" == 4321 ]] && [[ "$(envval TELEGRAM_TOPIC_ID)" == 5 ]] && [[ "$(envval STAGING_BRANCH)" == staging ]]'
R="$(cmd /config approval)"
check "a key alone shows its current value"                     'grep -q "hiện là \*\*auto\*\*" <<<"$R"'

echo "the block survives other board writes and manual edits:"
printf '%s' '{"command":"/auto","args":"Việc mới"}' > .agents/inbox/a.json; python3 scripts/room-ops.py inbox .agents/inbox/a.json >/dev/null
check "adding tasks keeps one settings block, no duplicates"    '[[ "$(grep -c "^- \*\*Plan Approval:\*\*" .agents/board.md)" == 1 ]] && grep -q "Plan Approval:\*\* auto" .agents/board.md'
sed -i.bak 's/^PLAN_APPROVAL=.*/PLAN_APPROVAL="ask"/' .agents/room.env; rm -f .agents/room.env.bak
cmd /status >/dev/null
check "editing room.env by hand shows up after the next /status" 'grep -q "Plan Approval:\*\* ask" .agents/board.md'

[[ $fail == 0 ]] && echo "OK" || { echo "FAILED"; exit 1; }
