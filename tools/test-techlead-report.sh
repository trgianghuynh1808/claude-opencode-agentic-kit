#!/usr/bin/env bash
# Hồi quy: Tech Lead gửi MỘT báo cáo cuối task (Verify, merge có link, ảnh một lần); Verify FAIL thì báo ngay; /ship không gửi lại ảnh.
#   tools/test-techlead-report.sh
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export AGENT_ROOMS_FILE="$T/rooms.json"
P="$T/proj"; mkdir -p "$P"; git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm init
"$KIT/install.sh" "$P" >/dev/null 2>&1; (cd "$P" && scripts/agent-room.sh init --topic 5 --port 4000 >/dev/null); sed -i.bak 's/^PLAN_APPROVAL=.*/PLAN_APPROVAL="auto"/' "$P/.agents/room.env"; rm -f "$P/.agents/room.env.bak"; git -C "$P" add -A; git -C "$P" commit -qm kit
git init -q --bare "$T/remote.git"; git -C "$P" remote add origin https://github.com/test/repo.git; git -C "$P" config remote.origin.pushurl "$T/remote.git"
git -C "$P" branch staging; cd "$P"; git checkout -q staging
fail=0
check() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }
OPS() { python3 scripts/room-ops.py "$@"; }
msgs() { find .agents/outbox -maxdepth 1 -name "*-$1.json" | sort; }
field() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2],""))' "$1" "$2"; }
alltext() { for f in $(msgs "$1"); do field "$f" text; echo "=====MSG====="; done; }
python3 - <<'PY'
p='.agents/board.md'; s=open(p).read()
t="- [ ] `T01` [plan_ready] Một (slug: `task-01-a`)\n- [ ] `T02` [plan_ready] Hai (slug: `task-02-b`)\n"
open(p,'w').write(s.replace("## Checklist & Tasks\n","## Checklist & Tasks\n\n"+t,1))
PY
mkdir -p .agents/tasks .agents/screenshots .agents/progress
plan() { printf '# Task\nVerify mode: light\n## Plan\n- [x] 1. [dễ] `a.ts` → x\n## Verify\n%s\n' "$2" > ".agents/tasks/2026-01-01-$1.md"; }
plan task-01-a ""; plan task-02-b ""
OPS progress task-01-a >/dev/null; OPS progress task-02-b >/dev/null          # plan_ready: states created
sed -i.bak 's/\[plan_ready\]/[in_progress]/' .agents/board.md; rm -f .agents/board.md.bak
find .agents/outbox -maxdepth 1 -name '*.json' -delete

echo "T01: Verify PASS, then merge:"
sleep 1; printf x > .agents/screenshots/task-01-view.png
plan task-01-a "- Typecheck PASS, cả bộ test 47 passed
- Review: không có finding blocking
VERIFY: PASS"
OPS progress task-01-a >/dev/null
check "a passing Verify sends nothing on its own"        '[[ -z "$(msgs techlead)" ]]'
echo y > a; git add -A; git commit -qm "feat: một"
sed -i.bak 's/`T01` \[in_progress\]/`T01` [done]/; s/- \[ \] `T01`/- [x] `T01`/' .agents/board.md; rm -f .agents/board.md.bak
OPS progress task-01-a >/dev/null
M="$(alltext techlead)"
check "exactly ONE Tech Lead message at the end of the task" '[[ "$(grep -c "=====MSG=====" <<<"$M")" == 1 ]]'
check "it has Verify (with notes) and Merge sections"     'grep -q "\*\*Verify\*\*" <<<"$M" && grep -q "✅ \*\*PASS\*\*" <<<"$M" && grep -q "47 passed" <<<"$M" && grep -q "\*\*Merge\*\*" <<<"$M"'
SHA=$(git rev-parse --short staging)
check "the merge commit is linked"                       'grep -q "\[$SHA\](https://github.com/test/repo/commit/$SHA)" <<<"$M"'
check "staging was pushed so that link opens"            '[[ "$(git --git-dir="$T/remote.git" rev-parse staging 2>/dev/null)" == "$(git rev-parse staging)" ]]'
f="$(msgs techlead | tail -1)"
check "the pictures are attached to this one message"    'field "$f" images | grep -q task-01-view.png'
check "no separate 'verify and review' start message"    '! grep -q "verify + review" <<<"$M"'

echo "T02: Verify FAIL is told at once:"
sleep 1; printf x > .agents/screenshots/task-02-bug.png
find .agents/outbox -maxdepth 1 -name '*.json' -delete
plan task-02-b "- T1 FAIL: nút không hiện
VERIFY: FAIL"
OPS progress task-02-b >/dev/null
M="$(alltext techlead)"
check "a failing Verify is reported immediately with its picture" 'grep -q "Verify chưa qua" <<<"$M" && field "$(msgs techlead | tail -1)" images | grep -q task-02-bug.png'

echo "ship approval (finalize):"
sed -i.bak 's/`T02` \[in_progress\]/`T02` [done]/; s/- \[ \] `T02`/- [x] `T02`/' .agents/board.md; rm -f .agents/board.md.bak
plan task-02-b "- đã sửa
VERIFY: PASS"
OPS progress task-02-b >/dev/null
find .agents/outbox -maxdepth 1 -name '*.json' -delete
OPS finalize >/dev/null
check "the pictures are NOT sent a second time"          '[[ -z "$(msgs techlead)" ]]'
card="$(field "$(msgs manager | tail -1)" text)"
check "the approval card points to the reports above"    'grep -q "T01.*ảnh trong báo cáo T01 ở trên" <<<"$card"'

[[ $fail == 0 ]] && echo "OK" || { echo "FAILED"; exit 1; }
