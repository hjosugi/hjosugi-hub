SHELL := /bin/sh

.PHONY: test fmt-check check collect export-static clean

test:
	mix test

fmt-check:
	mix format --check-formatted

check: fmt-check test export-static

collect:
	mix hub.collect

export-static:
	mix hub.export --out public

clean:
	rm -rf _build public data/items.term data/collection-report.json
