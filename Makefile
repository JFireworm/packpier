PYTHON ?= python3
.PHONY: bootstrap build lint unit integration check
bootstrap:
	npm ci --no-audit --no-fund
	./Scripts/bootstrap-sparkle.sh
build:
	./Scripts/build.sh
lint:
	npm run lint
	uvx --from ruff==0.14.5 ruff check --select E9,F63,F7,F82 Scripts Tests
	@for script in Scripts/*.sh; do bash -n "$$script" || exit 1; done
	xcrun swiftc -frontend -parse Sources/*.swift Loader/*.swift Loader/Services/*.swift Plugins/WeChatCeladon/Sources/WeChatCeladon/*.swift
	$(PYTHON) Scripts/lint-swift.py
	$(PYTHON) Scripts/plugin-archives.py --check
	$(PYTHON) Tests/project-contract.py
unit: build
	bash Scripts/test.sh
	node --test Plugins/CustomBackground/src/*.test.js Tests/window-policy.mjs
	swift test --package-path Plugins/WeChatCeladon
integration: build
	$(PYTHON) Tests/packaged-loader.py
	$(PYTHON) Tests/third-party-node.py
	$(PYTHON) Tests/plugin-library.py
	$(PYTHON) Tests/window-effects.py
	$(PYTHON) Tests/window-takeover.py
check: lint unit integration
