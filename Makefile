APP := build/Touchy.app
BIN := .build/release/Touchy
# Command Line Tools ship swift-testing outside the default search path.
TESTING_FW := /Library/Developer/CommandLineTools/Library/Developer/Frameworks

.PHONY: app test install clean

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp Info.plist $(APP)/Contents/Info.plist
	strip -x -o $(APP)/Contents/MacOS/Touchy $(BIN)
	codesign --force --sign - $(APP)

test:
	swift test $(if $(wildcard $(TESTING_FW)),-Xswiftc -F$(TESTING_FW) -Xlinker -F$(TESTING_FW) -Xlinker -rpath -Xlinker $(TESTING_FW))

install: app
	-pkill -x Touchy && sleep 0.5
	rm -rf /Applications/Touchy.app
	cp -R $(APP) /Applications/
	open /Applications/Touchy.app

clean:
	rm -rf .build build
