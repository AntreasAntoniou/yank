.PHONY: build run app install clean

# Compile a debug binary.
build:
	swift build

# Build the release .app bundle into ./build.
app:
	@bash Scripts/build-app.sh release

# Build and launch the app.
run: app
	@open build/Yank.app

# Copy the app into /Applications.
install: app
	@rm -rf /Applications/Yank.app
	@cp -R build/Yank.app /Applications/Yank.app
	@echo "✓ Installed to /Applications/Yank.app"

clean:
	swift package clean
	rm -rf build .build
