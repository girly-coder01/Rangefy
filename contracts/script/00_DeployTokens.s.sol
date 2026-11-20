// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/// @notice mWETH + mUSDC faucet tokens; funds MIRROR if set.
contract DeployTokens is HelperConfig {
    function run() external {
        vm.startBroadcast(deployerKey());
        MockERC20 weth = new MockERC20("Mock Wrapped Ether", "mWETH", 18, 5e18);
        MockERC20 usdc = new MockERC20("Mock USD Coin", "mUSDC", 6, 20_000e6);

        address mirror = vm.envOr("MIRROR", address(0));
        if (mirror != address(0)) {
            weth.mint(mirror, 1000e18);
            usdc.mint(mirror, 3_000_000e6);
        }
        vm.stopBroadcast();

        string[] memory k = new string[](2);
        address[] memory a = new address[](2);
        (k[0], a[0]) = ("mWETH", address(weth));
        (k[1], a[1]) = ("mUSDC", address(usdc));
        save("tokens", k, a);
        console2.log("mWETH", address(weth));
        console2.log("mUSDC", address(usdc));
    }
}
