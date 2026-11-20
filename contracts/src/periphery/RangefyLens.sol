// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {IRangefyHook} from "../interfaces/IRangefyHook.sol";
import {ISignalOracle, Signal} from "../interfaces/ISignalOracle.sol";
import {IRangeVault, RebalanceReason} from "../interfaces/IRangeVault.sol";
import {IVaultFactory, StrategyParams} from "../interfaces/IVaultFactory.sol";
import {ICuratorRegistry} from "../interfaces/ICuratorRegistry.sol";

interface IERC20View {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
}

/// @title RangefyLens
/// @notice Batched reads for the frontend.
contract RangefyLens {
    using StateLibrary for IPoolManager;

    struct VaultView {
        address vault;
        address curator;
        string curatorName;
        string name;
        string symbol;
        StrategyParams params;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 total0;
        uint256 total1;
        uint256 totalSupply;
        uint256 sharePriceWad;
        uint40 lastRebalance;
        uint256 rebalanceCount;
        bool depositsPaused;
        bool needsRebalance;
        uint8 reason;
        bool inRange;
    }

    struct PoolView {
        PoolId id;
        uint160 sqrtPriceX96;
        int24 tick;
        int24 emaTick;
        uint32 sigma;
        int32 drift;
        bool signalFresh;
        uint8 regime;
        uint24 fee;
        uint128 poolLiquidity;
        uint32 onchainSigma;
        uint16 confidenceBps;
        uint40 signalUpdatedAt;
    }

    IPoolManager public immutable poolManager;
    IRangefyHook public immutable hook;
    IVaultFactory public immutable factory;
    ICuratorRegistry public immutable registry;

    constructor(IPoolManager _poolManager, IRangefyHook _hook, IVaultFactory _factory, ICuratorRegistry _registry) {
        poolManager = _poolManager;
        hook = _hook;
        factory = _factory;
        registry = _registry;
    }

    function getPool(PoolKey calldata key) external view returns (PoolView memory p) {
        p.id = key.toId();
        (p.sqrtPriceX96, p.tick,,) = poolManager.getSlot0(p.id);
        p.poolLiquidity = poolManager.getLiquidity(p.id);
        p.emaTick = hook.emaTick(p.id);
        bool fromSignal;
        (p.sigma, p.drift, fromSignal) = hook.effectiveSigma(p.id);
        p.onchainSigma = hook.onchainSigmaTicks(p.id);
        p.regime = uint8(hook.currentRegime(p.id));
        p.fee = hook.currentFee(p.id);
        (Signal memory s, bool fresh) = hook.signalOracle().getSignal(p.id);
        p.signalFresh = fresh;
        p.confidenceBps = s.confidenceBps;
        p.signalUpdatedAt = s.updatedAt;
    }

    function getVault(address vault) public view returns (VaultView memory v) {
        IRangeVault rv = IRangeVault(vault);
        v.vault = vault;
        v.curator = rv.curator();
        v.curatorName = registry.getCurator(v.curator).name;
        v.name = IERC20View(vault).name();
        v.symbol = IERC20View(vault).symbol();
        v.params = rv.getParams();
        (v.liquidity, v.tickLower, v.tickUpper) = rv.getPosition();
        (v.total0, v.total1) = rv.getTotalAmounts();
        v.totalSupply = IERC20View(vault).totalSupply();
        v.sharePriceWad = rv.sharePrice();
        v.lastRebalance = rv.lastRebalance();
        v.rebalanceCount = rv.rebalanceCount();
        v.depositsPaused = rv.depositsPaused();
        RebalanceReason reason;
        (v.needsRebalance, reason) = rv.needsRebalance();
        v.reason = uint8(reason);

        (, int24 tick,,) = poolManager.getSlot0(_vaultPoolId(vault));
        v.inRange = v.liquidity > 0 && tick >= v.tickLower && tick < v.tickUpper;
    }

    function getAllVaults() external view returns (VaultView[] memory views) {
        address[] memory all = factory.allVaults();
        views = new VaultView[](all.length);
        for (uint256 i; i < all.length; ++i) {
            views[i] = getVault(all[i]);
        }
    }

    function getUserPositions(address user)
        external
        view
        returns (address[] memory vaults, uint256[] memory shares, uint256[] memory amount0, uint256[] memory amount1)
    {
        address[] memory all = factory.allVaults();
        uint256 n;
        for (uint256 i; i < all.length; ++i) {
            if (IERC20View(all[i]).balanceOf(user) > 0) n++;
        }
        vaults = new address[](n);
        shares = new uint256[](n);
        amount0 = new uint256[](n);
        amount1 = new uint256[](n);
        uint256 j;
        for (uint256 i; i < all.length; ++i) {
            uint256 s = IERC20View(all[i]).balanceOf(user);
            if (s == 0) continue;
            vaults[j] = all[i];
            shares[j] = s;
            (amount0[j], amount1[j]) = IRangeVault(all[i]).previewWithdraw(s);
            j++;
        }
    }

    function _vaultPoolId(address vault) internal view returns (PoolId) {
        return IVaultPoolId(vault).poolId();
    }
}

interface IVaultPoolId {
    function poolId() external view returns (PoolId);
}
