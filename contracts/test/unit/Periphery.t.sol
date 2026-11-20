// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {RangefyFixture} from "../utils/RangefyFixture.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {SimpleSwapRouter} from "../../src/periphery/SimpleSwapRouter.sol";
import {RangefyLens} from "../../src/periphery/RangefyLens.sol";
import {RangeVault} from "../../src/vault/RangeVault.sol";
import {Profile} from "../../src/interfaces/IVaultFactory.sol";
import {Regime} from "../../src/interfaces/ISignalOracle.sol";

contract MockERC20Test is Test {
    MockERC20 t;
    address alice = makeAddr("alice");

    function setUp() public {
        vm.warp(1_700_000_000);
        t = new MockERC20("Mock USD Coin", "mUSDC", 6, 20_000e6);
    }

    function test_decimals() public view {
        assertEq(t.decimals(), 6);
    }

    function test_faucet_oncePer24h() public {
        vm.startPrank(alice);
        t.faucet();
        assertEq(t.balanceOf(alice), 20_000e6);
        vm.expectRevert(abi.encodeWithSelector(MockERC20.FaucetCooldown.selector, vm.getBlockTimestamp() + 24 hours));
        t.faucet();
        assertEq(t.faucetAvailableIn(alice), 24 hours);
        vm.warp(vm.getBlockTimestamp() + 24 hours);
        t.faucet();
        assertEq(t.balanceOf(alice), 40_000e6);
        vm.stopPrank();
    }

    function test_mint_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        t.mint(alice, 1);
        t.mint(alice, 5);
        assertEq(t.balanceOf(alice), 5);
    }
}

contract RouterAndLensTest is RangefyFixture {
    SimpleSwapRouter router;
    RangefyLens lens;

    function setUp() public {
        setUpRangefy();
        setUpVaultStack();
        router = new SimpleSwapRouter(manager);
        lens = new RangefyLens(manager, hook, factory, registry);
        _approve(alice, address(router));
    }

    function test_swapExactIn() public {
        vm.warp(vm.getBlockTimestamp() + 60);
        uint256 b0 = bal0(alice);
        uint256 b1 = bal1(alice);
        vm.prank(alice);
        uint256 out = router.swapExactIn(poolKey, true, 1e18, 0.99e18, alice, vm.getBlockTimestamp());
        assertEq(b0 - bal0(alice), 1e18);
        assertEq(bal1(alice) - b1, out);
        assertGt(out, 0.99e18);
    }

    function test_swapExactIn_minOutAndDeadline() public {
        vm.prank(alice);
        vm.expectRevert(SimpleSwapRouter.TooLittleReceived.selector);
        router.swapExactIn(poolKey, true, 1e18, 1e18, alice, vm.getBlockTimestamp());
        vm.prank(alice);
        vm.expectRevert(SimpleSwapRouter.Expired.selector);
        router.swapExactIn(poolKey, true, 1e18, 0, alice, vm.getBlockTimestamp() - 1);
    }

    function test_swapToPrice_stopsAtLimit() public {
        uint160 target = TickMath.getSqrtPriceAtTick(300);
        vm.prank(alice);
        router.swapToPrice(poolKey, target, 1000e18, alice);
        assertEq(spotTick(), 300);
    }

    function test_swapToPrice_budgetBound() public {
        uint160 target = TickMath.getSqrtPriceAtTick(-3000);
        uint256 b0 = bal0(alice);
        vm.prank(alice);
        router.swapToPrice(poolKey, target, 1e18, alice);
        assertEq(b0 - bal0(alice), 1e18, "spent exactly the budget");
        assertGt(spotTick(), -3000, "did not reach target");
    }

    function test_lens_poolAndVaults() public {
        postSignal(500, 40, Regime.High);
        RangeVault v = createVault(Profile.Balanced);
        vm.prank(alice);
        v.deposit(10e18, 10e18, 0, alice);

        RangefyLens.PoolView memory p = lens.getPool(poolKey);
        assertEq(p.sigma, 500);
        assertEq(p.drift, 40);
        assertTrue(p.signalFresh);
        assertEq(p.regime, uint8(Regime.High));
        assertEq(p.fee, 7500);
        assertGt(p.poolLiquidity, 0);

        RangefyLens.VaultView[] memory vs = lens.getAllVaults();
        assertEq(vs.length, 1);
        assertEq(vs[0].vault, address(v));
        assertEq(vs[0].curatorName, "Harbor");
        assertTrue(vs[0].inRange);
        assertGt(vs[0].sharePriceWad, 0);

        (address[] memory vaults, uint256[] memory shares, uint256[] memory a0,) = lens.getUserPositions(alice);
        assertEq(vaults.length, 1);
        assertEq(shares[0], v.balanceOf(alice));
        assertGt(a0[0], 0);
        (address[] memory none,,,) = lens.getUserPositions(bob);
        assertEq(none.length, 0);
    }
}
