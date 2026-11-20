// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {HelperConfig} from "./HelperConfig.s.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {RangefyHook} from "../src/hook/RangefyHook.sol";

/// @notice Init the pool at ETH_PRICE_USD and add ±20% background liquidity.
contract InitPool is HelperConfig {
    function run() external {
        uint256 pk = deployerKey();
        address me = vm.addr(pk);
        address weth = load("tokens", "mWETH");
        address usdc = load("tokens", "mUSDC");
        RangefyHook hook = RangefyHook(load("core", "hook"));
        IPoolManager pm = IPoolManager(poolManager());
        uint256 ethPrice = vm.envOr("ETH_PRICE_USD", uint256(3000));

        bool wethIs0 = weth < usdc;
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(wethIs0 ? weth : usdc),
            currency1: Currency.wrap(wethIs0 ? usdc : weth),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        uint160 sqrtPriceX96 = sqrtPriceFor(ethPrice, wethIs0);
        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        // ±20% ≈ ±1800 ticks
        int24 lower = ((tick - 1800) / TICK_SPACING) * TICK_SPACING;
        int24 upper = ((tick + 1800) / TICK_SPACING) * TICK_SPACING;

        uint256 wethAmt = vm.envOr("BACKGROUND_WETH", uint256(50e18));
        uint256 usdcAmt = wethAmt * ethPrice / 1e12;
        (uint256 a0, uint256 a1) = wethIs0 ? (wethAmt, usdcAmt) : (usdcAmt, wethAmt);
        uint128 liq = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, TickMath.getSqrtPriceAtTick(lower), TickMath.getSqrtPriceAtTick(upper), a0, a1
        );

        PoolModifyLiquidityTest router = PoolModifyLiquidityTest(modifyLiquidityRouter());

        vm.startBroadcast(pk);
        pm.initialize(key, sqrtPriceX96);

        MockERC20(weth).mint(me, wethAmt * 2);
        MockERC20(usdc).mint(me, usdcAmt * 2);
        MockERC20(weth).approve(address(router), type(uint256).max);
        MockERC20(usdc).approve(address(router), type(uint256).max);
        router.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: lower, tickUpper: upper, liquidityDelta: int256(uint256(liq)), salt: 0}),
            ""
        );

        // optional: match regime thresholds to the trained model
        uint256 th0 = vm.envOr("REGIME_TH0", uint256(0));
        if (th0 != 0) {
            hook.setRegimeThresholds([uint32(th0), uint32(vm.envUint("REGIME_TH1")), uint32(vm.envUint("REGIME_TH2"))]);
        }
        vm.stopBroadcast();

        console2.log("pool initialized at tick", tick);
        console2.log("poolId");
        console2.logBytes32(keccak256(abi.encode(key)));
    }

    function sqrtPriceFor(uint256 ethPrice, bool wethIs0) public pure returns (uint160) {
        // sqrt(raw price * 2^192)
        uint256 q192 = 1 << 192;
        uint256 ratioX192 =
            wethIs0 ? FullMath.mulDiv(ethPrice * 1e6, q192, 1e18) : FullMath.mulDiv(1e18, q192, ethPrice * 1e6);
        return uint160(FixedPointMathLib.sqrt(ratioX192));
    }
}
