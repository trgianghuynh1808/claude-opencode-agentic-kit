#!/usr/bin/env bash
# Gộp mã nguồn kit thành kit-source.md rồi chép vào thư mục knowledge của Claude Project.
#
#   tools/sync-knowledge.sh ~/path/to/project-files   # lần đầu: chỉ định thư mục đích (được nhớ lại)
#   tools/sync-knowledge.sh                           # các lần sau: dùng thư mục đã nhớ
#   tools/sync-knowledge.sh --dry-run                 # chỉ báo có thay đổi hay không, không ghi file
#   KNOWLEDGE_DIR=~/x tools/sync-knowledge.sh         # ghi đè thư mục đích bằng biến môi trường
#
# Thư mục đích được nhớ trong .git/sync-knowledge-dir (nằm trong .git nên không bao giờ bị commit).
# Lấy file từ git (đã track + file mới chưa bị .gitignore), đọc nội dung đang có trên đĩa,
# nên thay đổi chưa commit cũng được gộp vào.
# Nếu nội dung không đổi (bỏ qua dòng ngày tạo) thì không ghi lại file.
#
# Công cụ bảo trì kit: nằm trong tools/ (không phải scripts/) nên install.sh không chép sang project khác.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_NAME="kit-source.md"

# Files listed in the structure tree but not embedded (shell glob, * also matches /)
EXCLUDE="LICENSE README.md .gitignore .DS_Store examples/opencode-agents/* $OUT_NAME"

# Embed order: earlier patterns first; included files matching no pattern go last (sorted)
ORDER="install.sh
scripts/run-task.sh
scripts/watch-tasks.sh
scripts/handoff.sh
scripts/wait-task.sh
scripts/notify.sh
scripts/log-gaps.sh
scripts/*
template/.agents/config.sh
template/.agents/tasks/_TEMPLATE.md
template/CLAUDE.md
template/AGENTS.md
template/*
examples/*
prompts/plan-task.md
prompts/generate-agents-md.md
prompts/review-and-ship.md
prompts/*
tools/*"

DRY_RUN=0
DEST_ARG=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,14p' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    -*) echo "⛔ Không hiểu tuỳ chọn: $arg (xem --help)"; exit 1 ;;
    *) DEST_ARG="$arg" ;;
  esac
done

cd "$KIT_DIR"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "⛔ $KIT_DIR không phải git repo."
  exit 1
fi
GIT_DIR_PATH="$(git rev-parse --git-dir)"
REMEMBER_FILE="$GIT_DIR_PATH/sync-knowledge-dir"

# ---------- thư mục đích ----------
DEST="${DEST_ARG:-${KNOWLEDGE_DIR:-}}"
if [[ -z "$DEST" && -f "$REMEMBER_FILE" ]]; then
  DEST="$(cat "$REMEMBER_FILE")"
fi
if [[ -z "$DEST" ]]; then
  echo "⛔ Chưa biết chép vào đâu. Chạy lần đầu với thư mục knowledge của Claude Project:"
  echo "   tools/sync-knowledge.sh ~/path/to/project-files"
  exit 1
fi
DEST="${DEST/#\~/$HOME}"
if [[ ! -d "$DEST" ]]; then
  echo "⛔ Không thấy thư mục $DEST"
  exit 1
fi
DEST="$(cd "$DEST" && pwd)"
TARGET="$DEST/$OUT_NAME"

# ---------- danh sách file ----------
is_excluded() {
  local f="$1" pat rc=1
  set -f   # keep patterns literal, do not expand against the filesystem
  for pat in $EXCLUDE; do
    # shellcheck disable=SC2254
    case "$f" in $pat) rc=0; break ;; esac
  done
  set +f
  return $rc
}

lang_for() {
  case "$1" in
    *.sh) echo bash ;;
    *.md) echo markdown ;;
    *.ts|*.tsx) echo ts ;;
    *.js|*.mjs|*.cjs) echo js ;;
    *.json) echo json ;;
    *.yml|*.yaml) echo yaml ;;
    *) echo "" ;;
  esac
}

ALL_FILES="$( { git ls-files; git ls-files --others --exclude-standard; } | LC_ALL=C sort -u )"

INCLUDED=""
while IFS= read -r f; do
  if [[ -z "$f" || ! -f "$f" ]]; then continue; fi
  if is_excluded "$f"; then continue; fi
  INCLUDED="$INCLUDED$f
"
done <<EOF
$ALL_FILES
EOF

# Sort included files by ORDER, keeping each file once
ORDERED=""
add_ordered() {
  case "
$ORDERED" in *"
$1
"*) return 0 ;; esac
  ORDERED="$ORDERED$1
"
}
set -f   # patterns in ORDER must not expand against the filesystem
while IFS= read -r pat; do
  [[ -z "$pat" ]] && continue
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    # shellcheck disable=SC2254
    case "$f" in $pat) add_ordered "$f" ;; esac
  done <<EOF
$INCLUDED
EOF
done <<EOF
$ORDER
EOF
set +f
while IFS= read -r f; do
  if [[ -n "$f" ]]; then add_ordered "$f"; fi
done <<EOF
$INCLUDED
EOF

if [[ -z "$ORDERED" ]]; then
  echo "⛔ Không có file nào để gộp."
  exit 1
fi

# ---------- tạo file ----------
TMP="$(mktemp "${TMPDIR:-/tmp}/sync-knowledge.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo "chưa có commit")"
DIRTY=""
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  DIRTY=", có thay đổi chưa commit"
fi

# Fence of tildes longer than any tilde run that starts a line in the file (min 4)
fence_for() {
  awk 'BEGIN { m = 3 }
       match($0, /^[ \t]*~+/) { s = substr($0, RSTART, RLENGTH); gsub(/[ \t]/, "", s); if (length(s) > m) m = length(s) }
       END { f = ""; for (i = 0; i <= m; i++) f = f "~"; print f }' "$1"
}

{
  echo "# kit-source — snapshot mã nguồn claude-opencode-kit"
  echo ""
  echo "_Tạo từ repo kit ngày $(date +%Y-%m-%d) (commit $COMMIT$DIRTY) bằng tools/sync-knowledge.sh. Đây là nguồn sự thật cho script và template; khi kit thay đổi, chạy lại script._"
  echo ""
  echo "Cấu trúc:"
  echo '```'
  printf '%s\n' "$ALL_FILES" | while IFS= read -r f; do
    if [[ -n "$f" && "$f" != "$OUT_NAME" ]]; then echo "$f"; fi
  done
  echo '```'
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    fence="$(fence_for "$f")"
    echo ""
    echo "## \`$f\`"
    echo ""
    echo "$fence$(lang_for "$f")"
    cat "$f"
    # Make sure the closing fence starts on its own line
    if [[ -s "$f" && -n "$(tail -c 1 "$f")" ]]; then echo ""; fi
    echo "$fence"
  done <<EOF
$ORDERED
EOF
} > "$TMP"

COUNT="$(printf '%s' "$ORDERED" | grep -c .)"
SIZE_KB="$(( ($(wc -c < "$TMP") + 1023) / 1024 ))"

# Compare ignoring the generated-date line
strip_date() { grep -v '^_Tạo từ repo kit' "$1" || true; }
if [[ -f "$TARGET" ]] && [[ "$(strip_date "$TARGET")" == "$(strip_date "$TMP")" ]]; then
  echo "✓ $TARGET không đổi ($COUNT file, ${SIZE_KB} KB). Không ghi lại."
  CHANGED=0
else
  CHANGED=1
fi

if [[ "$DRY_RUN" == "1" ]]; then
  if [[ "$CHANGED" == "1" ]]; then echo "• Sẽ cập nhật $TARGET ($COUNT file, ${SIZE_KB} KB). Chạy lại không có --dry-run để ghi."; fi
  exit 0
fi

if [[ "$CHANGED" == "1" ]]; then
  cp "$TMP" "$TARGET"
  echo "✓ Đã ghi $TARGET ($COUNT file, ${SIZE_KB} KB)"
fi

# Remember destination for next runs
if [[ ! -f "$REMEMBER_FILE" || "$(cat "$REMEMBER_FILE")" != "$DEST" ]]; then
  echo "$DEST" > "$REMEMBER_FILE"
  echo "  (đã nhớ thư mục đích; lần sau chỉ cần chạy tools/sync-knowledge.sh)"
fi

if [[ -n "$DIRTY" ]]; then
  echo "  ⚠ Repo kit có thay đổi chưa commit — file vừa gộp lấy nội dung trên đĩa."
fi
exit 0
