// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

enum Profile {
    Aggressive,
    Balanced,
    Conservative,
    Custom
}

struct StrategyParams {
    uint16 widthMultiplierBps; // half-width = sigma * multiplier / 10_000
    int24 minHalfWidth; // ticks
    int24 maxHalfWidth; // ticks
    uint16 driftWeightBps;
    uint32 minRebalanceInterval; // seconds
    int24 maxEmaDeviation; // ticks
    uint16 performanceFeeBps;
}

interface IVaultFactory {
    event VaultCreated(
        address indexed vault,
        address indexed curator,
        PoolId indexed poolId,
        Profile profile,
        StrategyParams params,
        string name,
        string symbol
    );

    error NotCurator();
    error WrongHook();
    error PoolNotRegistered();
    error InvalidParams(uint8 field);

    function createVault(
        PoolKey calldata key,
        Profile profile,
        StrategyParams calldata custom,
        string calldata name,
        string calldata symbol
    ) external returns (address vault);

    function presetParams(Profile profile) external pure returns (StrategyParams memory);
    function validateParams(StrategyParams memory p, int24 tickSpacing) external pure;
    function allVaults() external view returns (address[] memory);
    function vaultsOf(address curator) external view returns (address[] memory);
    function vaultsForPool(PoolId poolId) external view returns (address[] memory);
    function isVault(address vault) external view returns (bool);
}
