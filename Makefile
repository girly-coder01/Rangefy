SHELL := /bin/bash
PY ?= python3.11
export PATH := $(PATH):$(HOME)/.foundry/bin

.PHONY: help install build test fmt coverage wallets fund deploy sync-abis local-stack fork-stack e2e \
        ai-install ai-test ai-fetch ai-train ai-keeper ai-serve fe-install fe-dev fe-build fe-test test-all clean

help:
	@grep -E '^[a-z-]+:' Makefile | cut -d: -f1 | column

# contracts
install:
	git submodule update --init --recursive
build:
	cd contracts && forge build
test:
	cd contracts && forge test
fmt:
	cd contracts && forge fmt
coverage:
	cd contracts && forge coverage --ir-minimum --report summary

# Unichain Sepolia
wallets:
	./scripts/new-wallets.sh
fund:
	./scripts/fund-wallets.sh
deploy:
	./scripts/deploy-testnet.sh
sync-abis:
	./scripts/sync-abis.sh

# local
local-stack:
	./scripts/local-stack.sh
fork-stack:
	FORK=1 ./scripts/local-stack.sh
e2e:
	cd ai-engine && .venv/bin/pytest tests/test_e2e_local.py -v

# ai engine
ai-install:
	cd ai-engine && $(PY) -m venv .venv && .venv/bin/pip install -e ".[dev]"
ai-test:
	cd ai-engine && .venv/bin/pytest
ai-fetch:
	cd ai-engine && .venv/bin/python scripts/fetch_history.py --days 730
ai-train:
	cd ai-engine && .venv/bin/python scripts/train_model.py
ai-keeper:
	cd ai-engine && .venv/bin/python scripts/run_keeper.py
ai-serve:
	cd ai-engine && .venv/bin/uvicorn src.server.app:app --port 8000

# frontend
fe-install:
	cd frontend && npm ci
fe-dev:
	cd frontend && npm run dev
fe-build:
	cd frontend && npm run build
fe-test:
	cd frontend && npm test

test-all: test ai-test fe-test

clean:
	cd contracts && forge clean
	rm -rf ai-engine/.pytest_cache frontend/.next
