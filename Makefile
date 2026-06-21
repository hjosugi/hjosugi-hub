SHELL := /bin/sh

.PHONY: test fmt-check check collect export-static clean

test:
	mix test

fmt-check:
	mix format --check-formatted

check: test export-static

collect:
	mix site.collect

export-static:
	mix site.export --out public

clean:
	rm -rf _build public data/items.term data/collection-report.json
