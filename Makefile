# PremiumShot Mac build entry points.
CONFIG ?= release

.PHONY: test app run goldens clean

test:
	swift test -c $(CONFIG)

app:
	scripts/bundle-app.sh $(CONFIG)

run: app
	open build/PremiumShot.app

# Use only when accepting an intentional rendering change.
goldens:
	UPDATE_GOLDENS=1 swift test -c $(CONFIG) --filter GoldenTests

clean:
	rm -rf .build build out
