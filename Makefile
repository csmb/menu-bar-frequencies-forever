.PHONY: app install run test clean

app:
	Scripts/build-app.sh

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
