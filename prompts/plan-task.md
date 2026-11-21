# Prompt: Claude lên plan cho một task

Dùng trong Claude Code, bật **plan mode** (Shift+Tab) trước khi gửi.
CLAUDE.md đã mô tả định dạng plan và cách giao việc, nên prompt chỉ cần nêu mục tiêu.

```
Task: <mô tả tính năng / bug>

Mục tiêu:
1. <kết quả mong muốn 1>
2. <kết quả mong muốn 2>

Ràng buộc (nếu có):
- <ví dụ: không đổi logic server, chỉ sửa UI>

Đọc các file liên quan để hiểu luồng hiện tại, rồi đề xuất plan theo CLAUDE.md.
```

Sau khi bạn duyệt plan, Claude sẽ tự: tạo nhánh `task/<slug>` → ghi file task → commit → giao cho OpenCode.

## Bổ sung test cho task đã làm mà thiếu test

```
File .agents/tasks/<file>.md đã xong các bước code nhưng thiếu Test cases.
Cập nhật file task theo _TEMPLATE.md, KHÔNG sửa code:
1. Thêm mục "## Test cases" cho các kết quả trong "Mục tiêu".
2. Thêm các bước mới (chưa tick) để viết spec cho các test đó.
3. Nếu cần state khó đạt qua UI, thêm bước mở rộng test hook (xem AGENTS.md).
Sau khi tôi duyệt: commit và giao việc theo CLAUDE.md.
```
