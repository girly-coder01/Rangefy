// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Script.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {HelperConfig} from "./HelperConfig.s.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {CuratorRegistry} from "../src/curator/CuratorRegistry.sol";
import {VaultFactory} from "../src/vault/VaultFactory.sol";
import {RangeVault} from "../src/vault/RangeVault.sol";
import {Profile, StrategyParams} from "../src/interfaces/IVaultFactory.sol";

/// @notice Three demo curators, one seeded vault each.
contract SeedCurators is HelperConfig {
    struct Seed {
        string envKey;
        string name;
        string bio;
        Profile profile;
        string vaultName;
        string symbol;
    }

    function run() external {
        uint256 pk = deployerKey();
        address weth = load("tokens", "mWETH");
        address usdc = load("tokens", "mUSDC");
        CuratorRegistry registry = CuratorRegistry(load("core", "curatorRegistry"));
        VaultFactory factory = VaultFactory(load("core", "vaultFactory"));
        uint256 ethPrice = vm.envOr("ETH_PRICE_USD", uint256(3000));
        bool wethIs0 = weth < usdc;
        PoolKey memory key = PoolKey(
            Currency.wrap(wethIs0 ? weth : usdc),
            Currency.wrap(wethIs0 ? usdc : weth),
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            TICK_SPACING,
            IHooks(load("core", "hook"))
        );

        Seed[3] memory seeds = [
            Seed(
                "CURATOR_ATLAS_KEY",
                "Atlas",
                "Wide, patient ranges.",
                Profile.Conservative,
                "Atlas Conservative",
                "rfATL"
            ),
            Seed(
                "CURATOR_HARBOR_KEY",
                "Harbor",
                "Balanced width, steady fees.",
                Profile.Balanced,
                "Harbor Balanced",
                "rfHRB"
            ),
            Seed(
                "CURATOR_VECTOR_KEY",
                "Vector",
                "Tight ranges, frequent moves.",
                Profile.Aggressive,
                "Vector Aggressive",
                "rfVEC"
            )
        ];

        uint256 seedWeth = 2e18;
        uint256 seedUsdc = seedWeth * ethPrice / 1e12;
        address[] memory vaults = new address[](3);
        string[] memory names = new string[](3);

        for (uint256 i; i < 3; ++i) {
            uint256 ck = vm.envUint(seeds[i].envKey);
            address c = vm.addr(ck);

            vm.startBroadcast(pk);
            MockERC20(weth).mint(c, seedWeth * 2);
            MockERC20(usdc).mint(c, seedUsdc * 2);
            vm.stopBroadcast();

            StrategyParams memory none;
            vm.startBroadcast(ck);
            if (!registry.isCurator(c)) registry.register(seeds[i].name, _metadata(seeds[i].bio));
            RangeVault v =
                RangeVault(factory.createVault(key, seeds[i].profile, none, seeds[i].vaultName, seeds[i].symbol));
            MockERC20(weth).approve(address(v), type(uint256).max);
            MockERC20(usdc).approve(address(v), type(uint256).max);
            (uint256 a0, uint256 a1) = wethIs0 ? (seedWeth, seedUsdc * 11 / 10) : (seedUsdc * 11 / 10, seedWeth);
            v.deposit(a0, a1, 0, c);
            vm.stopBroadcast();

            vaults[i] = address(v);
            names[i] = seeds[i].symbol;
            console2.log(seeds[i].vaultName, address(v));
        }
        save("vaults", names, vaults);
    }

    function _metadata(string memory bio) internal pure returns (string memory) {
        return string.concat("data:application/json,{\"bio\":\"", bio, "\"}");
    }
}
