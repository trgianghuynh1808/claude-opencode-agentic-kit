import { defineConfig, devices } from '@playwright/test';

/**
 * Ví dụ Playwright config cho claude-opencode-kit.
 * Những phần kit cần:
 *  - reporter 'json' ghi ra test-results/results.json (agent đọc khi test fail)
 *  - trace/screenshot khi fail
 *  - webServer tự bật dev server, dùng lại nếu đã chạy sẵn
 * Sửa port, lệnh dev và health URL cho đúng project.
 */
export default defineConfig({
  testDir: './tests',

  /* App giữ state chung trên server (phòng, phiên...)? Chạy tuần tự cho ổn định.
     App stateless thì có thể bật fullyParallel: true và bỏ workers. */
  fullyParallel: false,
  workers: 1,

  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  timeout: 60_000,
  expect: { timeout: 10_000 },

  reporter: [
    ['list'],
    ['json', { outputFile: 'test-results/results.json' }],
  ],

  use: {
    baseURL: 'http://localhost:5173',
    headless: !process.env.HEADED,           // HEADED=1 để xem trình duyệt
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },

  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],

  /* Một dev server: dùng 1 mục. Server + client riêng: dùng mảng 2 mục như dưới. */
  webServer: [
    {
      command: 'npm run dev:server',
      url: 'http://localhost:3000/health',   // route trả 200 khi server sẵn sàng
      reuseExistingServer: true,
      timeout: 120_000,
    },
    {
      command: 'npm run dev:client',
      url: 'http://localhost:5173',
      reuseExistingServer: true,
      timeout: 120_000,
    },
  ],
});
