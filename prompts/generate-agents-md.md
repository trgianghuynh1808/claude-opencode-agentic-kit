# Prompt: tạo AGENTS.md cho project

Dùng với OpenCode (model tầm trung, ví dụ GLM-5.3) hoặc Claude, chạy ở thư mục gốc project.
Sửa phần "Bối cảnh đã biết" cho đúng project của bạn trước khi gửi.

```
Đọc AGENTS.md hiện có (đang là khung có TODO) rồi quét repo này để điền các mục còn TODO.
Viết tiếng Anh, toàn file tối đa ~120 dòng.

Bối cảnh đã biết:
- <stack, ví dụ: monorepo npm workspaces client/ (Vite) + server/ (Express)>
- <port dev server, lệnh dev>
- <app làm gì, có nhiều người dùng cùng lúc không>

Điền các mục:
1. Project Overview: app làm gì, stack của từng phần
2. Architecture: các phần giao tiếp bằng gì, port, state nằm ở đâu
3. Codebase Map: thư mục/file chính, mỗi cái 1 dòng, và luồng chạy chính
4. Commands: install, dev, build, typecheck/lint, e2e test
5. Code Conventions: rút ra từ code hiện có
6. Trong Testing Rules: điền dòng "Test hook" (có hay chưa, nếu có thì dùng thế nào)

GIỮ NGUYÊN các mục Testing Rules (trừ dòng Test hook), Verify Phase và Workflow Rules.
Chỉ ghi những gì thật sự có trong repo, chỗ nào không chắc thì ghi TODO.
Chỉ sửa AGENTS.md, không sửa file nào khác.
```

Sau đó tự đọc lại, sửa chỗ sai/TODO, rồi commit.
