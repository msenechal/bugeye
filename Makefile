# Bugeye. `make test-core` is what Linux runs; everything else needs a Mac with Xcode (spec §6).
SHELL := /bin/bash

PORTABLE_TESTS := BugeyeCoreTests BugeyeFeaturesTests BugeyeTestSupportTests \
	CaptureCoreTests QuickAccessCoreTests EditorCoreTests RecordingCoreTests MotionCoreTests \
	TextCoreTests ProvenanceCoreTests SearchCoreTests CollectionsCoreTests GuideCoreTests AICoreTests
empty :=
space := $(empty) $(empty)
CORE_FILTER := ^($(subst $(space),|,$(strip $(PORTABLE_TESTS))))\.

FORMAT_PATHS := Package.swift Sources Tests
# Where `make install` puts the app. Not /Applications while the first build's Bugeye.app lives there.
INSTALL_DIR ?= $(HOME)/Applications
SIGN_IDENTITY ?= Bugeye Dev

.PHONY: build test test-core lint format guards ownership icon bundle cert install fixture check-release-symbols clean

build:
	swift build

test:
	swift test

test-core:
	swift test --filter '$(CORE_FILTER)'

lint:
	swift format lint --strict --recursive --parallel $(FORMAT_PATHS)

format:
	swift format format --in-place --recursive --parallel $(FORMAT_PATHS)

guards:
	scripts/guards.sh
	scripts/test-guards.sh
	scripts/test-ownership.sh

# Folder ownership of an epic branch against BASE (contracts spec §3).
BASE ?= origin/main
ownership:
	scripts/ownership.sh $(BASE)

# macOS only from here on.

icon:
	swift run -c release BugeyeIconTool build/icon

bundle:
	scripts/bundle.sh

cert:
	scripts/cert.sh

install:
	SIGN_IDENTITY="$(SIGN_IDENTITY)" scripts/bundle.sh
	scripts/install.sh "$(INSTALL_DIR)"

fixture:
	swift run BugeyeFixture

check-release-symbols:
	scripts/check-release-symbols.sh

clean:
	rm -rf .build build
