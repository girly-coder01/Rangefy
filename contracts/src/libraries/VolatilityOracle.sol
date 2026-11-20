// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {PoolState} from "../interfaces/IRangefyHook.sol";
import {Constants} from "./Constants.sol";

/// @title VolatilityOracle
/// @notice Time-weighted EMA tick and realized variance.
/// @dev Only absorbs the pre-swap tick, so moving price and reading the EMA in one block changes nothing.
library VolatilityOracle {
    /// @notice Seed the oracle at pool initialization.
    function initialize(PoolState storage self, int24 tick, uint256 timestamp) internal {
        self.lastTick = tick;
        self.emaTickX1000 = int56(tick) * 1000;
        self.varPerSecWad = Constants.DEFAULT_VAR_PER_SEC_WAD;
        self.lastUpdate = uint40(timestamp);
    }

    /// @notice No-op within the same second.
    function update(PoolState storage self, int24 tick, uint256 timestamp) internal {
        PoolState memory s = self;
        if (timestamp <= s.lastUpdate) return; // once per block per pool; first swap in a block wins
        (s.emaTickX1000, s.varPerSecWad) = _advance(s, tick, timestamp);
        self.emaTickX1000 = s.emaTickX1000;
        self.varPerSecWad = s.varPerSecWad;
        self.lastTick = tick;
        self.lastUpdate = uint40(timestamp);
    }

    /// @notice Update without writing.
    function preview(PoolState memory s, int24 tick, uint256 timestamp) internal pure returns (PoolState memory) {
        if (timestamp > s.lastUpdate) {
            (s.emaTickX1000, s.varPerSecWad) = _advance(s, tick, timestamp);
            s.lastTick = tick;
            s.lastUpdate = uint40(timestamp);
        }
        return s;
    }

    /// @notice EMA tick rounded toward negative infinity.
    function emaTick(PoolState memory s) internal pure returns (int24) {
        int256 e = s.emaTickX1000;
        int256 q = e / 1000;
        if (e % 1000 < 0) q -= 1;
        return int24(q);
    }

    /// @notice 24h sigma in ticks, clamped to signal bounds.
    function sigmaTicks(PoolState memory s) internal pure returns (uint32) {
        uint256 sigma = FixedPointMathLib.sqrt((uint256(s.varPerSecWad) * Constants.SIGMA_HORIZON) / Constants.WAD);
        if (sigma < Constants.MIN_SIGMA_TICKS) return Constants.MIN_SIGMA_TICKS;
        if (sigma > Constants.MAX_SIGMA_TICKS) return Constants.MAX_SIGMA_TICKS;
        return uint32(sigma);
    }

    function _advance(PoolState memory s, int24 tick, uint256 timestamp)
        private
        pure
        returns (int56 emaX1000, uint128 varPerSecWad)
    {
        uint256 dt = timestamp - s.lastUpdate;

        // ema += alpha * (tick - ema), alpha = min(dt / EMA_WINDOW, 1)
        int256 alphaWad = int256(_min((dt * Constants.WAD) / Constants.EMA_WINDOW, Constants.WAD));
        int256 ema = s.emaTickX1000;
        ema += (alphaWad * (int256(tick) * 1000 - ema)) / int256(Constants.WAD);
        emaX1000 = int56(ema);

        // var += beta * (move^2 / dt - var), beta = min(dt / VAR_WINDOW, 1)
        int256 move = int256(tick) - int256(s.lastTick);
        int256 sampleWad = (move * move * int256(Constants.WAD)) / int256(dt);
        int256 betaWad = int256(_min((dt * Constants.WAD) / Constants.VAR_WINDOW, Constants.WAD));
        int256 v = int256(uint256(s.varPerSecWad));
        v += (betaWad * (sampleWad - v)) / int256(Constants.WAD);
        if (v < 0) v = 0;
        if (v > int256(uint256(type(uint128).max))) v = int256(uint256(type(uint128).max));
        varPerSecWad = uint128(uint256(v));
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
