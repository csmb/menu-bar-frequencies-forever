.PHONY: app dmg release install run test clean

# Build output lives OUTSIDE the repo, because the repo is in iCloud Drive.
# iCloud's file provider stamps com.apple.FinderInfo on the built .app bundle
# and re-adds it within a second of any strip, and codesign refuses to sign or
# --strict-verify a bundle carrying it ("resource fork, Finder information, or
# similar detritus not allowed"). Assembling and signing under ~/Library/Caches
# keeps the whole signing pipeline off iCloud. Override with
# `make BUILD_DIR=/somewhere dmg`; the scripts read the same variable.
BUILD_DIR ?= $(HOME)/Library/Caches/menu-bar-frequencies-forever
export BUILD_DIR

# The app name has spaces, so every use of these has to stay quoted.
APP = $(BUILD_DIR)/BFF.FM – Menu Bar Frequencies Forever.app
DEST = /Applications/BFF.FM – Menu Bar Frequencies Forever.app
PLIST = Scripts/Info.plist

app:
	Scripts/build-app.sh

dmg:
	Scripts/make-dmg.sh

# Cut a release: stamp the version into Info.plist, then build the notarized,
# stapled disk image. Info.plist is the only place a version is written; the
# DMG filename, the volume name, and the app itself all read it from there, so
# they cannot disagree.
#
#   make release VERSION=1.1
# The validation is a `case`, not `echo | grep -q`, to keep the no-pipe habit
# these scripts depend on — see CLAUDE.md, Build.
release:
	@case "$(VERSION)" in \
	  "") echo "usage: make release VERSION=1.1" >&2; \
	      echo "current: $$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $(PLIST))" >&2; \
	      exit 1 ;; \
	  *[!0-9.]*) echo "error: VERSION must be digits and dots, e.g. 1.1 — got '$(VERSION)'" >&2; \
	      exit 1 ;; \
	esac
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(PLIST)
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(PLIST)
	$(MAKE) dmg

install: app
	rm -rf "$(DEST)"
	cp -R "$(APP)" /Applications/
	@echo "Installed $(DEST)"

run: app
	open "$(APP)"

test:
	swift test

clean:
	rm -rf .build build "$(BUILD_DIR)"
