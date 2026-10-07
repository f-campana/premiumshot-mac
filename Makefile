# PremiumShot build entry points. Everything reviewers need runs from here.
#   make test       unit and golden tests
#   make app        builds build/PremiumShot.app (ad-hoc signed)
#   make fixtures   regenerates the synthetic fixtures (rarely needed; they are committed)
#   make goldens    accepts an intentional change to the golden images
CONFIG ?= release

.PHONY: test app fixtures goldens clean run

test:
	swift test

app:
	scripts/bundle-app.sh $(CONFIG)

run: app
	open build/PremiumShot.app

fixtures:
	swift run fixturegen fixtures

goldens:
	UPDATE_GOLDENS=1 swift test --filter GoldenTests

clean:
	rm -rf .build build out
