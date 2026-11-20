// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

/// @title SimpleSwapRouter
/// @notice Exact-input router for the UI and the mirror bot.
contract SimpleSwapRouter is IUnlockCallback {
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;

    IPoolManager public immutable poolManager;

    struct CallbackData {
        address payer;
        address to;
        PoolKey key;
        SwapParams params;
    }

    error Expired();
    error TooLittleReceived();
    error OnlyPoolManager();
    error ZeroAmount();
    error PriceAlreadyAtTarget();

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function swapExactIn(
        PoolKey calldata key,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        if (block.timestamp > deadline) revert Expired();
        if (amountIn == 0) revert ZeroAmount();
        SwapParams memory p = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn),
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        BalanceDelta d =
            abi.decode(poolManager.unlock(abi.encode(CallbackData(msg.sender, to, key, p))), (BalanceDelta));
        amountOut = uint256(int256(zeroForOne ? d.amount1() : d.amount0()));
        if (amountOut < amountOutMin) revert TooLittleReceived();
    }

    /// @notice Swap toward a target price, spending at most maxAmountIn.
    function swapToPrice(PoolKey calldata key, uint160 sqrtPriceLimitX96, uint256 maxAmountIn, address to)
        external
        returns (int256 amount0, int256 amount1)
    {
        if (maxAmountIn == 0) revert ZeroAmount();
        (uint160 sqrtP,,,) = poolManager.getSlot0(key.toId());
        if (sqrtP == sqrtPriceLimitX96) revert PriceAlreadyAtTarget();
        SwapParams memory p = SwapParams({
            zeroForOne: sqrtPriceLimitX96 < sqrtP,
            amountSpecified: -int256(maxAmountIn),
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });
        BalanceDelta d =
            abi.decode(poolManager.unlock(abi.encode(CallbackData(msg.sender, to, key, p))), (BalanceDelta));
        return (d.amount0(), d.amount1());
    }

    function unlockCallback(bytes calldata raw) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        CallbackData memory data = abi.decode(raw, (CallbackData));
        BalanceDelta delta = poolManager.swap(data.key, data.params, "");
        _settle(data.key.currency0, delta.amount0(), data.payer, data.to);
        _settle(data.key.currency1, delta.amount1(), data.payer, data.to);
        return abi.encode(delta);
    }

    function _settle(Currency c, int128 amount, address payer, address to) internal {
        if (amount < 0) {
            poolManager.sync(c);
            IERC20(Currency.unwrap(c)).safeTransferFrom(payer, address(poolManager), uint256(-int256(amount)));
            poolManager.settle();
        } else if (amount > 0) {
            poolManager.take(c, to, uint256(int256(amount)));
        }
    }
}
