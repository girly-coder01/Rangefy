// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {SignalOracle} from "../../src/oracle/SignalOracle.sol";
import {ISignalOracle, Signal, Regime} from "../../src/interfaces/ISignalOracle.sol";
import {Constants} from "../../src/libraries/Constants.sol";

contract SignalOracleTest is Test {
    SignalOracle oracle;
    address updater = makeAddr("updater");
    address alice = makeAddr("alice");
    PoolId constant POOL = PoolId.wrap(bytes32(uint256(1)));
    PoolId constant POOL2 = PoolId.wrap(bytes32(uint256(2)));

    function setUp() public {
        vm.warp(1_700_000_000);
        oracle = new SignalOracle(address(this), updater);
    }

    function _post(uint32 sigma, int32 drift, uint16 conf) internal {
        vm.prank(updater);
        oracle.postSignal(POOL, sigma, drift, Regime.High, conf, bytes8("v1"));
    }

    function test_constructor_rejectsZeroUpdater() public {
        vm.expectRevert(ISignalOracle.ZeroAddress.selector);
        new SignalOracle(address(this), address(0));
    }

    function test_post_storesAndEmits() public {
        vm.expectEmit(true, false, false, true, address(oracle));
        emit ISignalOracle.SignalPosted(POOL, 520, 80, Regime.High, 7000, bytes8("v1"), uint40(vm.getBlockTimestamp()));
        _post(520, 80, 7000);

        (Signal memory s, bool fresh) = oracle.getSignal(POOL);
        assertTrue(fresh);
        assertEq(s.sigmaTicks, 520);
        assertEq(s.driftTicks, 80);
        assertEq(uint8(s.regime), uint8(Regime.High));
        assertEq(s.confidenceBps, 7000);
        assertEq(s.updatedAt, vm.getBlockTimestamp());
        assertEq(s.modelVersion, bytes8("v1"));
    }

    function test_post_onlyUpdater() public {
        vm.prank(alice);
        vm.expectRevert(ISignalOracle.NotUpdater.selector);
        oracle.postSignal(POOL, 520, 0, Regime.Normal, 0, bytes8(0));
    }

    function test_post_bounds() public {
        vm.startPrank(updater);
        vm.expectRevert(ISignalOracle.SignalOutOfBounds.selector);
        oracle.postSignal(POOL, Constants.MIN_SIGMA_TICKS - 1, 0, Regime.Calm, 0, bytes8(0));
        vm.expectRevert(ISignalOracle.SignalOutOfBounds.selector);
        oracle.postSignal(POOL, Constants.MAX_SIGMA_TICKS + 1, 0, Regime.Calm, 0, bytes8(0));
        vm.expectRevert(ISignalOracle.SignalOutOfBounds.selector);
        oracle.postSignal(POOL, 300, Constants.MAX_DRIFT_TICKS + 1, Regime.Calm, 0, bytes8(0));
        vm.expectRevert(ISignalOracle.SignalOutOfBounds.selector);
        oracle.postSignal(POOL, 300, -Constants.MAX_DRIFT_TICKS - 1, Regime.Calm, 0, bytes8(0));
        vm.expectRevert(ISignalOracle.SignalOutOfBounds.selector);
        oracle.postSignal(POOL, 300, 0, Regime.Calm, 10_001, bytes8(0));

        // Edges are inclusive
        oracle.postSignal(POOL, Constants.MIN_SIGMA_TICKS, -Constants.MAX_DRIFT_TICKS, Regime.Calm, 0, bytes8(0));
        oracle.postSignal(POOL, Constants.MAX_SIGMA_TICKS, Constants.MAX_DRIFT_TICKS, Regime.Extreme, 10_000, bytes8(0));
        vm.stopPrank();
    }

    function test_freshness_boundary() public {
        _post(300, 0, 0);
        vm.warp(vm.getBlockTimestamp() + Constants.MAX_SIGNAL_AGE);
        (, bool fresh) = oracle.getSignal(POOL);
        assertTrue(fresh, "fresh at exactly MAX_SIGNAL_AGE");
        vm.warp(vm.getBlockTimestamp() + 1);
        (, fresh) = oracle.getSignal(POOL);
        assertFalse(fresh, "stale after MAX_SIGNAL_AGE");
    }

    function test_unknownPool_isNotFresh() public view {
        (Signal memory s, bool fresh) = oracle.getSignal(POOL2);
        assertFalse(fresh);
        assertEq(s.updatedAt, 0);
    }

    function test_postSignals_batch() public {
        PoolId[] memory ids = new PoolId[](2);
        ids[0] = POOL;
        ids[1] = POOL2;
        Signal[] memory sigs = new Signal[](2);
        sigs[0] = Signal(400, 10, Regime.Normal, 5000, 0, bytes8("a"));
        sigs[1] = Signal(900, -20, Regime.Extreme, 6000, 123, bytes8("b"));

        vm.prank(updater);
        oracle.postSignals(ids, sigs);

        (Signal memory s1,) = oracle.getSignal(POOL);
        (Signal memory s2, bool fresh2) = oracle.getSignal(POOL2);
        assertEq(s1.sigmaTicks, 400);
        assertEq(s2.driftTicks, -20);
        assertEq(s2.updatedAt, vm.getBlockTimestamp(), "input updatedAt ignored");
        assertTrue(fresh2);
    }

    function test_postSignals_lengthMismatch() public {
        vm.prank(updater);
        vm.expectRevert(ISignalOracle.LengthMismatch.selector);
        oracle.postSignals(new PoolId[](1), new Signal[](2));
    }

    function test_postSignals_boundsCheckedPerItem() public {
        PoolId[] memory ids = new PoolId[](1);
        Signal[] memory sigs = new Signal[](1);
        sigs[0] = Signal(1, 0, Regime.Calm, 0, 0, bytes8(0));
        vm.prank(updater);
        vm.expectRevert(ISignalOracle.SignalOutOfBounds.selector);
        oracle.postSignals(ids, sigs);
    }

    function test_setUpdater() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        oracle.setUpdater(alice);

        vm.expectRevert(ISignalOracle.ZeroAddress.selector);
        oracle.setUpdater(address(0));

        oracle.setUpdater(alice);
        assertEq(oracle.updater(), alice);
        vm.prank(updater);
        vm.expectRevert(ISignalOracle.NotUpdater.selector);
        oracle.postSignal(POOL, 300, 0, Regime.Calm, 0, bytes8(0));
    }
}
