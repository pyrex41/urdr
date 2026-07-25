PYTHON ?= python3

.PHONY: bootstrap fmt-check test conformance ci quality

# This is the only entry point permitted to fetch network dependencies.
bootstrap:
	URDR_BOOTSTRAP_NETWORK=1 $(PYTHON) scripts/bootstrap

fmt-check:
	URDR_OFFLINE=1 PYTHONDONTWRITEBYTECODE=1 $(PYTHON) scripts/repo-quality

test:
	URDR_OFFLINE=1 PYTHONDONTWRITEBYTECODE=1 $(PYTHON) -m unittest discover \
		-s scripts/tests -p 'test_*.py'

conformance:
	URDR_OFFLINE=1 PYTHONDONTWRITEBYTECODE=1 $(PYTHON) scripts/conformance

# The clean-tree wrapper proves that all CI checks are repository-pure.
ci:
	$(PYTHON) scripts/check-clean-tree -- $(MAKE) fmt-check test conformance

# Foundation-only gate. Full CI remains fail-closed until M0 conformance lands.
quality:
	$(PYTHON) scripts/check-clean-tree -- $(MAKE) fmt-check test
