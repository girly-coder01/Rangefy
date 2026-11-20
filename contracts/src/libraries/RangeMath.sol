// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";

import {StrategyParams} from "../interfaces/IVaultFactory.sol";
import {Constants} from "./Constants.sol";

/// @title RangeMath
/// @notice Range sizing and target-ratio math for vaults.
/// @dev Heavy functions are external (linked) to keep RangeVault/VaultDeployer under 24 KB.
library RangeMath {
    /// @notice Round `x` toward −∞ to a multiple of `s`.
    function floorTo(int256 x, int24 s) internal pure returns (int256) {
        int256 r = x % s;
        return r < 0 ? x - r - s : x - r;
    }

    /// @notice Round `x` toward +∞ to a multiple of `s`.
    function ceilTo(int256 x, int24 s) internal pure returns (int256) {
        int256 r = x % s;
        return r > 0 ? x - r + s : x - r;
    }

    /// @notice Target half-width: clamp(ceilTo(sigma * multiplier, s), minHalfWidth, maxHalfWidth).
    function halfWidth(uint32 sigma, StrategyParams memory p, int24 s) external pure returns (int24) {
        return _halfWidth(sigma, p, s);
    }

    function _halfWidth(uint32 sigma, StrategyParams memory p, int24 s) internal pure returns (int24) {
        int256 hw = ceilTo(
            (int256(uint256(sigma)) * int256(uint256(p.widthMultiplierBps))) / int256(uint256(Constants.BPS)), s
        );
        if (hw < p.minHalfWidth) hw = p.minHalfWidth;
        if (hw > p.maxHalfWidth) hw = p.maxHalfWidth;
        return int24(hw);
    }

    /// @notice Range around the EMA tick, shifted by a capped share of AI drift.
    function computeRange(int24 ema, uint32 sigma, int32 drift, StrategyParams memory p, int24 s)
        external
        pure
        returns (int24 lower, int24 upper)
    {
        int256 hw = _halfWidth(sigma, p, s);
        int256 bias = (int256(drift) * int256(uint256(p.driftWeightBps))) / int256(uint256(Constants.BPS));
        if (bias > hw / 2) bias = hw / 2;
        if (bias < -hw / 2) bias = -hw / 2;

        int256 center = int256(ema) + bias;
        int256 lo = floorTo(center - hw, s);
        int256 hi = ceilTo(center + hw, s);

        int256 minT = TickMath.minUsableTick(s);
        int256 maxT = TickMath.maxUsableTick(s);
        if (lo < minT) lo = minT;
        if (hi > maxT) hi = maxT;
        if (lo >= hi) (lo, hi) = hi == maxT ? (maxT - s, maxT) : (minT, minT + s);
        return (int24(lo), int24(hi));
    }

    /// @notice Token amounts represented by `liquidity` in [sqrtA, sqrtB] at price sqrtP.
    function amountsForLiquidity(uint160 sqrtP, uint160 sqrtA, uint160 sqrtB, uint128 liquidity, bool roundUp)
        external
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        return _amounts(sqrtP, sqrtA, sqrtB, liquidity, roundUp);
    }

    function _amounts(uint160 sqrtP, uint160 sqrtA, uint160 sqrtB, uint128 liquidity, bool roundUp)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        if (liquidity == 0) return (0, 0);
        if (sqrtP <= sqrtA) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtA, sqrtB, liquidity, roundUp);
        } else if (sqrtP < sqrtB) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtP, sqrtB, liquidity, roundUp);
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtA, sqrtP, liquidity, roundUp);
        } else {
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtA, sqrtB, liquidity, roundUp);
        }
    }

    /// @notice Raw token1/token0 price, WAD.
    function priceWad(uint160 sqrtP) external pure returns (uint256) {
        return FullMath.mulDiv(FullMath.mulDiv(sqrtP, sqrtP, FixedPoint96.Q96), Constants.WAD, FixedPoint96.Q96);
    }

    /// @notice Value of (amount0, amount1) in token1 units at `pWad`.
    function valueIn1(uint256 amount0, uint256 amount1, uint256 pWad) external pure returns (uint256) {
        return FullMath.mulDiv(amount0, pWad, Constants.WAD) + amount1;
    }

    /// @notice token0 the vault should hold to match the range ratio. x, y = amounts per unit liquidity.
    function targetAmount0(uint256 a0, uint256 a1, uint256 pWad, uint256 x, uint256 y) external pure returns (uint256) {
        uint256 denom = FullMath.mulDiv(x, pWad, Constants.WAD) + y; // value of one unit, in token1
        if (denom == 0) return a0;
        return FullMath.mulDiv(FullMath.mulDiv(a0, pWad, Constants.WAD) + a1, x, denom);
    }

    /// @notice Liquidity for (a0, a1) in [lo, hi] at sqrtP (rounded down).
    function liquidityForAmounts(uint160 sqrtP, int24 lo, int24 hi, uint256 a0, uint256 a1)
        external
        pure
        returns (uint128)
    {
        return LiquidityAmounts.getLiquidityForAmounts(
            sqrtP, TickMath.getSqrtPriceAtTick(lo), TickMath.getSqrtPriceAtTick(hi), a0, a1
        );
    }

    /// @notice (0, 0) for an empty range.
    function amountsForTicks(uint160 sqrtP, int24 lo, int24 hi, uint128 liquidity, bool roundUp)
        external
        pure
        returns (uint256, uint256)
    {
        if (lo >= hi || liquidity == 0) return (0, 0);
        return _amounts(sqrtP, TickMath.getSqrtPriceAtTick(lo), TickMath.getSqrtPriceAtTick(hi), liquidity, roundUp);
    }

    function sqrtPriceAtTick(int24 tick) external pure returns (uint160) {
        return TickMath.getSqrtPriceAtTick(tick);
    }

    function absDiff(int24 a, int24 b) internal pure returns (uint256) {
        return a > b ? uint256(int256(a) - int256(b)) : uint256(int256(b) - int256(a));
    }
}
