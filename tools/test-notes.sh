#!/usr/bin/env bash
# Hồi quy: lưu ý (Dev, Tech Lead, thẻ duyệt ship), kiểm tra xung đột trước khi ship, chi phí/vòng sửa/leo thang,
# ghi chú khi duyệt plan nghi ngờ, và thông báo cho lỗi vốn chỉ ghi log.   Chạy:  tools/test-notes.sh
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export AGENT_ROOMS_FILE="$T/rooms.json"
P="$T/proj"; mkdir -p "$P"; git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm init
"$KIT/install.sh" "$P" >/dev/null 2>&1; (cd "$P" && scripts/agent-room.sh init --topic 5 --port 4000 >/dev/null); git -C "$P" add -A; git -C "$P" commit -qm kit
git init -q --bare "$T/remote.git"; git -C "$P" remote add origin https://github.com/test/repo.git; git -C "$P" config remote.origin.pushurl "$T/remote.git"
git -C "$P" branch staging; cd "$P"; git checkout -q staging
fail=0
check() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }
OPS() { python3 scripts/room-ops.py "$@"; }
field() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2],""))' "$1" "$2"; }
msgs() { find .agents/outbox -maxdepth 1 -name "*-$1.json" | sort; }
alltext() { for f in $(msgs "$1"); do field "$f" text; echo "=====MSG====="; done; }
clearbox() { find .agents/outbox -maxdepth 1 -name '*.json' -delete; }
old() { python3 -c "import os,glob; [os.utime(f,(1,1)) for f in glob.glob('.agents/tasks/*.md')]"; }
setboard() { python3 - "$@" <<'PY'
import sys
p='.agents/board.md'; s=open(p).read()
t="".join(f"- [ ] `{i}` [{st}] {i} (slug: `{sl}`)\n" for i,st,sl in zip(sys.argv[1::3],sys.argv[2::3],sys.argv[3::3]))
open(p,'w').write(s.replace("## Checklist & Tasks\n","## Checklist & Tasks\n\n"+t,1))
PY
}

echo "extracting notes:"
python3 - <<'PY'
import importlib.util
spec=importlib.util.spec_from_file_location("ro","scripts/room-ops.py"); ro=importlib.util.module_from_spec(spec); spec.loader.exec_module(ro)
text="""# t
## Trạng thái hiện tại
- Bước 1 xong.
- Lưu ý T3: chỉ kiểm phần Build
- Cảnh báo: dùng test.fail cho bug badge
- Docs checked: no change needed
- Ghi chú không có tiền tố rõ ràng
## Lưu ý
- Nên thêm test cho Decorate
## Đã thử mà không được
- Mock WebSocket không ổn định
## Verify
Note: chưa chạy trên mobile thật
VERIFY: PASS
"""
n=ro.task_notes(text)
ok = (n==["chỉ kiểm phần Build","dùng test.fail cho bug badge","chưa chạy trên mobile thật","Nên thêm test cho Decorate","Đã thử không được: Mock WebSocket không ổn định"])
print("  %s explicit markers, ## Lưu ý and 'Đã thử' are found; plain remarks and 'Docs checked' are not" % ("✓" if ok else "✗ "+str(n)))
import sys; sys.exit(0 if ok else 1)
PY
[[ $? == 0 ]] || fail=1

echo "Dev step report carries NEW notes only:"
setboard T01 plan_ready task-01-a
git checkout -q -b task/task-01-a; mkdir -p .agents/tasks .agents/progress
plan() { cat > .agents/tasks/2026-01-01-task-01-a.md <<PLAN
# Task
Verify mode: none
## Plan
- [$1] 1. [dễ] \`a.ts\` → x
- [$2] 2. [vừa] \`b.ts\` → y
## Trạng thái hiện tại
$3
## Lưu ý
$4
## Đã thử mà không được
$5
## Verify
$6
PLAN
}
plan " " " " "" "" "" ""
git add -A; git commit -qm plan; OPS progress task-01-a >/dev/null
sed -i.bak 's/\[plan_ready\]/[in_progress]/' .agents/board.md; rm -f .agents/board.md.bak; clearbox
plan "x" " " "- Lưu ý T3: chỉ kiểm phần Build, Decorate chưa kiểm
- Docs checked: no change needed" "- Nên làm tiếp: test cho Decorate" "- Mock WebSocket không ổn định" ""
echo x > i; git add -A; git commit -qm "feat: một"; old; OPS progress task-01-a >/dev/null
M="$(alltext dev)"
check "the step report has a Lưu ý section with the three notes" 'grep -q "\*\*Lưu ý\*\*" <<<"$M" && grep -q "chỉ kiểm phần Build" <<<"$M" && grep -q "Nên làm tiếp: test cho Decorate" <<<"$M" && grep -q "Đã thử không được: Mock WebSocket" <<<"$M"'
check "'Docs checked' is not treated as a note"                '! grep -q "Docs checked" <<<"$M"'
clearbox
plan "x" "x" "- Lưu ý T3: chỉ kiểm phần Build, Decorate chưa kiểm" "- Nên làm tiếp: test cho Decorate" "- Mock WebSocket không ổn định" ""
echo y >> i; git add -A; git commit -qm "feat: hai"; old; OPS progress task-01-a >/dev/null
M="$(alltext dev)"
check "the second step does not repeat notes already reported" '! grep -q "Lưu ý" <<<"$M" && grep -q "Bước 1, 2/2\|Bước 2/2" <<<"$M"'

echo "Tech Lead final report lists every note:"
clearbox
plan "x" "x" "- Lưu ý T3: chỉ kiểm phần Build, Decorate chưa kiểm
- Lưu ý review: tên biến hơi dài (không chặn)" "- Nên làm tiếp: test cho Decorate" "- Mock WebSocket không ổn định" "VERIFY: PASS"
git add -A; git commit -qm "chore: notes"
sed -i.bak 's/`T01` \[in_progress\]/`T01` [done]/; s/- \[ \] `T01`/- [x] `T01`/' .agents/board.md; rm -f .agents/board.md.bak
OPS progress task-01-a >/dev/null
M="$(alltext techlead)"
check "the end-of-task report has all notes, including the review finding" 'grep -q "\*\*Lưu ý\*\*" <<<"$M" && grep -q "tên biến hơi dài" <<<"$M" && grep -q "Nên làm tiếp" <<<"$M" && grep -q "chỉ kiểm phần Build" <<<"$M"'

echo "ship card:"
echo '{"label":"T01 lên plan","cost_usd":0.10,"ts":"2026-01-01 10:00:00"}
{"label":"T01 verify, review, merge","cost_usd":0.21,"ts":"2026-01-01 10:10:00"}
{"label":"plan: tìm hiểu","cost_usd":9.0,"ts":"2026-01-01 10:20:00"}' > .agents/logs/usage.log 2>/dev/null || { mkdir -p .agents/logs; echo '{"label":"T01 lên plan","cost_usd":0.10}
{"label":"T01 verify, review, merge","cost_usd":0.21}
{"label":"plan: tìm hiểu","cost_usd":9.0}' > .agents/logs/usage.log; }
python3 - <<'PY'
import json
p='.agents/progress/task-01-a.json'; d=json.load(open(p)); d["fix"]=["abc1234"]; json.dump(d,open(p,'w'))
PY
echo "3 opencode-go/glm-5.3" > .agents/progress/task-01-a.esc
git checkout -q staging; git merge -q --squash task/task-01-a; git commit -qm "feat: squash"
clearbox; OPS finalize >/dev/null
card="$(field "$(msgs manager | tail -1)" text)"
check "the card lists the notes to read before approving"      'grep -q "Lưu ý cần xem trước khi duyệt" <<<"$card" && grep -q "T01.*chỉ kiểm phần Build" <<<"$card"'
check "the task line counts notes, fix cycles and escalations" 'grep -q "T01.*⚠️ 4 lưu ý.*1 vòng sửa.*1 lần leo thang model" <<<"$card"'
check "the merge pre-check says it is clean"                   'grep -q "merge sạch" <<<"$card"'
check "the batch cost counts only the batch tasks"             'grep -q "~\$0.31" <<<"$card" && ! grep -q "9.3" <<<"$card"'
git checkout -q main; echo main > a; git commit -qam "main side"; git checkout -q staging; echo staging > a; git commit -qam "staging side"
python3 - <<'PY'
p='.agents/board.md'; s=open(p).read(); open(p,'w').write(s.replace("[x] `T01` [done]","[x] `T01` [done]"))
PY
clearbox; OPS finalize >/dev/null
card="$(field "$(msgs manager | tail -1)" text)"
check "a conflict between main and staging is announced"       'grep -q "xung đột" <<<"$card" && grep -q "\`a\`" <<<"$card"'
check "commits only on main are mentioned"                     'grep -q "có 1 commit mà .staging. chưa có" <<<"$card"'

echo "doubted plan that was approved:"
clearbox; setboard T02 in_progress task-02-b
OPS review-note T02 "plan có 9 bước (>8); có migration" >/dev/null
M="$(alltext manager)"
check "the user is told why the plan was looked at closely"    'grep -q "xem kỹ trước khi duyệt" <<<"$M" && grep -q "có migration" <<<"$M"'
clearbox; sed -i.bak 's/`T02` \[in_progress\]/`T02` [BLOCKED]/' .agents/board.md; rm -f .agents/board.md.bak
OPS review-note T02 "x" >/dev/null
check "nothing is added when the plan was blocked"             '[[ -z "$(msgs manager)" ]]'

echo "problems are not silent:"
clearbox
echo 'not json' > .agents/progress/task-01-a.json
OPS progress task-01-a >/dev/null 2>&1; rc=$?
check "a broken progress state fails loudly (non-zero exit)"   '[[ $rc != 0 ]]'
check "...and the user is told once"                           '[[ "$(alltext manager | grep -c "lỗi khi tạo báo cáo tiến độ")" == 1 ]]'
OPS progress task-01-a >/dev/null 2>&1
check "...not again within the interval"                       '[[ "$(alltext manager | grep -c "lỗi khi tạo báo cáo tiến độ")" == 1 ]]'
rm -f .agents/progress/task-01-a.json; clearbox
git config remote.origin.pushurl "$T/does-not-exist.git"
setboard T03 in_progress task-03-c
git checkout -q -b task/task-03-c
printf '# Task\nVerify mode: none\n## Plan\n- [ ] 1. [dễ] `a` → x\n' > .agents/tasks/2026-01-01-task-03-c.md; git add -A; git commit -qm "plan c"
sed -i.bak 's/`T03` \[in_progress\]/`T03` [plan_ready]/' .agents/board.md; OPS progress task-03-c >/dev/null; sed -i.bak 's/`T03` \[plan_ready\]/`T03` [in_progress]/' .agents/board.md; rm -f .agents/board.md.bak
sed -i.bak 's/- \[ \] 1\./- [x] 1./' .agents/tasks/*task-03-c.md; rm -f .agents/tasks/*.bak; echo z > z; git add -A; git commit -qm "feat: c"; old; clearbox
OPS progress task-03-c >/dev/null
check "a failed push tells the user links are off, once"       '[[ "$(alltext manager | grep -c "chưa push được nhánh")" == 1 ]]'

[[ $fail == 0 ]] && echo "OK" || { echo "FAILED"; exit 1; }
