import { test, expect } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
});

const PAGES = [
  { name: "about", path: "/", ready: "h1" },
  { name: "radar", path: "/radar/", ready: ".radar-card" },
  { name: "popular", path: "/popular/", ready: ".radar-card" },
  { name: "digest", path: "/digest/", ready: "h1" },
  { name: "friends", path: "/friends/", ready: ".char-card" },
];

async function overflowingElements(page) {
  return page.evaluate(() => {
    const docWidth = document.documentElement.clientWidth;
    const offenders = [];
    for (const node of document.body.querySelectorAll("*")) {
      const rect = node.getBoundingClientRect();
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

test("theme toggle defaults dark, switches to light, and persists", async ({ page }) => {
  await page.goto("/", { waitUntil: "networkidle" });
  await page.waitForSelector("h1");

  const root = page.locator("html");
  const toggle = page.locator("#theme-toggle");
  const darkBg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);

  await expect(root).toHaveAttribute("data-theme", "dark");
  await expect(toggle).toBeVisible();
  await expect(toggle).toHaveText("theme:dark");
  await expect(toggle).toHaveAttribute("aria-pressed", "false");
  await expect(toggle).toHaveAttribute("aria-label", "Switch to light theme");

  await toggle.click();
  const lightBg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);

  await expect(root).toHaveAttribute("data-theme", "light");
  await expect(toggle).toHaveText("theme:light");
  await expect(toggle).toHaveAttribute("aria-pressed", "true");
  await expect(toggle).toHaveAttribute("aria-label", "Switch to dark theme");
  expect(lightBg).not.toBe(darkBg);
  await expect.poll(() => page.evaluate(() => localStorage.getItem("hjosugi-hub-theme"))).toBe("light");

  await page.goto("/radar/", { waitUntil: "networkidle" });
  await page.waitForSelector(".radar-card");
  await expect(root).toHaveAttribute("data-theme", "light");
  await expect(toggle).toHaveText("theme:light");

  await page.reload({ waitUntil: "networkidle" });
  await page.waitForSelector(".radar-card");
  await expect(root).toHaveAttribute("data-theme", "light");
  await expect(toggle).toHaveText("theme:light");
});

test("light theme does not introduce horizontal overflow", async ({ page }, testInfo) => {
  await page.addInitScript(() => {
    localStorage.setItem("hjosugi-hub-theme", "light");
  });

  for (const pageDef of PAGES) {
    await page.goto(pageDef.path, { waitUntil: "networkidle" });
    await page.waitForSelector(pageDef.ready, { timeout: 10_000 });

    const scrollWidth = await page.evaluate(() => document.documentElement.scrollWidth);
    const clientWidth = await page.evaluate(() => document.documentElement.clientWidth);
    const offenders = await overflowingElements(page);

    await expect(page.locator("html")).toHaveAttribute("data-theme", "light");
    expect(
      offenders,
      `${pageDef.name} overflows in light theme on ${testInfo.project.name}:\n${offenders.join("\n")}`,
    ).toEqual([]);
    expect(scrollWidth, `${pageDef.name} scrolls horizontally`).toBeLessThanOrEqual(clientWidth + 1);
  }
});
