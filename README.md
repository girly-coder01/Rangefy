<p align="center"><img src="frontend/public/logo-mark.svg" width="72" alt="Rangefy"/></p>

# Rangefy

**Liquidity that stays in range.**

Rangefy is an experimental active-liquidity protocol for Uniswap v4 on Unichain. It combines curator-defined vault strategies, an AI volatility forecast, and on-chain rules to manage concentrated liquidity positions.

## How it works

- **Curators** create vaults with bounded strategy settings, such as range width, rebalance timing, and performance fees.
- **Liquidity providers** deposit into a vault and receive ERC-20 shares representing their portion of its assets.
- **The AI engine** estimates volatility and short-term price drift and publishes signals for the pool.
- **The Uniswap v4 hook and vault contracts** adjust swap fees by volatility regime and calculate guarded position ranges on-chain. If an AI signal is stale, the hook's on-chain volatility estimate is used instead.
- **A keeper** can trigger eligible rebalances, but cannot choose the range or move vault funds. Rebalancing is permissionless under the vault's rules.

The goal is to make active liquidity management more transparent: curators set the strategy, while smart contracts enforce its limits. Vault shares, strategy rules, and pool signals are on-chain; forecasting and transaction automation run off-chain.

## Project status

Rangefy is a prototype, not a production-ready or audited financial product. The AI model and keeper are experimental, and the current design has limitations such as one concentrated position per vault. Do not deposit funds you cannot afford to lose.

## In this repository

- [`contracts/`](contracts/) — Uniswap v4 hook, vaults, curator registry, factory, and supporting contracts.
- [`ai-engine/`](ai-engine/) — volatility forecasting, signal publishing, keeper jobs, and API.
- [`frontend/`](frontend/) — Next.js interface and contract integrations.
- [Build blueprint](docs/Rangefy.md) — architecture, design details, and development/deployment instructions.
# Rangefy
