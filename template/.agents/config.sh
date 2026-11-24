# Cấu hình cho scripts/run-task.sh — file này được `source` bởi bash.
# Mọi giá trị đều có thể ghi đè tạm thời bằng biến môi trường khi chạy.

# Model cho từng nhãn độ khó. Xem ID chính xác: opencode models
MODELS=(
  "opencode-go/deepseek-v4.1-flash"   # [dễ]
  "opencode-go/glm-5.3"               # [vừa]
  "opencode-go/kimi-k3.1-pro"         # [khó]
)

# (Tùy chọn) Mức [vừa] chọn model theo thư mục của file đầu tiên trong bước: "tiền tố=model".
# Bước không khớp quy tắc nào dùng MODELS[1]. Ví dụ:
# MEDIUM_RULES=(
#   "client/=opencode-go/glm-5.3"
#   "server/=opencode-go/deepseek-v4.1-flash"
#   "tests/=opencode-go/deepseek-v4.1-flash"   # test-writing steps: try the cheap model, escalates on failure
# )
MEDIUM_RULES=()

# (Tùy chọn) Bước có file đầu tiên khớp tiền tố chạy trong phiên OpenCode MỚI (không --continue), để context không dài ra
# theo các bước trước. Hợp với bước viết test: plan đã mô tả test từng bước + ngữ cảnh nên không cần lịch sử phiên.
# FRESH_RULES=("tests/")
FRESH_RULES=()

# Model cho bước Verify trên trình duyệt (cần đọc được ảnh)
DEFAULT_VERIFY_MODEL="opencode-go/gemini-4-argon"

# URL app khi chạy dev (Verify mở URL này). Thêm query bật test hook nếu có, ví dụ ?test=1
DEFAULT_VERIFY_URL="http://localhost:5173"

# Agent chạy gì sau mỗi bước (viết như câu lệnh cho agent đọc)
DEFAULT_CHECK_HINT="npm run typecheck và các Playwright spec liên quan (nếu có)"

# Gợi ý thêm cho Verify, ví dụ: "Game 2 người chơi: luôn mở 2 session và cho cả 2 vào cùng phòng."
DEFAULT_VERIFY_HINT=""

# Ai làm bước Verify trên trình duyệt:
#   claude   = (mặc định) script dừng sau khi code xong; Claude verify + review trong Autopilot (tốn quota Claude)
#   opencode = OpenCode tự verify ngay sau khi code xong (tốn quota OpenCode, cần model đọc được ảnh)
DEFAULT_VERIFY_AGENT="claude"

# Gom tối đa bao nhiêu bước cùng nhãn vào một lần chạy OpenCode
BATCH_MAX="${BATCH_MAX:-4}"

# Giới hạn tổng số lần gọi OpenCode cho một task (bảo vệ quota)
MAX_RUNS="${MAX_RUNS:-20}"
