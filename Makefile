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
