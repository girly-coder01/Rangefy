// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Script.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";

import {HelperConfig} from "../HelperConfig.s.sol";

/// @notice anvil only: fresh v4 PoolManager + PoolModifyLiquidityTest.
contract DeployV4Local is HelperConfig {
    function run() external {
        require(block.chainid == 31_337, "local only");
        uint256 pk = deployerKey();
        vm.startBroadcast(pk);
        PoolManager pm = new PoolManager(vm.addr(pk));
        PoolModifyLiquidityTest mlr = new PoolModifyLiquidityTest(IPoolManager(address(pm)));
        vm.stopBroadcast();

        string[] memory k = new string[](2);
        address[] memory a = new address[](2);
        (k[0], a[0]) = ("poolManager", address(pm));
        (k[1], a[1]) = ("modifyLiquidityTest", address(mlr));
        save("v4", k, a);
        console2.log("PoolManager", address(pm));
        console2.log("PoolModifyLiquidityTest", address(mlr));
    }
}
