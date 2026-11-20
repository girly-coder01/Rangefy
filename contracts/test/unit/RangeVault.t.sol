// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {RangefyFixture} from "../utils/RangefyFixture.sol";
import {RangeVault} from "../../src/vault/RangeVault.sol";
import {IRangeVault, RebalanceReason} from "../../src/interfaces/IRangeVault.sol";
import {IVaultFactory, Profile, StrategyParams} from "../../src/interfaces/IVaultFactory.sol";
import {Regime} from "../../src/interfaces/ISignalOracle.sol";
import {Constants} from "../../src/libraries/Constants.sol";

contract RangeVaultTest is RangefyFixture {
    using StateLibrary for IPoolManager;

    RangeVault v;

    function setUp() public {
        setUpRangefy();
        setUpVaultStack();
        v = createVault(Profile.Balanced);
    }

    function _deposit(address who, uint256 a0, uint256 a1) internal returns (uint256 shares, uint256 u0, uint256 u1) {
        vm.prank(who);
        return v.deposit(a0, a1, 0, who);
    }

    // EMA converges, cooldown passes
    function _settle() internal {
        vm.warp(vm.getBlockTimestamp() + 2 hours);
    }

    // deposit

    function test_firstDeposit_mintsLiquidityAndBurnsMinShares() public {
        (int24 tLo, int24 tHi,,) = v.targetRange();
        (uint256 shares, uint256 u0, uint256 u1) = _deposit(alice, 10e18, 10e18);

        (uint128 liq, int24 lo, int24 hi) = v.getPosition();
        assertEq(lo, tLo);
        assertEq(hi, tHi);
        assertEq(shares, uint256(liq) - Constants.MIN_SHARES);
        assertEq(v.balanceOf(Constants.DEAD), Constants.MIN_SHARES);
        assertEq(v.balanceOf(alice), shares);
        assertEq(v.totalSupply(), liq);
        assertLe(u0, 10e18);
        assertLe(u1, 10e18);
        assertEq(bal0(alice), 1_000_000e18 - u0);
        assertEq(v.lastRebalance(), vm.getBlockTimestamp());
    }

    function test_firstDeposit_rangeFromSigma() public view {
        // σ ≈ 299 on-chain → 2σ = 598 → ceil to 600; EMA 0 → [-600, 600]
        (int24 lo, int24 hi, uint32 sigma, bool fromSignal) = v.targetRange();
        assertEq(sigma, 299);
        assertFalse(fromSignal);
        assertEq(lo, -600);
        assertEq(hi, 600);
    }

    function test_previewDeposit_matchesDeposit() public {
        (uint256 ps, uint256 p0, uint256 p1) = v.previewDeposit(10e18, 7e18);
        (uint256 s, uint256 u0, uint256 u1) = _deposit(alice, 10e18, 7e18);
        assertEq(ps, s);
        assertEq(p0, u0);
        assertEq(p1, u1);

        (ps, p0, p1) = v.previewDeposit(3e18, 3e18);
        (s, u0, u1) = _deposit(bob, 3e18, 3e18);
        assertEq(ps, s);
        assertApproxEqAbs(p0, u0, 2);
        assertApproxEqAbs(p1, u1, 2);
    }

    function test_secondDeposit_isProportional() public {
        (uint256 s1, uint256 a0, uint256 a1) = _deposit(alice, 10e18, 10e18);
        (uint256 s2, uint256 b0, uint256 b1) = _deposit(bob, a0 / 2, a1 / 2);
        assertApproxEqRel(s2 * 2, s1 + Constants.MIN_SHARES, 1e14);
        assertLe(b0, a0 / 2);
        assertLe(b1, a1 / 2);
    }

    function test_deposit_respectsMaxes() public {
        _deposit(alice, 10e18, 10e18);
        // Bob is token1-constrained: uses all-but-dust of token1, less token0.
        (, uint256 b0, uint256 b1) = _deposit(bob, 100e18, 1e18);
        assertLe(b1, 1e18);
        assertGt(b1, 1e18 - 1e15);
        assertLt(b0, 100e18);
    }

    function test_deposit_minSharesSlippage() public {
        (uint256 ps,,) = v.previewDeposit(10e18, 10e18);
        vm.prank(alice);
        vm.expectRevert(IRangeVault.Slippage.selector);
        v.deposit(10e18, 10e18, ps + 1, alice);
    }

    function test_deposit_zeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(IRangeVault.ZeroAmount.selector);
        v.deposit(0, 0, 0, alice);
    }

    function test_deposit_tooSmallFirstDepositReverts() public {
        vm.prank(alice);
        vm.expectRevert(IRangeVault.InsufficientShares.selector);
        v.deposit(10, 10, 0, alice); // L ≈ 300 < MIN_SHARES
    }

    function test_deposit_pausedReverts_withdrawStillWorks() public {
        (uint256 s,,) = _deposit(alice, 10e18, 10e18);
        vm.prank(curatorAddr);
        v.setDepositsPaused(true);

        vm.prank(bob);
        vm.expectRevert(IRangeVault.DepositsArePaused.selector);
        v.deposit(1e18, 1e18, 0, bob);

        vm.prank(alice);
        v.withdraw(s, 0, 0, alice);
        assertEq(v.balanceOf(alice), 0);
    }

    function test_deposit_priceDeviationReverts() public {
        _deposit(alice, 10e18, 10e18);
        vm.warp(vm.getBlockTimestamp() + 60);
        swapToTick(400); // same block: EMA stays near 0, spot is 400 ticks away (> 90)
        vm.prank(bob);
        vm.expectRevert(IRangeVault.PriceDeviation.selector);
        v.deposit(1e18, 1e18, 0, bob);
    }

    function test_sandwich_manipulateAndDepositInOneTxReverts() public {
        _deposit(alice, 10e18, 10e18);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        // Attacker pushes price and deposits in the same block/tx.
        swapToTick(-300);
        vm.prank(bob);
        vm.expectRevert(IRangeVault.PriceDeviation.selector);
        v.deposit(5e18, 5e18, 0, bob);
    }

    function test_accruedFeesNotStolenByLateDepositor() public {
        _deposit(alice, 50e18, 50e18);
        vm.warp(vm.getBlockTimestamp() + 60);
        generateFees(5, 20e18);

        uint256 b0 = bal0(bob);
        uint256 b1 = bal1(bob);
        (uint256 s,,) = _deposit(bob, 10e18, 10e18);
        vm.prank(bob);
        v.withdraw(s, 0, 0, bob);

        // Bob can only lose rounding dust; he captures none of the earlier fees.
        assertLe(bal0(bob), b0);
        assertLe(bal1(bob), b1);
        assertApproxEqAbs(bal0(bob), b0, 10);
        assertApproxEqAbs(bal1(bob), b1, 10);
    }

    // withdraw

    function test_withdraw_proRata() public {
        (uint256 s, uint256 u0, uint256 u1) = _deposit(alice, 10e18, 10e18);
        (uint256 p0, uint256 p1) = v.previewWithdraw(s / 2);
        vm.prank(alice);
        (uint256 o0, uint256 o1) = v.withdraw(s / 2, 0, 0, alice);
        assertEq(o0, p0);
        assertEq(o1, p1);
        assertApproxEqRel(o0 * 2, u0, 1e14);
        assertApproxEqRel(o1 * 2, u1, 1e14);
    }

    function test_withdraw_minAmounts() public {
        (uint256 s,,) = _deposit(alice, 10e18, 10e18);
        (uint256 p0,) = v.previewWithdraw(s);
        vm.prank(alice);
        vm.expectRevert(IRangeVault.Slippage.selector);
        v.withdraw(s, p0 + 1, 0, alice);
    }

    function test_withdraw_worksWithPriceDeviation() public {
        (uint256 s,,) = _deposit(alice, 10e18, 10e18);
        vm.warp(vm.getBlockTimestamp() + 60);
        swapToTick(450);
        vm.prank(alice);
        v.withdraw(s, 0, 0, alice);
        assertEq(v.balanceOf(alice), 0);
    }

    function test_withdraw_fullExitLeavesOnlyDeadShares() public {
        (uint256 s,,) = _deposit(alice, 10e18, 10e18);
        vm.prank(alice);
        v.withdraw(s, 0, 0, alice);
        assertEq(v.totalSupply(), Constants.MIN_SHARES);
        (uint128 liq,,) = v.getPosition();
        assertEq(liq, Constants.MIN_SHARES);
    }

    function test_withdraw_moreThanBalanceReverts() public {
        (uint256 s,,) = _deposit(alice, 10e18, 10e18);
        vm.prank(alice);
        vm.expectRevert(IRangeVault.InsufficientShares.selector);
        v.withdraw(s + 1, 0, 0, alice);
    }

    function test_withdraw_roundTripReturnsDeposit() public {
        uint256 b0 = bal0(alice);
        uint256 b1 = bal1(alice);
        (uint256 s,,) = _deposit(alice, 10e18, 10e18);
        vm.prank(alice);
        v.withdraw(s, 0, 0, alice);
        assertApproxEqAbs(bal0(alice), b0, 1e6);
        assertApproxEqAbs(bal1(alice), b1, 1e6);
        assertLe(bal0(alice), b0);
        assertLe(bal1(alice), b1);
    }

    // rebalance

    function test_needsRebalance_falseAfterDeposit() public {
        _deposit(alice, 10e18, 10e18);
        // past cooldown, σ decay stays under the 30% width-drift threshold
        vm.warp(vm.getBlockTimestamp() + 16 minutes);
        (bool needed, RebalanceReason r) = v.needsRebalance();
        assertFalse(needed);
        assertEq(uint8(r), uint8(RebalanceReason.None));
        vm.expectRevert(IRangeVault.NoRebalanceNeeded.selector);
        v.rebalance();
    }

    function test_rebalance_outOfRange() public {
        _deposit(alice, 10e18, 10e18);
        swapToTick(900);
        _settle();
        (bool needed, RebalanceReason r) = v.needsRebalance();
        assertTrue(needed);
        assertEq(uint8(r), uint8(RebalanceReason.OutOfRange));
        _assertRebalanceToTarget(RebalanceReason.OutOfRange);
    }

    function test_rebalance_nearEdge() public {
        _deposit(alice, 10e18, 10e18); // [-600, 600], buffer 120
        swapToTick(-540);
        _settle();
        (, RebalanceReason r) = v.needsRebalance();
        assertEq(uint8(r), uint8(RebalanceReason.NearEdge));
        _assertRebalanceToTarget(RebalanceReason.NearEdge);
    }

    function test_rebalance_widthDrift() public {
        _deposit(alice, 10e18, 10e18);
        _settle();
        postSignal(1000, 0, Regime.High); // 2σ = 2000 vs current 600
        (, RebalanceReason r) = v.needsRebalance();
        assertEq(uint8(r), uint8(RebalanceReason.WidthDrift));
        _assertRebalanceToTarget(RebalanceReason.WidthDrift);
        assertEq(v.tickUpper() - v.tickLower(), 4080); // 2σ = 2000 → ceil to spacing 2040
    }

    function test_rebalance_driftBiasShiftsCentre() public {
        _deposit(alice, 10e18, 10e18);
        _settle();
        postSignal(1000, 2000, Regime.High); // hw 2040, bias = 2000 * 20% = 400 (≤ hw/2)
        v.rebalance();
        assertEq(v.tickLower(), -1680); // floorTo(400 - 2040)
        assertEq(v.tickUpper(), 2460); // ceilTo(400 + 2040)
    }

    function test_rebalance_cooldown() public {
        _deposit(alice, 10e18, 10e18);
        swapToTick(900);
        vm.warp(vm.getBlockTimestamp() + 10 minutes); // < 15 min Balanced cooldown
        (bool needed,) = v.needsRebalance();
        assertFalse(needed);
        vm.expectRevert(IRangeVault.Cooldown.selector);
        v.rebalance();
    }

    function test_rebalance_priceDeviationGuard() public {
        _deposit(alice, 10e18, 10e18);
        _settle();
        swapToTick(900); // same block → EMA lags
        (bool needed,) = v.needsRebalance();
        assertFalse(needed);
        vm.expectRevert(IRangeVault.PriceDeviation.selector);
        v.rebalance();
    }

    function test_rebalance_ratioSwapLeavesLittleIdle() public {
        _deposit(alice, 1e18, 1e18); // small vs pool depth: the ratio swap stays inside the price limit
        swapToTick(1500); // fully out of range → position all token1
        _settle();
        v.rebalance();
        assertLt(_idleBps(), 100, "idle < 1% of value");
        (uint128 liq,,) = v.getPosition();
        assertGt(liq, 0);
        (bool needed,) = v.needsRebalance();
        assertFalse(needed);
    }

    function test_rebalance_limitStoppedSwapRedeploysIdleLater() public {
        _deposit(alice, 10e18, 10e18); // large vs pool depth: ratio swap hits EMA + 100 ticks and stops
        swapToTick(1500);
        _settle();
        v.rebalance();
        uint256 idleAfterFirst = _idleBps();
        assertGe(idleAfterFirst, Constants.IDLE_REBALANCE_BPS, "swap stopped at the price limit");

        vm.warp(vm.getBlockTimestamp() + 16 minutes); // cooldown; EMA catches up with spot
        // first range used maxHalfWidth; hold the target there so only idle capital triggers
        postSignal(3000, 0, Regime.High);
        (bool needed, RebalanceReason r) = v.needsRebalance();
        assertTrue(needed);
        assertEq(uint8(r), uint8(RebalanceReason.IdleExcess));
        v.rebalance();
        assertLt(_idleBps(), idleAfterFirst, "second pass redeploys more");
    }

    function _idleBps() internal view returns (uint256) {
        (uint160 sqrtP,,,) = manager.getSlot0(poolId);
        uint256 p = uint256(sqrtP) * uint256(sqrtP) / (1 << 96) * 1e18 / (1 << 96);
        (uint256 i0, uint256 i1) = v.idleBalances();
        (uint256 t0, uint256 t1) = v.getTotalAmounts();
        return (i0 * p / 1e18 + i1) * 10_000 / (t0 * p / 1e18 + t1);
    }

    function test_rebalance_oneSidedTargetSwapsEverything() public {
        // Tight custom strategy whose drift bias pushes the target range above spot.
        StrategyParams memory p = StrategyParams(5000, 60, 60, 5000, 60, 500, 0);
        vm.prank(curatorAddr);
        RangeVault t = RangeVault(factory.createVault(poolKey, Profile.Custom, p, "T", "T"));
        _approve(alice, address(t));
        vm.prank(alice);
        t.deposit(1e18, 1e18, 0, alice);
        _settle();
        postSignal(100, 2000, Regime.Calm); // hw 60, bias capped at 30 → [−60+30, 60+30] → [-60, 120] after rounding
        vm.prank(curatorAddr);
        t.curatorRebalance();
        assertLt(t.tickLower(), t.tickUpper());
        (uint128 liq,,) = t.getPosition();
        assertGt(liq, 0);
    }

    function test_rebalance_permissionlessAndCountsEvents() public {
        _deposit(alice, 10e18, 10e18);
        swapToTick(900);
        _settle();
        vm.prank(makeAddr("anyone"));
        v.rebalance();
        assertEq(v.rebalanceCount(), 1);
        assertEq(v.lastRebalance(), vm.getBlockTimestamp());
    }

    function test_rebalance_vaultSwapPaysVaultFee() public {
        _deposit(alice, 1e18, 1e18);
        swapToTick(900);
        _settle();
        uint256 p = _spotPrice();
        uint256 before = _valueAt(p);
        uint256 snap = vm.snapshotState();

        v.rebalance();
        uint256 lossDiscounted = before - _valueAt(p);
        vm.revertToState(snap);

        hook.setVaultFactory(address(0)); // vault now pays the Extreme regime fee
        v.rebalance();
        uint256 lossFull = before - _valueAt(p);
        assertGt(lossFull, lossDiscounted * 5);
    }

    function test_rebalance_preservesValue() public {
        _deposit(alice, 1e18, 1e18);
        swapToTick(900);
        _settle();
        uint256 p = _spotPrice();
        uint256 before = _valueAt(p);
        v.rebalance();
        // pool is Extreme here, but vault swaps pay vaultSwapFee (0.05%)
        assertApproxEqRel(_valueAt(p), before, 0.002e18);
        assertLt(_valueAt(p), before);
    }

    function _spotPrice() internal view returns (uint256) {
        (uint160 sqrtP,,,) = manager.getSlot0(poolId);
        return uint256(sqrtP) * uint256(sqrtP) / (1 << 96) * 1e18 / (1 << 96);
    }

    function _valueAt(uint256 p) internal view returns (uint256) {
        (uint256 t0, uint256 t1) = v.getTotalAmounts();
        return t0 * p / 1e18 + t1;
    }

    function _assertRebalanceToTarget(RebalanceReason expected) internal {
        (int24 tLo, int24 tHi,,) = v.targetRange();
        vm.expectEmit(false, false, false, false, address(v));
        emit IRangeVault.Rebalanced(expected, 0, 0, 0, 0, 0, 0, false, 0, 0);
        (int24 lo, int24 hi) = v.rebalance();
        assertEq(lo, tLo);
        assertEq(hi, tHi);
        assertEq(v.tickLower(), tLo);
        assertEq(v.tickUpper(), tHi);
        assertEq(lo % TICK_SPACING, 0);
        assertEq(hi % TICK_SPACING, 0);
    }

    // fees

    function test_harvest_accountsPerfFee() public {
        _deposit(alice, 50e18, 50e18);
        vm.warp(vm.getBlockTimestamp() + 60);
        generateFees(5, 20e18);

        (uint256 i0Before, uint256 i1Before) = v.idleBalances();
        v.harvest();
        (uint256 i0, uint256 i1) = v.idleBalances();
        uint256 c0 = v.curatorOwed0();
        uint256 c1 = v.curatorOwed1();
        assertGt(c0, 0);
        assertGt(c1, 0);
        // curator gets 10%, LPs 90%
        assertApproxEqAbs((i0 - i0Before) * 1000, c0 * 9000, 9000);
        assertApproxEqAbs((i1 - i1Before) * 1000, c1 * 9000, 9000);

        uint256 before = bal0(curatorAddr);
        vm.prank(curatorAddr);
        v.claimCuratorFees(curatorAddr);
        assertEq(bal0(curatorAddr) - before, c0);
        assertEq(v.curatorOwed0(), 0);
    }

    function test_totals_includePendingFeesNetOfPerfFee() public {
        _deposit(alice, 50e18, 50e18);
        vm.warp(vm.getBlockTimestamp() + 60);
        generateFees(3, 20e18);
        (uint256 t0, uint256 t1) = v.getTotalAmounts();
        v.harvest();
        (uint256 h0, uint256 h1) = v.getTotalAmounts();
        assertApproxEqAbs(t0, h0, 2);
        assertApproxEqAbs(t1, h1, 2);
    }

    function test_sharePrice_growsWithFees() public {
        _deposit(alice, 50e18, 50e18);
        uint256 p0 = v.sharePrice();
        vm.warp(vm.getBlockTimestamp() + 60);
        generateFees(5, 20e18);
        swapToTick(0);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        assertGt(v.sharePrice(), p0);
    }

    // curator

    function test_curator_onlyCurator() public {
        StrategyParams memory p = v.getParams();
        vm.startPrank(alice);
        vm.expectRevert(IRangeVault.OnlyCurator.selector);
        v.updateParams(p);
        vm.expectRevert(IRangeVault.OnlyCurator.selector);
        v.setDepositsPaused(true);
        vm.expectRevert(IRangeVault.OnlyCurator.selector);
        v.curatorRebalance();
        vm.expectRevert(IRangeVault.OnlyCurator.selector);
        v.claimCuratorFees(alice);
        vm.stopPrank();
    }

    function test_curator_updateParams() public {
        StrategyParams memory p = v.getParams();
        p.performanceFeeBps = 1001;
        vm.prank(curatorAddr);
        vm.expectRevert(IRangeVault.PerformanceFeeIncrease.selector);
        v.updateParams(p);

        p.performanceFeeBps = 500;
        p.maxEmaDeviation = 0;
        vm.prank(curatorAddr);
        vm.expectRevert(abi.encodeWithSelector(IVaultFactory.InvalidParams.selector, 5));
        v.updateParams(p);

        p.maxEmaDeviation = 90;
        p.widthMultiplierBps = 30_000;
        vm.prank(curatorAddr);
        v.updateParams(p);
        assertEq(v.getParams().performanceFeeBps, 500);
        assertEq(v.getParams().widthMultiplierBps, 30_000);
    }

    function test_curatorRebalance_skipsReasonButKeepsGuards() public {
        _deposit(alice, 10e18, 10e18);
        vm.prank(curatorAddr);
        vm.expectRevert(IRangeVault.Cooldown.selector);
        v.curatorRebalance();

        _settle();
        vm.prank(curatorAddr);
        v.curatorRebalance(); // no reason needed
        assertEq(v.rebalanceCount(), 1);
    }

    function test_unlockCallback_onlyPoolManager() public {
        vm.expectRevert(IRangeVault.OnlyPoolManager.selector);
        v.unlockCallback("");
    }
}
