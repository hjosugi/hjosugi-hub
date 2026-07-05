# Hjosugi Hub Architecture

Hjosugi Hub is a static-site pipeline. Elixir runs during local development and
GitHub Actions builds; the deployed site is plain files under `public/`.

## Data Flow

```text
config/feeds.exs
  -> HjosugiHub.Fetcher
  -> HjosugiHub.FeedParser
  -> HjosugiHub.Collector
  -> HjosugiHub.Store.merge_items
  -> radar-cache/items.term
  -> HjosugiHub.Renderer
  -> public/
```

`mix hub.collect` owns the network collection phase. It reads feed definitions,
fetches enabled sources concurrently, parses RSS/Atom/YouTube RSS into
`HjosugiHub.Item` structs, merges fresh items with the previous cache, and writes
`radar-cache/items.term`.

`mix hub.export` owns the static export phase. It reads `config/site.exs`,
`config/feeds.exs`, and the local cache, then renders the portfolio, radar pages,
JSON payloads, `health.json`, `robots.txt`, and static assets into `public/`.

## Module Responsibilities

`HjosugiHub.Config` loads and validates the human-editable site and feed config.

`HjosugiHub.Fetcher` performs HTTP requests with conditional feed metadata.
`HjosugiHub.Fetcher.Behaviour` keeps tests and alternate fetchers explicit.

`HjosugiHub.FeedParser` normalizes feed XML into item structs and extracts
source metadata such as authors, categories, links, scores, and publication
times.

`HjosugiHub.Collector` coordinates fetch concurrency, converts per-feed results
into a report, and preserves feed state for conditional requests.

`HjosugiHub.Store` is the cache and JSON boundary. It reads legacy cache entries
safely, merges items by stable id, sorts them, and writes public JSON.

`HjosugiHub.Renderer` turns site config and public items into HTML, JSON, CSP,
asset versions, `health.json`, `robots.txt`, and `sitemap.xml`.

`HjosugiHub.HTML`, `HjosugiHub.JSON`, `HjosugiHub.Util`, and
`HjosugiHub.Tagger` are pure helpers for escaping, encoding, text cleanup, stable
ids, dates, summaries, and tags.

`HjosugiHub.Kofun` and `HjosugiHub.Dochicken` generate inline pixel-art SVG used
by the static pages.

`Mix.Tasks.Hub.Collect` and `Mix.Tasks.Hub.Export` are the CLI shell around the
collector and renderer. `HjosugiHub.CLI` centralizes shared option parsing.

## Public Boundary

Everything written under `public/` is public and deployable to GitHub Pages.
That includes `radar-data/items.json`, `radar-data/site.json`,
`radar-data/feeds.json`, `health.json`, screenshots linked from HTML, and static
assets. Do not place secrets, private notes, or token-protected URLs in
`config/site.exs`, `config/feeds.exs`, or generated cache entries.

Generated local state stays out of git:

- `radar-cache/items.term`: rolling item cache restored by GitHub Actions cache.
- `radar-cache/feed-state.term`: per-feed conditional request metadata.
- `radar-cache/collection-report.json`: latest collection report.
- `public/`: final static export passed to GitHub Pages as an artifact.

## Cache Lifecycle

In the deploy workflow, `actions/cache` restores `radar-cache/items.term` using a
rolling `hjosugi-hub-items-` restore key. `mix hub.collect` merges new feed items
with that restored cache, then writes the updated cache and public JSON. A cache
miss is valid: export still succeeds with whatever the current collection run
can fetch.

The static export never reads from GitHub Pages. It is deterministic from the
checked-out config, restored cache, current collection result, templates, and
assets in the repository.
