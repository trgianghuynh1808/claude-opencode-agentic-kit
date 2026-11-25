#!/usr/bin/env bash
# Hồi quy: Dev báo MỘT tin cho mỗi bước xong (mô tả + mức độ + model, commit có link GitHub, kết quả test), không tin lẻ.
#   tools/test-step-report.sh
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export AGENT_ROOMS_FILE="$T/rooms.json"
P="$T/proj"; mkdir -p "$P"; git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm init
"$KIT/install.sh" "$P" >/dev/null 2>&1; (cd "$P" && scripts/agent-room.sh init --topic 5 --port 4000 >/dev/null); sed -i.bak 's/^PLAN_APPROVAL=.*/PLAN_APPROVAL="auto"/' "$P/.agents/room.env"; rm -f "$P/.agents/room.env.bak"; git -C "$P" add -A; git -C "$P" commit -qm kit
git init -q --bare "$T/remote.git"
git -C "$P" remote add origin https://github.com/test/repo.git            # what links are built from
git -C "$P" config remote.origin.pushurl "$T/remote.git"                  # where pushes really go
cd "$P"; git checkout -q -b staging
fail=0
check() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }
OPS() { python3 scripts/room-ops.py "$@"; }
slug=task-01-x
python3 - <<'PY'
p='.agents/board.md'; s=open(p).read()
open(p,'w').write(s.replace("## Checklist & Tasks\n","## Checklist & Tasks\n\n- [ ] `T01` [plan_ready] Demo (slug: `task-01-x`)\n",1))
PY
git checkout -q -b task/$slug; mkdir -p .agents/tasks .agents/progress
cat > .agents/tasks/2026-01-01-$slug.md <<'PLAN'
# Task: x
Verify mode: none
## Plan
- [ ] 1. [dễ] `a.ts` → đổi title
- [ ] 2. [vừa] `tests/b.spec.ts` → viết test
## Test status
- Kết quả từng test:
  - T1: chưa viết
  - T2: chưa viết
PLAN
git add -A; git commit -qm "plan: $slug"
OPS progress $slug >/dev/null                                   # plan_ready: creates the state, sends the plan summary
sed -i.bak 's/\[plan_ready\]/[in_progress]/' .agents/board.md; rm -f .agents/board.md.bak
old() { python3 -c "import os,sys,glob; [os.utime(f,(1,1)) for f in glob.glob('.agents/tasks/*.md')]"; }   # pretend the file has been quiet
devmsgs() { for f in $(find .agents/outbox -maxdepth 1 -name '*-dev.json' | sort); do python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["text"])' "$f"; echo "=====MSG====="; done; }
find .agents/outbox -maxdepth 1 -name '*.json' -delete

echo "step 1 finished (commit + checkbox + test result):"
echo "1 opencode-go/deepseek-v4.1-flash" >> ".agents/progress/$slug.models"
sed -i.bak 's/- \[ \] 1\./- [x] 1./; s/T1: chưa viết/T1: PASS/' .agents/tasks/*.md; rm -f .agents/tasks/*.bak; echo x > i; git add -A; git commit -qm "feat: đổi title"
SHA1=$(git rev-parse --short HEAD)
OPS progress $slug >/dev/null
check "not reported while the file is still being written (not settled)" '[[ -z "$(devmsgs)" ]]'
old; OPS progress $slug >/dev/null
M="$(devmsgs)"
check "exactly ONE message for the step"                 '[[ "$(grep -c "=====MSG=====" <<<"$M")" == 1 ]]'
check "the done report has Commit and Test sections, and NO description" 'grep -q "\*\*Commit\*\*" <<<"$M" && grep -q "\*\*Kết quả test\*\*" <<<"$M" && ! grep -q "Mô tả" <<<"$M"'
check "commit has a GitHub link"                         'grep -q "\[$SHA1\](https://github.com/test/repo/commit/$SHA1)" <<<"$M"'
check "test result is in the same message"               'grep -q "T1 ✅ PASS" <<<"$M"'
check "the task branch was pushed so the link opens"     '[[ "$(git --git-dir="$T/remote.git" rev-parse "task/$slug" 2>/dev/null)" == "$(git rev-parse HEAD)" ]]'
check "no separate 'start of step' or lone commit/test message" '! grep -q "Đang cày\|vừa commit thêm\|Kết quả test$" <<<"$(devmsgs | grep -v "^\*\*")" || true'

echo "a lone commit and a lone test result:"
find .agents/outbox -maxdepth 1 -name '*.json' -delete
echo y >> i; git add -A; git commit -qm "chore: tweak"; sed -i.bak 's/T2: chưa viết/T2: FAIL/' .agents/tasks/*.md; rm -f .agents/tasks/*.bak; old
OPS progress $slug >/dev/null
check "nothing is sent for them alone"                   '[[ -z "$(devmsgs)" ]]'
echo "2 opencode-go/glm-5.3" >> ".agents/progress/$slug.models"
sed -i.bak 's/- \[ \] 2\./- [x] 2./' .agents/tasks/*.md; rm -f .agents/tasks/*.bak; git add -A; git commit -qm "test: b"; old
OPS progress $slug >/dev/null
M="$(devmsgs)"
check "they ride along with the next finished step"      '[[ "$(grep -c "=====MSG=====" <<<"$M")" == 1 ]] && grep -q "Bước 2/2" <<<"$M" && grep -q "T2 ❌ FAIL" <<<"$M" && grep -q "chore: tweak" <<<"$M"'

echo "the message when a step STARTS:"
find .agents/outbox -maxdepth 1 -name '*.json' -delete
OPS step-start 6 opencode-go/glm-5.3 '- [ ] 2. [khó] `shared/src/decor.ts` → bỏ flip khỏi DecorationRotation' '- [ ] 3. [vừa] `tests/b.spec.ts` → viết test' >/dev/null
M="$(devmsgs)"
check "it announces the start of the steps"              'grep -q "Bắt đầu bước 2, 3/6" <<<"$M"'
check "it has the description with difficulty and model" 'grep -q "\*\*Mô tả\*\*" <<<"$M" && grep -q "Bước 2\*\* · mức \*\*khó\*\* · model \`glm-5.3\`" <<<"$M" && grep -q "Bước 3\*\* · mức \*\*vừa\*\*" <<<"$M"'
check "it shows what each step is about"                 'grep -q "bỏ flip khỏi DecorationRotation" <<<"$M"'

echo "leftovers at the end (flush):"
find .agents/outbox -maxdepth 1 -name '*.json' -delete
echo z >> i; git add -A; git commit -qm "docs: notes"; OPS progress $slug >/dev/null
check "a late commit is held back..."                    '[[ -z "$(devmsgs)" ]]'
OPS progress $slug --flush >/dev/null
check "...and sent once as 'Phần còn lại' when OpenCode is done" 'grep -q "Phần còn lại" <<<"$(devmsgs)"'

echo "links switched off:"
find .agents/outbox -maxdepth 1 -name '*.json' -delete
sed -i.bak 's/^COMMIT_LINKS=.*/COMMIT_LINKS="false"/' .agents/room.env; rm -f .agents/room.env.bak
rm -f .agents/progress/$slug.json; git -C "$T/remote.git" branch -D "task/$slug" -q
sed -i.bak 's/\[in_progress\]/[plan_ready]/' .agents/board.md; OPS progress $slug >/dev/null; sed -i.bak 's/\[plan_ready\]/[in_progress]/' .agents/board.md; rm -f .agents/board.md.bak
sed -i.bak 's/- \[x\] 1\./- [ ] 1./' .agents/tasks/*.md; rm -f .agents/tasks/*.bak
find .agents/outbox -maxdepth 1 -name '*.json' -delete
sed -i.bak 's/- \[ \] 1\./- [x] 1./' .agents/tasks/*.md; rm -f .agents/tasks/*.bak; echo w >> i; git add -A; git commit -qm "feat: again"; old
OPS progress $slug >/dev/null
M="$(devmsgs)"
check "COMMIT_LINKS=false: no link and nothing pushed"   '! grep -q "github.com" <<<"$M" && ! git --git-dir="$T/remote.git" rev-parse "task/$slug" >/dev/null 2>&1'

[[ $fail == 0 ]] && echo "OK" || { echo "FAILED"; exit 1; }
