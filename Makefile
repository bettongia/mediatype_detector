.DEFAULT_GOAL := default

# BEGIN: Primary tasks

default: format analyze checks site
.PHONY: default

pre_commit: format_check analyze license_check
.PHONY: pre_commit

cicd: default
.PHONY: cicd

# END: Primary tasks

format:
	dart format lib/ test/ example/
.PHONY: format

## Check formatting without modifying files. Fails if any file is unformatted —
## used by the pre-commit hook so the commit is blocked (rather than silently
## reformatting already-staged files). Mirrors `format`'s scope exactly.
format_check:
	dart format --output=none --set-exit-if-changed packages
.PHONY: format_check

analyze:
	dart analyze
.PHONY: analyze

checks: coverage.log license_check
.PHONY: checks

test: test.log
.PHONY: test

test.log: lib/** test/**
	dart test  | tee test.log

tests_all: test e2e_test
.PHONY: tests_all

e2e_test: e2e_test.log
.PHONY: e2e_test

e2e_test.log: lib/** test/**

load: loader_freedesktop_mimeinfo
.PHONY: load

loader_freedesktop_mimeinfo:
	dart run tool/freedesktop_mimeinfo.dart
.PHONY: loader_freedesktop_mimeinfo

loader_tika:
	dart run tool/tika.dart
.PHONY: loader_tika

license_check:
	cat addlicense_config.txt | xargs addlicense --check

license_add:
	cat addlicense_config.txt | xargs addlicense

coverage: coverage.log
.PHONY: coverage

coverage.log: lib/** test/**
	flutter test --coverage
	# dart test --coverage-path=coverage/lcov.info
	rm -rf site/coverage
	mkdir -p site/coverage
	genhtml coverage/lcov.info -o site/coverage/html

# BEGIN: Documentation site tasks
site/:
	mkdir -p site

site: styles site/index.html site/api.html site/spec.html site/roadmap.html api-docs/index.html | site/
.PHONY: site

styles: site/styles/styles.css
.PHONY: styles

site/index.html:  docs/index.md docs/.pandoc docs/template/header.html | site/
	pandoc --defaults="docs/.pandoc" docs/index.md -o "site/index.html";

site/spec.html:  docs/spec/*.md docs/spec/.pandoc docs/template/header.html | site/
	pandoc --defaults="docs/spec/.pandoc" --mathml docs/spec/*.md -o "site/spec.html";

site/roadmap.html: docs/roadmap/*.md docs/.pandoc docs/template/header.html | site/
	pandoc --defaults="docs/.pandoc" docs/roadmap/v*.md -o "site/roadmap.html";

site/styles/styles.css: docs/styles/styles.css | site/
	mkdir -p site/styles/
	cp docs/styles/styles.css site/styles/styles.css

api-docs/index.html:
	dart doc -o api-docs/index.html

# END: Documentation site tasks

clean:
	rm -rf site dist coverage
	rm -f *.log
	dart pub get

.PHONY: clean
