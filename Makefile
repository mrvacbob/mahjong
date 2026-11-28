# `make` builds ./mj; `make check` runs everything that should stay green.
# The Mercury cross-check needs `mmc`; it is skipped where that is missing.

PYTHON ?= python3.14
MMC := $(shell command -v mmc 2>/dev/null)

.PHONY: all mj mercury test corpus scenarios check clean

all: mj mercury

mj:
	swift build -c release --product mj
	cp "$$(swift build -c release --show-bin-path)/mj" ./mj

mercury:
ifdef MMC
	sh Sources/Mercury/build.sh
else
	@echo "mmc not found; skipping Sources/Mercury"
endif

test:
	swift test

corpus: all
	$(PYTHON) Tools/harness.py ./mj Corpus/*.txt
ifdef MMC
	$(PYTHON) Tools/harness.py Sources/Mercury/mj Corpus/*.txt
endif

scenarios:
	$(PYTHON) Tools/scenario.py --check

check: test corpus scenarios

clean:
	swift package clean
	rm -f mj Sources/Mercury/mj
