# 🚀 UPGRADE PLAN: Multi-Room Agentic Agency (Manager + Tech Lead + Senior Dev via Telegram)

Tài liệu này định nghĩa chi tiết kế hoạch nâng cấp kit `claude-opencode-agentic-kit` từ mô hình 2-agent thủ công sang mô hình **Multi-Room Agentic Agency** chạy tự động toàn trình (Autopilot) cho nhiều dự án song song, điều khiển từ xa qua Telegram Topics.

---

## 1. Mục tiêu kiến trúc
1. **Mô hình 3 tầng (3-Tier Agent Hierarchy):**
   - **Manager Agent (Claude Code - Headless):** Quản lý checklist, bóc tách task trên `board.md`, tự động duyệt plan (Proxy Approval) khi bật `AUTO_MODE`, điều phối Tech Lead, tổng hợp báo cáo/screenshot gửi người dùng, và dừng lại xin duyệt cuối (`/ship`).
   - **Tech Lead Agent (Claude Code):** Lên technical plan, điều phối OpenCode, verify qua Playwright, review và merge vào nhánh trung gian `staging`.
   - **Senior Dev Agent (OpenCode):** Thực thi code, chạy test dựa trên routing độ khó (như kit cũ).
2. **Project-as-a-Room (Multi-Tenant Isolation):** Mỗi dự án là một phòng độc lập (riêng port, riêng file môi trường `room.env`, riêng daemon chạy ngầm qua PM2/tmux).
3. **Telegram Control Plane:** 1 Telegram Supergroup bật tính năng **Topics** (mỗi Topic = 1 Project Room) nối với 1 **Telegram Bridge Bot** trung tâm.

---

## 2. Cấu trúc thư mục mới (New File Layout)

```text
claude-opencode-agentic-kit/
├── prompts/
│   └── MANAGER.md                    # System prompt cho Manager Agent
├── scripts/
│   ├── manager-loop.sh               # Daemon vòng lặp điều phối của Manager
│   └── agent-room.sh                 # CLI quản lý phòng (init, start, stop, status)
├── bridge-bot/                       # Ứng dụng Node.js trung tâm nối Telegram <-> Local Files
│   ├── package.json
│   ├── tsconfig.json
│   ├── rooms.json                    # Registry mapping: Topic ID <-> Project Path
│   └── src/
│       └── index.ts
└── UPGRADE_PLAN.md                   # File kế hoạch này
```

Bên trong từng project repo được upgrade, cấu trúc `.agents/` sẽ mở rộng thêm:
```text
.agents/
├── room.env                          # Cấu hình riêng (TOPIC_ID, APP_PORT, AUTO_MODE, STAGING_BRANCH)
├── board.md                          # Bảng trắng trạng thái checklist do Manager quản lý
├── inbox/                            # Nhận lệnh/checklist từ Telegram Bot (JSON)
├── outbox/                           # Xuất báo cáo và ảnh verify chờ Bot gửi lên Telegram (JSON)
└── screenshots/                      # Lưu ảnh chụp màn hình Playwright verify
```

---

## 3. Nội dung các thành phần cốt lõi

### 3.1. `prompts/MANAGER.md` (System Prompt cho Manager)
```markdown
# Role & Guidelines: Manager Agent (PM / Scrum Master)

Bạn là **Manager Agent** (Scrum Master / Project Manager) của dự án phần mềm này. Nhiệm vụ của bạn là quản lý tiến độ, điều phối Tech Lead (Claude Code) và giao tiếp với Product Owner (User) qua hệ thống file `.agents/`.

## Các Nguyên Tắc Vận Hành Cốt Lõi:
1. **Không tự viết code ứng dụng:** Bạn chỉ đọc/ghi các tệp quản lý trong `.agents/` (`board.md`, `room.env`, `inbox/`, `outbox/`, `tasks/`).
2. **Xử lý Inbox (`.agents/inbox/`):**
   - Đọc các tệp JSON yêu cầu từ user.
   - Lệnh `/auto <checklist>`: Đặt `AUTO_MODE=true` trong `room.env`, bóc tách checklist thành các task tuần tự trên `board.md`, tạo nhánh `staging` từ `main` nếu chưa có, và báo cáo xác nhận ra `outbox/`.
   - Lệnh `/status`: Đọc `board.md` và gửi tóm tắt tiến độ ra `outbox/`.
   - Lệnh `/stop`: Đặt `AUTO_MODE=false`, chuyển pha thành `IDLE`.
   - Lệnh `/ship`: Nếu toàn bộ task đã hoàn tất hoặc nhánh `staging` sẵn sàng, tiến hành lệnh merge `staging` vào `main`, push lên remote, dọn dẹp `board.md` và báo hoàn thành.
3. **Điều phối Tech Lead (Khi `AUTO_MODE=true`):**
   - Tìm task `[pending]` tiếp theo trên `board.md`, chuyển thành `[in_progress]`.
   - Kích hoạt Tech Lead (Claude Code) thực hiện task trên nhánh `task/<slug>` tách từ `staging`.
4. **Proxy Approval (Duyệt Plan tự động):**
   - Khi Tech Lead xuất plan ra `.agents/tasks/<slug>.md`, hãy đối chiếu plan với mục tiêu task gốc trên `board.md`.
   - **Guardrails An Toàn:** Nếu plan đụng tới file nhạy cảm (`.env`, migration phá hủy dữ liệu, secret) hoặc đi lệch yêu cầu -> Đánh dấu task là `[BLOCKED]`, tắt `AUTO_MODE=false`, xuất cảnh báo ra `outbox/` gọi User can thiệp.
   - Nếu hợp lệ -> Ghi nhận `APPROVED_BY_MANAGER` và gọi `scripts/handoff.sh` để giao việc cho OpenCode.
5. **Chốt Batch & Xin duyệt Ship:**
   - Sau khi Tech Lead verify & review xong, code được merge vào `staging`.
   - Khi tất cả task trên `board.md` đạt `[done]`, chuyển `Current Phase` thành `AWAITING_SHIP_APPROVAL`, tắt `AUTO_MODE=false`, gom báo cáo và danh sách ảnh chụp màn hình Playwright vào `.agents/outbox/` với yêu cầu `APPROVE_SHIP`.
```

### 3.2. Cấu trúc `.agents/room.env` mẫu
```env
PROJECT_NAME="my-awesome-project"
TELEGRAM_TOPIC_ID="12"
APP_PORT="3001"
PLAYWRIGHT_BASE_URL="http://localhost:3001"
AUTO_MODE="false"
STAGING_BRANCH="staging"
MAIN_BRANCH="main"
MAX_FIX_CYCLES="2"
```

### 3.3. Cấu trúc `.agents/board.md` mẫu
```markdown
# Project Board: my-awesome-project
- **Auto Mode:** OFF
- **Current Phase:** IDLE
- **Staging Branch:** staging

## Checklist & Tasks
- [ ] `T01` [pending] Task mẫu 1 (slug: `task-01-sample`)
- [ ] `T02` [pending] Task mẫu 2 (slug: `task-02-sample`)

## Activity Log
- [2026-11-25 11:00] Khởi tạo phòng thành công.
```

### 3.4. Script `scripts/manager-loop.sh` (Daemon quản lý phòng)
```bash
#!/bin/bash
# scripts/manager-loop.sh - Vòng lặp daemon của Manager
ROOM_DIR="$(pwd)"
ENV_FILE="$ROOM_DIR/.agents/room.env"
INBOX_DIR="$ROOM_DIR/.agents/inbox"
LOCK_FILE="$ROOM_DIR/.agents/manager.lock"

if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
fi

echo "🤖 [Manager Daemon] Bắt đầu giám sát phòng tại: $ROOM_DIR"

while true; do
  # Kiểm tra xem có file yêu cầu mới trong inbox hoặc AUTO_MODE đang bật cần tiếp tục xử lý
  NEW_MSG=$(ls -A "$INBOX_DIR"/*.json 2>/dev/null | head -n 1)
  AUTO_ENABLED=false
  if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    if [ "$AUTO_MODE" = "true" ]; then
      AUTO_ENABLED=true
    fi
  fi

  if [ -n "$NEW_MSG" ] || [ "$AUTO_ENABLED" = "true" ]; then
    if [ ! -f "$LOCK_FILE" ]; then
      touch "$LOCK_FILE"
      echo "⚙️ [Manager] Kích hoạt Claude Code làm Manager xử lý..."
      
      # Gọi Claude Code headless với prompt Manager
      claude -p "$(cat "$ROOM_DIR/prompts/MANAGER.md")" --dangerously-skip-permissions >> "$ROOM_DIR/.agents/logs/manager.log" 2>&1
      
      # Xử lý xong inbox message (nếu có) thì xóa hoặc move vào processed
      if [ -n "$NEW_MSG" ] && [ -f "$NEW_MSG" ]; then
        mkdir -p "$INBOX_DIR/processed"
        mv "$NEW_MSG" "$INBOX_DIR/processed/"
      fi

      rm -f "$LOCK_FILE"
    fi
  fi

  sleep 10
done
```

### 3.5. Cập nhật `scripts/` (handoff, wait-task, watch-tasks) và `CLAUDE.md`
- Đảm bảo các script bash hiện tại khi chạy đều đọc biến `APP_PORT` và `PLAYWRIGHT_BASE_URL` từ `.agents/room.env` (fallback về giá trị mặc định nếu không có file `room.env`).
- Bổ sung vào `CLAUDE.md` quy tắc: Khi `AUTO_MODE=true`, làm việc trên nhánh `staging`, sau khi viết plan ra file task thì không dừng terminal chờ input mà handoff luôn cho OpenCode, và khi hoàn thành task thì merge vào `staging`.

### 3.6. CLI quản lý phòng `scripts/agent-room.sh`
Viết một script bash tiện ích hỗ trợ 4 lệnh chính:
- `agent-room init --topic <ID> --port <PORT>`: Tạo cấu trúc `.agents/`, ghi file `room.env`, `board.md`, và đăng ký vào `bridge-bot/rooms.json`.
- `agent-room start`: Khởi chạy `manager-loop.sh` và `watch-tasks.sh` ngầm bằng PM2 hoặc tmux session đặt tên theo dự án.
- `agent-room stop`: Dừng các daemon của phòng.
- `agent-room status`: Kiểm tra trạng thái tiến trình và nội dung `board.md`.

### 3.7. Telegram Bridge Bot (`bridge-bot/src/index.ts`)
Viết một ứng dụng TypeScript nhỏ gọn (sử dụng thư viện `grammy` hoặc `node-telegram-bot-api`):
- **Cấu hình:** Đọc `BOT_TOKEN`, `ADMIN_USER_ID`, và file `rooms.json`.
- **Inbound (Telegram -> Local File):** Lắng nghe tin nhắn trong Supergroup theo `message_thread_id` (Topic ID). Map Topic ID sang thư mục project tương ứng trong `rooms.json`, tạo file JSON vào `.agents/inbox/`.
- **Outbound (Local File -> Telegram):** Watch thư mục `.agents/outbox/` của các phòng. Khi có file `.json` mới, đọc nội dung `text` và danh sách file `images`, gọi `sendPhoto` / `sendMediaGroup` gửi thẳng vào đúng Topic ID tương ứng, sau đó chuyển file outbox sang thư mục `sent/`.

---

## 4. Các bước Claude Code cần thực hiện tiếp theo:
1. Tạo thư mục `prompts/` và viết nội dung file `prompts/MANAGER.md`.
2. Tạo thư mục `scripts/` và hoàn thiện `manager-loop.sh` cùng `agent-room.sh`.
3. Cập nhật các script thực thi hiện tại (`handoff.sh`, `watch-tasks.sh`, `CLAUDE.md`) để tích hợp đọc `room.env` và hỗ trợ nhánh `staging`.
4. Khởi tạo cấu trúc thư mục `bridge-bot/` (Node.js/TypeScript) với `rooms.json` và mã nguồn bot bridge Telegram hoàn chỉnh.
5. Viết tài liệu hướng dẫn sử dụng chi tiết vào `README.md`.
---

## 5. Implementation notes (đã triển khai — khác với spec ở trên)

- **§3.4 `manager-loop.sh`:** không gọi `claude -p` mỗi 10 giây khi `AUTO_MODE=true` (đốt quota). Daemon đọc trạng thái task đầu tiên chưa xong trên `board.md` (`pending` → `plan_ready` → `in_progress` → `done`, hoặc `BLOCKED`) và mỗi vòng chỉ gọi đúng một vai khi có việc. Cùng (task, trạng thái) không tiến triển sau 2 lần → tắt `AUTO_MODE` và báo user (`/resume` để chạy lại).
- **§3.1 / §3.5 Proxy Approval:** `claude -p` không dừng giữa chừng được nên chia hai bước: Tech Lead chỉ lên plan và đặt `[plan_ready]` (không `handoff`); Manager (MODE `APPROVE_PLAN`) duyệt guardrail rồi mới chạy `scripts/handoff.sh`.
- **§3.5 `room.env`:** chỉ `run-task.sh` đọc (qua `scripts/room-env.sh`): URL verify = `DEFAULT_VERIFY_URL` với port thay bằng `APP_PORT` (giữ nguyên path/query như `?test=1`), task branch tách từ `staging`. `handoff.sh`, `wait-task.sh`, `watch-tasks.sh` không dùng port/URL nên không đổi.
- **§2 vị trí file:** `MANAGER.md` cài vào project tại `.agents/MANAGER.md` (tránh đụng `prompts/` của project). `install.sh` ghi đường dẫn kit vào `.agents/kit-dir` để `agent-room.sh init` tìm `bridge-bot/rooms.json` (ghi đè bằng `AGENT_ROOMS_FILE`).
- **§3.7 bot:** thêm nút inline **Ship / Giữ lại**, chỉ nhận lệnh từ `ADMIN_USER_ID` trong đúng `TELEGRAM_CHAT_ID`, ảnh outbox bị giới hạn trong thư mục phòng, outbox lỗi 3 lần chuyển sang `failed/`; phản hồi lệnh bằng reaction (👀 đã ghi inbox, 👍 Manager xong, 👎 lỗi) thay vì tin `đã nhận`.
- **Bổ sung sau khi chạy thật:** `bridge-bot/bridge.sh` (start/stop/status/logs) và `agent-room.sh start` tự bật bridge; bot có discovery mode (trả `ADMIN_USER_ID`, `TELEGRAM_CHAT_ID`, Topic ID) và log tin bị bỏ qua; tmux có cửa sổ `dashboard` (board + log gộp + watcher) và `manager`; log gộp `.agents/logs/activity.log` có giờ và màu theo vai.
- **Đã chạy thật (tmux):** bridge, `/status`, `/auto` một task nhỏ end-to-end trên `tea-party-two-players`. `/ship` (merge `staging` vào `main` và push) và 2 task liên tiếp đã chạy thật. **Chưa kiểm chứng:** pm2, nút Ship bằng bấm nút, nhiều phòng song song.
- **Lỗi tìm ra khi chạy thật:** `board.md` và `room.env` bị commit vào git trong khi daemon sửa chúng liên tục, làm `handoff.sh` bị chặn (cây dơ). Nay `install.sh` và `agent-room.sh init` git-ignore hai file này và gỡ khỏi git nếu bản cũ đã commit.
- **Health:** lệnh `/health` do bridge trả lời bằng code (pid daemon/watcher, `getMe` của bot từng vai, `claude`/`opencode --version`, git, port dev server), không gọi Claude. Daemon kiểm tra watcher còn sống trước khi bắt đầu mỗi task.
- **Tối ưu quota Claude:** việc cứng của Manager chuyển sang code (`scripts/room-ops.py`: `/status`, `/stop`, `/resume`, `/ship`, `/usage`, tách `/auto` theo dòng, kiểm tra plan OK/BLOCK/REVIEW, báo cáo chốt batch). Claude Manager chỉ còn cho plan nghi ngờ (REVIEW), `AUTO_SPLIT="claude"` và `CHAT_WITH_CLAUDE="true"`. Daemon tự chờ OpenCode (đọc `.agents/status`), chỉ gọi Tech Lead khi `done`/`stuck`; fix cycle kết thúc phiên sau handoff. Model theo vai (`MODEL_MANAGER`, `MODEL_TECHLEAD`), `--max-turns`, và `usage.log` (token, chi phí từng lần gọi) + lệnh `/usage`. Verify vẫn do Claude làm.
- **Báo tiến độ (Dev + Tech Lead):** `room-ops.py progress <slug>` đọc file task, board và git rồi gửi: plan (số bước, test), từng bước xong kèm commit, kết quả test, Verify (kèm ảnh), vòng sửa, merge vào staging. Daemon gọi mỗi vòng khi OpenCode đang chạy, và chạy nền mỗi 5 giây trong lúc Tech Lead làm việc. Tech Lead không còn phải tự viết tin; trạng thái đã báo nằm ở `.agents/progress/` (git-ignore).
- **Dọn dẹp sau `/ship`:** xóa status/progress của task đã ship, chuyển ảnh verify vào `archive/` (giữ 3 lô), board giữ `KEEP_SHIPPED` task gần nhất (mặc định 5), xóa tin inbox/outbox cũ hơn 7 ngày. Context sạch có sẵn do mỗi lần gọi Tech Lead là một tiến trình `claude -p` mới.
- **Dev báo đang làm bước nào:** `run-task.sh` gửi `🔧 Đang làm bước N–M/T · [nhãn] · model` kèm nội dung từng bước trước mỗi lần chạy OpenCode, `↗ Thử lại bước N với model mạnh hơn` khi leo thang, `⛔` khi bước vẫn fail ở model mạnh nhất. Cùng đợt sửa thứ tự tin: tin duyệt plan ghi vào outbox trước khi hand-off, mọi vai dùng tên file nano giây.
- **Giọng văn và định dạng tin nhắn:** cả 3 vai nói thân thiện, chia mục, task/bước thành danh sách. Nguồn viết markdown nhẹ (`**đậm**`, `` `code` ``, `- ` gạch đầu dòng), bridge đổi sang HTML của Telegram (`bridge-bot/src/format.ts`, có test), tin dài chia theo dòng, lỗi parse thì gửi lại dạng thô. `room-ops.py` là nơi duy nhất ghi tin (`say`, `say-steps`) cho watcher và `run-task.sh`. Lệnh `/health`, `/usage`, `/status` cũng chia mục.
- **Lệnh `kit`:** gom các bước thêm/cập nhật project thành một CLI (`kit new|add|upgrade|status|remove`). `kit new` tạo thư mục, git, repo GitHub (mặc định public, có xác nhận) rồi gắn phòng; `kit add` cho project có sẵn (giữ `CLAUDE.md`, thêm mục AUTO_MODE, tuỳ chọn `--agents` soạn nháp `AGENTS.md`); `kit upgrade` bỏ qua phòng bận hoặc cây git dơ, dừng và bật lại phòng đang chạy. Có test `tools/test-kit.sh`. Cùng đợt sửa `install.sh` thoát mã lỗi khi không có file `assume-unchanged` (pipefail).
- **Tạo phòng từ Telegram (`/newroom <tên> <port> [private] [local] [agents]`):** bridge tạo Topic `project-<tên>`, chạy `kit new|add` với Topic id đó, rồi để cả 3 bot chào trong Topic mới (Topic không có danh sách thành viên: bot nào ở trong group đều đăng được, nên "thêm bot" = kiểm tra bot có trong group + mỗi bot nói một câu) và gửi báo cáo `/health`. Kiểm tra trước khi tạo Topic (cây git dơ, chưa có commit, `gh` chưa đăng nhập, phòng đã tồn tại), thẻ xác nhận có nút, chỉ admin dùng được, tên project bị giới hạn ký tự, `kit` chạy không qua shell. Test đầu cuối với Telegram giả: `npm run test:e2e` trong `bridge-bot/`.
