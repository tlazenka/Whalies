PYTHON ?= python3

.PHONY: test python-tests swift-tests xcode-project format format-objc whaley-query \
  web-server whaley2010-verify \
  whaley2010-project whaley3d-verify whaley-archive-check whaley2010-archive-check \
  whaley-scala-check whaley-scala-web whaley-scala-native whaley-scala-run web-server-smoke stadium-integration-check \
  whaley-pages whaley-pages-check whaley-pages-publish

test:
	swift test

python-tests:
	"$(PYTHON)" python/whaley.py test

swift-tests:
	docker compose --profile test run --rm swift-tests

xcode-project:
	cd Apps && xcodegen generate

format:
	swift format . --recursive --in-place

format-objc:
	find Sources Apps -type f \( -name '*.h' -o -name '*.m' \) -exec clang-format -i {} +

whaley-query:
	docker compose --profile cli run --rm whaley-cli query $(ARGS)

web-server:
	docker compose up --build db server

web-server-smoke:
	bash scripts/verify-whaley-ssr.sh

whaley2010-verify:
	bash Apps/Whaley2010/verify-engine.sh

whaley2010-project: whaley2010-verify
	cd Apps && xcodegen generate

whaley3d-verify:
	bash Apps/Whaley/check-3d-projection.sh

whaley-archive-check:
	bash Apps/Whaley/check-archive-link.sh

whaley-scala-check:
	"$(PYTHON)" python/whaley.py sbt -- check

whaley-scala-web:
	"$(PYTHON)" python/whaley.py sbt -- web/stage

whaley-pages:
	"$(PYTHON)" python/whaley.py web package --target pages

whaley-pages-check: whaley-pages
	cd Scala && npm run test:pages

whaley-pages-publish: whaley-pages-check
	"$(PYTHON)" python/whaley.py web publish

whaley-scala-native:
	"$(PYTHON)" python/whaley.py sbt -- nativeApp/stageNative

whaley-scala-run:
	"$(PYTHON)" python/whaley.py sbt -- nativeApp/runNative

whaley2010-archive-check:
	bash Apps/Whaley2010/check-appstore-archive.sh

stadium-integration-check:
	bash scripts/check-stadium-integration.sh
