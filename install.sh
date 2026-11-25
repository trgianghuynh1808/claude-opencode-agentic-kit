#!/usr/bin/env bash
# Cài claude-opencode-agentic-kit vào một project có sẵn.
#
#   ./install.sh /path/to/your-project            # cài lần đầu
#   ./install.sh /path/to/your-project --force    # ghi đè cả file cấu hình/template đã có
#
# Luôn cập nhật:  scripts/*.sh (run-task, watch-tasks, log-gaps, handoff, wait-task, notify, room-env,
#                 manager-loop, agent-room), .agents/MANAGER.md
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

echo "Cài claude-opencode-agentic-kit vào $TARGET"
echo ""
echo "Scripts:"
copy_always scripts/run-task.sh    scripts/run-task.sh
copy_always scripts/watch-tasks.sh scripts/watch-tasks.sh
copy_always scripts/log-gaps.sh    scripts/log-gaps.sh
copy_always scripts/handoff.sh     scripts/handoff.sh
copy_always scripts/wait-task.sh   scripts/wait-task.sh
copy_always scripts/notify.sh      scripts/notify.sh
copy_always scripts/room-env.sh    scripts/room-env.sh
copy_always scripts/manager-loop.sh scripts/manager-loop.sh
copy_always scripts/agent-room.sh  scripts/agent-room.sh
copy_always scripts/board-view.sh  scripts/board-view.sh
chmod +x "$TARGET"/scripts/*.sh
copy_always prompts/MANAGER.md     .agents/MANAGER.md
mkdir -p "$TARGET/.agents"
echo "$KIT_DIR" > "$TARGET/.agents/kit-dir"   # agent-room.sh dùng để tìm bridge-bot/rooms.json

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
for entry in ".agents/board.md" ".agents/room.env" ".agents/kit-dir" ".agents/queue/" ".agents/status/" ".agents/run.log" "test-results/" "playwright-report/"; do
  if grep -qxF "$entry" "$TARGET/.gitignore" || grep -qxF "/$entry" "$TARGET/.gitignore"; then
    echo "  • $entry đã có"
  else
    echo "$entry" >> "$TARGET/.gitignore"
    echo "  ✓ thêm $entry"
  fi
done

# board.md/room.env do daemon sửa liên tục: nếu bản cũ đã commit chúng, gỡ khỏi git (giữ file) để handoff không bị chặn vì cây dơ
for f in .agents/board.md .agents/room.env; do
  if git -C "$TARGET" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    git -C "$TARGET" rm --cached -q "$f" && echo "  ✓ gỡ $f khỏi git (file vẫn còn, nhớ commit)"
  fi
done
git -C "$TARGET" ls-files -v | grep '^h ' | awk '{print $2}' | while read -r f; do
  git -C "$TARGET" update-index --no-assume-unchanged "$f" && echo "  ✓ bỏ assume-unchanged: $f"
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
  4. Commit:  git add -A && git commit -m "chore: add claude-opencode-agentic-kit"
  5. (Tùy chọn) Chế độ nhiều phòng qua Telegram: scripts/agent-room.sh init --topic <ID> --port <PORT>
     rồi scripts/agent-room.sh start — xem README mục "Multi-room mode".
  6. Ô trái:  scripts/watch-tasks.sh      Ô phải:  claude (plan mode)
     Duyệt plan xong, Claude tự chạy tiếp: chờ OpenCode → verify → review → ship (Autopilot).
EOF
