// Zero-dependency static server for the exported `public/` site, used by the
// Playwright E2E suite. Before serving it seeds `public/radar-data/items.json` with
// deterministic fixtures (recent timestamps) so the radar landing view always
// renders cards to measure. Run `mix hub.export --out public` first.
import { createServer } from "node:http";
import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join, normalize } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "public");
const port = Number(process.env.E2E_PORT || 4173);

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".txt": "text/plain; charset=utf-8",
  ".xml": "application/xml; charset=utf-8",
  ".png": "image/png",
  ".ico": "image/x-icon",
};

const ext = (path) => {
  const dot = path.lastIndexOf(".");
  return dot === -1 ? "" : path.slice(dot);
};

// Seed deterministic radar data with recent dates so the default (last-30-days)
// landing view shows cards. Keeps the long-URL fixtures that triggered the
// original mobile horizontal-overflow bug.
async function seed() {
  const raw = await readFile(join(here, "fixtures", "items.json"), "utf8");
  const items = JSON.parse(raw);
  const now = Date.now();
  const seeded = items.map((item, i) => {
    const at = new Date(now - i * 86_400_000).toISOString();
    return { ...item, published_at: at, collected_at: at };
  });
  await writeFile(join(root, "radar-data", "items.json"), JSON.stringify(seeded), "utf8");
}

async function serveFile(res, urlPath) {
  let rel = decodeURIComponent(urlPath.split("?")[0]);
  if (rel.endsWith("/")) rel += "index.html";
  const full = normalize(join(root, rel));
  if (!full.startsWith(root)) {
    res.writeHead(403).end("forbidden");
    return;
  }
  try {
    const body = await readFile(full);
    res.writeHead(200, { "content-type": MIME[ext(full)] || "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404, { "content-type": "text/plain" }).end("not found");
  }
}

await seed();

createServer((req, res) => serveFile(res, req.url || "/")).listen(port, () => {
  // Playwright's webServer waits for this URL to respond.
  console.log(`e2e static server on http://127.0.0.1:${port}`);
});
