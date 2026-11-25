#!/usr/bin/env bash
# Hồi quy: báo cáo duyệt ship chỉ gửi ảnh do chính từng task chụp lúc Verify, không gửi ảnh chung trong thư mục.
#   tools/test-finalize-shots.sh
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
OPS() { python3 scripts/room-ops.py "$@"; }

# Board: T01 verified with pictures (recorded while it ran), T02 Verify none, T03 pictures found by file name, T04 light but no picture.
python3 - <<'PY'
p='.agents/board.md'; s=open(p).read()
tasks="".join(f"- [x] `T0{i}` [done] Task {i} (slug: `task-0{i}-t{i}`)\n" for i in (1,2,3,4))
open(p,'w').write(s.replace("## Checklist & Tasks\n","## Checklist & Tasks\n\n"+tasks,1))
PY
mkdir -p .agents/tasks .agents/screenshots .agents/progress
plan() { printf '# Task\nVerify mode: %s\n## Plan\n- [x] 1. [dễ] x\n## Verify\n%s\n' "$2" "$3" > ".agents/tasks/2026-11-25-$1.md"; }
plan task-01-t1 full  "VERIFY: PASS"
plan task-02-t2 none  ""
plan task-03-t3 light "VERIFY: PASS"
plan task-04-t4 light "VERIFY: PASS"
# old pictures from earlier work, one tracked by git, all NEWER than the task pictures below (the bug picked the newest ones)
printf x > .agents/screenshots/t01-a.png; printf x > .agents/screenshots/t01-b.png; printf x > .agents/screenshots/task-03-layout.png
sleep 1
printf x > .agents/screenshots/old-kitchen.png; git add -f .agents/screenshots/old-kitchen.png; git commit -qm "old tracked picture"
printf x > .agents/screenshots/unrelated-1.png; printf x > .agents/screenshots/unrelated-2.png
echo '{"task_shots": [".agents/screenshots/t01-a.png", ".agents/screenshots/t01-b.png"]}' > .agents/progress/task-01-t1.json
git add -A .; git commit -qm tasks 2>/dev/null; git branch -f main staging >/dev/null 2>&1

OPS finalize >/dev/null
msgs() { find .agents/outbox -maxdepth 1 -name '*.json' | sort; }
field() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2],""))' "$1" "$2"; }
first="$(msgs | head -1)"; last="$(msgs | tail -1)"
check "the picture messages come first, the approval card is last" '[[ "$(field "$last" requires)" == APPROVE_SHIP ]]'
check "the approval card itself carries no pictures"               '[[ "$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1])).get(\"images\",[])))" "$last")" == 0 ]]'
check "one picture message per task that has pictures (T01, T03)"   '[[ "$(msgs | wc -l | tr -d " ")" == 3 ]]'
m1="$(msgs | sed -n 1p)"; m2="$(msgs | sed -n 2p)"
check "T01 message is announced by the Tech Lead with its task id"  '[[ "$(field "$m1" from)" == techlead ]] && field "$m1" text | grep -q "T01"'
check "T01 gets exactly its two recorded pictures"                  '[[ "$(field "$m1" images)" == *t01-a.png* && "$(field "$m1" images)" == *t01-b.png* && "$(field "$m1" images)" != *unrelated* && "$(field "$m1" images)" != *old-kitchen* ]]'
check "T03 gets the picture named task-03-*"                        'field "$m2" text | grep -q "T03" && [[ "$(field "$m2" images)" == *task-03-layout.png* && "$(field "$m2" images)" != *unrelated* ]]'
allimgs="$(for f in $(msgs); do field "$f" images; done)"
check "unrelated and old pictures are never sent"                   '! grep -q "unrelated\|old-kitchen" <<<"$allimgs"'
card="$(field "$last" text)"
check "summary: T01 says how many pictures are above"               'grep -q "T01.*2 ảnh ở trên" <<<"$card"'
check "summary: T02 (Verify none) says there are no pictures"       'grep -q "T02.*Verify bỏ qua.*không có ảnh" <<<"$card"'
check "summary: T04 (light, nothing captured) says so honestly"     'grep -q "T04.*không có ảnh chụp" <<<"$card"'

echo "the full path (pictures recorded by the progress tracker):"
rm -rf .agents/outbox/*.json .agents/progress/*; mkdir -p .agents/progress
python3 - <<'PY'
p='.agents/board.md'; s=open(p).read()
s=s.replace("[done] Task 1","[in_progress] Task 1").replace("- [x] `T01`","- [ ] `T01`")
open(p,'w').write(s)
PY
plan task-01-t1 full ""                        # Verify not reported yet
OPS progress task-01-t1 >/dev/null            # first tick: state file created (t0)
sleep 1; printf x > .agents/screenshots/fresh-verify.png   # picture made while verifying
plan task-01-t1 full "VERIFY: PASS"           # the Tech Lead writes the result
OPS progress task-01-t1 >/dev/null            # Verify PASS reported -> pictures recorded for the task
sed -i.bak 's/- \[ \] `T01` \[in_progress\]/- [x] `T01` [done]/' .agents/board.md; rm -f .agents/board.md.bak
find .agents/outbox -maxdepth 1 -name '*.json' -delete
OPS finalize >/dev/null
allimgs="$(for f in $(msgs); do field "$f" images; done)"
check "a picture taken during Verify is attached to its task"       'grep -q "fresh-verify.png" <<<"$allimgs"'

[[ $fail == 0 ]] && echo "OK" || { echo "FAILED"; exit 1; }
