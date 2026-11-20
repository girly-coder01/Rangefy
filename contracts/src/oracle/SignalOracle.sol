// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {ISignalOracle, Signal, Regime} from "../interfaces/ISignalOracle.sol";
import {Constants} from "../libraries/Constants.sol";

/// @title SignalOracle
/// @notice Latest AI volatility signal per pool. Bounded, and stale after MAX_SIGNAL_AGE.
contract SignalOracle is ISignalOracle, Ownable2Step {
    address public updater;

    mapping(PoolId => Signal) internal _signals;

    modifier onlyUpdater() {
        if (msg.sender != updater) revert NotUpdater();
        _;
    }

    constructor(address initialOwner, address initialUpdater) Ownable(initialOwner) {
        if (initialUpdater == address(0)) revert ZeroAddress();
        updater = initialUpdater;
        emit UpdaterChanged(address(0), initialUpdater);
    }

    function postSignal(
        PoolId poolId,
        uint32 sigmaTicks,
        int32 driftTicks,
        Regime regime,
        uint16 confidenceBps,
        bytes8 modelVersion
    ) external onlyUpdater {
        _post(poolId, sigmaTicks, driftTicks, regime, confidenceBps, modelVersion);
    }

    // input updatedAt is ignored
    function postSignals(PoolId[] calldata ids, Signal[] calldata signals) external onlyUpdater {
        if (ids.length != signals.length) revert LengthMismatch();
        for (uint256 i; i < ids.length; ++i) {
            Signal calldata s = signals[i];
            _post(ids[i], s.sigmaTicks, s.driftTicks, s.regime, s.confidenceBps, s.modelVersion);
        }
    }

    function getSignal(PoolId poolId) external view returns (Signal memory s, bool fresh) {
        s = _signals[poolId];
        fresh = s.updatedAt != 0 && block.timestamp - s.updatedAt <= Constants.MAX_SIGNAL_AGE;
    }

    function setUpdater(address newUpdater) external onlyOwner {
        if (newUpdater == address(0)) revert ZeroAddress();
        emit UpdaterChanged(updater, newUpdater);
        updater = newUpdater;
    }

    function _post(
        PoolId poolId,
        uint32 sigmaTicks,
        int32 driftTicks,
        Regime regime,
        uint16 confidenceBps,
        bytes8 modelVersion
    ) internal {
        if (
            sigmaTicks < Constants.MIN_SIGMA_TICKS || sigmaTicks > Constants.MAX_SIGMA_TICKS
                || driftTicks > Constants.MAX_DRIFT_TICKS || driftTicks < -Constants.MAX_DRIFT_TICKS
                || confidenceBps > Constants.BPS
        ) revert SignalOutOfBounds();

        uint40 nowTs = uint40(block.timestamp);
        _signals[poolId] = Signal({
            sigmaTicks: sigmaTicks,
            driftTicks: driftTicks,
            regime: regime,
            confidenceBps: confidenceBps,
            updatedAt: nowTs,
            modelVersion: modelVersion
        });
        emit SignalPosted(poolId, sigmaTicks, driftTicks, regime, confidenceBps, modelVersion, nowTs);
    }
}
