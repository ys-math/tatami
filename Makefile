APP := dist/Tatami.app

.PHONY: build test app run install lint format clean

build:
	swift build

test:
	swift test

app:
	scripts/bundle.sh

run: app
	-pkill -x Tatami
	open $(APP)

install: app
	-pkill -x Tatami
	rm -rf ~/Applications/Tatami.app
	mkdir -p ~/Applications
	cp -R $(APP) ~/Applications/
	open ~/Applications/Tatami.app

lint:
	swift format lint --strict --recursive Sources Tests Package.swift

format:
	swift format --in-place --recursive Sources Tests Package.swift

clean:
	swift package clean
	rm -rf dist
