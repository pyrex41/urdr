PYTHON ?= python3
# Default is the full four-port matrix. For M1 single-port development:
#   make conformance REQUIRED_IMPLS=shen-cl
REQUIRED_IMPLS ?= shen-go,shen-lua,shen-cl,shen-rust

.PHONY: bootstrap fmt-check test conformance conformance-shake ci quality

# This is the only entry point permitted to fetch network dependencies.
bootstrap:
	URDR_BOOTSTRAP_NETWORK=1 $(PYTHON) scripts/bootstrap

fmt-check:
	URDR_OFFLINE=1 PYTHONDONTWRITEBYTECODE=1 $(PYTHON) scripts/repo-quality

test:
	URDR_OFFLINE=1 PYTHONDONTWRITEBYTECODE=1 $(PYTHON) -m unittest discover \
		-s scripts/tests -p 'test_*.py'

conformance:
	URDR_OFFLINE=1 PYTHONDONTWRITEBYTECODE=1 REQUIRED_IMPLS=$(REQUIRED_IMPLS) \
		$(PYTHON) scripts/conformance

# Second lane: the same reviewed cases, shaken by Ratatoskr into standalone
# artifacts and run per target. The source lane above proves four independent
# implementations agree on the source; this proves the artifact you deploy
# behaves identically. Needs the stage-2 toolchains (go, luajit, sbcl, cargo).
conformance-shake:
	URDR_OFFLINE=1 URDR_SHAKE=1 PYTHONDONTWRITEBYTECODE=1 \
		REQUIRED_IMPLS=$(REQUIRED_IMPLS) $(PYTHON) scripts/conformance

# The clean-tree wrapper proves that all CI checks are repository-pure.
ci:
	$(PYTHON) scripts/check-clean-tree -- $(MAKE) fmt-check test conformance

# Foundation-only gate. Full CI remains fail-closed until M0 conformance lands.
quality:
	$(PYTHON) scripts/check-clean-tree -- $(MAKE) fmt-check test
