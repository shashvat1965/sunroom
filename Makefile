# Sunroom — build, test and package.
#
# Script contract (Scripts/):
#   build-app.sh   defaults to a release build of the current architecture,
#                  accepts --debug and --universal, writes dist/Sunroom.app,
#                  and ad-hoc signs it.
#   make-icon.swift generates Resources/AppIcon.png and .icns from code; run it
#                  through `swift`.

SHELL := /bin/bash

APP_NAME   := Sunroom
DIST_DIR   := dist
APP_BUNDLE := $(DIST_DIR)/$(APP_NAME).app

VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
ifeq ($(strip $(VERSION)),)
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist 2>/dev/null || echo 0.1.0)
endif

ZIP := $(DIST_DIR)/$(APP_NAME)-$(VERSION)-universal.zip

.PHONY: all build test app release icon run clean help

all: build

## build: compile the Swift package (debug)
build:
	swift build

## test: run the test suite
test:
	swift test

## app: build the app bundle into dist/ (release, current architecture)
app:
	./Scripts/build-app.sh

## release: universal release build, zipped with a checksum
release:
	rm -f "$(ZIP)" "$(ZIP).sha256"
	./Scripts/build-app.sh --universal
	@test -d "$(APP_BUNDLE)" || { echo "error: $(APP_BUNDLE) was not produced" >&2; exit 1; }
	ditto -c -k --sequesterRsrc --keepParent "$(APP_BUNDLE)" "$(ZIP)"
	shasum -a 256 "$(ZIP)" > "$(ZIP).sha256"
	@echo "release: $(ZIP)"
	@cat "$(ZIP).sha256"

## run: build the app and open it
run: app
	open "$(APP_BUNDLE)"

## icon: regenerate the app icon from Scripts/make-icon.swift
icon:
	swift Scripts/make-icon.swift

## clean: remove build products
clean:
	rm -rf .build "$(DIST_DIR)"

## help: list targets
help:
	@echo "Sunroom $(VERSION)"
	@echo ""
	@echo "Targets:"
	@sed -n 's/^## \([a-z]*\): \(.*\)/  make \1 — \2/p' Makefile
