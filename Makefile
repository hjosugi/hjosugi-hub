SHELL := /bin/sh

.PHONY: test fmt-check check collect export-static e2e clean

test:
	mix test

fmt-check:
	mix format --check-formatted

check: fmt-check test export-static

# Browser E2E + responsive/design verification. Exports the site first so the
# Playwright server has something to serve. Requires `npm ci` once.
e2e: export-static
	npx playwright test

collect:
	mix hub.collect

export-static:
	mix hub.export --out public

clean:
	rm -rf _build public radar-cache

.PHONY: graphify-setup graphify-update

## Install graphify and register its skill with Claude, Copilot and Codex.
graphify-setup:
	@sh scripts/graphify.sh setup

## Upgrade graphify, refresh the skill, and update the knowledge graph.
graphify-update:
	@sh scripts/graphify.sh update
