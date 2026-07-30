PYTHON ?= python3
# Default is the full four-port matrix. For M1 single-port development:
#   make conformance REQUIRED_IMPLS=shen-cl
REQUIRED_IMPLS ?= shen-go,shen-lua,shen-cl,shen-rust

.PHONY: bootstrap fmt-check test adversarial conformance conformance-shake ci quality

# This is the only entry point permitted to fetch network dependencies.
bootstrap:
	URDR_BOOTSTRAP_NETWORK=1 $(PYTHON) scripts/bootstrap

# Build the port launchers from the pinned checkouts and stamp each with the
# commit it came from. `bootstrap` materializes sources but leaves build output
# alone, so without this a launcher built before a repin survives it and the
# gate runs code that is not the reviewed commit. The gate now refuses a
# launcher whose stamp does not match its pin, so this is a required step
# after every bootstrap, not a convenience.
ports:
	sh scripts/build-ports

fmt-check:
	URDR_OFFLINE=1 PYTHONDONTWRITEBYTECODE=1 $(PYTHON) scripts/repo-quality

# Two offline discovery roots: the foundation unit tests and the
# adversarial negative/mutation harness (pure Python + committed fixtures;
# its optional Shen launcher probes live behind `make adversarial`).
test:
	URDR_OFFLINE=1 PYTHONDONTWRITEBYTECODE=1 $(PYTHON) -m unittest discover \
		-s scripts/tests -p 'test_*.py'
	URDR_OFFLINE=1 PYTHONDONTWRITEBYTECODE=1 $(PYTHON) -m unittest discover \
		-s shen/tests/adversarial -p 'test_*.py'

# The adversarial harness plus its read-only launcher probes. The probes
# require all four pinned launchers (see scripts/build-ports), so this
# target is not part of the offline `test` lane.
adversarial:
	URDR_OFFLINE=1 PYTHONDONTWRITEBYTECODE=1 \
		$(PYTHON) shen/tests/adversarial/run --probe-ports

conformance:
	URDR_OFFLINE=1 PYTHONDONTWRITEBYTECODE=1 REQUIRED_IMPLS=$(REQUIRED_IMPLS) \
		$(PYTHON) scripts/conformance

# Second lane: the same reviewed cases, shaken by Ratatoskr into standalone
# artifacts and run per target. The source lane above proves four independent
# implementations agree on the source; this proves the artifact you deploy
# behaves identically.
#
# shen-rust is left out by default. Measured per case on this corpus, stage 1
# is under a second and the stage-2 builds are lua 1s / shen-cl 4s / go 13s --
# but rust is 169s, ~88% of the total, and it is not cacheable: a warm rebuild
# is still ~98s because the cost is compiling the generated crate, not its
# dependencies. Including it takes the lane from 5 to 52 minutes. Run the full
# matrix on a schedule instead:
#
#   make conformance-shake SHAKE_IMPLS=shen-go,shen-lua,shen-cl,shen-rust
SHAKE_IMPLS ?= shen-go,shen-lua,shen-cl

conformance-shake:
	URDR_OFFLINE=1 URDR_SHAKE=1 PYTHONDONTWRITEBYTECODE=1 \
		REQUIRED_IMPLS=$(SHAKE_IMPLS) $(PYTHON) scripts/conformance

# The clean-tree wrapper proves that all CI checks are repository-pure.
ci:
	$(PYTHON) scripts/check-clean-tree -- $(MAKE) fmt-check test conformance

# Foundation-only gate. Full CI remains fail-closed until M0 conformance lands.
quality:
	$(PYTHON) scripts/check-clean-tree -- $(MAKE) fmt-check test
