.DEFAULT_GOAL := default

include site.mk

# BEGIN: Primary tasks

default: prepare format analyze license_check test doc_site
.PHONY: default

pre_commit: prepare format_check analyze license_check coverage_check
.PHONY: pre_commit

cicd: prepare format_check analyze license_check coverage_check
.PHONY: cicd

# END: Primary tasks

format:
	dart format lib/ test/ example/
.PHONY: format

## Check formatting without modifying files. Fails if any file is unformatted —
## used by the pre-commit hook so the commit is blocked (rather than silently
## reformatting already-staged files). Mirrors `format`'s scope exactly.
format_check:
	dart format --output=none --set-exit-if-changed lib test
.PHONY: format_check

analyze:
	dart analyze
.PHONY: analyze


test:
	dart test  | tee test.log
.PHONY: test

tests_all: test e2e_test
.PHONY: tests_all

e2e_test: e2e_test.log
.PHONY: e2e_test

e2e_test.log: lib/** test/**

load: loader_freedesktop_mimeinfo loader_tika
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

coverage:
	dart test --coverage-path=coverage/lcov.info
	lcov --remove coverage/lcov.info '*/g/*' --output-file coverage/lcov.filtered.info
	rm -rf site/coverage
	mkdir -p site/coverage
	genhtml coverage/lcov.filtered.info -o site/coverage
.PHONY: coverage

## Run tests with coverage and fail if hand-written code falls below 90%.
## Excludes generated /g/ files from the threshold calculation.
coverage_check:
	dart test --coverage-path=coverage/lcov.info
	lcov --remove coverage/lcov.info '*/g/*' --output-file coverage/lcov.filtered.info
	@set -e; \
	pct=$$(lcov --summary coverage/lcov.filtered.info 2>&1 | grep 'lines\.\.\.' | awk '{print $$2}' | tr -d '%'); \
	echo "Coverage: $${pct}%"; \
	awk "BEGIN { if ($${pct} < 90) { print \"FAIL: $${pct}% is below the 90% threshold\"; exit 1 } }"
.PHONY: coverage_check


prepare:
	dart pub get

clean:
	rm -rf site dist coverage
	rm -f *.log
	dart pub get

.PHONY: clean
