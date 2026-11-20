// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {IVaultFactory, Profile, StrategyParams} from "../interfaces/IVaultFactory.sol";
import {IRangefyHook} from "../interfaces/IRangefyHook.sol";
import {ICuratorRegistry} from "../interfaces/ICuratorRegistry.sol";
import {Constants} from "../libraries/Constants.sol";
import {VaultDeployer} from "./VaultDeployer.sol";

/// @title VaultFactory
/// @notice Registered curators launch vaults with bounded params.
contract VaultFactory is IVaultFactory {
    IPoolManager public immutable poolManager;
    IRangefyHook public immutable hook;
    ICuratorRegistry public immutable registry;
    // vault creation code lives there (size limit)
    VaultDeployer public immutable deployer;

    address[] internal _all;
    mapping(address => address[]) internal _byCurator;
    mapping(PoolId => address[]) internal _byPool;
    mapping(address => bool) public isVault;

    constructor(IPoolManager _poolManager, IRangefyHook _hook, ICuratorRegistry _registry, VaultDeployer _deployer) {
        poolManager = _poolManager;
        hook = _hook;
        registry = _registry;
        deployer = _deployer;
    }

    function createVault(
        PoolKey calldata key,
        Profile profile,
        StrategyParams calldata custom,
        string calldata name,
        string calldata symbol
    ) external returns (address vault) {
        if (!registry.isCurator(msg.sender)) revert NotCurator();
        if (address(key.hooks) != address(hook)) revert WrongHook();
        PoolId id = key.toId();
        if (!hook.isRegistered(id)) revert PoolNotRegistered();

        StrategyParams memory p = profile == Profile.Custom ? custom : presetParams(profile);
        validateParams(p, key.tickSpacing);

        vault = deployer.deploy(poolManager, hook, key, p, msg.sender, name, symbol);
        _all.push(vault);
        _byCurator[msg.sender].push(vault);
        _byPool[id].push(vault);
        isVault[vault] = true;
        emit VaultCreated(vault, msg.sender, id, profile, p, name, symbol);
    }

    /// @dev Assumes tick spacing 60.
    function presetParams(Profile profile) public pure returns (StrategyParams memory) {
        if (profile == Profile.Aggressive) {
            return StrategyParams({
                widthMultiplierBps: 10_000, // 1σ
                minHalfWidth: 120,
                maxHalfWidth: 3000,
                driftWeightBps: 3000,
                minRebalanceInterval: 5 minutes,
                maxEmaDeviation: 60,
                performanceFeeBps: 1500
            });
        }
        if (profile == Profile.Balanced) {
            return StrategyParams({
                widthMultiplierBps: 20_000, // 2σ
                minHalfWidth: 300,
                maxHalfWidth: 6000,
                driftWeightBps: 2000,
                minRebalanceInterval: 15 minutes,
                maxEmaDeviation: 90,
                performanceFeeBps: 1000
            });
        }
        if (profile == Profile.Conservative) {
            return StrategyParams({
                widthMultiplierBps: 35_000, // 3.5σ
                minHalfWidth: 600,
                maxHalfWidth: 12_000,
                driftWeightBps: 1000,
                minRebalanceInterval: 1 hours,
                maxEmaDeviation: 120,
                performanceFeeBps: 500
            });
        }
        StrategyParams memory none;
        return none;
    }

    /// @dev Reverts InvalidParams(index of first bad field).
    function validateParams(StrategyParams memory p, int24 tickSpacing) public pure {
        if (
            p.widthMultiplierBps < Constants.MIN_WIDTH_MULTIPLIER_BPS
                || p.widthMultiplierBps > Constants.MAX_WIDTH_MULTIPLIER_BPS
        ) {
            revert InvalidParams(0);
        }
        if (p.minHalfWidth < Constants.MIN_HALF_WIDTH_FLOOR || p.minHalfWidth % tickSpacing != 0) {
            revert InvalidParams(1);
        }
        if (
            p.maxHalfWidth < p.minHalfWidth || p.maxHalfWidth > Constants.MAX_HALF_WIDTH_CEIL
                || p.maxHalfWidth % tickSpacing != 0
        ) {
            revert InvalidParams(2);
        }
        if (p.driftWeightBps > Constants.MAX_DRIFT_WEIGHT_BPS) revert InvalidParams(3);
        if (
            p.minRebalanceInterval < Constants.MIN_REBALANCE_INTERVAL_FLOOR
                || p.minRebalanceInterval > Constants.MAX_REBALANCE_INTERVAL
        ) {
            revert InvalidParams(4);
        }
        if (p.maxEmaDeviation <= 0 || p.maxEmaDeviation > Constants.MAX_EMA_DEVIATION_CEIL) revert InvalidParams(5);
        if (p.performanceFeeBps > Constants.MAX_PERFORMANCE_FEE) revert InvalidParams(6);
    }

    function allVaults() external view returns (address[] memory) {
        return _all;
    }

    function vaultsOf(address curator) external view returns (address[] memory) {
        return _byCurator[curator];
    }

    function vaultsForPool(PoolId poolId) external view returns (address[] memory) {
        return _byPool[poolId];
    }

    function vaultCount() external view returns (uint256) {
        return _all.length;
    }
}
