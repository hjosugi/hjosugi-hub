# Repository instructions

This project is an Elixir static-site pipeline for GitHub Pages.

## Commands

```bash
mix format --check-formatted
mix test
mix site.collect
mix site.export --out public
```

## Rules

- Do not reintroduce non-Elixir runtime code.
- Keep the deployed site static and cheap to host.
- Treat everything exported under `public/` as public.
- Convert feed content to plain text before rendering or exporting it.
- Keep `config/site.exs` and `config/feeds.exs` human-editable.
- Avoid dependencies unless OTP/Elixir standard tooling is clearly insufficient.
