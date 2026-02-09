.PHONY: build run test open log log-stream clean help

APP_DIR := app/macos
DIST_DIR := dist
BUNDLE_ID := ai.openclaw.launcher

help:
	@echo "OpenClaw Launcher - Development Commands"
	@echo ""
	@echo "  make build       - Build the .app and .dmg"
	@echo "  make run         - Build and run the app"
	@echo "  make open        - Open the app (without rebuilding)"
	@echo "  make test        - Run unit tests"
	@echo "  make log         - Show recent app logs (last 5 min)"
	@echo "  make log-stream  - Stream app logs in real-time"
	@echo "  make clean       - Clean build artifacts"
	@echo ""

build:
	@cd $(APP_DIR) && ./build.sh

run: build open

open:
	@open $(DIST_DIR)/OpenClawLauncher.app

test:
	@cd $(APP_DIR) && swift test

log:
	@echo "Showing logs for OpenClawLauncher (last 5 minutes)..."
	@echo "---"
	@log show --predicate 'subsystem == "$(BUNDLE_ID)" OR process == "OpenClawLauncher"' \
		--style compact --last 5m

log-stream:
	@echo "Streaming logs for OpenClawLauncher... (Ctrl+C to stop)"
	@echo "---"
	@log stream --predicate 'subsystem == "$(BUNDLE_ID)" OR process == "OpenClawLauncher"' \
		--style compact

clean:
	@rm -rf $(DIST_DIR)/ $(APP_DIR)/.build
	@echo "Cleaned."
