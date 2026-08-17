.PHONY: app dmg install run test clean

app:
	Scripts/build-app.sh

dmg:
	Scripts/make-dmg.sh

install: app
	rm -rf /Applications/BFF.fm.app
	cp -R build/BFF.fm.app /Applications/
	@echo "Installed /Applications/BFF.fm.app"

run: app
	open build/BFF.fm.app

test:
	swift test

clean:
	rm -rf .build build
