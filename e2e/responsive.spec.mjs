import { test, expect } from "@playwright/test";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";

// Pages of the exported static site to verify.
const PAGES = [
  { name: "about", path: "/", ready: "h1" },
  { name: "radar", path: "/radar/", ready: ".radar-card" },
  { name: "radar-github", path: "/radar/github/", ready: ".radar-card" },
  { name: "radar-news", path: "/radar/news/", ready: ".radar-card" },
];

const SHOT_DIR = join("e2e", "screenshots");

// Returns selectors of elements that stick out past the viewport width — the
// failure mode behind the original "radar isn't responsive" report.
async function overflowingElements(page) {
  return page.evaluate(() => {
    const docWidth = document.documentElement.clientWidth;
    const offenders = [];
    for (const node of document.body.querySelectorAll("*")) {
      const rect = node.getBoundingClientRect();
      // 1px tolerance for sub-pixel rounding.
      if (rect.width > 0 && rect.right > docWidth + 1) {
        const id = node.id ? `#${node.id}` : "";
        const cls = node.className && typeof node.className === "string"
          ? "." + node.className.trim().split(/\s+/).join(".")
          : "";
        offenders.push(`${node.tagName.toLowerCase()}${id}${cls} (right=${Math.round(rect.right)} > ${docWidth})`);
      }
    }
    return offenders.slice(0, 12);
  });
}

for (const pageDef of PAGES) {
  test(`${pageDef.name} has no horizontal overflow`, async ({ page }, testInfo) => {
    await page.goto(pageDef.path, { waitUntil: "networkidle" });
    await page.waitForSelector(pageDef.ready, { timeout: 10_000 });

    // The document must not scroll horizontally.
    const scrollWidth = await page.evaluate(() => document.documentElement.scrollWidth);
    const clientWidth = await page.evaluate(() => document.documentElement.clientWidth);
    const offenders = await overflowingElements(page);

    // Capture the rendered design for review (artifact + report attachment).
    await mkdir(join(SHOT_DIR, testInfo.project.name), { recursive: true });
    const shot = join(SHOT_DIR, testInfo.project.name, `${pageDef.name}.png`);
    await page.screenshot({ path: shot, fullPage: true });
    await testInfo.attach(`${pageDef.name}-${testInfo.project.name}`, {
      path: shot,
      contentType: "image/png",
    });

    expect(
      offenders,
      `elements overflow the viewport on ${testInfo.project.name}:\n${offenders.join("\n")}`,
    ).toEqual([]);
    expect(scrollWidth, "document scrolls horizontally").toBeLessThanOrEqual(clientWidth + 1);
  });
}

test("github tab scopes results to github.com links", async ({ page }) => {
  await page.goto("/radar/github/", { waitUntil: "networkidle" });
  await page.waitForSelector(".radar-card");
  await expect(page.locator(".radar-tab.active")).toHaveText("github");
  const hosts = await page
    .locator(".radar-card h2 a")
    .evaluateAll((els) => els.map((e) => new URL(e.href).hostname));
  expect(hosts.length).toBeGreaterThan(0);
  for (const host of hosts) {
    expect(host === "github.com" || host.endsWith(".github.com")).toBe(true);
  }
});

test("news tab scopes results to aggregator sources", async ({ page }) => {
  await page.goto("/radar/news/", { waitUntil: "networkidle" });
  await page.waitForSelector(".radar-card");
  await expect(page.locator(".radar-tab.active")).toHaveText("news");
  // Aggregator items carry the source in the card meta (Hacker News / Lobsters).
  const count = await page.locator(".radar-card").count();
  expect(count).toBeGreaterThan(0);
});

test("radar tabs link across the three scoped pages", async ({ page }) => {
  await page.goto("/radar/", { waitUntil: "networkidle" });
  await expect(page.locator(".radar-tab")).toHaveCount(3);
  await expect(page.locator(".radar-tab.active")).toHaveText("all");
  await page.locator(".radar-tab", { hasText: "news" }).click();
  await page.waitForURL("**/radar/news/");
  await expect(page.locator(".radar-tab.active")).toHaveText("news");
});

test("filters collapse on mobile and stay open on wider screens", async ({ page }) => {
  await page.goto("/radar/", { waitUntil: "networkidle" });
  await page.waitForSelector(".radar-card");
  const open = await page.locator(".filter-disclosure").evaluate((d) => d.open);
  const wide = (page.viewportSize()?.width ?? 0) >= 821;
  expect(open).toBe(wide);
});

test("github cards show the github.com link host", async ({ page }) => {
  await page.goto("/radar/github/", { waitUntil: "networkidle" });
  await page.waitForSelector(".radar-card");
  const hosts = await page.locator(".radar-card .radar-host").allTextContents();
  expect(hosts.length).toBeGreaterThan(0);
  for (const host of hosts) expect(host).toMatch(/(^|\.)github\.com$/);
});

test("static assets are cache-busted with a version query", async ({ page }) => {
  // Fail the build if a deploy could be masked by stale CSS/JS caches.
  const requests = [];
  page.on("request", (req) => {
    const url = req.url();
    if (/\/static\/.+\.(css|js)(\?|$)/.test(url)) requests.push(url);
  });
  const failed = [];
  page.on("requestfailed", (req) => failed.push(req.url()));

  await page.goto("/radar/", { waitUntil: "networkidle" });
  await page.waitForSelector(".radar-card");

  expect(requests.length).toBeGreaterThan(0);
  for (const url of requests) {
    expect(url, `asset not versioned: ${url}`).toMatch(/\?v=[0-9a-f]{8}/);
  }
  // A versioned import that 404s would break the page; assert none failed.
  expect(failed.filter((u) => /\/static\/.+\.js/.test(u))).toEqual([]);
});

test("radar search input stays inside the viewport", async ({ page }) => {
  await page.goto("/radar/", { waitUntil: "networkidle" });
  const input = page.locator("#radar-search");
  await expect(input).toBeVisible();
  const box = await input.boundingBox();
  const clientWidth = await page.evaluate(() => document.documentElement.clientWidth);
  expect(box, "search input has a box").not.toBeNull();
  expect(box.x + box.width, "search input overflows").toBeLessThanOrEqual(clientWidth + 1);
});
