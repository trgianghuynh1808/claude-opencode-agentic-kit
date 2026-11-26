#!/usr/bin/env bash
# Regression: /task and /revise with pictures through the inbox dispatcher (room-ops.py inbox).
#   tools/test-inbox-images.sh
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
mkdir -p .agents/outbox .agents/inbox/files .agents/plan-feedback
send() { rm -f .agents/outbox/*.json; printf '%s' "$1" > .agents/inbox/c.json; python3 scripts/room-ops.py inbox .agents/inbox/c.json >/dev/null; rm -f .agents/inbox/c.json
         python3 -c 'import json,glob; fs=sorted(glob.glob(".agents/outbox/*.json")); print(json.load(open(fs[-1]))["text"] if fs else "")'; }
printf x > .agents/inbox/files/1-1.jpg; printf y > .agents/inbox/files/1-2.png
out="$(send '{"command":"/task","args":"Làm nút A\nLàm nút B","images":[".agents/inbox/files/1-1.jpg",".agents/inbox/files/1-2.png"]}')"
check "reply mentions the pictures" 'grep -q "2 ảnh" <<<"$out"'
id1="$(grep -o '`T[0-9]*`' .agents/board.md | head -1 | tr -d '`')"; id2="$(grep -o '`T[0-9]*`' .agents/board.md | sed -n 2p | tr -d '`')"
check "both tasks got both pictures" '[[ -f .agents/attachments/$id1/req-1.jpg && -f .agents/attachments/$id2/req-2.png ]]'
check "inbox pictures removed" '[[ -z "$(ls .agents/inbox/files)" ]]'
out="$(send '{"command":"/task","args":"Việc không ảnh"}')"
check "plain /task has no picture note" '! grep -q "kèm" <<<"$out"'
# revise: a task waiting for the user
sed -i.bak "s/\`$id1\` \[pending\]/\`$id1\` [awaiting_plan]/" .agents/board.md; rm -f .agents/board.md.bak
printf z > .agents/inbox/files/2-1.png
send "{\"command\":\"/revise\",\"args\":\"$id1 dùng màu xanh như ảnh\",\"images\":[\".agents/inbox/files/2-1.png\"]}" >/dev/null
fb="$(cat .agents/plan-feedback/*.md 2>/dev/null)"
check "feedback file lists the revise picture" 'grep -q "attachments/$id1/rev-" <<<"$fb"'
check "revise picture stored" 'ls .agents/attachments/$id1/rev-*-1.png >/dev/null 2>&1'
# the plan prompt tells the Tech Lead where the pictures are
check "plan prompt mentions the attachments folder" 'grep -q "attachments/%s/" "$KIT/scripts/manager-loop.sh"'
exit $fail
