// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";

/// @title HelperConfig
/// @notice Config + address book in deployments/<chainId>/.
abstract contract HelperConfig is Script {
    // Uniswap v4, Unichain Sepolia
    address internal constant UNICHAIN_SEPOLIA_POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    address internal constant UNICHAIN_SEPOLIA_MODIFY_LIQUIDITY_TEST = 0x5fa728C0A5cfd51BEe4B060773f50554c0C8A7AB;
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    int24 internal constant TICK_SPACING = 60;

    function deployerKey() internal view returns (uint256) {
        return vm.envUint("PRIVATE_KEY");
    }

    function poolManager() internal view returns (address) {
        return vm.envOr("POOL_MANAGER", UNICHAIN_SEPOLIA_POOL_MANAGER);
    }

    function modifyLiquidityRouter() internal view returns (address) {
        return vm.envOr("POOL_MODIFY_LIQUIDITY_TEST", UNICHAIN_SEPOLIA_MODIFY_LIQUIDITY_TEST);
    }

    // address book

    function _bookPath(string memory step) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", vm.toString(block.chainid), "/", step, ".json");
    }

    function save(string memory step, string[] memory keys, address[] memory values) internal {
        string memory dir = string.concat(vm.projectRoot(), "/deployments/", vm.toString(block.chainid));
        vm.createDir(dir, true);
        string memory obj = step;
        string memory json;
        for (uint256 i; i < keys.length; ++i) {
            json = vm.serializeAddress(obj, keys[i], values[i]);
        }
        json = vm.serializeUint(obj, "block", block.number);
        vm.writeJson(json, _bookPath(step));
    }

    function load(string memory step, string memory key) internal view returns (address) {
        return vm.parseJsonAddress(vm.readFile(_bookPath(step)), string.concat(".", key));
    }
}
