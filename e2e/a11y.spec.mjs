import { test, expect } from "@playwright/test";
import { AxeBuilder } from "@axe-core/playwright";

const A11Y_PROJECT = "desktop-1280";

const STATIC_PAGES = [
  { name: "about", path: "/", ready: "h1" },
  { name: "radar", path: "/radar/", ready: "[data-result-summary]", dynamicResults: true },
  { name: "popular", path: "/popular/", ready: "[data-result-summary]", dynamicResults: true },
  { name: "friends", path: "/friends/", ready: ".char-card" },
];

async function waitForPageReady(page, pageDef) {
  await page.waitForSelector(pageDef.ready, { timeout: 10_000 });

  if (pageDef.dynamicResults) {
    await expect(page.locator("[data-result-summary]")).not.toHaveText("Loading items...", {
      timeout: 10_000,
    });
  }
}

function summarizeViolations(violations) {
  return violations.map(({ id, impact, help, helpUrl, nodes }) => ({
    id,
    impact,
    help,
    helpUrl,
    nodes: nodes.slice(0, 5).map(({ target, failureSummary }) => ({
      target: target.join(", "),
      failureSummary,
    })),
  }));
}

test.describe("accessibility", () => {
  test.beforeEach(async ({ page }, testInfo) => {
    test.skip(
      testInfo.project.name !== A11Y_PROJECT,
      `axe runs once in the ${A11Y_PROJECT} project`,
    );
    await page.emulateMedia({ reducedMotion: "reduce" });
  });

  for (const pageDef of STATIC_PAGES) {
    test(`${pageDef.name} has no axe violations`, async ({ page }) => {
      await page.goto(pageDef.path, { waitUntil: "networkidle" });
      await waitForPageReady(page, pageDef);

      const results = await new AxeBuilder({ page }).analyze();
      expect(summarizeViolations(results.violations)).toEqual([]);
    });
  }
});
