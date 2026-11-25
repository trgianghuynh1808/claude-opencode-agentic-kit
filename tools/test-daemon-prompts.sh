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
for fn in techlead_prompt manager_prompt plan_tech_prompt plan_mgr_prompt; do eval "$(sed -n "/^$fn()/,/^}/p" "$SRC")"; done
STAGING_BRANCH=staging; MAIN_BRANCH=main; MAX_FIX_CYCLES=2
MANAGER_PROMPT="$KIT/prompts/MANAGER.md"; ROOM_DIR=/tmp/x

echo "techlead_prompt plan:"
p="$(techlead_prompt plan T01 task-01-x)"
check "không rỗng"                    '[[ -n "$p" ]]'
check "nêu nhánh staging"             '[[ "$p" == *staging* ]]'
check "cấm handoff ở pha plan"        '[[ "$p" == *"KHÔNG chạy scripts/handoff.sh"* ]]'
check "hướng dẫn báo tiến độ tự động" '[[ "$p" == *"VERIFY: PASS|FAIL"* ]]'
check "cấm kill tiến trình không tự bật" '[[ "$p" == *"KHÔNG kill hay dừng tiến trình bạn không tự khởi động"* ]]'
check "dặn đọc dòng Selectors thay vì bịa" '[[ "$p" == *"ĐỌC dòng Selectors"* ]]'

echo "techlead_prompt finish:"
p="$(techlead_prompt finish T01 task-01-x done .agents/tasks/2026-01-01-task-01-x.md)"
check "không rỗng"                    '[[ -n "$p" ]]'
check "cấm wait-task.sh"              '[[ "$p" == *"không chạy scripts/wait-task.sh"* ]]'
check "nêu trạng thái OpenCode"       '[[ "$p" == *"\"done\""* ]]'
check "nêu file plan"                 '[[ "$p" == *2026-01-01-task-01-x.md* ]]'
check "cấm kill tiến trình (pha finish)" '[[ "$p" == *"KHÔNG kill hay dừng tiến trình bạn không tự khởi động"* ]]'

echo "manager_prompt:"
p="$(manager_prompt APPROVE_PLAN "Task: T01")"
check "không rỗng"                    '[[ -n "$p" ]]'
check "có MODE"                       '[[ "$p" == *"MODE: APPROVE_PLAN"* ]]'

echo "plan_tech_prompt:"
p="$(plan_tech_prompt "Project có mấy màn hình?")"
check "không rỗng"                    '[[ -n "$p" ]]'
check "chứa câu hỏi"                  '[[ "$p" == *"Project có mấy màn hình?"* ]]'
check "nói rõ chỉ đọc"                '[[ "$p" == *"KHÔNG sửa gì"* && "$p" == *"Read, Grep, Glob"* ]]'

echo "plan_mgr_prompt:"
p="$(plan_mgr_prompt "CAU_HOI_X" "BOARD_Y" "PHAN_TICH_Z")"
check "không rỗng"                    '[[ -n "$p" ]]'
check "chứa cả ba đầu vào"            '[[ "$p" == *CAU_HOI_X* && "$p" == *BOARD_Y* && "$p" == *PHAN_TICH_Z* ]]'
check "yêu cầu mục /task gợi ý"       '[[ "$p" == *"/task"* ]]'

[[ $fail == 0 ]] && echo "OK" || { echo "FAILED"; exit 1; }
