.PHONY: app dmg release install run test clean

# Build output lives OUTSIDE the repo, because the repo is in iCloud Drive.
# iCloud's file provider stamps com.apple.FinderInfo on the built .app bundle
# and re-adds it within a second of any strip, and codesign refuses to sign or
# --strict-verify a bundle carrying it ("resource fork, Finder information, or
# similar detritus not allowed"). Assembling and signing under ~/Library/Caches
# keeps the whole signing pipeline off iCloud. Override with
# `make BUILD_DIR=/somewhere dmg`; the scripts read the same variable.
#
# `=`, not `?=`: a BUILD_DIR exported in your shell for some other tool is
# ignored, because `make clean` would otherwise go after that tool's output.
# Only a command-line override counts, and an empty one is refused — the
# scripts fall back to the default on empty while APP here would not, so
# `make install` deleted the installed app and then had nothing to copy.
BUILD_DIR = $(HOME)/Library/Caches/menu-bar-frequencies-forever
ifeq ($(strip $(BUILD_DIR)),)
$(error BUILD_DIR is empty — leave it unset for the default, or name a directory)
endif
export BUILD_DIR

# The app name has spaces, so every use of these has to stay quoted.
NAME = BFF.FM – Menu Bar Frequencies Forever
APP = $(BUILD_DIR)/$(NAME).app
DEST = /Applications/$(NAME).app
PLIST = Scripts/Info.plist

app:
	Scripts/build-app.sh

dmg:
	Scripts/make-dmg.sh

# Cut a release: stamp the version into Info.plist, then build the notarized,
# stapled disk image. Info.plist is the only place the app's version is
# written; the DMG filename, the volume name, and the app itself all read it
# from there, so they cannot disagree. (The User-Agent carries a version of its
# own, set by hand in BFFAPI.swift.)
#
#   make release VERSION=1.1
# The validation is a `case`, not `echo | grep -q`, to keep the no-pipe habit
# these scripts depend on — see CLAUDE.md, Build.
#
# A release is built from a commit: SwiftPM compiles every source file in the
# folder, committed or not, and this folder is iCloud-synced. The version
# stamp is the one change allowed, because release writes it itself and a
# re-run after a failed notarization must not trip over it. And a release has
# to open on other Macs, so REQUIRE_DISTRIBUTABLE makes make-dmg.sh refuse an
# ad-hoc build instead of finishing it with a warning.
release:
	@case "$(VERSION)" in \
	  "") echo "usage: make release VERSION=1.1" >&2; \
	      echo "current: $$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $(PLIST))" >&2; \
	      exit 1 ;; \
	  *[!0-9.]*) echo "error: VERSION must be digits and dots, e.g. 1.1 — got '$(VERSION)'" >&2; \
	      exit 1 ;; \
	esac
	@uncommitted="$$(git status --porcelain -- . ':!$(PLIST)')"; \
	if [ -n "$$uncommitted" ]; then \
	  echo "error: a release is built from a commit, and these changes are not committed:" >&2; \
	  echo "$$uncommitted" >&2; \
	  exit 1; \
	fi
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(PLIST)
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(PLIST)
	REQUIRE_DISTRIBUTABLE=1 $(MAKE) dmg

install: app
	test -d "$(APP)"
	rm -rf "$(DEST)"
	cp -R "$(APP)" /Applications/
	@echo "Installed $(DEST)"

run: app
	open "$(APP)"

test:
	swift test

# Only what this project writes into BUILD_DIR — it may be a directory you
# pointed it at, and anything else in there is yours. The directory itself
# goes only if that leaves it empty.
clean:
	rm -rf .build build "$(APP)"
	rm -f "$(BUILD_DIR)/$(NAME) "*.dmg
	rmdir "$(BUILD_DIR)" 2>/dev/null || true
