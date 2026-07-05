import { test, expect } from "@playwright/test";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";

// Capture the final design deterministically: the site only skips its
// scroll-reveal fade (which would leave off-screen sections at opacity:0 in a
// full-page screenshot) under reduced motion. Set it per page so it applies
// before the scripts run.
test.beforeEach(async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
});

// Pages of the exported static site to verify.
const PAGES = [
  { name: "about", path: "/", ready: "h1" },
  { name: "radar", path: "/radar/", ready: ".radar-card" },
  { name: "popular", path: "/popular/", ready: ".radar-card" },
  { name: "friends", path: "/friends/", ready: ".char-card" },
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

test("radar is a single view with no category tabs", async ({ page }) => {
  await page.goto("/radar/", { waitUntil: "networkidle" });
  await page.waitForSelector(".radar-card");
  await expect(page.locator(".radar-tabs")).toHaveCount(0);
  await expect(page.locator(".radar-tab")).toHaveCount(0);
  // radar shows the full set, including non-github items (e.g. lobste.rs).
  const hosts = await page.locator(".radar-card .radar-host").allTextContents();
  expect(hosts.some((h) => !/github\.com$/.test(h))).toBe(true);
});

test("popular is a separate page scoped to github.com links", async ({ page }) => {
  await page.goto("/popular/", { waitUntil: "networkidle" });
  await page.waitForSelector(".radar-card");
  await expect(page.locator("h1")).toHaveText(/Popular on GitHub/i);
  await expect(page.locator("nav a.active")).toHaveText("popular/");
  const hosts = await page
    .locator(".radar-card h2 a")
    .evaluateAll((els) => els.map((e) => new URL(e.href).hostname));
  expect(hosts.length).toBeGreaterThan(0);
  for (const host of hosts) {
    expect(host === "github.com" || host.endsWith(".github.com")).toBe(true);
  }
});

test("nav exposes radar and popular as separate pages", async ({ page }) => {
  await page.goto("/", { waitUntil: "networkidle" });
  await expect(page.locator('nav a[href="radar/"]')).toHaveCount(1);
  await expect(page.locator('nav a[href="popular/"]')).toHaveCount(1);
});

test("friends page introduces both mascots with pixel sprites and pose frames", async ({ page }) => {
  await page.goto("/friends/", { waitUntil: "networkidle" });
  await expect(page.locator(".char-card")).toHaveCount(2);
  // Each character's hero sprite and a row of pose frames render as inline SVG.
  await expect(page.locator(".char-hero-sprite svg")).toHaveCount(2);
  expect(await page.locator(".char-frames .frame").count()).toBeGreaterThanOrEqual(6);
  await expect(page.locator(".dochicken-svg").first()).toBeVisible();
  // The friends page is reachable from the primary nav.
  await page.goto("/", { waitUntil: "networkidle" });
  await expect(page.locator('nav a[href="friends/"]')).toHaveCount(1);
});

test("about page renders its project and skill sections opaquely", async ({ page }) => {
  await page.goto("/", { waitUntil: "networkidle" });
  expect(await page.locator(".project-card").count()).toBeGreaterThan(0);
  expect(await page.locator(".skill-group").count()).toBeGreaterThan(0);
  await expect(page.locator('.project-card h3 a[href="https://github.com/hjosugi/irodori-table"]')).toHaveText("Irodori Table");
  await expect(page.locator('.project-card a[href="https://hjosugi.github.io/irodori-docs/"]')).toHaveText("docs");
  await expect(page.locator('.project-card h3 a[href="https://github.com/hjosugi/sql-dialect-fmt"]')).toHaveText("sql-dialect-fmt");
  // toBeVisible() ignores opacity, so assert the reveal fade is actually
  // resolved (sections must not be left at opacity:0).
  const opacity = await page
    .locator(".section")
    .first()
    .evaluate((n) => getComputedStyle(n).opacity);
  expect(opacity).toBe("1");
});

test("filters collapse on mobile and stay open on wider screens", async ({ page }) => {
  await page.goto("/radar/", { waitUntil: "networkidle" });
  await page.waitForSelector(".radar-card");
  const open = await page.locator(".filter-disclosure").evaluate((d) => d.open);
  const wide = (page.viewportSize()?.width ?? 0) >= 821;
  expect(open).toBe(wide);
});

test("cards show the link host in their meta", async ({ page }) => {
  await page.goto("/popular/", { waitUntil: "networkidle" });
  await page.waitForSelector(".radar-card");
  const hosts = await page.locator(".radar-card .radar-host").allTextContents();
  expect(hosts.length).toBeGreaterThan(0);
  for (const host of hosts) expect(host).toMatch(/(^|\.)github\.com$/);
});

test("score renders a labelled points value with a tooltip", async ({ page }) => {
  await page.goto("/popular/", { waitUntil: "networkidle" });
  await page.waitForSelector(".radar-card");
  const score = page.locator(".radar-score").first();
  await expect(score).toHaveText(/▲\s*\d+\s*pts/);
  await expect(score).toHaveAttribute("title", /points/i);
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

for (const query of ["サーバー", "にほんご", "foobar"]) {
  test(`radar search normalizes Japanese/fullwidth query ${query}`, async ({ page }) => {
    await page.goto("/radar/", { waitUntil: "networkidle" });
    await page.waitForSelector(".radar-card");

    await page.locator("#radar-search").fill(query);
    await page.locator("#static-search-form").press("Enter");

    const card = page.locator(".radar-card", { hasText: "サーバ運用とＦＯＯＢＡＲ設計" });
    await expect(card).toBeVisible();
  });
}

test("radar results support keyboard navigation, save, and open", async ({ page }) => {
  await page.goto("/radar/", { waitUntil: "networkidle" });
  await page.waitForSelector(".radar-card");

  const input = page.locator("#radar-search");
  await page.keyboard.press("/");
  await expect(input).toBeFocused();
  await input.fill("a");
  await page.keyboard.press("Enter");

  const cards = page.locator("[data-result-card]");
  expect(await cards.count()).toBeGreaterThan(1);
  const first = cards.nth(0);
  const second = cards.nth(1);
  const firstUrl = await first.locator("h2 a").getAttribute("href");

  await page.keyboard.press("j");
  await expect(first).toBeFocused();
  await page.keyboard.press("j");
  await expect(second).toBeFocused();
  await page.keyboard.press("k");
  await expect(first).toBeFocused();

  await page.keyboard.press("s");
  await expect(first.locator(".save-btn")).toHaveText(/saved/);

  await page.evaluate(() => {
    window.__openedByKeyboard = [];
    window.open = (url) => {
      window.__openedByKeyboard.push(url);
      return null;
    };
  });
  await page.keyboard.press("o");
  await expect.poll(() => page.evaluate(() => window.__openedByKeyboard[0])).toBe(firstUrl);
});
