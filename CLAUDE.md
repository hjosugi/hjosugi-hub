# Repository instructions

This project is an Elixir static-site pipeline for GitHub Pages.

## Commands

```bash
mix format --check-formatted
mix test
mix hub.collect
mix hub.export --out public
```

Deployment is handled by `.github/workflows/pages.yml` (`Deploy Hjosugi Hub`).
GitHub Pages source should be set to GitHub Actions for `hjosugi/hjosugi-hub`.
The workflow exports `public/` and deploys it as a Pages artifact; do not commit
`public/`.

## Rules

- Do not reintroduce non-Elixir runtime code.
- Keep the deployed site static and cheap to host.
- Treat everything exported under `public/` as public.
- Convert feed content to plain text before rendering or exporting it.
- Keep `config/site.exs` and `config/feeds.exs` human-editable.
- Avoid dependencies unless OTP/Elixir standard tooling is clearly insufficient.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
