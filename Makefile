.PHONY: gen open test build lint format clean bootstrap

# Run recipes under bash with pipefail so a failing xcodebuild is not masked
# by a downstream pipe (e.g. `| xcbeautify`).
SHELL := /bin/bash
.SHELLFLAGS := -eo pipefail -c

SCHEME ?= Mend
DESTINATION ?= platform=iOS Simulator,name=iPhone 17

bootstrap:
	@command -v xcodegen >/dev/null 2>&1 || { echo "Install XcodeGen: brew install xcodegen"; exit 1; }
	@command -v swiftformat >/dev/null 2>&1 || echo "(optional) brew install swiftformat"

gen: bootstrap
	xcodegen generate

open: gen
	open Mend.xcodeproj

test: gen
	@if command -v xcbeautify >/dev/null 2>&1; then \
		xcodebuild test \
			-project Mend.xcodeproj \
			-scheme $(SCHEME) \
			-destination '$(DESTINATION)' \
			| xcbeautify; \
	else \
		xcodebuild test \
			-project Mend.xcodeproj \
			-scheme $(SCHEME) \
			-destination '$(DESTINATION)'; \
	fi

build: gen
	@if command -v xcbeautify >/dev/null 2>&1; then \
		xcodebuild build \
			-project Mend.xcodeproj \
			-scheme $(SCHEME) \
			-destination '$(DESTINATION)' \
			| xcbeautify; \
	else \
		xcodebuild build \
			-project Mend.xcodeproj \
			-scheme $(SCHEME) \
			-destination '$(DESTINATION)'; \
	fi

lint:
	swiftformat --lint . || true

format:
	swiftformat .

clean:
	rm -rf build DerivedData Mend.xcodeproj
