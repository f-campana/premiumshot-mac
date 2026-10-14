CONFIG ?= release
ARCH ?= $(shell uname -m)
VERSION ?= $(shell cat VERSION)
export ARCH VERSION

.PHONY: test app dev-app run cli check release goldens clean
test:
	swift test -c $(CONFIG) --arch $(ARCH)
app:
	scripts/bundle-app.sh $(CONFIG)
dev-app:
	scripts/bundle-app.sh debug
run: app
	open build/PremiumShot.app
cli:
	swift build -c release --arch $(ARCH) --product pshot
check: test app cli
	python3 scripts/check-release-metadata.py
	python3 scripts/check-cli.py
	git diff --check
release:
	scripts/release.sh
# Reference images change only after accepting an intentional renderer change.
goldens:
	UPDATE_GOLDENS=1 swift test -c $(CONFIG) --filter GoldenTests
clean:
	rm -rf .build build out
