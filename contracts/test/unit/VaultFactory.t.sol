// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {RangefyFixture} from "../utils/RangefyFixture.sol";
import {IVaultFactory, Profile, StrategyParams} from "../../src/interfaces/IVaultFactory.sol";
import {RangeVault} from "../../src/vault/RangeVault.sol";
import {VaultDeployer} from "../../src/vault/VaultDeployer.sol";
import {Constants} from "../../src/libraries/Constants.sol";

contract VaultFactoryTest is RangefyFixture {
    function setUp() public {
        setUpRangefy();
        setUpVaultStack();
    }

    function _valid() internal view returns (StrategyParams memory) {
        return factory.presetParams(Profile.Balanced);
    }

    function test_createVault_preset() public {
        RangeVault v = createVault(Profile.Balanced);
        assertTrue(factory.isVault(address(v)));
        assertEq(v.curator(), curatorAddr);
        assertEq(address(v.factory()), address(factory));
        assertEq(address(v.hook()), address(hook));
        assertEq(address(v.signalOracle()), address(oracle));
        assertEq(v.name(), "Harbor Balanced");
        assertEq(v.symbol(), "rfHRB");
        assertEq(v.decimals(), 18);
        assertEq(v.getParams().widthMultiplierBps, 20_000);

        assertEq(factory.allVaults().length, 1);
        assertEq(factory.vaultsOf(curatorAddr)[0], address(v));
        assertEq(factory.vaultsForPool(poolId)[0], address(v));
    }

    function test_createVault_custom() public {
        StrategyParams memory p = _valid();
        p.widthMultiplierBps = 25_000;
        vm.prank(curatorAddr);
        RangeVault v = RangeVault(factory.createVault(poolKey, Profile.Custom, p, "C", "C"));
        assertEq(v.getParams().widthMultiplierBps, 25_000);
    }

    function test_createVault_nonCuratorReverts() public {
        StrategyParams memory none;
        vm.prank(alice);
        vm.expectRevert(IVaultFactory.NotCurator.selector);
        factory.createVault(poolKey, Profile.Balanced, none, "x", "x");
    }

    function test_createVault_wrongHookReverts() public {
        PoolKey memory k = poolKey;
        k.hooks = IHooks(address(0xBEEF));
        StrategyParams memory none;
        vm.prank(curatorAddr);
        vm.expectRevert(IVaultFactory.WrongHook.selector);
        factory.createVault(k, Profile.Balanced, none, "x", "x");
    }

    function test_createVault_unregisteredPoolReverts() public {
        PoolKey memory k = poolKey;
        k.tickSpacing = 120; // never initialized
        StrategyParams memory none;
        vm.prank(curatorAddr);
        vm.expectRevert(IVaultFactory.PoolNotRegistered.selector);
        factory.createVault(k, Profile.Balanced, none, "x", "x");
    }

    function test_presets_areValid() public view {
        factory.validateParams(factory.presetParams(Profile.Aggressive), TICK_SPACING);
        factory.validateParams(factory.presetParams(Profile.Balanced), TICK_SPACING);
        factory.validateParams(factory.presetParams(Profile.Conservative), TICK_SPACING);
    }

    function test_presets_matchSpec() public view {
        StrategyParams memory a = factory.presetParams(Profile.Aggressive);
        assertEq(a.widthMultiplierBps, 10_000);
        assertEq(a.minRebalanceInterval, 5 minutes);
        assertEq(a.performanceFeeBps, 1500);
        StrategyParams memory c = factory.presetParams(Profile.Conservative);
        assertEq(c.minHalfWidth, 600);
        assertEq(c.maxHalfWidth, 12_000);
        assertEq(c.maxEmaDeviation, 120);
    }

    function test_custom_zeroParamsRejected() public {
        StrategyParams memory none;
        vm.prank(curatorAddr);
        vm.expectRevert(abi.encodeWithSelector(IVaultFactory.InvalidParams.selector, 0));
        factory.createVault(poolKey, Profile.Custom, none, "x", "x");
    }

    function _expectInvalid(StrategyParams memory p, uint8 field) internal {
        vm.expectRevert(abi.encodeWithSelector(IVaultFactory.InvalidParams.selector, field));
        factory.validateParams(p, TICK_SPACING);
    }

    function test_validate_edges() public {
        StrategyParams memory p;

        p = _valid();
        p.widthMultiplierBps = Constants.MIN_WIDTH_MULTIPLIER_BPS - 1;
        _expectInvalid(p, 0);
        p = _valid();
        p.widthMultiplierBps = Constants.MAX_WIDTH_MULTIPLIER_BPS + 1;
        _expectInvalid(p, 0);
        p = _valid();
        p.minHalfWidth = 0;
        _expectInvalid(p, 1);
        p = _valid(); // not a multiple of 60
        p.minHalfWidth = 330;
        _expectInvalid(p, 1);
        p = _valid(); // < min
        p.maxHalfWidth = 240;
        _expectInvalid(p, 2);
        p = _valid(); // > ceil
        p.maxHalfWidth = 40_020;
        _expectInvalid(p, 2);
        p = _valid();
        p.maxHalfWidth = 6030;
        _expectInvalid(p, 2);
        p = _valid();
        p.driftWeightBps = 5001;
        _expectInvalid(p, 3);
        p = _valid();
        p.minRebalanceInterval = 59;
        _expectInvalid(p, 4);
        p = _valid();
        p.minRebalanceInterval = 1 days + 1;
        _expectInvalid(p, 4);
        p = _valid();
        p.maxEmaDeviation = 0;
        _expectInvalid(p, 5);
        p = _valid();
        p.maxEmaDeviation = 501;
        _expectInvalid(p, 5);
        p = _valid();
        p.performanceFeeBps = 2001;
        _expectInvalid(p, 6);

        // Inclusive edges pass
        p = StrategyParams(5000, 60, 39_960, 5000, 60, 500, 2000);
        factory.validateParams(p, TICK_SPACING);
        p = StrategyParams(50_000, 60, 60, 0, 1 days, 1, 0);
        factory.validateParams(p, TICK_SPACING);
    }

    function test_deployer_onlyFactory() public {
        StrategyParams memory p = _valid();
        vm.expectRevert(VaultDeployer.OnlyFactory.selector);
        vaultDeployer.deploy(manager, hook, poolKey, p, alice, "x", "x");
    }

    function test_deployer_bindOnce() public {
        vm.expectRevert(VaultDeployer.AlreadyBound.selector);
        vaultDeployer.bindFactory(alice);
        VaultDeployer d = new VaultDeployer();
        vm.prank(alice);
        vm.expectRevert(VaultDeployer.NotAdmin.selector);
        d.bindFactory(alice);
    }
}
