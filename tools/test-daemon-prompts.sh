#!/usr/bin/env bash
# Hồi quy cho scripts/manager-loop.sh: mọi prompt daemon sinh ra phải khác rỗng và đủ ý chính.
# (bash -n chỉ kiểm cú pháp: một dấu " lạc trong chuỗi vẫn qua được nhưng làm prompt rỗng.)
#   tools/test-daemon-prompts.sh
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$KIT/scripts/manager-loop.sh"
fail=0
check() { # tên điều-kiện
  if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi
}

# Nạp đúng các hàm tạo prompt (bash 3.2 trên macOS không hỗ trợ source <(...), dùng eval)
for fn in techlead_prompt manager_prompt; do eval "$(sed -n "/^$fn()/,/^}/p" "$SRC")"; done
STAGING_BRANCH=staging; MAIN_BRANCH=main; MAX_FIX_CYCLES=2
MANAGER_PROMPT="$KIT/prompts/MANAGER.md"; ROOM_DIR=/tmp/x

echo "techlead_prompt plan:"
p="$(techlead_prompt plan T01 task-01-x)"
check "không rỗng"                    '[[ -n "$p" ]]'
check "nêu nhánh staging"             '[[ "$p" == *staging* ]]'
check "cấm handoff ở pha plan"        '[[ "$p" == *"KHÔNG chạy scripts/handoff.sh"* ]]'
check "hướng dẫn báo tiến độ tự động" '[[ "$p" == *"VERIFY: PASS|FAIL"* ]]'

echo "techlead_prompt finish:"
p="$(techlead_prompt finish T01 task-01-x done .agents/tasks/2026-01-01-task-01-x.md)"
check "không rỗng"                    '[[ -n "$p" ]]'
check "cấm wait-task.sh"              '[[ "$p" == *"không chạy scripts/wait-task.sh"* ]]'
check "nêu trạng thái OpenCode"       '[[ "$p" == *"\"done\""* ]]'
check "nêu file plan"                 '[[ "$p" == *2026-01-01-task-01-x.md* ]]'

echo "manager_prompt:"
p="$(manager_prompt APPROVE_PLAN "Task: T01")"
check "không rỗng"                    '[[ -n "$p" ]]'
check "có MODE"                       '[[ "$p" == *"MODE: APPROVE_PLAN"* ]]'

[[ $fail == 0 ]] && echo "OK" || { echo "FAILED"; exit 1; }
