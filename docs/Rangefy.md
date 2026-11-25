# Rangefy — Build Blueprint

> **AI-curated liquidity vaults for Uniswap v4.**
> Curators define the strategy. An AI volatility model sizes the range. A Uniswap v4 hook prices risk and guards every rebalance on-chain.

| | |
|---|---|
| **Target event** | Atrium Academy Uniswap Hook Incubator — Hookathon |
| **Theme** | Active Management and Curation |
| **Chain** | Unichain Sepolia (chain ID `1301`) |
| **Sponsor integrations** | None required. No Reactive Network. Automation is a self-hosted keeper whose actions are fully constrained on-chain |
| **Stack** | Solidity 0.8.26 · Foundry · Uniswap v4 core + periphery · Python 3.11 (FastAPI, PyTorch, scikit-learn, web3.py) · Next.js 16 · wagmi v2 · viem · RainbowKit · Tailwind v4 |

This document is the single source of truth. An engineer or AI agent should be able to build, deploy and demo the whole system end-to-end on Unichain Sepolia from this file alone. Where this document and intuition disagree, follow this document; where this document and the live Uniswap docs disagree on an address or API signature, follow the live docs and update this file.

---

## Table of Contents

1. [Problem](#1-problem)
2. [Solution](#2-solution)
3. [Theme Fit](#3-theme-fit)
4. [System Architecture](#4-system-architecture)
5. [Repository Layout](#5-repository-layout)
6. [Smart Contracts](#6-smart-contracts)
7. [Core Algorithms (exact math)](#7-core-algorithms-exact-math)
8. [End-to-End Flows](#8-end-to-end-flows)
9. [AI Engine and Keeper](#9-ai-engine-and-keeper)
10. [Frontend](#10-frontend)
11. [Design System](#11-design-system) · [Brand and Logo](#brand-and-logo)
12. [Configuration and Environment](#12-configuration-and-environment)
13. [Deployment Runbook (Unichain Sepolia)](#13-deployment-runbook-unichain-sepolia)
14. [Testing Plan](#14-testing-plan)
15. [Security Model](#15-security-model)
16. [Build Order and Milestones](#16-build-order-and-milestones)
17. [Demo Script and Acceptance Criteria](#17-demo-script-and-acceptance-criteria)
18. [References](#18-references)

---

## 1. Problem

Concentrated liquidity earns far more fees than full-range liquidity — but only while the price stays inside the range. Passive LPs lose in three ways:

- **Out-of-range drift.** Price leaves the range, the position stops earning and sits 100% in the losing asset.
- **Wrong width.** A narrow range in a volatile market rebalances constantly and bleeds impermanent loss; a wide range in a calm market wastes capital. The right width changes with volatility, every day.
- **Flat fees.** A static fee tier undercharges during volatile periods, when LPs are most exposed to informed (toxic) flow.

Existing active managers are either opaque off-chain bots that LPs must trust completely, or rigid on-chain rules that ignore market conditions. There is no system where **a curator's strategy, an AI's market view and on-chain safety rules** are combined transparently.

## 2. Solution

Rangefy is three things working together:

1. **Curated vaults.** Anyone can register as a curator and launch a vault on a Rangefy pool with a strategy profile (how wide, how often to rebalance, performance fee). LPs pick a curator, deposit both tokens and receive ERC-20 vault shares.
2. **AI volatility signal.** An off-chain model (Transformer + Random Forest ensemble) forecasts 24-hour volatility and short-term drift for the pool's pair and posts it on-chain as a signed-by-role signal.
3. **The Rangefy hook.** A Uniswap v4 hook that:
   - keeps an on-chain **EMA tick oracle** and **realized-volatility estimate** updated on every swap,
   - sets a **dynamic swap fee** from the volatility regime (higher fee when the market is dangerous for LPs),
   - gives vaults a manipulation-resistant reference price for every deposit and rebalance.

The vault, not the keeper, computes the new range on-chain from the curator's profile and the signal. The keeper only says "now". If the AI signal is stale, everything falls back to the hook's on-chain volatility. If the keeper dies, anyone can call `rebalance()` and the same rules apply.

### Key Features

- AI-sized ranges: width = curator multiplier × forecast volatility, bounded by curator min/max.
- Range re-centring with bounded AI drift bias.
- Dynamic fees per volatility regime (Calm / Normal / High / Extreme).
- Permissionless, rule-bound rebalancing with EMA-deviation guard and cooldown.
- Curator marketplace and leaderboard ranked by share-price growth vs HODL.
- Fully live testnet: a market-mirror bot keeps the testnet pool tracking the real ETH/USD price so ranges move with the real market.

## 3. Theme Fit

| "Active Management and Curation" | Rangefy |
|---|---|
| Active liquidity management | Automatic range re-centring and re-sizing, fee compounding on every rebalance/harvest |
| Curation | Curator registry, vaults with curator-defined strategy profiles and bounded parameters, curator performance fees, public leaderboard |
| Risk management for LPs | Volatility-regime dynamic fees, EMA-deviation guards, cooldowns, curators can never touch LP funds |
| Hook-native | The hook is the oracle, fee engine and safety reference — vaults cannot work without it |

---

## 4. System Architecture

```
                         ┌──────────────────────────────────────────────┐
                         │                 FRONTEND (Next.js)            │
                         │ Vaults · Vault detail · Curate · Leaderboard  │
                         │ Swap · Faucet · AI Signal                     │
                         └───────┬───────────────────────┬──────────────┘
                     wagmi/viem  │ reads + txs            │ REST (forecast, history)
                                 ▼                        ▼
┌──────────────────────────── UNICHAIN SEPOLIA ───────────┐   ┌──────────────── AI ENGINE + KEEPER (Python) ───────────┐
│                                                         │   │                                                        │
│  PoolManager (Uniswap v4, canonical)                    │   │  collector   ← Coinbase/Binance 1m candles (real ETH)   │
│     │  hook callbacks                                   │   │  features    → vol windows, returns, on-chain stats     │
│     ▼                                                   │   │  model       → Transformer + RF → sigma24h, drift, regime│
│  RangefyHook ──reads──► SignalOracle ◄──postSignal──────┼───┤  signal_job  (every 60s, post on change / heartbeat)    │
│   · EMA tick, volatility                                │   │  rebalance_job (every 15s: needsRebalance → rebalance)  │
│   · dynamic fee                                         │   │  harvest_job (hourly)                                   │
│     ▲                                                   │   │  mirror_job  (every 20s: swap testnet pool → real price)│
│     │ getPoolState / emaTick                            │   │  FastAPI     /signal /forecast /keeper /mirror          │
│  RangeVault (one per curator strategy, ERC-20 shares) ◄─┼───┤  SQLite      signal + keeper history                    │
│     ▲ created by                                        │   └────────────────────────────────────────────────────────┘
│  VaultFactory ──checks──► CuratorRegistry               │
│                                                         │
│  MockERC20 mWETH / mUSDC (faucet) · SimpleSwapRouter    │
└─────────────────────────────────────────────────────────┘
```

### Trust boundaries

| Actor | Can | Cannot |
|---|---|---|
| LP | Deposit, withdraw any time | — |
| Curator | Create vaults, tune params inside factory bounds, lower fee, pause deposits, claim own fees | Move LP funds, pause withdrawals, set range directly, raise fee above cap |
| Keeper (anyone) | Call `rebalance`, `harvest` when conditions hold | Choose the range, bypass cooldown or EMA guard |
| Signal updater (AI engine EOA) | Post bounded signals | Post values outside hard bounds; signals expire after `MAX_SIGNAL_AGE` |
| Protocol owner | Set fee schedule (bounded), rotate signal updater, register pools | Touch vault funds |

---

## 5. Repository Layout

New repository `rangefy/` (monorepo):

```
rangefy/
├── contracts/                          # Foundry
│   ├── foundry.toml
│   ├── remappings.txt
│   ├── src/
│   │   ├── hook/RangefyHook.sol
│   │   ├── oracle/SignalOracle.sol
│   │   ├── vault/RangeVault.sol
│   │   ├── vault/VaultFactory.sol
│   │   ├── curator/CuratorRegistry.sol
│   │   ├── periphery/SimpleSwapRouter.sol
│   │   ├── periphery/RangefyLens.sol     # batched view helper for the frontend
│   │   ├── mocks/MockERC20.sol              # faucet-enabled token
│   │   ├── libraries/RangeMath.sol          # range + target-ratio math
│   │   ├── libraries/VolatilityOracle.sol   # EMA tick + variance updates
│   │   ├── libraries/Constants.sol
│   │   └── interfaces/                      # IRangefyHook, ISignalOracle, IRangeVault, ...
│   ├── script/
│   │   ├── 00_DeployTokens.s.sol
│   │   ├── 01_DeployCore.s.sol              # SignalOracle, CuratorRegistry, hook (mined), factory, router, lens
│   │   ├── 02_InitPool.s.sol                # init pool + background liquidity
│   │   ├── 03_SeedCurators.s.sol            # 3 demo curators + vaults + first deposits
│   │   └── HelperConfig.s.sol
│   └── test/
│       ├── unit/  fuzz/  invariant/  integration/  fork/
│       └── utils/RangefyFixture.sol
├── ai-engine/                          # Python: model + keeper + API
│   ├── pyproject.toml / requirements.txt
│   ├── src/
│   │   ├── data/        collector.py, candles.py, onchain.py, dataset.py, labeler.py
│   │   ├── features/    extractor.py, preprocessor.py
│   │   ├── models/      transformer.py, random_forest.py, ewma_baseline.py, ensemble.py
│   │   ├── training/    train.py, evaluate.py, backtest_lp.py
│   │   ├── inference/   forecaster.py, signal_mapper.py
│   │   ├── chain/       client.py, abis/, tx.py
│   │   ├── keeper/      signal_job.py, rebalance_job.py, harvest_job.py, mirror_job.py, scheduler.py
│   │   ├── store/       db.py (SQLite)
│   │   └── server/      app.py, routes.py
│   ├── scripts/         fetch_history.py, train_model.py, backtest.py, run_keeper.py
│   └── tests/
├── frontend/                           # Next.js 16
│   └── src/ app/ components/ hooks/ config/ lib/ providers/
├── scripts/sync-abis.sh                # copies contracts/out ABIs → frontend + ai-engine
├── docker-compose.yml                  # ai-engine (api + keeper) + frontend
├── Makefile
├── FEEDBACK.md                         # Uniswap v4 dev-experience notes (hookathon deliverable)
└── README.md
```

Dependencies (`forge install`): `Uniswap/v4-core`, `Uniswap/v4-periphery`, `OpenZeppelin/openzeppelin-contracts` (v5), `foundry-rs/forge-std`.

Remappings:
```
forge-std/=lib/forge-std/src/
@uniswap/v4-core/=lib/v4-core/
@uniswap/v4-periphery/=lib/v4-periphery/
@openzeppelin/=lib/openzeppelin-contracts/
solmate/=lib/v4-core/lib/solmate/
```

`foundry.toml`: `solc = "0.8.26"`, `evm_version = "cancun"`, `optimizer = true`, `optimizer_runs = 200`, `via_ir = true` (vault math is stack-heavy), fuzz runs 256, invariant runs 128, `rpc_endpoints.unichain_sepolia = "${UNICHAIN_SEPOLIA_RPC_URL}"`.

---

## 6. Smart Contracts

All contracts: SPDX MIT, `pragma solidity ^0.8.26`, custom errors, events for every state change, NatSpec on external functions. Units: ticks are `int24`, fees are in pips (1e-6, so `3000` = 0.30%), bps are `uint16` out of 10_000.

### 6.1 Constants.sol

```solidity
library Constants {
    // Signal
    uint256 constant MAX_SIGNAL_AGE        = 15 minutes;
    uint32  constant MIN_SIGMA_TICKS       = 20;      // 0.2%  24h vol floor
    uint32  constant MAX_SIGMA_TICKS       = 5_000;   // 50%   24h vol ceiling
    int32   constant MAX_DRIFT_TICKS       = 2_000;

    // Volatility oracle
    uint256 constant EMA_WINDOW            = 300;     // seconds, EMA tick time constant
    uint256 constant VAR_WINDOW            = 3_600;   // seconds, variance EWMA time constant
    uint256 constant SIGMA_HORIZON         = 86_400;  // range sizing horizon (24h)
    uint256 constant WAD                   = 1e18;

    // Fees (pips)
    uint24  constant MIN_FEE               = 100;     // 0.01%
    uint24  constant MAX_FEE               = 30_000;  // 3%

    // Vault
    uint256 constant MIN_SHARES            = 1_000;   // burned to dead address on first deposit
    uint16  constant MAX_PERFORMANCE_FEE   = 2_000;   // 20%
    uint16  constant MAX_SWAP_SLIPPAGE_BPS = 100;     // 1% from EMA price during rebalance swap
    uint16  constant EDGE_BUFFER_BPS       = 1_000;   // rebalance when within 10% of range width from an edge
    uint16  constant WIDTH_DRIFT_BPS       = 3_000;   // rebalance when target half-width differs ≥30%
    uint32  constant MIN_REBALANCE_INTERVAL_FLOOR = 60;      // 1 minute (testnet demo)
    uint32  constant MAX_REBALANCE_INTERVAL       = 1 days;
    int24   constant MIN_HALF_WIDTH_FLOOR  = 60;
    int24   constant MAX_HALF_WIDTH_CEIL   = 40_000;
    int24   constant MAX_EMA_DEVIATION_CEIL = 500;    // 5%
}
```

### 6.2 SignalOracle.sol

Stores the latest AI signal per pool. Owned (`Ownable2Step`). One `updater` address (the AI engine EOA).

```solidity
enum Regime { Calm, Normal, High, Extreme }

struct Signal {
    uint32  sigmaTicks;     // forecast 24h 1-sigma move, in ticks (1 tick ≈ 1 bp)
    int32   driftTicks;     // forecast 24h drift, in ticks (signed)
    Regime  regime;
    uint16  confidenceBps;  // 0..10_000
    uint40  updatedAt;
    bytes8  modelVersion;
}

function postSignal(PoolId poolId, uint32 sigmaTicks, int32 driftTicks, Regime regime,
                    uint16 confidenceBps, bytes8 modelVersion) external onlyUpdater;
function postSignals(PoolId[] calldata ids, Signal[] calldata s) external onlyUpdater; // batch
function getSignal(PoolId poolId) external view returns (Signal memory s, bool fresh);
function setUpdater(address) external onlyOwner;

event SignalPosted(PoolId indexed poolId, uint32 sigmaTicks, int32 driftTicks, Regime regime,
                   uint16 confidenceBps, bytes8 modelVersion, uint40 updatedAt);
error SignalOutOfBounds(); error NotUpdater();
```

Validation: `MIN_SIGMA_TICKS <= sigmaTicks <= MAX_SIGMA_TICKS`, `|driftTicks| <= MAX_DRIFT_TICKS`, `confidenceBps <= 10_000`. `fresh = block.timestamp - updatedAt <= MAX_SIGNAL_AGE`.

### 6.3 RangefyHook.sol

Extends `BaseHook` (`@uniswap/v4-periphery/src/utils/BaseHook.sol`), `Ownable2Step`.

**Permissions**

```solidity
Hooks.Permissions({
    beforeInitialize: true,   // require dynamic-fee pool, register pool
    afterInitialize:  true,   // seed oracle with initial tick
    beforeAddLiquidity: false, afterAddLiquidity: false,
    beforeRemoveLiquidity: false, afterRemoveLiquidity: false,
    beforeSwap: true,         // update oracle with pre-swap tick, return dynamic fee override
    afterSwap:  true,         // emit live pool state for the frontend/keeper
    beforeDonate: false, afterDonate: false,
    beforeSwapReturnDelta: false, afterSwapReturnDelta: false,
    afterAddLiquidityReturnDelta: false, afterRemoveLiquidityReturnDelta: false
})
```
Flags to mine: `BEFORE_INITIALIZE_FLAG | AFTER_INITIALIZE_FLAG | BEFORE_SWAP_FLAG | AFTER_SWAP_FLAG`.

**State**

```solidity
struct PoolState {
    int24   lastTick;        // tick at last oracle update
    int56   emaTickX1000;    // EMA tick scaled by 1000 for precision
    uint128 varPerSecWad;    // EWMA of (Δtick)^2 / Δt, WAD-scaled
    uint40  lastUpdate;
    bool    registered;
}

ISignalOracle public signalOracle;
mapping(PoolId => PoolState) public poolStates;
uint24[4] public regimeFee;           // pips per Regime; default [500, 3000, 7500, 15000]
uint32[3] public regimeThresholds;    // sigmaTicks boundaries for on-chain fallback; default [150, 400, 900]
```

**Callbacks**

- `_beforeInitialize(sender, key, sqrtPriceX96)`: revert `NotDynamicFee()` unless `LPFeeLibrary.isDynamicFee(key.fee)`; mark `registered`; emit `PoolRegistered(poolId, currency0, currency1, tickSpacing)`.
- `_afterInitialize(sender, key, sqrtPriceX96, tick)`: `lastTick = tick; emaTickX1000 = tick*1000; varPerSecWad = defaultVar; lastUpdate = now`. `defaultVar` corresponds to sigma 300 ticks/24h: `300^2 * WAD / 86400`.
- `_beforeSwap(sender, key, params, hookData)`:
  1. Read current (pre-swap) tick via `StateLibrary.getSlot0(poolManager, id)`.
  2. `VolatilityOracle.update(state, tick, block.timestamp)` (see §7.1).
  3. `fee = currentFee(id)` (see §7.2).
  4. Return `(selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG)`.
- `_afterSwap(...)`: read post-swap tick; emit `PoolStateUpdated(poolId, tick, emaTick(id), sigmaTicks(id), currentFee(id), regime)`. Return `(selector, 0)`.

**Views (used by vaults, lens, keeper)**

```solidity
function emaTick(PoolId) external view returns (int24);           // extrapolated to now with current spot tick
function onchainSigmaTicks(PoolId) external view returns (uint32); // sqrt(varPerSec * SIGMA_HORIZON)
function effectiveSigma(PoolId) external view returns (uint32 sigma, int32 drift, bool fromSignal);
function currentRegime(PoolId) external view returns (Regime);
function currentFee(PoolId) external view returns (uint24);
function getPoolState(PoolId) external view returns (PoolState memory);
```

`emaTick` view must extrapolate the EMA with the current spot tick (same formula as update but not stored) so a long gap without swaps does not leave a stale reference.

**Admin**: `setRegimeFees(uint24[4])` (each within `[MIN_FEE, MAX_FEE]`, non-decreasing), `setRegimeThresholds(uint32[3])` (increasing), `setSignalOracle(address)`.

**Events**: `PoolRegistered`, `PoolStateUpdated`, `RegimeFeesUpdated`, `RegimeThresholdsUpdated`.

### 6.4 CuratorRegistry.sol

```solidity
struct Curator { string name; string metadataURI; uint40 registeredAt; bool active; }
function register(string calldata name, string calldata metadataURI) external;  // name 3..32 chars, unique
function update(string calldata metadataURI) external;
function isCurator(address) external view returns (bool);
function getCurator(address) external view returns (Curator memory);
function allCurators() external view returns (address[] memory);
event CuratorRegistered(address indexed curator, string name, string metadataURI);
event CuratorUpdated(address indexed curator, string metadataURI);
```

`metadataURI` may be a `data:application/json;base64,...` URI (bio, avatar URL, strategy description) so no IPFS dependency is required.

### 6.5 VaultFactory.sol

```solidity
enum Profile { Aggressive, Balanced, Conservative, Custom }

struct StrategyParams {
    uint16 widthMultiplierBps;   // half-width = sigma * multiplier / 10_000
    int24  minHalfWidth;         // ticks
    int24  maxHalfWidth;         // ticks
    uint16 driftWeightBps;       // how much AI drift shifts the centre (0..5_000)
    uint32 minRebalanceInterval; // seconds
    int24  maxEmaDeviation;      // ticks; spot must be within this of EMA to deposit/rebalance
    uint16 performanceFeeBps;    // ≤ MAX_PERFORMANCE_FEE
}

function createVault(PoolKey calldata key, Profile profile, StrategyParams calldata custom,
                     string calldata name, string calldata symbol) external returns (address vault);
function presetParams(Profile) external pure returns (StrategyParams memory);
function validateParams(StrategyParams memory, int24 tickSpacing) public pure;
function allVaults() external view returns (address[] memory);
function vaultsOf(address curator) external view returns (address[] memory);
function vaultsForPool(PoolId) external view returns (address[] memory);
event VaultCreated(address indexed vault, address indexed curator, PoolId indexed poolId,
                   Profile profile, StrategyParams params, string name, string symbol);
```

Rules: caller must be an active curator; `key.hooks == hook`; pool must be `registered` in the hook; params validated:
- `5_000 <= widthMultiplierBps <= 50_000` (0.5σ .. 5σ)
- `MIN_HALF_WIDTH_FLOOR <= minHalfWidth <= maxHalfWidth <= MAX_HALF_WIDTH_CEIL`, both multiples of `tickSpacing`
- `driftWeightBps <= 5_000`
- `MIN_REBALANCE_INTERVAL_FLOOR <= minRebalanceInterval <= MAX_REBALANCE_INTERVAL`
- `0 < maxEmaDeviation <= MAX_EMA_DEVIATION_CEIL`
- `performanceFeeBps <= MAX_PERFORMANCE_FEE`

Presets (tick spacing 60):

| Profile | Multiplier | Min HW | Max HW | Drift wt | Min interval | Max EMA dev | Perf fee |
|---|---|---|---|---|---|---|---|
| Aggressive | 10_000 (1σ) | 120 | 3_000 | 3_000 | 5 min | 60 | 15% |
| Balanced | 20_000 (2σ) | 300 | 6_000 | 2_000 | 15 min | 90 | 10% |
| Conservative | 35_000 (3.5σ) | 600 | 12_000 | 1_000 | 1 h | 120 | 5% |

Deploy vaults with `new RangeVault(...)` (simplest; gas is irrelevant on testnet).

### 6.6 RangeVault.sol

ERC-20 shares (`@openzeppelin` ERC20, 18 decimals), `IUnlockCallback`, `ReentrancyGuard`. One concentrated position in the PoolManager owned by the vault (`owner = address(this)`, `salt = bytes32(0)`). Leftover tokens are held as plain ERC-20 "idle" balances in the vault.

**Immutable / state**

```solidity
IPoolManager public immutable poolManager;
IRangefyHook public immutable hook;
ISignalOracle  public immutable signalOracle;
address public immutable curator;
PoolKey public poolKey;       // stored, PoolId cached
StrategyParams public params;

int24  public tickLower;
int24  public tickUpper;
uint40 public lastRebalance;
bool   public depositsPaused;
uint256 public curatorOwed0;
uint256 public curatorOwed1;
uint256 public rebalanceCount;
```

**External API**

```solidity
// LP
function deposit(uint256 amount0Max, uint256 amount1Max, uint256 minShares, address to)
    external returns (uint256 shares, uint256 used0, uint256 used1);
function withdraw(uint256 shares, uint256 amount0Min, uint256 amount1Min, address to)
    external returns (uint256 amount0, uint256 amount1);
function previewDeposit(uint256 amount0Max, uint256 amount1Max)
    external view returns (uint256 shares, uint256 used0, uint256 used1);
function previewWithdraw(uint256 shares) external view returns (uint256 amount0, uint256 amount1);

// Keeper (permissionless)
function needsRebalance() external view returns (bool needed, RebalanceReason reason);
function rebalance() external returns (int24 newLower, int24 newUpper);
function harvest() external;        // collect fees, take perf fee, leave rest idle (compounded on next rebalance)

// Curator
function updateParams(StrategyParams calldata p) external onlyCurator; // perf fee may only decrease
function setDepositsPaused(bool) external onlyCurator;
function curatorRebalance() external onlyCurator; // ignores trigger reasons, still enforces cooldown + EMA guard
function claimCuratorFees(address to) external onlyCurator;

// Views
function getTotalAmounts() external view returns (uint256 total0, uint256 total1); // position@spot + idle + uncollected fees net of perf fee
function getPosition() external view returns (uint128 liquidity, int24 lower, int24 upper);
function idleBalances() external view returns (uint256 idle0, uint256 idle1);
function targetRange() external view returns (int24 lower, int24 upper, uint32 sigma, bool fromSignal);
function sharePrice() external view returns (uint256 priceInToken1Wad); // NAV/share at EMA price
```

```solidity
enum RebalanceReason { None, OutOfRange, NearEdge, WidthDrift, Initial }

event Deposit(address indexed sender, address indexed to, uint256 shares, uint256 amount0, uint256 amount1);
event Withdraw(address indexed sender, address indexed to, uint256 shares, uint256 amount0, uint256 amount1);
event Rebalanced(RebalanceReason reason, int24 oldLower, int24 oldUpper, int24 newLower, int24 newUpper,
                 uint128 newLiquidity, uint32 sigmaUsed, bool fromSignal, int24 spotTick, int24 emaTick);
event FeesCollected(uint256 fees0, uint256 fees1, uint256 curatorFee0, uint256 curatorFee1);
event Snapshot(uint256 total0, uint256 total1, uint256 totalSupply, int24 emaTick, uint40 timestamp);
event ParamsUpdated(StrategyParams params);
event DepositsPaused(bool paused);
event CuratorFeesClaimed(address to, uint256 amount0, uint256 amount1);

error DepositsArePaused(); error InsufficientShares(); error Slippage(); error PriceDeviation();
error Cooldown(); error NoRebalanceNeeded(); error OnlyCurator(); error OnlyPoolManager(); error ZeroAmount();
```

`Snapshot` is emitted after every deposit, withdraw, rebalance and harvest — it is the time series the frontend uses for share-price and leaderboard charts.

**Unlock callback actions** — `poolManager.unlock(abi.encode(Action, payload))`, dispatched in `unlockCallback` (revert `OnlyPoolManager` if `msg.sender != poolManager`):

| Action | Payload | Steps |
|---|---|---|
| `DEPOSIT` | `(user, fraction or initial amounts)` | collect fees → add liquidity → settle from user |
| `WITHDRAW` | `(to, shares, supplyBefore)` | collect fees → remove pro-rata liquidity → take to `to` |
| `REBALANCE` | `(reason)` | collect + remove all → perf fee → optional swap to target ratio → add new range → settle/take net |
| `HARVEST` | — | collect fees (zero-delta modify) → perf fee → take to vault |

Settlement helper (use in every action, at the end of the callback):

```solidity
function _settleNet(Currency c, address payer) internal {
    int256 d = TransientStateLibrary.currencyDelta(poolManager, address(this), c);
    if (d < 0) {                              // vault owes the PoolManager
        poolManager.sync(c);
        if (payer == address(this)) IERC20(Currency.unwrap(c)).safeTransfer(address(poolManager), uint256(-d));
        else IERC20(Currency.unwrap(c)).safeTransferFrom(payer, address(poolManager), uint256(-d));
        poolManager.settle();
    } else if (d > 0) {                       // PoolManager owes the vault
        poolManager.take(c, address(this), uint256(d));
    }
}
```
Native ETH is out of scope: both pool currencies are ERC-20s.

### 6.7 SimpleSwapRouter.sol

Minimal router used by the frontend Swap page and the mirror bot (avoids Universal Router encoding complexity on testnet):

```solidity
function swapExactIn(PoolKey calldata key, bool zeroForOne, uint256 amountIn, uint256 amountOutMin,
                     address to, uint256 deadline) external returns (uint256 amountOut);
function swapToPrice(PoolKey calldata key, uint160 sqrtPriceLimitX96, uint256 maxAmountIn,
                     address to) external returns (int256 amount0, int256 amount1); // used by mirror bot
```
Implements `unlockCallback`: `poolManager.swap(key, SwapParams({zeroForOne, amountSpecified: -int256(amountIn), sqrtPriceLimitX96}), "")`, then settles the negative side from `msg.sender` (via `transferFrom`) and takes the positive side to `to`. `sqrtPriceLimitX96` for `swapExactIn` is `TickMath.MIN_SQRT_PRICE + 1` / `MAX_SQRT_PRICE - 1`.

### 6.8 RangefyLens.sol

Read-only aggregator to keep the frontend to one RPC call per screen:

```solidity
struct VaultView {
    address vault; address curator; string curatorName; string name; string symbol;
    StrategyParams params; int24 tickLower; int24 tickUpper; uint128 liquidity;
    uint256 total0; uint256 total1; uint256 totalSupply; uint256 sharePriceWad;
    uint40 lastRebalance; uint256 rebalanceCount; bool depositsPaused;
    bool needsRebalance; uint8 reason; bool inRange;
}
struct PoolView {
    PoolId id; uint160 sqrtPriceX96; int24 tick; int24 emaTick; uint32 sigma; int32 drift;
    bool signalFresh; uint8 regime; uint24 fee; uint128 poolLiquidity;
}
function getPool(PoolKey calldata) external view returns (PoolView memory);
function getVault(address) external view returns (VaultView memory);
function getAllVaults() external view returns (VaultView[] memory);
function getUserPositions(address user) external view returns (address[] memory vaults, uint256[] memory shares,
                                                                uint256[] memory amount0, uint256[] memory amount1);
```

### 6.9 MockERC20.sol

OpenZeppelin ERC20 with configurable decimals and a rate-limited faucet:

```solidity
constructor(string memory name, string memory symbol, uint8 decimals, uint256 faucetAmount);
function faucet() external;                 // mints faucetAmount to msg.sender, once per 24h per address
function mint(address to, uint256) external onlyOwner;  // for scripts / bots
```
Tokens: `mWETH` (18 decimals, faucet 5 mWETH) and `mUSDC` (6 decimals, faucet 20,000 mUSDC).

---

## 7. Core Algorithms (exact math)

Notation: `t` = tick, `s` = tickSpacing (60), `clamp(x,a,b)`, `floorTo(x,s)` rounds toward −∞ to a multiple of `s`, `ceilTo` toward +∞.

### 7.1 Volatility oracle update (hook, every `beforeSwap`)

Inputs: stored state, pre-swap tick `t`, `now`.

```
dt = now - lastUpdate
if dt == 0: return                                    // once per block per pool; first swap in a block wins
alphaWad = min(dt * WAD / EMA_WINDOW, WAD)
emaTickX1000 += alphaWad * (t*1000 - emaTickX1000) / WAD

move      = t - lastTick
sampleWad = move^2 * WAD / dt                         // variance per second for this interval
betaWad   = min(dt * WAD / VAR_WINDOW, WAD)
varPerSecWad += betaWad * (sampleWad - varPerSecWad) / WAD     // signed math, then cast

lastTick = t; lastUpdate = now
```

Why this is manipulation-resistant: the EMA only ever absorbs the **pre-swap** tick, weighted by elapsed time. Moving the price and reading the EMA in the same block does not change it, so a sandwich around `deposit()`/`rebalance()` is caught by the EMA-deviation guard.

`onchainSigmaTicks = sqrt(varPerSecWad * SIGMA_HORIZON / WAD)`, clamped to `[MIN_SIGMA_TICKS, MAX_SIGMA_TICKS]`.

### 7.2 Effective sigma, regime and fee

```
(signal, fresh) = signalOracle.getSignal(id)
if fresh:  sigma = signal.sigmaTicks; drift = signal.driftTicks; regime = signal.regime
else:      sigma = onchainSigmaTicks; drift = 0
           regime = Calm if sigma < th[0], Normal if < th[1], High if < th[2], else Extreme

// Safety floor: never trust the AI to be calmer than the chain shows right now
regimeOnchain = regime from onchainSigmaTicks
regime = max(regime, regimeOnchain - 1)

fee = regimeFee[regime]          // default 500 / 3000 / 7500 / 15000 pips
```

### 7.3 Target range (vault, view `targetRange()`)

```
(sigma, drift, fromSignal) = hook.effectiveSigma(id)
halfWidth = clamp(ceilTo(sigma * widthMultiplierBps / 10_000, s), minHalfWidth, maxHalfWidth)
bias      = clamp(drift * driftWeightBps / 10_000, -halfWidth/2, +halfWidth/2)
center    = hook.emaTick(id) + bias
lower     = floorTo(center - halfWidth, s)
upper     = ceilTo(center + halfWidth, s)
lower, upper clamped to [TickMath.minUsableTick(s), TickMath.maxUsableTick(s)]
```

### 7.4 Rebalance trigger (`needsRebalance()`)

Pre-conditions (all must hold, else `(false, None)`):
- `liquidity > 0` or vault has idle balances
- `now >= lastRebalance + minRebalanceInterval`
- `|spotTick - emaTick| <= maxEmaDeviation`

Reasons, checked in this order:
1. `OutOfRange` — `spot < tickLower || spot >= tickUpper`
2. `NearEdge` — `spot < tickLower + w*EDGE_BUFFER_BPS/10_000 || spot >= tickUpper - w*EDGE_BUFFER_BPS/10_000`, where `w = tickUpper - tickLower`
3. `WidthDrift` — `|targetHalfWidth - currentHalfWidth| * 10_000 >= currentHalfWidth * WIDTH_DRIFT_BPS`
4. `Initial` — position has zero liquidity but idle balances exist

`rebalance()` reverts `NoRebalanceNeeded` / `Cooldown` / `PriceDeviation` accordingly. `curatorRebalance()` skips the reason check only.

### 7.5 Rebalance execution (inside `unlockCallback`)

```
1. if liquidity > 0:
       (callerDelta, feesAccrued) = modifyLiquidity(lower, upper, -liquidity)     // removes + collects fees
       curatorFee_i = feesAccrued_i * performanceFeeBps / 10_000
       curatorOwed_i += curatorFee_i
2. Available amounts (in PoolManager-credit + vault-held terms):
       A0 = idle0 + callerDelta.amount0 - curatorFee0        // idle excludes curatorOwed
       A1 = idle1 + callerDelta.amount1 - curatorFee1
3. (newLower, newUpper) = targetRange()
4. Ratio swap:
       P = spot price token1/token0 from sqrtPriceX96 (WAD)
       (x, y) = LiquidityAmounts.getAmountsForLiquidity(sqrtP, sqrtA, sqrtB, 1e18)
       V = A0*P + A1                                            // value in token1
       target0 = (x + y == 0) ? 0 : V * x / (x*P + y)           // token0 needed at target ratio
       if A0 > target0 * 1.005:   swap token0→token1, exactIn = (A0 - target0), zeroForOne = true
       elif A0 < target0 * 0.995: swap token1→token0, exactIn = (target0 - A0) * P, zeroForOne = false
       sqrtPriceLimitX96 = sqrtPrice at (emaTick ∓ MAX_SWAP_SLIPPAGE_BPS ticks) // stops at limit, never reverts
       update A0, A1 with the swap delta
       (if a range is entirely above/below spot, x or y is 0 and the whole balance swaps to one side)
5. L = LiquidityAmounts.getLiquidityForAmounts(sqrtP_afterSwap, sqrtA, sqrtB, A0, A1)
   modifyLiquidity(newLower, newUpper, +L)
6. _settleNet(currency0, vault); _settleNet(currency1, vault)   // leftovers become idle ERC-20 balances
7. tickLower/Upper = new; lastRebalance = now; rebalanceCount++; emit Rebalanced, FeesCollected, Snapshot
```

The vault's own swap passes through the hook (fee applies, EMA updates) — that is fine and expected. The vault is not the hook, so hook callbacks are not skipped.

### 7.6 Deposit math (price-independent proportional minting)

```
1. Collect fees first (zero-delta modifyLiquidity if liquidity > 0), apply perf fee, take rest to vault as idle.
   → accrued fees belong to existing holders, not the depositor.
2. Guard: |spot - emaTick| <= maxEmaDeviation, depositsPaused == false.
3. If totalSupply == 0 (first deposit):
       (lower, upper) = targetRange()   (store them)
       L = getLiquidityForAmounts(sqrtP, lower, upper, amount0Max, amount1Max)
       shares = L;  mint MIN_SHARES to 0x…dEaD, mint shares - MIN_SHARES to `to`
   Else:
       (p0, p1) = getAmountsForLiquidity(sqrtP, lower, upper, totalLiquidity)   // rounded up
       cost0 = p0 + idle0;  cost1 = p1 + idle1                                   // whole-vault composition
       f = min(cost0 == 0 ? ∞ : amount0Max*WAD/cost0, cost1 == 0 ? ∞ : amount1Max*WAD/cost1)
       ΔL = totalLiquidity * f / WAD
       shares = totalSupply * f / WAD
       idleIn_i = idle_i * f / WAD (round up)
4. modifyLiquidity(lower, upper, +ΔL) → settle negative deltas with transferFrom(user → PoolManager)
   transferFrom(user → vault, idleIn_i)
5. used_i = liquidity cost_i + idleIn_i; require used_i <= amount_iMax; require shares >= minShares
6. mint shares; emit Deposit, Snapshot
```

### 7.7 Withdraw math

```
1. Collect fees (as in deposit step 1).
2. ΔL = liquidity * shares / totalSupply
   out_i(idle) = idle_i * shares / totalSupply
3. burn shares (after computing with pre-burn supply)
4. modifyLiquidity(lower, upper, -ΔL) → take positive deltas directly to `to`
   transfer idle portion vault → `to`
5. require amount_i >= amount_iMin; emit Withdraw, Snapshot
```
Withdraw has **no** price-deviation guard and is never pausable — LPs can always exit.

### 7.8 NAV, share price, performance

```
priceWad (token1 per token0, decimal-adjusted) from emaTick
NAV_token1 = total0 * priceWad / 10^dec0 * 10^dec1 / WAD + total1
sharePriceWad = NAV_token1 * 1e18 / totalSupply
```

Leaderboard metric (computed off-chain in the frontend from `Snapshot` events):
- **Vault return** = sharePrice(now) / sharePrice(at creation) − 1
- **HODL return** = value now of the token amounts at the first deposit, divided by their value then − 1
- **Alpha vs HODL** = vault return − HODL return (primary rank key)
- Secondary: fees APR (sum of `FeesCollected` in token1 over the window, annualised over TVL), time-in-range % (from `PoolStateUpdated` ticks vs the vault range history), rebalance count.

---

## 8. End-to-End Flows

### 8.1 Protocol bootstrap (once, by deployer)

```
00_DeployTokens   → mWETH, mUSDC
01_DeployCore     → SignalOracle(updater = AI EOA)
                  → CuratorRegistry
                  → RangefyHook (CREATE2 via HookMiner, flags as §6.3)
                  → VaultFactory(hook, registry, signalOracle, poolManager)
                  → SimpleSwapRouter(poolManager), RangefyLens
02_InitPool       → PoolKey{currency0,currency1 sorted, fee: DYNAMIC_FEE_FLAG, tickSpacing: 60, hooks: hook}
                  → poolManager.initialize(key, sqrtPriceX96 from ETH_PRICE env)
                  → background liquidity via PoolModifyLiquidityTest (±20% range, 50 mWETH + matching mUSDC)
03_SeedCurators   → 3 curator EOAs register ("Atlas" Conservative, "Harbor" Balanced, "Vector" Aggressive)
                  → each creates a vault and makes a first deposit
```

### 8.2 Curator creates a vault

```
Curator ── register(name, metadataURI) ─► CuratorRegistry
Curator ── createVault(key, profile, params, name, symbol) ─► VaultFactory
                                     validate params, check hook pool registration
                                     new RangeVault(...)  ─► emit VaultCreated
Frontend shows vault in /vaults with "Awaiting first deposit"
```

### 8.3 LP deposits

```
LP ─ approve(mWETH, vault), approve(mUSDC, vault)
LP ─ previewDeposit(a0Max, a1Max) (view)  → UI shows shares + exact used amounts
LP ─ deposit(a0Max, a1Max, minShares = preview * 0.99, LP)
      vault ─ unlock(DEPOSIT)
              PoolManager ─► vault.unlockCallback
                 collect fees (zero-delta) → perf fee → idle
                 guard EMA deviation
                 modifyLiquidity(+ΔL)  (no hook call: add-liquidity callbacks disabled)
                 _settleNet(c0, LP), _settleNet(c1, LP)
              transferFrom(LP → vault, idle portion)
      mint shares → emit Deposit, Snapshot
```

### 8.4 Market moves → AI signal → fee changes

```
mirror_job: real ETH/USD moves 1.2% → swapToPrice on testnet pool
   PoolManager.swap → hook.beforeSwap: oracle update, fee = regimeFee[regime]
                    → hook.afterSwap: emit PoolStateUpdated(tick, ema, sigma, fee, regime)
signal_job (60s): candles + on-chain features → model → sigma=520 ticks, drift=+80, regime=High
   if changed ≥10% or regime changed or heartbeat 10 min → SignalOracle.postSignal(...)
Next swap uses High-regime fee (0.75%) → LPs paid more during volatility
```

### 8.5 Keeper rebalances

```
rebalance_job (every 15s):
  vaults = factory.allVaults()
  for v in vaults: (needed, reason) = v.needsRebalance()   // multicall
     if needed: send v.rebalance()  (gas estimate first; skip on revert, log reason)
vault.rebalance():
  re-check conditions → unlock(REBALANCE) → §7.5 → emit Rebalanced, FeesCollected, Snapshot
Frontend (event watcher) animates range bands moving to the new position
```

### 8.6 LP withdraws

```
LP ─ previewWithdraw(shares) → withdraw(shares, min0, min1, LP)
     vault ─ unlock(WITHDRAW): collect fees → remove ΔL → take to LP; transfer idle share to LP
     burn → emit Withdraw, Snapshot
```

### 8.7 Failure / fallback paths (must be demoable)

| Situation | Behaviour |
|---|---|
| AI engine offline > 15 min | Signal stale → hook and vaults use on-chain sigma; fee from on-chain regime. UI shows "Signal stale — on-chain fallback" |
| Keeper offline | Anyone can press "Rebalance" in the vault UI when `needsRebalance` is true |
| Price manipulated in same block | `PriceDeviation` revert on deposit/rebalance |
| Curator wants to rug | No function moves LP funds to the curator; perf fee capped and only decreasable |
| Rebalance swap would move price too far | Swap stops at `sqrtPriceLimitX96`; leftover stays idle; next rebalance continues |

---

## 9. AI Engine and Keeper

Python 3.11. The AI engine forecasts volatility and short-term drift for Rangefy pools and publishes signals for on-chain range sizing.

### 9.1 Data

- **Training data:** ETH-USD 1-minute candles, last 2 years. Sources (no API key): Coinbase Exchange `GET https://api.exchange.coinbase.com/products/ETH-USD/candles?granularity=60&start=..&end=..` (max 300 candles per call) or Binance `GET https://api.binance.com/api/v3/klines?symbol=ETHUSDT&interval=1m&limit=1000`. `scripts/fetch_history.py` pages through and writes `data/raw/ethusd_1m.parquet`.
- **Live data:** the same endpoints polled every 60s for the latest 1440 candles; plus on-chain pool features from `PoolStateUpdated` events (swap count, mean |Δtick|, current fee, vault TVL).

### 9.2 Features (per minute, computed on a rolling window)

| Group | Features |
|---|---|
| Returns | log returns over 1m, 5m, 15m, 1h, 4h, 24h |
| Realized vol | std of 1m log returns over 15m, 1h, 6h, 24h, 7d (annualised and per-24h) |
| Range vol | Parkinson (high/low) vol over 1h, 6h, 24h |
| Volume | volume z-score vs 24h and 7d means |
| Seasonality | sin/cos hour-of-day, day-of-week |
| On-chain (live only, zero-filled in training) | testnet swaps per minute, mean abs tick move |

Sequence input for the Transformer: last 240 minutes × feature vector. Tabular input for the RF: the latest feature row plus summary statistics.

### 9.3 Labels

- `sigma24h` = std(1m log returns over the **next** 1440 minutes) × sqrt(1440), converted to ticks: `sigmaTicks = sigma24h / ln(1.0001)` (≈ sigma × 10,000).
- `drift24h` = log(close[t+1440] / close[t]) in ticks (clipped to ±2000).
- `regime` = quantile bucket of `sigmaTicks` on the training set: Calm < 30th pct, Normal 30–70, High 70–95, Extreme > 95. Store the bucket edges; they become `regimeThresholds` in the hook so on-chain fallback and AI agree.

### 9.4 Models

| Model | Output | Notes |
|---|---|---|
| EWMA baseline (λ = 0.94 on 1h returns) | sigma | Must be beaten, reported in README |
| Random Forest (scikit-learn, 300 trees, max_depth 12) | log sigma, drift | Tabular features |
| Transformer (PyTorch: 2 layers, 4 heads, d_model 64, dropout 0.1) | log sigma, drift | Sequence features, Huber loss |
| Ensemble | weighted mean in log space (weights fit on validation, default 0.5/0.5) | Regime derived from ensemble sigma via stored edges |

Train/validation/test split is chronological (70/15/15), no shuffling. Metrics: MAE in ticks, QLIKE for variance, regime accuracy, and **LP backtest**.

`training/backtest_lp.py`: simulate a vault on the test period with 1-minute prices — fixed ±600-tick range vs AI-sized range (Balanced profile) — fees earned = time-in-range × assumed volume × fee tier, minus impermanent loss and rebalance swap cost. Output a table and chart for the README.

Confidence: `confidenceBps = 10_000 × (1 − clamp(|σ_RF − σ_TF| / σ_ens, 0, 1))`.

### 9.5 Keeper jobs (`keeper/scheduler.py`, APScheduler or asyncio loop)

| Job | Interval | Logic |
|---|---|---|
| `signal_job` | 60s | Build features → ensemble forecast → post if `|Δsigma|/sigma ≥ 10%` or regime changed or 10 min since last post. Clamp to contract bounds. Persist to SQLite |
| `rebalance_job` | 15s | Multicall `needsRebalance()` over `factory.allVaults()`; for each `true`, `estimate_gas` then send `rebalance()`; record tx hash, reason, gas |
| `harvest_job` | 1h | `harvest()` on vaults with liquidity and no rebalance in the last hour |
| `mirror_job` | 20s | Get real ETH-USD mid price; compute testnet pool price from `sqrtPriceX96`; if deviation > 0.3%, call `SimpleSwapRouter.swapToPrice` with the target `sqrtPriceLimitX96` and a `maxAmountIn` budget (default 2 mWETH or 6,000 mUSDC per call). Mirror wallet is minted tokens by the deployer |
| `noise_job` (optional) | 30–90s random | Small random swaps (0.01–0.2 mWETH) both directions to generate fee volume for the demo |

Transaction handling: one nonce manager per key, EIP-1559 fees, 3 retries with fee bump, never send two txs to the same vault concurrently. Separate keys: `SIGNAL_UPDATER_KEY`, `KEEPER_KEY`, `MIRROR_KEY`.

### 9.6 API (FastAPI, port 8000, CORS for the frontend origin)

| Method | Path | Returns |
|---|---|---|
| GET | `/health` | status, model version, last job runs |
| GET | `/signal/latest?poolId=` | latest forecast + whether posted on-chain + tx hash |
| GET | `/signal/history?poolId=&hours=24` | time series of sigma, drift, regime, confidence |
| GET | `/forecast` | live ensemble breakdown: EWMA, RF, Transformer, ensemble |
| GET | `/keeper/status` | last rebalances, harvests, failures |
| GET | `/mirror/status` | real price, testnet price, deviation, last mirror tx |
| GET | `/model/backtest` | backtest summary (from training run JSON) |

---

## 10. Frontend

Next.js 16 App Router, TypeScript, Tailwind v4, wagmi v2 + viem + RainbowKit, TanStack Query, zustand, Recharts, sonner, lucide-react, next-themes. Configure the app for Unichain Sepolia (`1301`) and connect it to the Rangefy contracts and AI API.

### 10.1 Data strategy (real-time)

- **Live state:** `RangefyLens.getAllVaults()` / `getPool()` via `useReadContract` with `refetchInterval: 4000` and refetch on every watched event.
- **Events:** `useWatchContractEvent` on hook `PoolStateUpdated`, vault `Rebalanced`, `Deposit`, `Withdraw`, `Snapshot`, oracle `SignalPosted` → toast + invalidate queries.
- **History:** `publicClient.getLogs` from `DEPLOY_BLOCK` in 10,000-block chunks, cached in zustand + `sessionStorage`; then incremental from the last seen block.
- **AI data:** fetch `NEXT_PUBLIC_AI_API_URL` endpoints with TanStack Query (30s). If unreachable, show on-chain signal only.

### 10.2 Pages

| Route | Purpose | Key components |
|---|---|---|
| `/` | Landing + live protocol stats | `Hero`, `StatsBar` (TVL, vaults, curators, regime, current fee, real vs testnet ETH), `HowItWorks`, `TopVaults` |
| `/vaults` | Browse vaults | `VaultFilters` (profile, sort by alpha/TVL/APR), `VaultCard` grid |
| `/vaults/[address]` | Vault detail | `RangeChart`, `VaultStats`, `DepositWithdrawPanel`, `StrategyCard`, `RebalanceHistory`, `RebalanceButton` |
| `/curate` | Become curator, create vault | `CuratorRegisterForm`, `ProfilePicker`, `ParamSliders`, `RangePreview` (live target range from current sigma), `CreateVaultButton` |
| `/curators` | Leaderboard | `LeaderboardTable` (alpha vs HODL, APR, TVL, time-in-range, rebalances), `CuratorProfileDrawer` |
| `/curators/[address]` | Curator profile | vaults, combined performance, curator fees, claim button (own profile) |
| `/ai` | AI signal transparency | `RegimeBadge`, `SigmaChart` (forecast vs realized), `ModelBreakdown`, `BacktestCard`, `SignalFeed` |
| `/swap` | Generate fees / test | `SwapCard` using `SimpleSwapRouter` (shows current dynamic fee) |
| `/faucet` | Get test tokens | `FaucetCard` for mWETH, mUSDC, link to Unichain Sepolia ETH faucet |
| `/portfolio` | My positions | `getUserPositions` table, per-vault P&L vs HODL |

### 10.3 Wireframes

**Vault detail**
```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ← Vaults   Harbor · Balanced · mWETH/mUSDC            [In range ●] [Regime: High]│
├──────────────────────────────────────────────┬───────────────────────────────┤
│ RangeChart (24h | 7d | All)                  │  Deposit | Withdraw            │
│  price line (testnet) + dotted real price    │  mWETH  [ 1.00      ] MAX       │
│  shaded band = vault range over time         │  mUSDC  [ 3,050.12  ] MAX       │
│  markers ◆ = rebalances (hover: reason)      │  You receive ≈ 1,204.3 rfHRB    │
│                                              │  Uses 1.00 mWETH / 3,041 mUSDC  │
│                                              │  [ Approve mWETH ] [ Deposit ]  │
├──────────────┬──────────────┬────────────────┤  Your position: 0.82 mWETH +    │
│ TVL $124,300 │ Alpha +2.4%  │ Fee APR 31.2%  │  2,511 mUSDC  (P&L vs HODL +1.1%)│
│ Share +5.8%  │ In range 94% │ Rebalances 17  ├───────────────────────────────┤
├──────────────┴──────────────┴────────────────┤  Strategy                      │
│ Rebalance history                            │  2.0σ width · 300–6000 ticks    │
│ time   reason     old range → new range  σ   │  drift weight 20% · 15m cooldown│
│ 14:02  NearEdge   2980–3120 → 3010–3160  412 │  perf fee 10% · AI signal: fresh│
│ ...                                          │  Next target: 3,020–3,170       │
│                         [Rebalance now] (enabled only when needsRebalance)    │
└──────────────────────────────────────────────┴───────────────────────────────┘
```

**Curate**
```
┌───────────────────────────────────────────────────────────────┐
│ Step 1  Register as curator   Name [ Harbor ]  Bio [ ... ]  [Register]│
│ Step 2  Choose profile  ( Aggressive )( ● Balanced )( Conservative )( Custom )│
│ Step 3  Tune parameters (sliders, bounded by factory limits)   │
│   Width multiplier 2.0σ  ───●────   Min/Max half-width 300/6000│
│   Drift weight 20%  ─●──   Cooldown 15m ─●─   Perf fee 10% ─●─ │
│ RangePreview: current price, target range at today's σ,        │
│   what range would have looked like over last 24h              │
│ Step 4  Name & symbol [ Harbor Balanced ] [ rfHRB ]  [Create vault]│
└───────────────────────────────────────────────────────────────┘
```

### 10.4 Hooks (`src/hooks/`)

`usePool`, `useVaults`, `useVault(address)`, `useVaultHistory(address)` (Snapshot + Rebalanced logs), `usePoolHistory` (PoolStateUpdated logs), `useSignal`, `useAIForecast`, `useDeposit`, `useWithdraw`, `useRebalance`, `useCurator`, `useCreateVault`, `useFaucet`, `useSwap`, `useUserPositions`, `useTokenApproval`.

Every write hook: simulate (`useSimulateContract`) → write → `waitForTransactionReceipt` → sonner toast with Uniscan link → invalidate queries. Map custom errors (`PriceDeviation`, `Cooldown`, `Slippage`, `DepositsArePaused`) to human messages.

### 10.5 Tick/price helpers (`lib/math.ts`)

```ts
price(tick) = 1.0001 ** tick * 10 ** (dec0 - dec1)          // token1 per token0
if token0 is mUSDC, invert so the UI always shows mUSDC per mWETH
tickFromPrice(p) = Math.log(p / 10 ** (dec0 - dec1)) / Math.log(1.0001)
```

---

## 11. Design System

Rangefy uses Uniswap pink as its primary accent and teal for "in range" states.

| Token | Light | Dark | Use |
|---|---|---|---|
| `--background` | `#fafafa` | `#09090b` | page |
| `--card` | `#ffffff` | `#111114` | panels |
| `--border` | `#e5e7eb` | `#1f1f2e` | dividers |
| `--foreground` | `#171717` | `#f4f4f5` | text |
| `--muted` | `#6b7280` | `#a1a1aa` | secondary text |
| `--accent` | `#FF007A` | `#FF007A` | primary actions, brand |
| `--range` | `#14b8a6` | `#2dd4bf` | in-range band, "healthy" |
| `--success` / `--warning` / `--danger` | `#22c55e` / `#eab308` / `#ef4444` | `#4ade80` / `#facc15` / `#f87171` | states |
| Regime colours | Calm `#38bdf8`, Normal `#a3a3a3`, High `#f59e0b`, Extreme `#ef4444` | same | regime badge, chart background tint |

- Fonts: Inter (UI), JetBrains Mono (numbers, ticks, addresses), `tabular-nums` everywhere numbers update live.
- Dark mode default, toggle via next-themes.
- Layout: max width 1200px, 16px gutters on mobile, single column under 768px (deposit panel moves below the chart).
- Motion: range band transitions 400ms ease-out on rebalance; number changes flash `--range` for 600ms.
- Accessibility: all states have text labels, not colour only; focus rings on all controls; charts have a table fallback.

### Brand and Logo

**Name:** Rangefy, the verb for what the product does: it "rangefies" your liquidity, keeping it in the right range. Tagline: *Liquidity that stays in range.*

**Logo concept: "The Bracket and the Pulse"**
The mark shows the core idea in one glance: a price line moving through a liquidity range that adjusts to follow it.

- **Two range brackets:** rounded vertical bars on the left and right in teal (`--range`). They stand for the vault's lower and upper ticks. The right bracket sits slightly higher than the left, showing that the range has just re-centred toward the price.
- **The price pulse:** a smooth pink (`--accent`) wave that enters from the left, rises through the middle and exits right. It is the market price.
- **The current-price dot:** a solid pink dot where the wave crosses the centre of the range, meaning "in range, right now".
- **The shape as a whole** reads as a stylised "R" turned on its side or a heartbeat inside a frame, so it's memorable even at 16px.

**Construction**
- 64 × 64 grid, 6px corner radius on the brackets, 4px stroke on the wave at full size (2px at favicon size).
- Brackets: 8 × 40, at x = 8 and x = 48; the right one is offset 4px up.
- Wave: cubic curve from (4, 40) through (32, 30) to (60, 22); dot of radius 5 at (32, 30).
- Keep clear space around the mark equal to one bracket width (8 units).

**Wordmark**
- "Rangefy" set in Inter Bold (or Satoshi Bold as an alternative), letter spacing −2%.
- "Range" in `--foreground`, "fy" in `--accent`: the pink shows the action, the "-fy".
- Lockup: mark on the left, wordmark on the right, with a gap equal to 0.5× the mark's height.

**Colours**
| Element | Colour |
|---|---|
| Brackets | Teal `#14b8a6` (light) / `#2dd4bf` (dark) |
| Price wave + dot | Pink `#FF007A` |
| Wordmark "Range" | `#171717` (light) / `#f4f4f5` (dark) |
| Monochrome version | All white on dark, all `#171717` on light |

**Variants**
- Full lockup (mark + wordmark): site header, README banner, demo video.
- Mark only: favicon, app icon, social avatar (on a `#09090b` rounded square).
- Monochrome: watermarks, slides, single-colour prints.

**Don'ts:** don't rotate the mark, swap the bracket and wave colours, add gradients or shadows, or stretch it.

**Starter SVG** (`frontend/public/logo-mark.svg`):
```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64" role="img" aria-label="Rangefy">
  <rect x="8"  y="14" width="8" height="40" rx="4" fill="#2dd4bf"/>
  <rect x="48" y="10" width="8" height="40" rx="4" fill="#2dd4bf"/>
  <path d="M4 40 C 16 40, 22 30, 32 30 S 48 22, 60 22" fill="none" stroke="#FF007A" stroke-width="4" stroke-linecap="round"/>
  <circle cx="32" cy="30" r="5" fill="#FF007A"/>
</svg>
```
A designer can refine curves and spacing; the SVG is the reference for proportions and colours.

---

## 12. Configuration and Environment

### 12.1 Network — Unichain Sepolia (1301)

RPC `https://sepolia.unichain.org` · Explorer `https://sepolia.uniscan.xyz` · Faucet: Unichain Sepolia faucets listed at docs.unichain.org.

Uniswap v4 canonical deployments (**verify each against https://docs.uniswap.org/contracts/v4/deployments before deploying**):

| Contract | Address |
|---|---|
| PoolManager | `0x00B036B58a818B1BC34d502D3fE730Db729e62AC` |
| PositionManager | `0xf969Aee60879C54bAAed9F3eD26147Db216Fd664` |
| StateView | `0xc199F1072a74D4e905ABa1A84d9a45E2546B6222` |
| PoolSwapTest | `0x9140a78c1A137c7fF1c151EC8231272aF78a99A4` |
| PoolModifyLiquidityTest | `0x5fa728C0A5cfd51BEe4B060773f50554c0C8A7AB` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| CREATE2 Deployer | `0x4e59b44847b379578588920cA78FbF26c0B4956C` |

### 12.2 `contracts/.env`

```
UNICHAIN_SEPOLIA_RPC_URL=https://sepolia.unichain.org
PRIVATE_KEY=0x...                 # deployer / owner
POOL_MANAGER=0x00B036B58a818B1BC34d502D3fE730Db729e62AC
POOL_MODIFY_LIQUIDITY_TEST=0x5fa728C0A5cfd51BEe4B060773f50554c0C8A7AB
SIGNAL_UPDATER=0x...              # AI engine EOA
KEEPER=0x...
MIRROR=0x...
ETH_PRICE_USD=3000                # initial pool price
CURATOR_ATLAS_KEY=0x...  CURATOR_HARBOR_KEY=0x...  CURATOR_VECTOR_KEY=0x...
ETHERSCAN_API_KEY=...             # Uniscan/Blockscout verification
```

### 12.3 `ai-engine/.env`

```
RPC_URL=https://sepolia.unichain.org
CHAIN_ID=1301
SIGNAL_UPDATER_KEY=0x...
KEEPER_KEY=0x...
MIRROR_KEY=0x...
SIGNAL_ORACLE=0x...  HOOK=0x...  FACTORY=0x...  ROUTER=0x...  LENS=0x...
TOKEN0=0x...  TOKEN1=0x...  POOL_TICK_SPACING=60
PRICE_SOURCE=coinbase             # or binance
MIRROR_DEVIATION_BPS=30
MIRROR_MAX_IN_TOKEN0=2000000000000000000
ENABLE_NOISE=true
API_CORS_ORIGINS=http://localhost:3000,https://rangefy.vercel.app
MODEL_DIR=data/models
DB_PATH=data/rangefy.db
```

### 12.4 `frontend/.env.local`

```
NEXT_PUBLIC_UNICHAIN_RPC_URL=https://sepolia.unichain.org
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=...
NEXT_PUBLIC_AI_API_URL=http://localhost:8000
NEXT_PUBLIC_DEPLOY_BLOCK=...
```
Contract addresses live in `frontend/src/config/addresses.ts`, generated by `scripts/sync-abis.sh` from `contracts/broadcast/*/1301/run-latest.json`.

---

## 13. Deployment Runbook (Unichain Sepolia)

```bash
# 0. Tooling
foundryup && node -v (20+) && python3.11 -V
# Fund deployer, updater, keeper, mirror and 3 curator EOAs with Unichain Sepolia ETH (≥0.05 each)

# 1. Contracts
cd contracts && forge install && forge build && forge test
forge script script/00_DeployTokens.s.sol  --rpc-url unichain_sepolia --broadcast --verify
forge script script/01_DeployCore.s.sol    --rpc-url unichain_sepolia --broadcast --verify
forge script script/02_InitPool.s.sol      --rpc-url unichain_sepolia --broadcast
forge script script/03_SeedCurators.s.sol  --rpc-url unichain_sepolia --broadcast

# 2. ABIs + addresses → frontend and ai-engine
cd .. && ./scripts/sync-abis.sh

# 3. AI engine
cd ai-engine && python3.11 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python scripts/fetch_history.py --days 730
python scripts/train_model.py            # writes data/models/*, regime edges, backtest JSON
python scripts/run_keeper.py &           # signal, rebalance, harvest, mirror jobs
uvicorn src.server.app:app --port 8000

# 4. Frontend
cd ../frontend && npm install && npm run dev   # then deploy to Vercel
```

`02_InitPool` details:
- Sort tokens: `currency0 = min(mWETH, mUSDC)`.
- Price `p` = mUSDC per mWETH = `ETH_PRICE_USD`. Raw price token1/token0 = `p × 10^(dec1 − dec0)` if token0 is mWETH, else `(1/p) × 10^(dec1 − dec0)`.
- `sqrtPriceX96 = floor(sqrt(rawPrice) × 2^96)` — compute in the script with `FixedPointMathLib.sqrt` on a WAD-scaled value, or pass it precomputed via env.
- After init, set hook `regimeThresholds` from the trained regime edges (or update later from the AI engine owner script).

Hook deployment (`01_DeployCore`):
```solidity
uint160 flags = uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG
                      | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
bytes memory args = abi.encode(poolManager, signalOracle, owner);
(address hookAddr, bytes32 salt) = HookMiner.find(CREATE2_DEPLOYER, flags, type(RangefyHook).creationCode, args);
RangefyHook hook = new RangefyHook{salt: salt}(poolManager, signalOracle, owner);
require(address(hook) == hookAddr);
```

---

## 14. Testing Plan

### 14.1 Contracts (Foundry) — target ≥ 90% line coverage on `src/`

Use `Deployers` from v4-core test utils in `RangefyFixture` (fresh PoolManager, tokens, mined hook, factory, 3 vaults).

| Suite | Cases |
|---|---|
| Hook unit | rejects non-dynamic-fee pool; seeds oracle on init; EMA moves toward tick by expected alpha; same-block second swap doesn't update; variance grows with large moves; fee per regime; signal-stale fallback; regime floor rule; admin bounds |
| SignalOracle | updater-only; bounds; freshness boundary at exactly `MAX_SIGNAL_AGE`; batch post |
| Registry/Factory | non-curator can't create; param bounds (each edge); presets valid; pool must be registered; vault indexes |
| Vault deposit | first deposit mints `L − MIN_SHARES` and burns `MIN_SHARES`; proportional second deposit; respects maxes; minShares slippage; paused deposits revert; price-deviation revert; accrued fees not stolen by new depositor |
| Vault withdraw | pro-rata amounts; min amounts; works while paused; works with price deviation; full exit leaves only dead shares |
| Rebalance | each reason triggers; cooldown; deviation guard; new range equals `targetRange()`; ratio swap leaves idle < 1% of value; perf fee accounting; range entirely one-sided; curatorRebalance |
| Harvest | fees moved to idle, perf fee to curatorOwed |
| Router | exactIn, swapToPrice stops at limit |
| Fuzz | random deposit/withdraw sequences: `withdraw(all) ≈ deposited ± fees − rounding`; random swaps + rebalances never revert unexpectedly |
| Invariant | sum of user shares + dead == totalSupply; vault token balances ≥ curatorOwed; no function lets curator decrease LP NAV beyond perf fee; ticks always aligned to spacing and lower < upper |
| Fork (`--fork-url` Unichain Sepolia) | full flow against canonical PoolManager |
| Integration | `RangefyE2E.t.sol`: deploy → 3 vaults → deposits → 50 random swaps with warps → keeper loop → withdraws; assert events and balances |

### 14.2 AI engine (pytest)
Feature shapes and no look-ahead (labels use only future, features only past); label conversion to ticks; regime edges monotonic; model save/load; signal mapper clamps to contract bounds; keeper jobs with a mocked web3 (needsRebalance true → tx sent; revert → logged, not crashed); mirror computes the correct direction and limit price; API endpoint schemas.

### 14.3 Frontend (Jest + Testing Library)
Tick/price math (both token orderings); error mapping; VaultCard/RangeChart render with fixture data; DepositWithdrawPanel button states (approve → deposit, insufficient balance, paused); leaderboard sorting.

### 14.4 Live testnet smoke test (`scripts/smoke.sh`)
Faucet → deposit into each vault → push price 3% via router → wait for keeper rebalance (≤ 2 min) → check `Rebalanced` event → withdraw → print balances.

---

## 15. Security Model

| Threat | Mitigation |
|---|---|
| Sandwiching deposits/rebalances | EMA-of-pre-swap-tick reference + `maxEmaDeviation` guard; swap `sqrtPriceLimitX96` bounded from EMA |
| Malicious/compromised keeper | Keeper chooses nothing; range computed on-chain; cooldown limits frequency |
| Compromised AI signal key | Hard bounds on sigma/drift; drift weight ≤ 50% and bias ≤ half-width; regime floor from on-chain vol; signal expiry; owner can rotate updater |
| Curator abuse | Params bounded by factory; perf fee only decreases; cannot pause withdrawals; never custody of LP funds |
| First-depositor share inflation | `MIN_SHARES` burned; shares minted from liquidity, not raw token balances |
| Fee theft by late depositor | Fees collected before every deposit/withdraw |
| Rounding drain | Round up amounts owed by user, round down amounts paid out and shares minted |
| Reentrancy | `nonReentrant` on all vault externals; state written before external transfers; unlockCallback only from PoolManager |
| Token weirdness | Only standard ERC-20 mocks on testnet; SafeERC20 everywhere |
| Hook griefing | Hook only touches its own storage in callbacks; no external calls except `signalOracle` view |

Known limitations (state honestly in README): single position per vault (no limit orders), keeper is centralised in the demo, AI model trained on CEX prices not testnet flow, no audit.

---

## 16. Build Order and Milestones

| # | Milestone | Done when |
|---|---|---|
| 1 | Scaffold repo, deps, CI (`forge test`, `pytest`, `npm test`) | All three pipelines green on empty tests |
| 2 | `VolatilityOracle` lib + `RangefyHook` + `SignalOracle` | Hook unit tests pass; dynamic fee observed in a test swap |
| 3 | `CuratorRegistry` + `VaultFactory` | Factory tests pass |
| 4 | `RangeVault` deposit/withdraw | Deposit/withdraw unit + fuzz tests pass |
| 5 | `RangeVault` rebalance/harvest + `RangeMath` | Rebalance tests + invariants pass |
| 6 | Router, Lens, MockERC20, scripts; deploy to Unichain Sepolia | Pool live, 3 seeded vaults visible on Uniscan |
| 7 | AI engine: data fetch, features, models, backtest | Ensemble beats EWMA baseline on test MAE; backtest JSON generated |
| 8 | Keeper jobs + API | Signals posting, mirror tracking real price within 0.3%, rebalances happening on testnet |
| 9 | Frontend core: vaults list, vault detail, deposit/withdraw, faucet | Full LP flow from the browser |
| 10 | Frontend: curate, leaderboard, AI page, swap, portfolio | Curator can create a vault from the UI |
| 11 | Polish: README, architecture diagram, FEEDBACK.md, demo video | §17 checklist all green |

---

## 17. Demo Script and Acceptance Criteria

**Demo (≤ 5 minutes)**
1. Landing page: live regime badge, dynamic fee, real ETH price vs testnet pool price (mirror bot keeping them aligned).
2. `/ai`: forecast vs realized volatility, model breakdown, backtest: AI-sized ranges vs fixed range.
3. `/curate`: register a new curator, choose Balanced, adjust width, see the live range preview, create the vault.
4. `/faucet` → `/vaults/[new]`: deposit; position appears in range.
5. `/swap`: push the price ~3% (or wait for the real market); watch `NearEdge` → keeper rebalance → range band slides in the chart, rebalance row appears.
6. Stop the AI engine for the fallback: show "signal stale → on-chain fallback" and a manual "Rebalance now" by any wallet.
7. `/curators` leaderboard: alpha vs HODL, fee APR, time-in-range.
8. Withdraw: tokens + fees returned.

**Acceptance criteria**
- [ ] All contracts deployed and verified on Unichain Sepolia; addresses in README.
- [ ] `forge test`, `pytest`, `npm test` all pass; coverage reported.
- [ ] A swap on the pool pays the regime fee, and the fee changes when the regime changes.
- [ ] At least 3 vaults with different profiles have rebalanced automatically on testnet (event links in README).
- [ ] Deposit, withdraw, create vault, rebalance and faucet all work from the deployed frontend with a fresh wallet.
- [ ] Stale-signal fallback demonstrated.
- [ ] `sandwich` test (manipulate + deposit in one tx) reverts with `PriceDeviation`.
- [ ] README includes architecture diagram, backtest results, known limitations; `FEEDBACK.md` present.

---

## 18. References

- Uniswap v4 docs: https://docs.uniswap.org/contracts/v4/overview
- v4 deployments: https://docs.uniswap.org/contracts/v4/deployments
- Dynamic fees: https://docs.uniswap.org/contracts/v4/concepts/dynamic-fees
- Hook address mining (HookMiner): `v4-periphery/src/utils/HookMiner.sol`
- `LiquidityAmounts`: `v4-periphery/src/libraries/LiquidityAmounts.sol`; `TickMath`, `StateLibrary`, `TransientStateLibrary`, `LPFeeLibrary`: `v4-core/src/libraries/`
- Unichain docs: https://docs.unichain.org
- Coinbase Exchange candles API: https://docs.cdp.coinbase.com/exchange/reference/exchangerestapi_getproductcandles
- Binance klines API: https://developers.binance.com/docs/binance-spot-api-docs/rest-api/market-data-endpoints
- Prior art for active LP management: Charm Alpha Vaults, Arrakis, Gamma (for comparison in README)

---

## 19. Implementation Notes (deviations from this blueprint)

Recorded while building milestones 1–6. Where these differ from the sections above, these win.

| Area | Blueprint | As built | Why |
|---|---|---|---|
| `BaseHook` / `HookMiner` | `@uniswap/v4-periphery/src/utils/…` | Vendored at `contracts/src/vendor/` from v4-periphery@`3779387e` | Upstream removed both in Feb 2026 (#510, `5da22e60`) |
| Regime floor (§7.2) | `max(regime, regimeOnchain − 1)` | Same, saturating at `Calm` | `Calm − 1` underflows |
| Pool registration (§6.3) | Any `initialize` registers the pool | `beforeInitialize` requires `sender == owner()` | Matches the trust table (“protocol owner registers pools”); stops vaults on arbitrary tokens |
| Signal read in the hook | Direct call | Length-checked `staticcall`; any failure ⇒ stale signal | A broken or garbage oracle must never brick swaps (`try/catch` misses decode failures and code-less addresses) |
| `driftTicks` sign | Unspecified | Pool-tick direction (positive = token1 per token0 rising) | The AI engine must negate ETH/USD drift when mUSDC is `currency0` |
| `VaultFactory` | Embeds `new RangeVault(...)`; constructor `(hook, registry, signalOracle, poolManager)` | `VaultFactory(poolManager, hook, registry, vaultDeployer)`; vaults created by a separate `VaultDeployer` bound once to the factory. Vault reads the oracle from `hook.signalOracle()` | Factory with embedded vault code was 26.7 KB (> 24 KB EIP-170 limit) |
| `RangeMath` | Internal library | Heavy functions are `external` (linked library, auto-linked by Foundry) | Keeps `RangeVault`/`VaultDeployer` under 24 KB |
| Deposit / rebalance rounding | — | 2 wei margin on deposit maxima; 1 wei on rebalance amounts | PoolManager rounds owed amounts up; guarantees `used ≤ max` |
| `needsRebalance` order (§7.4) | OutOfRange, NearEdge, WidthDrift, Initial | `Initial` is returned first whenever liquidity is 0 | Range checks are meaningless without a position |
| Lens `PoolView` | — | Adds `onchainSigma`, `confidenceBps`, `signalUpdatedAt` | Needed by the AI page and the “signal stale” banner |
| Address book | Parse `broadcast/*/run-latest.json` | Scripts write `contracts/deployments/<chainId>/{tokens,core,vaults}.json`; `sync-abis.sh` reads them | Simpler and stable across re-runs |
| Python | 3.11 | `requires-python >= 3.11`; CI uses 3.11, local venv may be newer | — |
| PoolManager address | `0x00B0…62AC` | `0x00B0…62AC` | Verify against the official Uniswap deployments page before deploying |
| Rebalance reasons (§7.4) | None, OutOfRange, NearEdge, WidthDrift, Initial | Adds `IdleExcess` (enum value 5): idle ≥ `IDLE_REBALANCE_BPS` (10%) of vault value at spot | When the ratio swap stops at its EMA ± 100-tick limit (vault large vs pool depth), the leftover would otherwise sit idle until the price moved again |
| Rebalance swap fee | — | Vault swaps pay the hook's regime fee like any swap (up to 1.5% in Extreme) | Open question: a lower fee for registered vaults would cut LP rebalance cost but needs the hook to know the factory |
| AI engine data | Coinbase / Binance candles | Same fetchers (`src/data/candles.py`); `src/data/synthetic.py` adds a GARCH-style synthetic ETH generator for offline dev/tests (`train_model.py --synthetic DAYS`) | The build machine could not reach the exchange APIs |
| AI engine split | 70/15/15 chronological | Same, plus a 1-day embargo between splits | Labels look 24h ahead; without a gap, val/test labels overlap train |
| Transformer | 2 layers, 4 heads, d64, Huber | Same; output bias initialized to training means; trains on Apple MPS when available | Calibrated from step 0 (val loss 2.37 → 0.11 on the smoke run) |
| LP backtest | Fixed ±600 vs AI-sized | Adds an EWMA-sized strategy; fees = fee · minute volume · L / pool liquidity (assumptions recorded in `backtest.json`) | Shows whether the AI beats the simple baseline, not only a fixed range |
| Vault rebalance fee | Vault swaps pay the regime fee | Hook charges `vaultSwapFee` (default 500 pips) when `sender` is a factory-registered vault (`setVaultFactory`, `setVaultSwapFee`); lookup is a guarded staticcall | Up to 1.5% per rebalance was a direct cost to LPs; only rule-bound vault swaps qualify |
| Hook deployment | `new RangefyHook{salt}` | `01_DeployCore` calls the CREATE2 proxy directly with `salt ++ initcode` | Forge's create2 routing didn't land on the mined address on a Unichain fork |
| Frontend chains | Unichain Sepolia | `NEXT_PUBLIC_CHAIN_ID` selects 1301, 31337 (local) or 31338 (fork); addresses come from `frontend/src/config/deployments/<id>.json` | Same build runs against testnet or the local stacks |
