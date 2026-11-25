<p align="center"><img src="frontend/public/logo-mark.svg" width="72" alt="Rangefy"/></p>

# Rangefy

AI-curated liquidity vaults for Uniswap v4 on Unichain. Curators define the strategy, an AI volatility model sizes the range, and a v4 hook prices risk and guards every rebalance on-chain.

Built for the Atrium Academy Uniswap Hook Incubator Hookathon (Active Management and Curation). Full design: [docs/Rangefy.md](docs/Rangefy.md).

## How it works

- **RangefyHook** keeps an EMA tick and realized volatility, updated before every swap, and sets the LP fee per volatility regime (0.05% → 1.5%). Registered vaults pay a flat 0.05% on their own rebalance swaps.
- **SignalOracle** holds the AI's 24h sigma/drift forecast. Values are bounded and expire after 15 minutes; the hook falls back to on-chain volatility and never lets the AI read more than one regime calmer than the chain.
- **RangeVault** (one per curator strategy) computes every range on-chain from the curator's params and the hook's sigma. Anyone can call `rebalance()` when the rules allow; curators can't touch LP funds.
- **AI engine** (Python) trains a Transformer + Random Forest ensemble, posts signals, runs the keeper and a market mirror that keeps the testnet pool tracking real ETH/USD.
- **Frontend** (Next.js 16, wagmi, RainbowKit) for LPs, curators and the leaderboard.

## Repo

| Path | |
|---|---|
| `contracts/` | Foundry. Hook, oracle, registry, factory + deployer, vault, router, lens, faucet token, deploy scripts |
| `ai-engine/` | Data, features, models, training, keeper, FastAPI |
| `frontend/` | Next.js app |
| `scripts/` | wallets, funding, deploy, ABI sync, local stack |

## Tests

```bash
make install                 # submodules
make test                    # 107 Foundry tests
make ai-install ai-test      # 37 pytest (+6 E2E when a local chain is up)
make fe-install fe-test      # 12 jest
```

Full local stack (anvil + Uniswap v4 + every deploy script + keeper E2E):

```bash
make local-stack && make e2e     # fresh chain
make fork-stack  && make e2e     # fork of Unichain Sepolia, canonical v4 contracts
```

## Deploy to Unichain Sepolia

```bash
make wallets     # writes contracts/.env with keys for deployer, signal updater, keeper, mirror, 3 curators
# fund the printed deployer address with Unichain Sepolia ETH (~0.05)
make fund        # deployer → other roles
make deploy      # preflight, deploy 00–03, verify on Blockscout, sync addresses
```

`make deploy` writes `frontend/src/config/deployments/1301.json`, `ai-engine/.env.addresses` and `ai-engine/.env`.

Uniswap v4 on Unichain Sepolia (checked on-chain): PoolManager `0x00B036B58a818B1BC34d502D3fE730Db729e62AC`, PoolModifyLiquidityTest `0x5fa728C0A5cfd51BEe4B060773f50554c0C8A7AB`.

### AI engine + keeper

Train on real data (needs network access to Coinbase or Binance):

```bash
cd ai-engine
.venv/bin/python scripts/fetch_history.py --days 730
.venv/bin/python scripts/train_model.py      # prints regime edges → REGIME_TH0..2 for 02_InitPool
```

Run on a VPS with Docker, behind HTTPS (the Vercel app can't call plain http):

```bash
docker compose up -d --build     # api on :8000 + keeper, sharing ai-engine/data
```

### Frontend on Vercel

- Root directory: `frontend`
- Env:
  - `NEXT_PUBLIC_CHAIN_ID=1301`
  - `NEXT_PUBLIC_AI_API_URL=https://<your-api-host>`
  - `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=<from cloud.reown.com>` (injected wallets work without it)
  - optional `NEXT_PUBLIC_UNICHAIN_RPC_URL`

Commit `frontend/src/config/deployments/1301.json` after deploying so the build picks up the addresses.

## Known limitations

One position per vault, centralised keeper in the demo (anyone can still rebalance), model trained on CEX prices rather than testnet flow, unaudited.
