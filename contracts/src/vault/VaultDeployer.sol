// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {IRangefyHook} from "../interfaces/IRangefyHook.sol";
import {IVaultFactory, StrategyParams} from "../interfaces/IVaultFactory.sol";
import {RangeVault} from "./RangeVault.sol";

/// @title VaultDeployer
/// @notice Deploys vaults for the factory; split out to keep the factory under 24 KB.
contract VaultDeployer {
    address public immutable admin;
    address public factory;

    error OnlyFactory();
    error AlreadyBound();
    error NotAdmin();

    constructor() {
        admin = msg.sender;
    }

    function bindFactory(address factory_) external {
        if (msg.sender != admin) revert NotAdmin();
        if (factory != address(0)) revert AlreadyBound();
        factory = factory_;
    }

    function deploy(
        IPoolManager poolManager,
        IRangefyHook hook,
        PoolKey calldata key,
        StrategyParams calldata params,
        address curator,
        string calldata name,
        string calldata symbol
    ) external returns (address) {
        if (msg.sender != factory) revert OnlyFactory();
        return address(new RangeVault(poolManager, hook, key, params, curator, IVaultFactory(msg.sender), name, symbol));
    }
}
