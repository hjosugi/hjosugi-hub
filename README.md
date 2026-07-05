# Hjosugi Hub

An Elixir-powered static portfolio and public technical radar.

The deployed site is plain static HTML/CSS/JS for GitHub Pages. Elixir Mix tasks
collect RSS/Atom feeds, normalize and tag items, then export the portfolio and
searchable radar page to `public/`.

## Quick Start

Requires Elixir 1.18 or newer.

```bash
mix test
mix hub.collect
mix hub.export --out public
```

Open `public/index.html` for the portfolio and `public/radar/index.html` for
the searchable radar index. For the radar page, serve `public/` over HTTP so
browser `fetch()` can load `radar-data/items.json`.

## E2E / responsive design checks

Browser-based end-to-end tests (Playwright) verify the exported site stays
responsive — no horizontal overflow on phone, tablet, and desktop viewports —
and capture full-page screenshots of every page for design review. This is
dev-only tooling and is never deployed to `public/`.

```bash
npm ci
npx playwright install --with-deps chromium
make e2e   # exports the site, then runs the responsive suite
```

Screenshots land in `e2e/screenshots/<viewport>/` (gitignored) and are uploaded
as CI artifacts by the `e2e` job in [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## Configuration

- `config/site.exs`: profile, links, skills, and selected projects
- `config/feeds.exs`: RSS/Atom/YouTube feed sources
- `radar-cache/`: generated local collection cache, ignored by Git
- `radar-data/items.sample.json`: sample public radar JSON payload
- `priv/static_site/templates/`: static HTML templates
- `priv/static_site/assets/`: CSS and browser-side search JavaScript

## Deployment

GitHub Pages is the intended production target for Hjosugi Hub: no always-on
server, no database, and no paid worker. The repository should be named
`hjosugi-hub`; with the default GitHub Pages domain the site will be published at
`https://hjosugi.github.io/hjosugi-hub/`.

Deployment is handled by [`.github/workflows/pages.yml`](.github/workflows/pages.yml):

1. `mix test`
2. `mix hub.collect --timeout 20000 --workers 6 --max-items 1000`
3. `mix hub.export --out public --base-url <GitHub Pages URL>`
4. Deploys `public/` with `actions/deploy-pages`

Set it up once in GitHub:

1. Open the repository settings for `hjosugi/hjosugi-hub`.
2. Go to **Pages**.
3. Set **Build and deployment** -> **Source** to **GitHub Actions**.
4. Push to `main`, or run **Deploy Hjosugi Hub** from the Actions tab.

The deploy workflow also runs daily at 06:00 JST to refresh the public radar
data. GitHub Actions schedules are UTC, so the workflow uses `0 21 * * *`.
It passes GitHub Pages' resolved URL to `mix hub.export --base-url`, so
`robots.txt` and `sitemap.xml` match the actual Pages URL. No secrets are
required.

`public/` is generated output and is intentionally ignored by Git. Do not commit
it; GitHub Pages receives it from the workflow artifact.

Important: GitHub Pages cannot hide collected data. Anything in
`public/radar-data/items.json` is public.

## License

MIT
