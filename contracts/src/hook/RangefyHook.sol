// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {BaseHook} from "../vendor/BaseHook.sol";
import {IRangefyHook, PoolState} from "../interfaces/IRangefyHook.sol";
import {ISignalOracle, Signal, Regime} from "../interfaces/ISignalOracle.sol";
import {VolatilityOracle} from "../libraries/VolatilityOracle.sol";
import {Constants} from "../libraries/Constants.sol";

/// @title RangefyHook
/// @notice EMA tick + realized vol oracle, regime-based dynamic fee, and price reference for Rangefy vaults.
contract RangefyHook is BaseHook, Ownable2Step, IRangefyHook {
    using StateLibrary for IPoolManager;
    using VolatilityOracle for PoolState;

    uint256 private constant SIGNAL_RETURN_SIZE = 7 * 32; // Signal (6 words) + bool

    ISignalOracle public signalOracle;
    mapping(PoolId => PoolState) public poolStates;

    /// @notice LP fee in pips for Calm, Normal, High, Extreme.
    uint24[4] public regimeFee = [uint24(500), 3000, 7500, 15_000];

    /// @notice Sigma boundaries between regimes. Keep in sync with the model's regime edges.
    uint32[3] public regimeThresholds = [uint32(150), 400, 900];

    /// @notice Registered vaults pay `vaultSwapFee` on their own rebalance swaps.
    address public vaultFactory;
    uint24 public vaultSwapFee = 500;

    constructor(IPoolManager _poolManager, ISignalOracle _signalOracle, address _owner)
        BaseHook(_poolManager)
        Ownable(_owner)
    {
        if (address(_signalOracle) == address(0)) revert ZeroAddress();
        signalOracle = _signalOracle;
        emit SignalOracleUpdated(address(_signalOracle));
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // Owner-only so vaults can only exist on vetted pools.
    function _beforeInitialize(address sender, PoolKey calldata key, uint160) internal override returns (bytes4) {
        if (!LPFeeLibrary.isDynamicFee(key.fee)) revert NotDynamicFee();
        if (sender != owner()) revert NotPoolAdmin();
        PoolId id = key.toId();
        poolStates[id].registered = true;
        emit PoolRegistered(id, key.currency0, key.currency1, key.tickSpacing);
        return this.beforeInitialize.selector;
    }

    function _afterInitialize(address, PoolKey calldata key, uint160, int24 tick) internal override returns (bytes4) {
        poolStates[key.toId()].initialize(tick, block.timestamp);
        return this.afterInitialize.selector;
    }

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId id = key.toId();
        (, int24 tick,,) = poolManager.getSlot0(id);
        PoolState storage state = poolStates[id];
        state.update(tick, block.timestamp); // pre-swap tick only

        uint24 fee;
        if (_isVault(sender)) {
            fee = vaultSwapFee;
        } else {
            (Regime regime,) = _regimeAndSigma(id, state);
            fee = regimeFee[uint8(regime)];
        }
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        PoolId id = key.toId();
        (, int24 tick,,) = poolManager.getSlot0(id);
        PoolState memory s = poolStates[id];
        (Regime regime, uint32 sigma) = _regimeAndSigma(id, s);
        emit PoolStateUpdated(id, tick, s.emaTick(), sigma, regimeFee[uint8(regime)], regime);
        return (this.afterSwap.selector, 0);
    }

    function emaTick(PoolId id) external view returns (int24) {
        return _liveState(id).emaTick();
    }

    function onchainSigmaTicks(PoolId id) external view returns (uint32) {
        return _liveState(id).sigmaTicks();
    }

    function effectiveSigma(PoolId id) external view returns (uint32 sigma, int32 drift, bool fromSignal) {
        (Signal memory sig, bool fresh) = _readSignal(id);
        if (fresh) return (sig.sigmaTicks, sig.driftTicks, true);
        return (_liveState(id).sigmaTicks(), 0, false);
    }

    function currentRegime(PoolId id) external view returns (Regime regime) {
        (regime,) = _regimeAndSigma(id, _liveState(id));
    }

    function currentFee(PoolId id) external view returns (uint24) {
        (Regime regime,) = _regimeAndSigma(id, _liveState(id));
        return regimeFee[uint8(regime)];
    }

    function getPoolState(PoolId id) external view returns (PoolState memory) {
        return poolStates[id];
    }

    function isRegistered(PoolId id) external view returns (bool) {
        return poolStates[id].registered;
    }

    function regimeForSigma(uint32 sigma) public view returns (Regime) {
        if (sigma < regimeThresholds[0]) return Regime.Calm;
        if (sigma < regimeThresholds[1]) return Regime.Normal;
        if (sigma < regimeThresholds[2]) return Regime.High;
        return Regime.Extreme;
    }

    // admin

    /// @notice Each fee in [MIN_FEE, MAX_FEE], non-decreasing by regime.
    function setRegimeFees(uint24[4] calldata fees) external onlyOwner {
        for (uint256 i; i < 4; ++i) {
            if (fees[i] < Constants.MIN_FEE || fees[i] > Constants.MAX_FEE) revert InvalidFees();
            if (i > 0 && fees[i] < fees[i - 1]) revert InvalidFees();
        }
        regimeFee = fees;
        emit RegimeFeesUpdated(fees);
    }

    /// @notice Strictly increasing, within signal sigma bounds.
    function setRegimeThresholds(uint32[3] calldata thresholds) external onlyOwner {
        if (
            thresholds[0] < Constants.MIN_SIGMA_TICKS || thresholds[0] >= thresholds[1]
                || thresholds[1] >= thresholds[2] || thresholds[2] > Constants.MAX_SIGMA_TICKS
        ) revert InvalidThresholds();
        regimeThresholds = thresholds;
        emit RegimeThresholdsUpdated(thresholds);
    }

    function setSignalOracle(ISignalOracle newOracle) external onlyOwner {
        if (address(newOracle) == address(0)) revert ZeroAddress();
        signalOracle = newOracle;
        emit SignalOracleUpdated(address(newOracle));
    }

    /// @notice Zero disables the vault fee.
    function setVaultFactory(address factory) external onlyOwner {
        vaultFactory = factory;
        emit VaultFactoryUpdated(factory);
    }

    function setVaultSwapFee(uint24 fee) external onlyOwner {
        if (fee < Constants.MIN_FEE || fee > Constants.MAX_FEE) revert InvalidFees();
        vaultSwapFee = fee;
        emit VaultSwapFeeUpdated(fee);
    }

    // internal

    // Not written. Spot can only move through beforeSwap, which updates first, so this can't be pushed in-block.
    function _liveState(PoolId id) internal view returns (PoolState memory s) {
        s = poolStates[id];
        if (!s.registered) revert PoolNotRegistered();
        (, int24 tick,,) = poolManager.getSlot0(id);
        s = s.preview(tick, block.timestamp);
    }

    // Fresh signal wins, but never more than one regime calmer than on-chain vol.
    function _regimeAndSigma(PoolId id, PoolState memory s) internal view returns (Regime regime, uint32 sigma) {
        uint32 onchainSigma = s.sigmaTicks();
        Regime onchainRegime = regimeForSigma(onchainSigma);
        (Signal memory sig, bool fresh) = _readSignal(id);
        if (!fresh) return (onchainRegime, onchainSigma);

        regime = sig.regime;
        sigma = sig.sigmaTicks;
        if (onchainRegime > Regime.Calm) {
            Regime floor_ = Regime(uint8(onchainRegime) - 1);
            if (regime < floor_) regime = floor_;
        }
    }

    // Low-level so a broken oracle reads as stale instead of bricking swaps.
    function _readSignal(PoolId id) internal view returns (Signal memory sig, bool fresh) {
        (bool ok, bytes memory ret) = address(signalOracle).staticcall(abi.encodeCall(ISignalOracle.getSignal, (id)));
        if (!ok || ret.length < SIGNAL_RETURN_SIZE) return (sig, false);
        (sig, fresh) = abi.decode(ret, (Signal, bool));
    }

    function _isVault(address account) internal view returns (bool) {
        address f = vaultFactory;
        if (f == address(0)) return false;
        (bool ok, bytes memory ret) = f.staticcall(abi.encodeWithSignature("isVault(address)", account));
        return ok && ret.length >= 32 && abi.decode(ret, (uint256)) == 1;
    }
}
