import { expect, test } from "@playwright/test";

const runtimeFailures = new WeakMap();

test.beforeEach(async ({ page, baseURL }) => {
  const failures = [];
  const expectedOrigin = new URL(baseURL).origin;
  let applicationReady = false;
  runtimeFailures.set(page, failures);
  page.on("console", (message) => {
    if (["error", "warning"].includes(message.type())) {
      failures.push(`${message.type()}: ${message.text()}`);
    }
  });
  page.on("pageerror", (error) => failures.push(`pageerror: ${error.message}`));
  page.on("request", (request) => {
    if (new URL(request.url()).origin !== expectedOrigin) {
      failures.push(`external request: ${request.url()}`);
    } else if (applicationReady) {
      failures.push(`runtime request: ${request.method()} ${request.url()}`);
    }
  });

  await page.goto("/");
  await expect(page.getByRole("status", { name: "Application status" })).toHaveText("Ready");
  applicationReady = true;
});

test.afterEach(async ({ page }) => {
  expect(runtimeFailures.get(page)).toEqual([]);
});

test("renders a complete simple-template example through WASM", async ({ page }) => {
  await page.getByRole("button", { name: "Use example" }).click();

  await expect(page.getByLabel("Value for role")).toHaveValue("release engineer");
  await expect(page.getByLabel("Rendered prompt")).toHaveValue(/release engineer/);
  await expect(page.getByRole("status", { name: "Preflight result" })).toContainText(
    "Ready to use",
  );
});

test("fails strictly for missing values and renders after input", async ({ page }) => {
  await page.getByRole("textbox", { name: "Prompt template" }).fill("Hello {{name}}.");

  await expect(page.getByText("MISSING_VARIABLE_VALUE", { exact: true })).toBeVisible();
  await expect(page.getByLabel("Rendered prompt")).toHaveValue("");

  await page.getByLabel("Value for name").fill("Ada");
  await expect(page.getByLabel("Rendered prompt")).toHaveValue("Hello Ada.");
  await expect(page.getByText("MISSING_VARIABLE_VALUE", { exact: true })).toHaveCount(0);
});

test("treats an explicitly cleared field as an empty supplied value", async ({ page }) => {
  await page.getByRole("textbox", { name: "Prompt template" }).fill("Before{{value}}after");
  const value = page.getByLabel("Value for value");
  await value.fill("temporary");
  await value.fill("");

  await expect(page.getByLabel("Rendered prompt")).toHaveValue("Beforeafter");
  await expect(page.getByText("MISSING_VARIABLE_VALUE", { exact: true })).toHaveCount(0);
});

test("preserves values through invalid edits and lets users remove unused values", async ({ page }) => {
  const template = page.getByRole("textbox", { name: "Prompt template" });
  await template.fill("Hello {{name}}.");
  await page.getByLabel("Value for name").fill("private-value");
  await template.fill("Hello {{name");
  await expect(page.locator('textarea[data-variable="name"]')).toHaveValue("private-value");

  await template.fill("Hello {{name}}.");
  await expect(page.getByLabel("Rendered prompt")).toHaveValue("Hello private-value.");
  await template.fill("No variables here.");
  await expect(page.getByText("UNUSED_VARIABLE_VALUE", { exact: true })).toBeVisible();
  await expect(page.locator('textarea[data-variable="name"]')).toHaveValue("private-value");

  await page.getByRole("button", { name: "Remove value for name" }).click();
  await expect(page.getByText("UNUSED_VARIABLE_VALUE", { exact: true })).toHaveCount(0);
  await expect(page.getByLabel("Value for name")).toHaveCount(0);
});

test("invalidates stale output when the WASM values boundary rejects input", async ({ page }) => {
  const names = ["a", "b", "c", "d", "e"];
  await page
    .getByRole("textbox", { name: "Prompt template" })
    .fill(names.map((name) => `{{${name}}}`).join(""));
  await page.getByLabel("Value for e").fill("x");

  for (const name of names.slice(0, 4)) {
    await page.getByLabel(`Value for ${name}`).fill("x".repeat(220_000));
  }
  await expect(page.getByLabel("Rendered prompt")).not.toHaveValue("");

  await page.getByLabel("Value for e").fill("x".repeat(220_000));
  await expect(page.getByText("INPUT_LIMIT", { exact: true })).toBeVisible();
  await expect(page.getByLabel("Rendered prompt")).toHaveValue("");
  await expect(page.getByRole("button", { name: "Copy output" })).toBeDisabled();
  await expect(page.getByRole("button", { name: "Download .txt" })).toBeDisabled();

  await page.getByLabel("Value for e").fill("x");
  await expect(page.getByText("INPUT_LIMIT", { exact: true })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Copy output" })).toBeEnabled();
});

test("checks LangChain literal braces and keeps rendering non-recursive", async ({ page }) => {
  await page.getByLabel("LangChain f-string subset").check();
  await page
    .getByRole("textbox", { name: "Prompt template" })
    .fill('Return {"status":"ok"} for {name}.');
  await expect(page.getByText("LIKELY_LITERAL_BRACES", { exact: true })).toBeVisible();

  await page
    .getByRole("textbox", { name: "Prompt template" })
    .fill('Return {{"status":"ok"}} for {name}.');
  await page.getByLabel("Value for name").fill("{{next_step}}");
  await expect(page.getByLabel("Rendered prompt")).toHaveValue(
    'Return {"status":"ok"} for {{next_step}}.',
  );
  await expect(page.getByLabel("Value for next_step")).toHaveCount(0);
});

test("keeps work when switching to Chinese", async ({ page }) => {
  await page.getByRole("button", { name: "Use example" }).click();
  await page.getByRole("button", { name: "切换到中文" }).click();

  await expect(page.getByRole("textbox", { name: "提示词模板" })).toHaveValue(
    /release checklist/,
  );
  await expect(page.getByLabel("渲染结果")).toHaveValue(/release engineer/);
  await expect(page.getByRole("button", { name: "Switch to English" })).toBeVisible();
});

test("copies and downloads the rendered prompt", async ({ page, context, baseURL }) => {
  await context.grantPermissions(["clipboard-read", "clipboard-write"], {
    origin: new URL(baseURL).origin,
  });
  await page.getByRole("button", { name: "Use example" }).click();
  const expected = await page.getByLabel("Rendered prompt").inputValue();

  await page.getByRole("button", { name: "Copy output" }).click();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(expected);

  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "Download .txt" }).click();
  const download = await downloadPromise;
  expect(download.suggestedFilename()).toBe("prompt.txt");
  const stream = await download.createReadStream();
  const chunks = [];
  for await (const chunk of stream) {
    chunks.push(chunk);
  }
  expect(Buffer.concat(chunks).toString("utf8")).toBe(expected);
});

test("has visible focus, reduced motion, and no page-level overflow", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });

  await page.keyboard.press("Tab");
  const focus = await page.evaluate(() => {
    const style = getComputedStyle(document.activeElement);
    return { outlineStyle: style.outlineStyle, outlineWidth: style.outlineWidth };
  });
  expect(focus.outlineStyle).not.toBe("none");
  expect(Number.parseFloat(focus.outlineWidth)).toBeGreaterThanOrEqual(2);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= document.documentElement.clientWidth,
    ),
  ).toBe(true);

  const transitionSeconds = await page.getByRole("button", { name: "Use example" }).evaluate(
    (button) => Number.parseFloat(getComputedStyle(button).transitionDuration),
  );
  expect(transitionSeconds).toBeLessThan(0.001);

  const longName = `v${"a".repeat(4095)}`;
  await page.getByRole("textbox", { name: "Prompt template" }).fill(`{{${longName}}}`);
  await expect(page.locator(".variable-field textarea")).toHaveCount(1);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= document.documentElement.clientWidth,
    ),
  ).toBe(true);
});

test("completes the main workflow with the keyboard", async ({ page, context, baseURL }) => {
  await context.grantPermissions(["clipboard-read", "clipboard-write"], {
    origin: new URL(baseURL).origin,
  });
  for (let index = 0; index < 8; index += 1) {
    await page.keyboard.press("Tab");
  }
  await expect(page.getByRole("textbox", { name: "Prompt template" })).toBeFocused();
  await page.keyboard.type("Hello {{name}}.");
  await page.keyboard.press("Tab");
  await expect(page.getByLabel("Value for name")).toBeFocused();
  await page.keyboard.type("Ada");
  await expect(page.getByLabel("Rendered prompt")).toHaveValue("Hello Ada.");

  await page.keyboard.press("Tab");
  await expect(page.getByLabel("Rendered prompt")).toBeFocused();
  await page.keyboard.press("Tab");
  await expect(page.getByRole("button", { name: "Copy output" })).toBeFocused();
  await page.keyboard.press("Enter");
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe("Hello Ada.");
});
