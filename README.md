# Hjosugi Hub

An Elixir-powered static portfolio and public technical radar.

The deployed site is plain static HTML/CSS/JS for GitHub Pages. Elixir Mix tasks
collect RSS/Atom feeds, normalize and tag items, then export the portfolio and
searchable radar page to `public/`.

## Quick Start

Requires Elixir 1.16 or newer.

```bash
mix test
mix hub.collect
mix hub.export --out public
```

Open `public/index.html` for the portfolio and `public/radar/index.html` for
the searchable radar index. For the radar page, serve `public/` over HTTP so
browser `fetch()` can load `data/items.json`.

## Configuration

- `config/site.exs`: profile, links, skills, and selected projects
- `config/feeds.exs`: RSS/Atom/YouTube feed sources
- `priv/static_site/templates/`: static HTML templates
- `priv/static_site/assets/`: CSS and browser-side search JavaScript

## Deployment

GitHub Pages is the cheapest path here: no always-on server, no database, and no
paid worker. The included Pages workflow runs every six hours:

1. `mix hub.collect --timeout 20000 --workers 6 --max-items 1000`
2. `mix hub.export --out public`
3. Deploys `public/` with `actions/deploy-pages`

Enable GitHub Pages with "GitHub Actions" as the source and push `main`.

Important: GitHub Pages cannot hide collected data. Anything in
`public/data/items.json` is public.

## License

MIT
