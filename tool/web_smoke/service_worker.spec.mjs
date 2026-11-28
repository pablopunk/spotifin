import { expect, test } from '@playwright/test';

function collectErrors(page) {
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(message.text());
  });
  return errors;
}

async function waitForServiceWorkerControl(page) {
  await page.evaluate(async () => {
    await navigator.serviceWorker.ready;
    if (navigator.serviceWorker.controller) return;
    await new Promise((resolve) =>
      navigator.serviceWorker.addEventListener('controllerchange', resolve, { once: true }));
  });
}

async function expectFlutterAppLoaded(page) {
  await expect(page.locator('flutter-view')).toBeAttached({ timeout: 30_000 });
}

test('app loads and survives a reload served by the service worker', async ({ page }) => {
  const errors = collectErrors(page);

  const first = await page.goto('/');
  expect(first?.status()).toBe(200);
  await expectFlutterAppLoaded(page);
  await waitForServiceWorkerControl(page);

  const reloaded = await page.reload();
  expect(reloaded?.ok()).toBe(true);
  await expectFlutterAppLoaded(page);
  expect(await page.evaluate(() => navigator.serviceWorker.controller !== null)).toBe(true);

  expect(errors.filter((message) => /redirect/i.test(message))).toEqual([]);
});
