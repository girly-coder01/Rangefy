// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {StrategyParams} from "./IVaultFactory.sol";

enum RebalanceReason {
    None,
    OutOfRange,
    NearEdge,
    WidthDrift,
    Initial,
    IdleExcess
}

interface IRangeVault {
    event Deposit(address indexed sender, address indexed to, uint256 shares, uint256 amount0, uint256 amount1);
    event Withdraw(address indexed sender, address indexed to, uint256 shares, uint256 amount0, uint256 amount1);
    event Rebalanced(
        RebalanceReason reason,
        int24 oldLower,
        int24 oldUpper,
        int24 newLower,
        int24 newUpper,
        uint128 newLiquidity,
        uint32 sigmaUsed,
        bool fromSignal,
        int24 spotTick,
        int24 emaTick
    );
    event FeesCollected(uint256 fees0, uint256 fees1, uint256 curatorFee0, uint256 curatorFee1);
    event Snapshot(uint256 total0, uint256 total1, uint256 totalSupply, int24 emaTick, uint40 timestamp);
    event ParamsUpdated(StrategyParams params);
    event DepositsPaused(bool paused);
    event CuratorFeesClaimed(address to, uint256 amount0, uint256 amount1);

    error DepositsArePaused();
    error InsufficientShares();
    error Slippage();
    error PriceDeviation();
    error Cooldown();
    error NoRebalanceNeeded();
    error OnlyCurator();
    error OnlyPoolManager();
    error ZeroAmount();
    error PerformanceFeeIncrease();

    // LP
    function deposit(uint256 amount0Max, uint256 amount1Max, uint256 minShares, address to)
        external
        returns (uint256 shares, uint256 used0, uint256 used1);
    function withdraw(uint256 shares, uint256 amount0Min, uint256 amount1Min, address to)
        external
        returns (uint256 amount0, uint256 amount1);
    function previewDeposit(uint256 amount0Max, uint256 amount1Max)
        external
        view
        returns (uint256 shares, uint256 used0, uint256 used1);
    function previewWithdraw(uint256 shares) external view returns (uint256 amount0, uint256 amount1);

    // Keeper
    function needsRebalance() external view returns (bool needed, RebalanceReason reason);
    function rebalance() external returns (int24 newLower, int24 newUpper);
    function harvest() external;

    // Curator
    function updateParams(StrategyParams calldata p) external;
    function setDepositsPaused(bool paused) external;
    function curatorRebalance() external;
    function claimCuratorFees(address to) external;

    // Views
    function curator() external view returns (address);
    function tickLower() external view returns (int24);
    function tickUpper() external view returns (int24);
    function lastRebalance() external view returns (uint40);
    function rebalanceCount() external view returns (uint256);
    function depositsPaused() external view returns (bool);
    function getParams() external view returns (StrategyParams memory);
    function getTotalAmounts() external view returns (uint256 total0, uint256 total1);
    function getPosition() external view returns (uint128 liquidity, int24 lower, int24 upper);
    function idleBalances() external view returns (uint256 idle0, uint256 idle1);
    function targetRange() external view returns (int24 lower, int24 upper, uint32 sigma, bool fromSignal);
    function sharePrice() external view returns (uint256 priceInToken1Wad);
}
