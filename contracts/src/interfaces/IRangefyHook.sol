// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Regime, ISignalOracle} from "./ISignalOracle.sol";

/// @dev Packs into one slot.
struct PoolState {
    int24 lastTick;
    int56 emaTickX1000;
    uint128 varPerSecWad; // EWMA of dTick^2 / dt
    uint40 lastUpdate;
    bool registered;
}

interface IRangefyHook {
    event PoolRegistered(PoolId indexed poolId, Currency currency0, Currency currency1, int24 tickSpacing);
    event PoolStateUpdated(
        PoolId indexed poolId, int24 tick, int24 emaTick, uint32 sigmaTicks, uint24 fee, Regime regime
    );
    event RegimeFeesUpdated(uint24[4] fees);
    event RegimeThresholdsUpdated(uint32[3] thresholds);
    event SignalOracleUpdated(address indexed signalOracle);
    event VaultFactoryUpdated(address indexed vaultFactory);
    event VaultSwapFeeUpdated(uint24 fee);

    error NotDynamicFee();
    error NotPoolAdmin();
    error PoolNotRegistered();
    error InvalidFees();
    error InvalidThresholds();
    error ZeroAddress();

    function signalOracle() external view returns (ISignalOracle);

    /// @notice EMA tick extrapolated to now with the current spot tick.
    function emaTick(PoolId id) external view returns (int24);

    /// @notice Realized 24h sigma in ticks, clamped to signal bounds.
    function onchainSigmaTicks(PoolId id) external view returns (uint32);

    /// @notice Fresh AI signal if available, otherwise on-chain sigma with zero drift.
    function effectiveSigma(PoolId id) external view returns (uint32 sigma, int32 drift, bool fromSignal);

    function currentRegime(PoolId id) external view returns (Regime);

    function currentFee(PoolId id) external view returns (uint24);

    function getPoolState(PoolId id) external view returns (PoolState memory);

    function isRegistered(PoolId id) external view returns (bool);
}
