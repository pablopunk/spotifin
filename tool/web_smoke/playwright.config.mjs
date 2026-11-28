import { defineConfig, devices } from '@playwright/test';

const buildDirectory = process.env.WEB_BUILD_DIR ?? '../../build/web';

export default defineConfig({
  testDir: '.',
  timeout: 60_000,
  retries: 0,
  reporter: 'list',
  use: { baseURL: 'http://127.0.0.1:4173' },
  projects: [{ name: 'webkit', use: { ...devices['Desktop Safari'] } }],
  webServer: {
    command: `node serve.mjs "${buildDirectory}" 4173`,
    url: 'http://127.0.0.1:4173/',
    reuseExistingServer: false,
  },
});
