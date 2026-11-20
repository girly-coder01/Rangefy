// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Constants
/// @dev ticks ~ 1bp of price, fees in pips (1e-6), bps out of 10_000
library Constants {
    // signal
    uint256 internal constant MAX_SIGNAL_AGE = 15 minutes;
    uint32 internal constant MIN_SIGMA_TICKS = 20; // 0.2% 24h vol floor
    uint32 internal constant MAX_SIGMA_TICKS = 5000; // 50% 24h vol ceiling
    int32 internal constant MAX_DRIFT_TICKS = 2000;

    // volatility oracle
    uint256 internal constant EMA_WINDOW = 300; // seconds
    uint256 internal constant VAR_WINDOW = 3600; // seconds
    uint256 internal constant SIGMA_HORIZON = 86_400;
    uint256 internal constant WAD = 1e18;
    // seed: sigma 300 ticks / 24h
    uint128 internal constant DEFAULT_VAR_PER_SEC_WAD = uint128((300 * 300 * WAD) / SIGMA_HORIZON);

    // fees (pips)
    uint24 internal constant MIN_FEE = 100; // 0.01%
    uint24 internal constant MAX_FEE = 30_000; // 3%

    // vault
    uint256 internal constant MIN_SHARES = 1000; // burned to DEAD on first deposit
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint16 internal constant BPS = 10_000;
    uint16 internal constant MAX_PERFORMANCE_FEE = 2000; // 20%
    uint16 internal constant MAX_SWAP_SLIPPAGE_BPS = 100; // rebalance swap limit from EMA
    uint16 internal constant EDGE_BUFFER_BPS = 1000; // near-edge trigger, % of width
    uint16 internal constant WIDTH_DRIFT_BPS = 3000;
    uint16 internal constant RATIO_TOLERANCE_BPS = 50;
    uint16 internal constant IDLE_REBALANCE_BPS = 1000;
    uint32 internal constant MIN_REBALANCE_INTERVAL_FLOOR = 60;
    uint32 internal constant MAX_REBALANCE_INTERVAL = 1 days;
    int24 internal constant MIN_HALF_WIDTH_FLOOR = 60;
    int24 internal constant MAX_HALF_WIDTH_CEIL = 40_000;
    int24 internal constant MAX_EMA_DEVIATION_CEIL = 500; // 5%
    uint16 internal constant MIN_WIDTH_MULTIPLIER_BPS = 5000; // 0.5σ
    uint16 internal constant MAX_WIDTH_MULTIPLIER_BPS = 50_000; // 5σ
    uint16 internal constant MAX_DRIFT_WEIGHT_BPS = 5000;
}
