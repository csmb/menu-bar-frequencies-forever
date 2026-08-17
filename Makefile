.PHONY: app dmg install run test clean

# The app name has spaces, so every use of these has to stay quoted.
APP = build/BFF.FM – Menu Bar Frequencies Forever.app
DEST = /Applications/BFF.FM – Menu Bar Frequencies Forever.app

app:
	Scripts/build-app.sh

dmg:
	Scripts/make-dmg.sh

install: app
	rm -rf "$(DEST)"
	cp -R "$(APP)" /Applications/
	@echo "Installed $(DEST)"

run: app
	open "$(APP)"

test:
	swift test

clean:
	rm -rf .build build
