# Task: <tên>

Verify mode: light
<!-- none: refactor/đổi chữ/không ảnh hưởng UI · light: mặc định · full: luồng người dùng mới, nhiều người dùng, logic đồng bộ -->

## Mục tiêu

## Ý tưởng
<!-- 2-4 dòng mô tả sơ bộ cách làm (hướng tiếp cận, không phải danh sách bước); hiện trong thẻ plan gửi người dùng -->

## Quyết định đã chốt
-

## Ngữ cảnh
<!-- Claude ghi sẵn: file, hàm, type, hằng số các bước cần (snippet ngắn) để OpenCode khỏi phải tự tìm lại. Gồm cả "sự thật để test": tên field/method đúng của test hook, cách cấp dữ liệu/tiền, cách phiên thứ 2 vào, thứ test runner không import được, chỗ dễ đoán nhầm. -->
-

## Plan
<!-- Mỗi bước: - [ ] N. [dễ|vừa|khó] <file> → <hàm>: <làm gì>. Phải có bước viết spec cho các Test cases. -->
- [ ] 1. [dễ|vừa|khó] ...

## Test cases
<!-- Claude viết khi lên plan. Tối đa 3 test, mỗi test gắn với một ý trong Mục tiêu. Mỗi test: một dòng tên — kiểm tra điều gì — file spec, rồi mô tả từng bước để OpenCode không phải tự thiết kế test. -->
- [ ] T1. <tên> — <kiểm tra gì> — tests/<file>.spec.ts
  - Setup: <dữ liệu ban đầu: user duy nhất, cách tạo state, 1 hay 2 phiên>
  - Steps: <1. thao tác (hook/message/click) · 2. ... theo thứ tự>
  - Assert: <giá trị cụ thể mong đợi sau từng thao tác>

## Trạng thái hiện tại
<!-- Tiến độ từng bước. Bước tạo/đổi giao diện ghi thêm MỘT dòng: Selectors: #id, .class, [data-x] (file chứa chúng). Bước test đọc dòng này trước khi grep code. -->

## Test status
- Lần chạy cuối:
- Kết quả từng test:
  - T1: PASS | FAIL | chưa viết
- Fail chi tiết:

## Verify
<!-- Bước Verify tự điền: từng kịch bản đã kiểm tra trên trình duyệt, PASS/FAIL, screenshot, lỗi phát hiện, dòng kết luận cuối cùng. -->

## Lưu ý
<!-- Điều người duyệt cần biết: lệch plan, phần chưa kiểm tra, bug đã biết, việc nên làm tiếp. Mỗi dòng một ý; hệ thống chuyển lên Telegram. CHỈ cho người duyệt: không ghi nhắc việc cho agent/maintainer (vd "nên áp dụng vào kit", "chạy lại X sau"), những ý đó để trong Ngữ cảnh hoặc Trạng thái hiện tại, không dùng "Lưu ý:". -->

## Đã thử mà không được
-

## Số liệu
- Quota Claude:
- Quota Go:
- Số lần tự sửa:
- Model dùng:
