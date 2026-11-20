// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {HelperConfig} from "./HelperConfig.s.sol";
import {HookMiner} from "../src/vendor/HookMiner.sol";
import {SignalOracle} from "../src/oracle/SignalOracle.sol";
import {ISignalOracle} from "../src/interfaces/ISignalOracle.sol";
import {CuratorRegistry} from "../src/curator/CuratorRegistry.sol";
import {RangefyHook} from "../src/hook/RangefyHook.sol";
import {VaultDeployer} from "../src/vault/VaultDeployer.sol";
import {VaultFactory} from "../src/vault/VaultFactory.sol";
import {SimpleSwapRouter} from "../src/periphery/SimpleSwapRouter.sol";
import {RangefyLens} from "../src/periphery/RangefyLens.sol";

contract DeployCore is HelperConfig {
    function run() external {
        uint256 pk = deployerKey();
        address owner = vm.addr(pk);
        IPoolManager pm = IPoolManager(poolManager());
        address updater = vm.envAddress("SIGNAL_UPDATER");

        vm.startBroadcast(pk);
        SignalOracle oracle = new SignalOracle(owner, updater);
        CuratorRegistry registry = new CuratorRegistry();
        RangefyHook hook = _deployHook(pm, oracle, owner);

        VaultDeployer deployer = new VaultDeployer();
        VaultFactory factory = new VaultFactory(pm, hook, registry, deployer);
        deployer.bindFactory(address(factory));
        hook.setVaultFactory(address(factory));
        SimpleSwapRouter router = new SimpleSwapRouter(pm);
        RangefyLens lens = new RangefyLens(pm, hook, factory, registry);
        vm.stopBroadcast();

        string[] memory k = new string[](8);
        address[] memory a = new address[](8);
        (k[0], a[0]) = ("signalOracle", address(oracle));
        (k[1], a[1]) = ("curatorRegistry", address(registry));
        (k[2], a[2]) = ("hook", address(hook));
        (k[3], a[3]) = ("vaultDeployer", address(deployer));
        (k[4], a[4]) = ("vaultFactory", address(factory));
        (k[5], a[5]) = ("router", address(router));
        (k[6], a[6]) = ("lens", address(lens));
        (k[7], a[7]) = ("poolManager", address(pm));
        save("core", k, a);

        console2.log("RangefyHook", address(hook));
        console2.log("VaultFactory", address(factory));
        console2.log("RangefyLens", address(lens));
    }

    // call the CREATE2 proxy directly so the address matches what we mined
    function _deployHook(IPoolManager pm, SignalOracle oracle, address owner) internal returns (RangefyHook) {
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        bytes memory args = abi.encode(pm, ISignalOracle(address(oracle)), owner);
        bytes memory initCode = abi.encodePacked(type(RangefyHook).creationCode, args);
        (address hookAddr, bytes32 salt) = HookMiner.find(CREATE2_DEPLOYER, flags, type(RangefyHook).creationCode, args);

        (bool ok, bytes memory ret) = CREATE2_DEPLOYER.call(abi.encodePacked(salt, initCode));
        require(ok && ret.length == 20 && address(bytes20(ret)) == hookAddr, "hook deploy failed");
        return RangefyHook(hookAddr);
    }
}
