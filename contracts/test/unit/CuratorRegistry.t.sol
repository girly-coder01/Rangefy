// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CuratorRegistry} from "../../src/curator/CuratorRegistry.sol";
import {ICuratorRegistry, Curator} from "../../src/interfaces/ICuratorRegistry.sol";

contract CuratorRegistryTest is Test {
    CuratorRegistry reg;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        reg = new CuratorRegistry();
    }

    function test_register() public {
        vm.expectEmit(true, false, false, true);
        emit ICuratorRegistry.CuratorRegistered(alice, "Atlas", "data:application/json;base64,e30=");
        vm.prank(alice);
        reg.register("Atlas", "data:application/json;base64,e30=");

        assertTrue(reg.isCurator(alice));
        Curator memory c = reg.getCurator(alice);
        assertEq(c.name, "Atlas");
        assertEq(c.registeredAt, vm.getBlockTimestamp());
        assertTrue(c.active);
        assertEq(reg.allCurators().length, 1);
        assertEq(reg.curatorCount(), 1);
    }

    function test_register_twiceReverts() public {
        vm.startPrank(alice);
        reg.register("Atlas", "");
        vm.expectRevert(ICuratorRegistry.AlreadyRegistered.selector);
        reg.register("Atlas2", "");
        vm.stopPrank();
    }

    function test_register_nameUniqueCaseInsensitive() public {
        vm.prank(alice);
        reg.register("Atlas", "");
        vm.prank(bob);
        vm.expectRevert(ICuratorRegistry.NameTaken.selector);
        reg.register("ATLAS", "");
    }

    function test_register_nameValidation() public {
        string[6] memory bad =
            ["ab", "this-name-is-way-too-long-for-the-reg", "bad!", " lead", "trail ", unicode"émile"];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(alice);
            vm.expectRevert(ICuratorRegistry.InvalidName.selector);
            reg.register(bad[i], "");
        }
        vm.prank(alice);
        reg.register("Ok_Name-1 x", "");
        vm.prank(bob);
        reg.register("abc", ""); // min length
    }

    function test_update() public {
        vm.prank(alice);
        vm.expectRevert(ICuratorRegistry.NotRegistered.selector);
        reg.update("x");

        vm.startPrank(alice);
        reg.register("Atlas", "a");
        reg.update("b");
        vm.stopPrank();
        assertEq(reg.getCurator(alice).metadataURI, "b");
    }

    function test_isCurator_falseForUnknown() public view {
        assertFalse(reg.isCurator(bob));
    }
}
