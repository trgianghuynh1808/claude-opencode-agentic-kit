#!/usr/bin/env bash
# Quản lý bridge bot chạy ngầm (tmux hoặc pm2). Chạy ở đâu cũng được.
#
#   bridge-bot/bridge.sh start    bật bridge nếu chưa chạy (tự build lần đầu)
#   bridge-bot/bridge.sh stop     tắt bridge
#   bridge-bot/bridge.sh status   đang chạy hay không
#   bridge-bot/bridge.sh logs     xem log (tmux attach / pm2 logs)
#
# Biến: ROOM_RUNNER=pm2|tmux (mặc định: pm2 nếu có, không thì tmux)

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="agent-bridge"

die() { echo "⛔ $*" >&2; exit 1; }
runner() {
  if [[ -n "${ROOM_RUNNER:-}" ]]; then echo "$ROOM_RUNNER"
  elif command -v pm2 >/dev/null 2>&1; then echo pm2
  elif command -v tmux >/dev/null 2>&1; then echo tmux
  else die "Cần pm2 hoặc tmux."; fi
}
running() {
  case "$(runner)" in
    pm2)  pm2 describe "$NAME" >/dev/null 2>&1 ;;
    tmux) tmux has-session -t "$NAME" 2>/dev/null ;;
  esac
}

cmd_start() {
  if running; then echo "✅ Bridge đã chạy."; return; fi
  [[ -f "$DIR/.env" ]] || die "Thiếu $DIR/.env (copy từ .env.example rồi điền BOT_TOKEN, ADMIN_USER_ID, TELEGRAM_CHAT_ID)."
  if [[ ! -f "$DIR/dist/index.js" || "$DIR/src/index.ts" -nt "$DIR/dist/index.js" ]]; then
    echo "🔧 Build bridge..."
    (cd "$DIR" && { [[ -d node_modules ]] || npm install --no-audit --no-fund; } && npm run build >/dev/null)
  fi
  case "$(runner)" in
    pm2)  (cd "$DIR" && pm2 start dist/index.js --name "$NAME" --node-args="--env-file=.env" >/dev/null) ;;
    tmux) tmux new-session -d -s "$NAME" -c "$DIR" "node --env-file=.env dist/index.js" ;;
  esac
  echo "✅ Bridge đã chạy ($(runner): $NAME). Xem log: bridge-bot/bridge.sh logs"
}

cmd_stop() {
  if ! running; then echo "Bridge không chạy."; return; fi
  case "$(runner)" in
    pm2)  pm2 delete "$NAME" >/dev/null ;;
    tmux) tmux kill-session -t "$NAME" ;;
  esac
  echo "🛑 Đã dừng bridge."
}

case "${1:-}" in
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  status) running && echo "Bridge: đang chạy" || echo "Bridge: không chạy" ;;
  logs)   case "$(runner)" in pm2) pm2 logs "$NAME" ;; tmux) tmux attach -t "$NAME" ;; esac ;;
  *) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
