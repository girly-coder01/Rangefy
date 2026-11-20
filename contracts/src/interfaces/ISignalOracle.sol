// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

enum Regime {
    Calm,
    Normal,
    High,
    Extreme
}

/// @dev driftTicks is in pool tick direction (positive = token1/token0 up).
struct Signal {
    uint32 sigmaTicks; // 24h 1-sigma
    int32 driftTicks;
    Regime regime;
    uint16 confidenceBps; // 0..10_000
    uint40 updatedAt;
    bytes8 modelVersion;
}

interface ISignalOracle {
    event SignalPosted(
        PoolId indexed poolId,
        uint32 sigmaTicks,
        int32 driftTicks,
        Regime regime,
        uint16 confidenceBps,
        bytes8 modelVersion,
        uint40 updatedAt
    );
    event UpdaterChanged(address indexed previousUpdater, address indexed newUpdater);

    error SignalOutOfBounds();
    error NotUpdater();
    error LengthMismatch();
    error ZeroAddress();

    function updater() external view returns (address);

    function postSignal(
        PoolId poolId,
        uint32 sigmaTicks,
        int32 driftTicks,
        Regime regime,
        uint16 confidenceBps,
        bytes8 modelVersion
    ) external;

    function postSignals(PoolId[] calldata ids, Signal[] calldata signals) external;

    function getSignal(PoolId poolId) external view returns (Signal memory s, bool fresh);

    function setUpdater(address newUpdater) external;
}
