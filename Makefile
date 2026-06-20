SHELL := /bin/sh

.PHONY: test fmt-check check collect export-static clean

test:
	mix test

fmt-check:
	mix format --check-formatted

check: test export-static

collect:
	mix sg.collect

export-static:
	mix sg.export --out public

clean:
	rm -rf _build public data/items.term data/collection-report.json
