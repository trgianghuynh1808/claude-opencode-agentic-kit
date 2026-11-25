#!/usr/bin/env bash
# Hồi quy: các prompt mà run-task.sh gửi cho OpenCode (bước code và Verify) có quy tắc an toàn tiến trình và selector.
# Dùng `opencode` giả ghi lại prompt, thư mục tạm. Chạy:  tools/test-run-task-prompt.sh
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat > "$T/bin/opencode" <<'STUB'
#!/usr/bin/env bash
# opencode giả: lưu prompt (đối số cuối) từng lần gọi; ở bước code thì tick các bước được giao rồi commit
n=$(( $(cat "$KT/count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$KT/count"
prompt="${@: -1}"; printf '%s' "$prompt" > "$KT/prompt-$n.txt"
nums=$(sed -nE 's/.*các bước ([0-9, ]+), không làm.*/\1/p' <<<"$prompt" | tr -d ' ' | tr ',' ' ')
task=$(ls .agents/tasks/*.md | grep -v _TEMPLATE | head -1)
for k in $nums; do sed -i.bak -E "s/^- \[ \] $k\./- [x] $k./" "$task"; rm -f "$task.bak"; echo "w$k" >> work.txt; git add -A; git commit -qm "feat: bước $k" 2>/dev/null; done
exit 0
STUB
chmod +x "$T/bin/opencode"
export KT="$T" PATH="$T/bin:$PATH"

P="$T/proj"; mkdir -p "$P"; git -C "$P" init -q -b main; git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/a"; git -C "$P" add -A; git -C "$P" commit -qm init
"$KIT/install.sh" "$P" >/dev/null 2>&1; git -C "$P" add -A; git -C "$P" commit -qm kit; git -C "$P" checkout -q -b task/x
cd "$P"; mkdir -p .agents/tasks
printf '# Task: x\nVerify mode: light\n## Plan\n- [ ] 1. [dễ] `a.ts`: thêm nút\n## Trạng thái hiện tại\n## Test status\n## Verify\n' > .agents/tasks/2026-01-01-task-01-x.md
git add -A; git commit -qm plan
fail=0
check() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }

VERBOSE=0 ACTIONS=0 VERIFY_AGENT=opencode VERIFY_MODE=light AUTOPILOT=1 scripts/run-task.sh .agents/tasks/2026-01-01-task-01-x.md >/dev/null 2>&1
CODE="$(cat "$KT/prompt-1.txt" 2>/dev/null)"; VER="$(cat "$KT/prompt-2.txt" 2>/dev/null)"
echo "prompt của bước code:"
check "có lời giao bước"                          '[[ "$CODE" == *"Làm LẦN LƯỢT các bước 1"* ]]'
check "cấm kill tiến trình không tự khởi động"    '[[ "$CODE" == *"KHÔNG kill, restart hay dừng"* && "$CODE" == *"dev server đang nghe cổng"* ]]'
check "bắt dừng và ghi lại thay vì kill"          '[[ "$CODE" == *"không tick bước"* && "$CODE" == *"DỪNG để Tech Lead xử lý"* ]]'
check "bước UI phải ghi dòng Selectors"           '[[ "$CODE" == *"MỘT dòng '"'"'Selectors: ...'"'"'"* ]]'
check "bước test phải đọc Selectors trước khi grep" '[[ "$CODE" == *"ĐỌC dòng '"'"'Selectors:'"'"'"* ]]'
echo "prompt của bước Verify (OpenCode):"
check "Verify cũng cấm kill tiến trình"           '[[ "$VER" == *"KHÔNG kill, restart hay dừng"* ]]'
check "Verify dùng Selectors thay vì grep"        '[[ "$VER" == *"dòng '"'"'Selectors:'"'"'"* ]]'

[[ $fail == 0 ]] && echo "OK" || { echo "FAILED"; exit 1; }
