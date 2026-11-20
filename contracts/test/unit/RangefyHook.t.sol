// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {RangefyFixture} from "../utils/RangefyFixture.sol";
import {IRangefyHook, PoolState} from "../../src/interfaces/IRangefyHook.sol";
import {ISignalOracle, Regime} from "../../src/interfaces/ISignalOracle.sol";
import {Constants} from "../../src/libraries/Constants.sol";

contract RevertingOracle {
    fallback() external {
        revert("boom");
    }
}

contract GarbageOracle {
    fallback() external {
        assembly {
            mstore(0, 1)
            return(0, 32)
        }
    }
}

contract RangefyHookTest is RangefyFixture {
    function setUp() public {
        setUpRangefy();
    }

    // initialization

    function test_init_rejectsStaticFeePool() public {
        PoolKey memory k = PoolKey(currency0, currency1, 3000, TICK_SPACING, IHooks(address(hook)));
        vm.expectRevert();
        manager.initialize(k, SQRT_PRICE_1_1);
    }

    function test_init_rejectsNonOwner() public {
        PoolKey memory k = PoolKey(currency0, currency1, LPFeeLibrary.DYNAMIC_FEE_FLAG, 120, IHooks(address(hook)));
        vm.prank(alice);
        vm.expectRevert();
        manager.initialize(k, SQRT_PRICE_1_1);
    }

    function test_init_registersAndSeedsOracle() public view {
        PoolState memory s = hook.getPoolState(poolId);
        assertTrue(s.registered);
        assertTrue(hook.isRegistered(poolId));
        assertEq(s.lastTick, 0);
        assertEq(s.emaTickX1000, 0);
        assertEq(s.varPerSecWad, Constants.DEFAULT_VAR_PER_SEC_WAD);
        assertEq(s.lastUpdate, T0);
    }

    function test_views_revertForUnknownPool() public {
        vm.expectRevert(IRangefyHook.PoolNotRegistered.selector);
        hook.emaTick(PoolId.wrap(bytes32(uint256(123))));
    }

    // oracle updates

    function test_swap_updatesEmaWithPreSwapTick() public {
        swapToTick(600); // same timestamp as init → oracle no-op
        assertEq(hook.getPoolState(poolId).emaTickX1000, 0);

        vm.warp(T0 + 60);
        int24 pre = spotTick();
        swapExactIn(true, 1e15);
        // alpha = 60/300 → ema = 0.2 * pre
        assertEq(hook.getPoolState(poolId).emaTickX1000, int56(pre) * 200);
        assertEq(hook.getPoolState(poolId).lastTick, pre);
    }

    function test_swap_sameBlockSecondSwapDoesNotUpdate() public {
        vm.warp(T0 + 60);
        swapExactIn(false, 1e18);
        PoolState memory a = hook.getPoolState(poolId);
        swapExactIn(false, 50e18);
        PoolState memory b = hook.getPoolState(poolId);
        assertEq(a.emaTickX1000, b.emaTickX1000);
        assertEq(a.varPerSecWad, b.varPerSecWad);
        assertEq(a.lastTick, b.lastTick);
    }

    function test_emaView_extrapolatesWithSpot() public {
        swapToTick(600);
        vm.warp(T0 + 10_000); // alpha saturates
        assertEq(hook.emaTick(poolId), 600);
        assertEq(hook.getPoolState(poolId).emaTickX1000, 0, "view does not write");
    }

    function test_emaView_resistsSameBlockManipulation() public {
        vm.warp(T0 + 1000);
        swapToTick(3000);
        // oracle only saw the pre-swap tick
        assertEq(spotTick(), 3000);
        assertEq(hook.emaTick(poolId), 0);
    }

    function test_variance_growsWithLargeMoves() public {
        uint32 sigma0 = hook.onchainSigmaTicks(poolId);
        for (uint256 i = 1; i <= 10; ++i) {
            vm.warp(T0 + i * 60);
            swapToTick(i % 2 == 0 ? int24(-1200) : int24(1200));
        }
        vm.warp(T0 + 11 * 60);
        assertGt(hook.onchainSigmaTicks(poolId), sigma0);
    }

    function test_afterSwap_emitsPoolState() public {
        vm.warp(T0 + 60);
        vm.expectEmit(true, false, false, false, address(hook));
        emit IRangefyHook.PoolStateUpdated(poolId, 0, 0, 0, 0, Regime.Calm);
        swapExactIn(true, 1e18);
    }

    // fees and regimes

    function test_fee_onchainRegimeWithoutSignal() public view {
        // seeded sigma ≈ 299 → Normal (150 ≤ σ < 400)
        assertEq(uint8(hook.currentRegime(poolId)), uint8(Regime.Normal));
        assertEq(hook.currentFee(poolId), 3000);
        (uint32 sigma, int32 drift, bool fromSignal) = hook.effectiveSigma(poolId);
        assertEq(sigma, 299);
        assertEq(drift, 0);
        assertFalse(fromSignal);
    }

    function test_fee_freshSignalSetsRegime() public {
        postSignal(1000, 50, Regime.Extreme);
        assertEq(hook.currentFee(poolId), 15_000);
        (uint32 sigma, int32 drift, bool fromSignal) = hook.effectiveSigma(poolId);
        assertEq(sigma, 1000);
        assertEq(drift, 50);
        assertTrue(fromSignal);
    }

    function test_fee_dynamicFeeChargedOnSwap() public {
        vm.warp(T0 + 60);
        uint256 snap = vm.snapshotState();

        postSignal(100, 0, Regime.Calm);
        BalanceDelta calm = swapExactIn(true, 10e18);
        vm.revertToState(snap);

        postSignal(2000, 0, Regime.Extreme);
        BalanceDelta extreme = swapExactIn(true, 10e18);

        assertEq(calm.amount0(), extreme.amount0(), "same input");
        assertGt(calm.amount1(), extreme.amount1(), "higher fee, less out");
        // Fee difference ≈ 1.45% of 10e18 at ~1:1
        uint256 diff = uint256(int256(calm.amount1() - extreme.amount1()));
        assertApproxEqRel(diff, 0.145e18, 0.02e18);
    }

    function test_fee_regimeFloorFromOnchainVol() public {
        // Make on-chain sigma (≈299) read as Extreme, then post a Calm signal.
        hook.setRegimeThresholds([uint32(30), 40, 50]);
        postSignal(100, 0, Regime.Calm);
        // floor = Extreme - 1 = High
        assertEq(uint8(hook.currentRegime(poolId)), uint8(Regime.High));
        assertEq(hook.currentFee(poolId), 7500);
    }

    function test_fee_regimeFloorSaturatesAtCalm() public {
        hook.setRegimeThresholds([uint32(1000), 2000, 3000]); // on-chain reads Calm
        postSignal(100, 0, Regime.Calm);
        assertEq(uint8(hook.currentRegime(poolId)), uint8(Regime.Calm));
        assertEq(hook.currentFee(poolId), 500);
    }

    function test_signal_staleFallsBackToOnchain() public {
        postSignal(2000, 300, Regime.Extreme);
        vm.warp(T0 + Constants.MAX_SIGNAL_AGE + 1);
        (uint32 sigma, int32 drift, bool fromSignal) = hook.effectiveSigma(poolId);
        assertFalse(fromSignal);
        assertEq(drift, 0);
        assertEq(sigma, hook.onchainSigmaTicks(poolId));
        assertEq(uint8(hook.currentRegime(poolId)), uint8(hook.regimeForSigma(sigma)));
    }

    function test_signal_brokenOracleNeverBricksSwaps() public {
        hook.setSignalOracle(ISignalOracle(address(new RevertingOracle())));
        vm.warp(T0 + 60);
        swapExactIn(true, 1e18);
        assertEq(hook.currentFee(poolId), 3000);

        hook.setSignalOracle(ISignalOracle(address(new GarbageOracle())));
        swapExactIn(false, 1e18);
        assertEq(hook.currentFee(poolId), 3000);

        hook.setSignalOracle(ISignalOracle(makeAddr("eoa-no-code")));
        swapExactIn(true, 1e18);
        assertEq(hook.currentFee(poolId), 3000);
    }

    // admin

    function test_admin_onlyOwner() public {
        vm.startPrank(alice);
        bytes memory err = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice);
        vm.expectRevert(err);
        hook.setRegimeFees([uint24(500), 3000, 7500, 15_000]);
        vm.expectRevert(err);
        hook.setRegimeThresholds([uint32(150), 400, 900]);
        vm.expectRevert(err);
        hook.setSignalOracle(ISignalOracle(alice));
        vm.stopPrank();
    }

    function test_admin_setRegimeFeesBounds() public {
        vm.expectRevert(IRangefyHook.InvalidFees.selector);
        hook.setRegimeFees([uint24(99), 3000, 7500, 15_000]);
        vm.expectRevert(IRangefyHook.InvalidFees.selector);
        hook.setRegimeFees([uint24(500), 3000, 7500, 30_001]);
        vm.expectRevert(IRangefyHook.InvalidFees.selector);
        hook.setRegimeFees([uint24(500), 3000, 2999, 15_000]);

        hook.setRegimeFees([uint24(100), 100, 100, 30_000]);
        assertEq(hook.regimeFee(3), 30_000);
        assertEq(hook.currentFee(poolId), 100);
    }

    function test_admin_setRegimeThresholdsBounds() public {
        vm.expectRevert(IRangefyHook.InvalidThresholds.selector);
        hook.setRegimeThresholds([uint32(400), 400, 900]);
        vm.expectRevert(IRangefyHook.InvalidThresholds.selector);
        hook.setRegimeThresholds([uint32(19), 400, 900]);
        vm.expectRevert(IRangefyHook.InvalidThresholds.selector);
        hook.setRegimeThresholds([uint32(150), 400, 5001]);
        hook.setRegimeThresholds([uint32(200), 500, 1000]);
        assertEq(hook.regimeThresholds(1), 500);
    }

    function test_admin_vaultFeeSetters() public {
        vm.prank(makeAddr("alice"));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, makeAddr("alice")));
        hook.setVaultFactory(address(1));

        vm.expectRevert(IRangefyHook.InvalidFees.selector);
        hook.setVaultSwapFee(99);
        vm.expectRevert(IRangefyHook.InvalidFees.selector);
        hook.setVaultSwapFee(30_001);
        hook.setVaultSwapFee(100);
        assertEq(hook.vaultSwapFee(), 100);
    }

    function test_vaultFactory_brokenFactoryNeverBricksSwaps() public {
        hook.setVaultFactory(address(new RevertingOracle()));
        vm.warp(T0 + 60);
        swapExactIn(true, 1e18);
        hook.setVaultFactory(address(new GarbageOracle())); // returns 1 → treated as vault
        swapExactIn(false, 1e18);
        hook.setVaultFactory(makeAddr("eoa"));
        swapExactIn(true, 1e18);
    }

    function test_admin_setSignalOracleRejectsZero() public {
        vm.expectRevert(IRangefyHook.ZeroAddress.selector);
        hook.setSignalOracle(ISignalOracle(address(0)));
    }
}
