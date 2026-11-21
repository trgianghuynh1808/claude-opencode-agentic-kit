#!/usr/bin/env bash
# Cài claude-opencode-kit vào một project có sẵn.
#
#   ./install.sh /path/to/your-project            # cài lần đầu
#   ./install.sh /path/to/your-project --force    # ghi đè cả file cấu hình/template đã có
#
# Luôn cập nhật:  scripts/run-task.sh, scripts/watch-tasks.sh, scripts/log-gaps.sh
# Chỉ tạo nếu chưa có (trừ khi --force):
#   CLAUDE.md, AGENTS.md, .agents/config.sh, .agents/tasks/_TEMPLATE.md

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-}"
FORCE=0
[[ "${2:-}" == "--force" ]] && FORCE=1

if [[ -z "$TARGET" ]]; then
  echo "Cách dùng: ./install.sh /path/to/your-project [--force]"
  exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"

if ! git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "⛔ $TARGET không phải git repo. Chạy 'git init' trước."
  exit 1
fi

copy_always() {   # file thuộc kit: luôn cập nhật
  mkdir -p "$(dirname "$TARGET/$2")"
  cp "$KIT_DIR/$1" "$TARGET/$2"
  echo "  ✓ $2"
}

copy_once() {     # file người dùng sẽ sửa: không ghi đè nếu đã có
  if [[ -e "$TARGET/$2" && "$FORCE" != "1" ]]; then
    echo "  • $2 đã có, giữ nguyên (dùng --force để ghi đè)"
  else
    mkdir -p "$(dirname "$TARGET/$2")"
    cp "$KIT_DIR/$1" "$TARGET/$2"
    echo "  ✓ $2"
  fi
}

echo "Cài claude-opencode-kit vào $TARGET"
echo ""
echo "Scripts:"
copy_always scripts/run-task.sh    scripts/run-task.sh
copy_always scripts/watch-tasks.sh scripts/watch-tasks.sh
copy_always scripts/log-gaps.sh    scripts/log-gaps.sh
copy_always scripts/handoff.sh     scripts/handoff.sh
copy_always scripts/wait-task.sh   scripts/wait-task.sh
copy_always scripts/notify.sh      scripts/notify.sh
chmod +x "$TARGET"/scripts/run-task.sh "$TARGET"/scripts/watch-tasks.sh "$TARGET"/scripts/log-gaps.sh \
         "$TARGET"/scripts/handoff.sh "$TARGET"/scripts/wait-task.sh "$TARGET"/scripts/notify.sh

echo ""
echo "Cấu hình và template:"
copy_once template/CLAUDE.md                 CLAUDE.md
copy_once template/AGENTS.md                 AGENTS.md
copy_once template/.agents/config.sh         .agents/config.sh
copy_once template/.agents/tasks/_TEMPLATE.md .agents/tasks/_TEMPLATE.md
mkdir -p "$TARGET/.agents/queue" "$TARGET/.agents/status"

echo ""
echo ".gitignore:"
touch "$TARGET/.gitignore"
for entry in ".agents/queue/" ".agents/status/" ".agents/run.log" "test-results/" "playwright-report/"; do
  if grep -qxF "$entry" "$TARGET/.gitignore" || grep -qxF "/$entry" "$TARGET/.gitignore"; then
    echo "  • $entry đã có"
  else
    echo "$entry" >> "$TARGET/.gitignore"
    echo "  ✓ thêm $entry"
  fi
done

echo ""
echo "Kiểm tra công cụ:"
for cmd in git claude opencode npx; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  ✓ $cmd"
  else
    echo "  ✗ $cmd chưa có — xem README phần Yêu cầu"
  fi
done

cat <<'EOF'

Xong. Bước tiếp theo (chi tiết trong README):
  1. Sửa .agents/config.sh: model, URL dev, lệnh kiểm tra.
  2. Điền AGENTS.md bằng prompts/generate-agents-md.md, đọc lại rồi commit.
  3. Cài Playwright Test nếu chưa có (xem examples/playwright.config.ts).
  4. Commit:  git add -A && git commit -m "chore: add claude-opencode-kit"
  5. Ô trái:  scripts/watch-tasks.sh      Ô phải:  claude (plan mode)
     Duyệt plan xong, Claude tự chạy tiếp: chờ OpenCode → verify → review → ship (Autopilot).
EOF
