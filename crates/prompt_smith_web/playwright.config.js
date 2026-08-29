import { defineConfig } from "@playwright/test";

const testPort = process.env.PLAYWRIGHT_PORT ?? "4181";
if (!/^\d{1,5}$/.test(testPort) || Number(testPort) === 0 || Number(testPort) > 65535) {
  throw new Error("PLAYWRIGHT_PORT must be an integer between 1 and 65535");
}

const viewports = [
  ["mobile-375", { width: 375, height: 812 }],
  ["tablet-768", { width: 768, height: 1024 }],
  ["desktop-1024", { width: 1024, height: 768 }],
  ["desktop-1440", { width: 1440, height: 900 }],
];

export default defineConfig({
  testDir: "./tests/browser",
  outputDir: "test-results",
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  reporter: "line",
  use: {
    baseURL: `http://127.0.0.1:${testPort}`,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },
  webServer: {
    command: `npx --no-install http-server smoke -a 127.0.0.1 -p ${testPort} -c-1 --silent`,
    url: `http://127.0.0.1:${testPort}`,
    reuseExistingServer: false,
  },
  projects: viewports.map(([name, viewport]) => ({ name, use: { viewport } })),
});
