# Prompt: review và ship

Khi `watch-tasks.sh` báo xong (thông báo macOS "OpenCode đã xong ✅" hoặc "cần trợ giúp ⛔"):

## Review

Trong Claude Code, gõ `/clear` rồi:

```
review
```

CLAUDE.md đã hướng dẫn Claude đọc file task (gồm Test status và Verify) và `git diff main...HEAD`,
báo lỗi / chỗ lệch plan / test thiếu, và kết luận có sẵn sàng ship không.

## Ship

```
ship
```

Claude sẽ: kiểm tra → `git merge --squash` nhánh task vào main → 1 commit Conventional Commit → push → xóa nhánh task.
Push bị từ chối thì Claude dừng và báo, không force push.

## Khi OpenCode bị kẹt

Script in sẵn câu cần dán, dạng:

```
Đọc .agents/tasks/<file>.md và test-results/results.json. Tìm nguyên nhân bước <N> và sửa.
```

Sau khi Claude sửa và commit, giao lại phần còn lại cho OpenCode:

```bash
echo .agents/tasks/<file>.md > .agents/queue/$(date +%s).job
```
