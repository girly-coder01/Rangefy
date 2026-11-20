// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {RangefyHook} from "../../src/hook/RangefyHook.sol";
import {SignalOracle} from "../../src/oracle/SignalOracle.sol";
import {Regime} from "../../src/interfaces/ISignalOracle.sol";
import {CuratorRegistry} from "../../src/curator/CuratorRegistry.sol";
import {VaultFactory} from "../../src/vault/VaultFactory.sol";
import {VaultDeployer} from "../../src/vault/VaultDeployer.sol";
import {RangeVault} from "../../src/vault/RangeVault.sol";
import {Profile, StrategyParams} from "../../src/interfaces/IVaultFactory.sol";

// Fresh PoolManager, hook at a flag address, 1:1 dynamic-fee pool with deep background liquidity.
abstract contract RangefyFixture is Deployers {
    using StateLibrary for IPoolManager;

    uint160 internal constant HOOK_FLAGS = uint160(
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
    );
    int24 internal constant TICK_SPACING = 60;
    uint256 internal constant T0 = 1_700_000_000;

    address internal updater = makeAddr("updater");
    address internal curatorAddr = makeAddr("curator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    CuratorRegistry internal registry;
    VaultDeployer internal vaultDeployer;
    VaultFactory internal factory;
    SignalOracle internal oracle;
    RangefyHook internal hook;
    PoolKey internal poolKey;
    PoolId internal poolId;

    function setUpRangefy() internal {
        vm.warp(T0);
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        oracle = new SignalOracle(address(this), updater);
        hook = deployHook(address(oracle), address(this));

        (poolKey, poolId) = initPool(
            currency0, currency1, IHooks(address(hook)), LPFeeLibrary.DYNAMIC_FEE_FLAG, TICK_SPACING, SQRT_PRICE_1_1
        );

        modifyLiquidityRouter.modifyLiquidity(
            poolKey, ModifyLiquidityParams({tickLower: -6000, tickUpper: 6000, liquidityDelta: 1000e18, salt: 0}), ""
        );
    }

    function setUpVaultStack() internal {
        registry = new CuratorRegistry();
        vaultDeployer = new VaultDeployer();
        factory = new VaultFactory(manager, hook, registry, vaultDeployer);
        vaultDeployer.bindFactory(address(factory));
        hook.setVaultFactory(address(factory));

        vm.prank(curatorAddr);
        registry.register("Harbor", "");

        address[3] memory users = [alice, bob, curatorAddr];
        for (uint256 i; i < users.length; ++i) {
            MockERC20(Currency.unwrap(currency0)).mint(users[i], 1_000_000e18);
            MockERC20(Currency.unwrap(currency1)).mint(users[i], 1_000_000e18);
        }
    }

    function createVault(Profile profile) internal returns (RangeVault v) {
        StrategyParams memory none;
        vm.prank(curatorAddr);
        v = RangeVault(factory.createVault(poolKey, profile, none, "Harbor Balanced", "rfHRB"));
        _approve(alice, address(v));
        _approve(bob, address(v));
    }

    function _approve(address user, address spender) internal {
        vm.startPrank(user);
        MockERC20(Currency.unwrap(currency0)).approve(spender, type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(spender, type(uint256).max);
        vm.stopPrank();
    }

    function bal0(address a) internal view returns (uint256) {
        return MockERC20(Currency.unwrap(currency0)).balanceOf(a);
    }

    function bal1(address a) internal view returns (uint256) {
        return MockERC20(Currency.unwrap(currency1)).balanceOf(a);
    }

    function generateFees(uint256 rounds, uint256 size) internal {
        for (uint256 i; i < rounds; ++i) {
            swapExactIn(true, size);
            swapExactIn(false, size);
        }
    }

    function deployHook(address signalOracle_, address owner_) internal returns (RangefyHook h) {
        address hookAddr = address(HOOK_FLAGS | (uint160(0x4444) << 144));
        deployCodeTo("RangefyHook.sol:RangefyHook", abi.encode(manager, signalOracle_, owner_), hookAddr);
        h = RangefyHook(hookAddr);
    }

    function spotTick() internal view returns (int24 tick) {
        (, tick,,) = manager.getSlot0(poolId);
    }

    function swapToTick(int24 targetTick) internal {
        int24 cur = spotTick();
        if (cur == targetTick) return;
        bool zeroForOne = targetTick < cur;
        swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(1e30),
                sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(targetTick)
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
    }

    function swapExactIn(bool zeroForOne, uint256 amountIn) internal returns (BalanceDelta) {
        return swap(poolKey, zeroForOne, -int256(amountIn), "");
    }

    function postSignal(uint32 sigma, int32 drift, Regime regime) internal {
        vm.prank(updater);
        oracle.postSignal(poolId, sigma, drift, regime, 8000, bytes8("test-v1"));
    }
}
