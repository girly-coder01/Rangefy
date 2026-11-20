// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {FixedPoint128} from "@uniswap/v4-core/src/libraries/FixedPoint128.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {IRangeVault, RebalanceReason} from "../interfaces/IRangeVault.sol";
import {IRangefyHook} from "../interfaces/IRangefyHook.sol";
import {ISignalOracle} from "../interfaces/ISignalOracle.sol";
import {IVaultFactory, StrategyParams} from "../interfaces/IVaultFactory.sol";
import {RangeMath} from "../libraries/RangeMath.sol";
import {Constants} from "../libraries/Constants.sol";

/// @title RangeVault
/// @notice One curator strategy, one concentrated position. Ranges are computed on-chain; anyone can rebalance.
/// @dev Tokens outside the position sit in the vault as idle balances (excluding curatorOwed).
contract RangeVault is IRangeVault, ERC20, ReentrancyGuardTransient, IUnlockCallback {
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using SafeCast for uint256;

    enum Action {
        DEPOSIT,
        WITHDRAW,
        REBALANCE,
        HARVEST
    }

    struct DepositArgs {
        address payer;
        address to;
        uint256 amount0Max;
        uint256 amount1Max;
        uint256 minShares;
    }

    struct WithdrawArgs {
        address owner;
        address to;
        uint256 shares;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    IPoolManager public immutable poolManager;
    IRangefyHook public immutable hook;
    ISignalOracle public immutable signalOracle;
    IVaultFactory public immutable factory;
    address public immutable curator;
    PoolId public immutable poolId;
    int24 internal immutable _spacing;
    IERC20 internal immutable _token0;
    IERC20 internal immutable _token1;

    PoolKey internal _key;
    StrategyParams public params;

    int24 public tickLower;
    int24 public tickUpper;
    uint40 public lastRebalance;
    bool public depositsPaused;
    uint256 public curatorOwed0;
    uint256 public curatorOwed1;
    uint256 public rebalanceCount;

    modifier onlyCurator() {
        if (msg.sender != curator) revert OnlyCurator();
        _;
    }

    constructor(
        IPoolManager _poolManager,
        IRangefyHook _hook,
        PoolKey memory key_,
        StrategyParams memory params_,
        address curator_,
        IVaultFactory factory_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        poolManager = _poolManager;
        hook = _hook;
        signalOracle = _hook.signalOracle();
        factory = factory_;
        curator = curator_;
        _key = key_;
        poolId = key_.toId();
        _spacing = key_.tickSpacing;
        _token0 = IERC20(Currency.unwrap(key_.currency0));
        _token1 = IERC20(Currency.unwrap(key_.currency1));
        params = params_;
    }

    // lp

    function deposit(uint256 amount0Max, uint256 amount1Max, uint256 minShares, address to)
        external
        nonReentrant
        returns (uint256 shares, uint256 used0, uint256 used1)
    {
        if (depositsPaused) revert DepositsArePaused();
        if (amount0Max == 0 && amount1Max == 0) revert ZeroAmount();
        bytes memory ret = poolManager.unlock(
            abi.encode(Action.DEPOSIT, abi.encode(DepositArgs(msg.sender, to, amount0Max, amount1Max, minShares)))
        );
        (shares, used0, used1) = abi.decode(ret, (uint256, uint256, uint256));
        emit Deposit(msg.sender, to, shares, used0, used1);
        _emitSnapshot();
    }

    // never paused, no price guard
    function withdraw(uint256 shares, uint256 amount0Min, uint256 amount1Min, address to)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (shares == 0) revert ZeroAmount();
        if (shares > balanceOf(msg.sender)) revert InsufficientShares();
        bytes memory ret = poolManager.unlock(
            abi.encode(Action.WITHDRAW, abi.encode(WithdrawArgs(msg.sender, to, shares, amount0Min, amount1Min)))
        );
        (amount0, amount1) = abi.decode(ret, (uint256, uint256));
        emit Withdraw(msg.sender, to, shares, amount0, amount1);
        _emitSnapshot();
    }

    function previewDeposit(uint256 amount0Max, uint256 amount1Max)
        external
        view
        returns (uint256 shares, uint256 used0, uint256 used1)
    {
        (uint160 sqrtP,) = _spot();
        uint256 supply = totalSupply();
        if (supply == 0) {
            (int24 lo, int24 hi,,) = targetRange();
            uint128 l = _liquidityFor(sqrtP, lo, hi, _margin(amount0Max), _margin(amount1Max));
            if (l <= Constants.MIN_SHARES) return (0, 0, 0);
            (used0, used1) = _amountsFor(sqrtP, lo, hi, l, true);
            return (uint256(l) - Constants.MIN_SHARES, used0, used1);
        }
        (uint256 fees0, uint256 fees1) = _pendingFeesNet();
        (uint256 idle0, uint256 idle1) = idleBalances();
        return _proportional(sqrtP, amount0Max, amount1Max, idle0 + fees0, idle1 + fees1, supply);
    }

    function previewWithdraw(uint256 shares) external view returns (uint256 amount0, uint256 amount1) {
        uint256 supply = totalSupply();
        if (supply == 0 || shares == 0) return (0, 0);
        (uint160 sqrtP,) = _spot();
        uint128 liq = _liquidity();
        uint128 dl = uint128(FullMath.mulDiv(liq, shares, supply));
        (amount0, amount1) = _amountsFor(sqrtP, tickLower, tickUpper, dl, false);
        (uint256 fees0, uint256 fees1) = _pendingFeesNet();
        (uint256 idle0, uint256 idle1) = idleBalances();
        amount0 += FullMath.mulDiv(idle0 + fees0, shares, supply);
        amount1 += FullMath.mulDiv(idle1 + fees1, shares, supply);
    }

    // keeper (permissionless)

    function needsRebalance() public view returns (bool needed, RebalanceReason reason) {
        reason = _rebalanceReason();
        needed = reason != RebalanceReason.None;
    }

    function rebalance() external nonReentrant returns (int24 newLower, int24 newUpper) {
        _checkRebalanceGuards();
        RebalanceReason reason = _reasonIgnoringGuards();
        if (reason == RebalanceReason.None) revert NoRebalanceNeeded();
        return _rebalance(reason);
    }

    function harvest() external nonReentrant {
        if (_liquidity() == 0) return;
        poolManager.unlock(abi.encode(Action.HARVEST, ""));
        _emitSnapshot();
    }

    // curator

    /// @notice Perf fee can only go down.
    function updateParams(StrategyParams calldata p) external onlyCurator {
        factory.validateParams(p, _spacing);
        if (p.performanceFeeBps > params.performanceFeeBps) revert PerformanceFeeIncrease();
        params = p;
        emit ParamsUpdated(p);
    }

    function setDepositsPaused(bool paused) external onlyCurator {
        depositsPaused = paused;
        emit DepositsPaused(paused);
    }

    /// @notice Skips the reason check; cooldown and EMA guard still apply.
    function curatorRebalance() external onlyCurator nonReentrant {
        _checkRebalanceGuards();
        if (_liquidity() == 0 && !_hasIdle()) revert ZeroAmount();
        _rebalance(_reasonIgnoringGuards());
    }

    function claimCuratorFees(address to) external onlyCurator nonReentrant {
        (uint256 a0, uint256 a1) = (curatorOwed0, curatorOwed1);
        curatorOwed0 = 0;
        curatorOwed1 = 0;
        if (a0 > 0) _token0.safeTransfer(to, a0);
        if (a1 > 0) _token1.safeTransfer(to, a1);
        emit CuratorFeesClaimed(to, a0, a1);
    }

    // unlock callback

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        (Action action, bytes memory payload) = abi.decode(data, (Action, bytes));
        if (action == Action.DEPOSIT) return _onDeposit(abi.decode(payload, (DepositArgs)));
        if (action == Action.WITHDRAW) return _onWithdraw(abi.decode(payload, (WithdrawArgs)));
        if (action == Action.REBALANCE) return _onRebalance(abi.decode(payload, (RebalanceReason)));
        _collectFees();
        return "";
    }

    // collect fees first so they go to existing holders
    function _onDeposit(DepositArgs memory a) internal returns (bytes memory) {
        _collectFees();
        (uint160 sqrtP, int24 spot) = _spot();
        if (RangeMath.absDiff(spot, hook.emaTick(poolId)) > uint256(uint24(params.maxEmaDeviation))) {
            revert PriceDeviation();
        }

        uint256 supply = totalSupply();
        uint256 shares;
        uint256 used0;
        uint256 used1;

        if (supply == 0) {
            (int24 lo, int24 hi,,) = targetRange();
            uint128 l = _liquidityFor(sqrtP, lo, hi, _margin(a.amount0Max), _margin(a.amount1Max));
            if (l <= Constants.MIN_SHARES) revert InsufficientShares();
            tickLower = lo;
            tickUpper = hi;
            lastRebalance = uint40(block.timestamp);
            (used0, used1) = _modify(lo, hi, int256(uint256(l)));
            shares = uint256(l) - Constants.MIN_SHARES;
            _mint(Constants.DEAD, Constants.MIN_SHARES);
        } else {
            (uint256 idle0, uint256 idle1) = idleBalances();
            uint256 dl;
            uint256 idleIn0;
            uint256 idleIn1;
            (shares, dl, idleIn0, idleIn1) =
                _proportionalAmounts(sqrtP, a.amount0Max, a.amount1Max, idle0, idle1, supply);
            if (dl > 0) (used0, used1) = _modify(tickLower, tickUpper, int256(dl));
            if (idleIn0 > 0) _token0.safeTransferFrom(a.payer, address(this), idleIn0);
            if (idleIn1 > 0) _token1.safeTransferFrom(a.payer, address(this), idleIn1);
            used0 += idleIn0;
            used1 += idleIn1;
        }

        if (shares == 0 || shares < a.minShares) revert Slippage();
        if (used0 > a.amount0Max || used1 > a.amount1Max) revert Slippage();

        _settleNet(_key.currency0, a.payer);
        _settleNet(_key.currency1, a.payer);
        _mint(a.to, shares);
        return abi.encode(shares, used0, used1);
    }

    function _onWithdraw(WithdrawArgs memory a) internal returns (bytes memory) {
        _collectFees();
        uint256 supply = totalSupply();
        (uint256 idle0, uint256 idle1) = idleBalances();
        uint256 dl = FullMath.mulDiv(_liquidity(), a.shares, supply);
        uint256 idleOut0 = FullMath.mulDiv(idle0, a.shares, supply);
        uint256 idleOut1 = FullMath.mulDiv(idle1, a.shares, supply);
        _burn(a.owner, a.shares);

        uint256 out0 = idleOut0;
        uint256 out1 = idleOut1;
        if (dl > 0) {
            (BalanceDelta delta,) = poolManager.modifyLiquidity(_key, _modParams(tickLower, tickUpper, -int256(dl)), "");
            uint256 p0 = uint256(int256(delta.amount0()));
            uint256 p1 = uint256(int256(delta.amount1()));
            if (p0 > 0) poolManager.take(_key.currency0, a.to, p0);
            if (p1 > 0) poolManager.take(_key.currency1, a.to, p1);
            out0 += p0;
            out1 += p1;
        }
        if (out0 < a.amount0Min || out1 < a.amount1Min) revert Slippage();

        if (idleOut0 > 0) _token0.safeTransfer(a.to, idleOut0);
        if (idleOut1 > 0) _token1.safeTransfer(a.to, idleOut1);
        return abi.encode(out0, out1);
    }

    // pull everything, resize around the EMA, swap toward target ratio, redeploy
    function _onRebalance(RebalanceReason reason) internal returns (bytes memory) {
        int24 oldLower = tickLower;
        int24 oldUpper = tickUpper;

        uint128 liq = _liquidity();
        if (liq > 0) {
            (, BalanceDelta fees) =
                poolManager.modifyLiquidity(_key, _modParams(oldLower, oldUpper, -int256(uint256(liq))), "");
            _accrueCuratorFee(fees);
        }
        _settleNet(_key.currency0, address(this));
        _settleNet(_key.currency1, address(this));

        (int24 lo, int24 hi, uint32 sigma, bool fromSignal) = targetRange();
        int24 ema = hook.emaTick(poolId);
        _swapToRatio(lo, hi, ema);

        (uint160 sqrtP, int24 spot) = _spot();
        (uint256 a0, uint256 a1) = idleBalances();
        // 1 wei margin for PoolManager round-up
        uint128 newLiq = _liquidityFor(sqrtP, lo, hi, a0 > 0 ? a0 - 1 : 0, a1 > 0 ? a1 - 1 : 0);
        if (newLiq > 0) {
            _modify(lo, hi, int256(uint256(newLiq)));
            _settleNet(_key.currency0, address(this));
            _settleNet(_key.currency1, address(this));
        }

        tickLower = lo;
        tickUpper = hi;
        lastRebalance = uint40(block.timestamp);
        rebalanceCount++;
        emit Rebalanced(reason, oldLower, oldUpper, lo, hi, newLiq, sigma, fromSignal, spot, ema);
        return abi.encode(lo, hi);
    }

    // views

    function poolKey() external view returns (PoolKey memory) {
        return _key;
    }

    function getParams() external view returns (StrategyParams memory) {
        return params;
    }

    /// @notice Position at spot + idle + pending fees net of perf fee.
    function getTotalAmounts() public view returns (uint256 total0, uint256 total1) {
        (uint160 sqrtP,) = _spot();
        (total0, total1) = _amountsFor(sqrtP, tickLower, tickUpper, _liquidity(), false);
        (uint256 idle0, uint256 idle1) = idleBalances();
        (uint256 fees0, uint256 fees1) = _pendingFeesNet();
        total0 += idle0 + fees0;
        total1 += idle1 + fees1;
    }

    function getPosition() external view returns (uint128 liquidity, int24 lower, int24 upper) {
        return (_liquidity(), tickLower, tickUpper);
    }

    function idleBalances() public view returns (uint256 idle0, uint256 idle1) {
        uint256 b0 = _token0.balanceOf(address(this));
        uint256 b1 = _token1.balanceOf(address(this));
        idle0 = b0 > curatorOwed0 ? b0 - curatorOwed0 : 0;
        idle1 = b1 > curatorOwed1 ? b1 - curatorOwed1 : 0;
    }

    function targetRange() public view returns (int24 lower, int24 upper, uint32 sigma, bool fromSignal) {
        int32 drift;
        (sigma, drift, fromSignal) = hook.effectiveSigma(poolId);
        (lower, upper) = RangeMath.computeRange(hook.emaTick(poolId), sigma, drift, params, _spacing);
    }

    /// @notice NAV per share in raw token1 (WAD) at the EMA price.
    function sharePrice() external view returns (uint256 priceInToken1Wad) {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;
        (uint256 t0, uint256 t1) = getTotalAmounts();
        uint256 pWad = RangeMath.priceWad(RangeMath.sqrtPriceAtTick(hook.emaTick(poolId)));
        return FullMath.mulDiv(RangeMath.valueIn1(t0, t1, pWad), Constants.WAD, supply);
    }

    // rebalance rules

    function _rebalanceReason() internal view returns (RebalanceReason) {
        if (block.timestamp < uint256(lastRebalance) + params.minRebalanceInterval) return RebalanceReason.None;
        (, int24 spot) = _spot();
        if (RangeMath.absDiff(spot, hook.emaTick(poolId)) > uint256(uint24(params.maxEmaDeviation))) {
            return RebalanceReason.None;
        }
        return _reasonIgnoringGuards();
    }

    function _checkRebalanceGuards() internal view {
        if (block.timestamp < uint256(lastRebalance) + params.minRebalanceInterval) revert Cooldown();
        (, int24 spot) = _spot();
        if (RangeMath.absDiff(spot, hook.emaTick(poolId)) > uint256(uint24(params.maxEmaDeviation))) {
            revert PriceDeviation();
        }
    }

    function _reasonIgnoringGuards() internal view returns (RebalanceReason) {
        if (totalSupply() == 0) return RebalanceReason.None;
        if (_liquidity() == 0) return _hasIdle() ? RebalanceReason.Initial : RebalanceReason.None;

        (, int24 spot) = _spot();
        int24 lo = tickLower;
        int24 hi = tickUpper;
        if (spot < lo || spot >= hi) return RebalanceReason.OutOfRange;

        int256 w = int256(hi) - int256(lo);
        int256 buffer = (w * int256(uint256(Constants.EDGE_BUFFER_BPS))) / int256(uint256(Constants.BPS));
        if (spot < lo + buffer || spot >= hi - buffer) return RebalanceReason.NearEdge;

        (uint32 sigma,,) = hook.effectiveSigma(poolId);
        uint256 target = uint256(uint24(RangeMath.halfWidth(sigma, params, _spacing)));
        uint256 current = uint256(w / 2);
        uint256 diff = target > current ? target - current : current - target;
        if (diff * Constants.BPS >= current * Constants.WIDTH_DRIFT_BPS) return RebalanceReason.WidthDrift;

        if (_idleShareBps() >= Constants.IDLE_REBALANCE_BPS) return RebalanceReason.IdleExcess;

        return RebalanceReason.None;
    }

    // idle / total value, bps
    function _idleShareBps() internal view returns (uint256) {
        (uint160 sqrtP,) = _spot();
        uint256 pWad = RangeMath.priceWad(sqrtP);
        (uint256 i0, uint256 i1) = idleBalances();
        (uint256 t0, uint256 t1) = getTotalAmounts();
        uint256 total = RangeMath.valueIn1(t0, t1, pWad);
        if (total == 0) return 0;
        return FullMath.mulDiv(RangeMath.valueIn1(i0, i1, pWad), Constants.BPS, total);
    }

    function _rebalance(RebalanceReason reason) internal returns (int24 lo, int24 hi) {
        bytes memory ret = poolManager.unlock(abi.encode(Action.REBALANCE, abi.encode(reason)));
        (lo, hi) = abi.decode(ret, (int24, int24));
        _emitSnapshot();
    }

    // pool manager (inside unlockCallback only)

    function _collectFees() internal {
        if (_liquidity() == 0) return;
        (, BalanceDelta fees) = poolManager.modifyLiquidity(_key, _modParams(tickLower, tickUpper, 0), "");
        _accrueCuratorFee(fees);
        _settleNet(_key.currency0, address(this));
        _settleNet(_key.currency1, address(this));
    }

    function _accrueCuratorFee(BalanceDelta fees) internal {
        uint256 f0 = uint256(int256(fees.amount0()));
        uint256 f1 = uint256(int256(fees.amount1()));
        if (f0 == 0 && f1 == 0) return;
        uint256 c0 = (f0 * params.performanceFeeBps) / Constants.BPS;
        uint256 c1 = (f1 * params.performanceFeeBps) / Constants.BPS;
        curatorOwed0 += c0;
        curatorOwed1 += c1;
        emit FeesCollected(f0, f1, c0, c1);
    }

    function _modify(int24 lo, int24 hi, int256 liquidityDelta) internal returns (uint256 owed0, uint256 owed1) {
        (BalanceDelta delta,) = poolManager.modifyLiquidity(_key, _modParams(lo, hi, liquidityDelta), "");
        int128 d0 = delta.amount0();
        int128 d1 = delta.amount1();
        owed0 = d0 < 0 ? uint256(-int256(d0)) : 0;
        owed1 = d1 < 0 ? uint256(-int256(d1)) : 0;
    }

    // swap toward the range ratio; stops at EMA ± MAX_SWAP_SLIPPAGE_BPS, leftovers stay idle
    function _swapToRatio(int24 lo, int24 hi, int24 ema) internal {
        (uint160 sqrtP,) = _spot();
        (uint256 a0, uint256 a1) = idleBalances();
        uint256 pWad = RangeMath.priceWad(sqrtP);
        (uint256 x, uint256 y) = RangeMath.amountsForTicks(sqrtP, lo, hi, 1e18, false);
        uint256 target0 = RangeMath.targetAmount0(a0, a1, pWad, x, y);

        bool zeroForOne;
        uint256 amountIn;
        if (a0 * Constants.BPS > target0 * (Constants.BPS + Constants.RATIO_TOLERANCE_BPS)) {
            zeroForOne = true;
            amountIn = a0 - target0;
        } else if (a0 * Constants.BPS < target0 * (Constants.BPS - Constants.RATIO_TOLERANCE_BPS)) {
            amountIn = FullMath.mulDiv(target0 - a0, pWad, Constants.WAD);
            if (amountIn > a1) amountIn = a1;
        } else {
            return;
        }
        if (amountIn == 0) return;

        int24 slip = int24(uint24(Constants.MAX_SWAP_SLIPPAGE_BPS));
        int24 limitTick = zeroForOne ? ema - slip : ema + slip;
        if (limitTick < TickMath.MIN_TICK + 1) limitTick = TickMath.MIN_TICK + 1;
        if (limitTick > TickMath.MAX_TICK - 1) limitTick = TickMath.MAX_TICK - 1;
        uint160 limit = RangeMath.sqrtPriceAtTick(limitTick);
        // already past the limit
        if (zeroForOne ? limit >= sqrtP : limit <= sqrtP) return;

        poolManager.swap(
            _key,
            SwapParams({zeroForOne: zeroForOne, amountSpecified: -amountIn.toInt256(), sqrtPriceLimitX96: limit}),
            ""
        );
        _settleNet(_key.currency0, address(this));
        _settleNet(_key.currency1, address(this));
    }

    function _settleNet(Currency c, address payer) internal {
        int256 d = poolManager.currencyDelta(address(this), c);
        if (d < 0) {
            poolManager.sync(c);
            IERC20 token = IERC20(Currency.unwrap(c));
            if (payer == address(this)) token.safeTransfer(address(poolManager), uint256(-d));
            else token.safeTransferFrom(payer, address(poolManager), uint256(-d));
            poolManager.settle();
        } else if (d > 0) {
            poolManager.take(c, address(this), uint256(d));
        }
    }

    // math

    // f = min(amount_i / cost_i) over position + idle
    function _proportionalAmounts(
        uint160 sqrtP,
        uint256 amount0Max,
        uint256 amount1Max,
        uint256 idle0,
        uint256 idle1,
        uint256 supply
    ) internal view returns (uint256 shares, uint256 dl, uint256 idleIn0, uint256 idleIn1) {
        uint128 liq = _liquidity();
        (uint256 p0, uint256 p1) = _amountsFor(sqrtP, tickLower, tickUpper, liq, true);
        uint256 cost0 = p0 + idle0;
        uint256 cost1 = p1 + idle1;
        if (cost0 == 0 && cost1 == 0) revert ZeroAmount();

        uint256 m0 = _margin(amount0Max);
        uint256 m1 = _margin(amount1Max);
        uint256 f = type(uint256).max;
        if (cost0 > 0) f = FullMath.mulDiv(m0, Constants.WAD, cost0);
        if (cost1 > 0) {
            uint256 f1 = FullMath.mulDiv(m1, Constants.WAD, cost1);
            if (f1 < f) f = f1;
        }

        dl = FullMath.mulDiv(liq, f, Constants.WAD);
        shares = FullMath.mulDiv(supply, f, Constants.WAD);
        idleIn0 = FullMath.mulDivRoundingUp(idle0, f, Constants.WAD);
        idleIn1 = FullMath.mulDivRoundingUp(idle1, f, Constants.WAD);
    }

    function _proportional(
        uint160 sqrtP,
        uint256 amount0Max,
        uint256 amount1Max,
        uint256 idle0,
        uint256 idle1,
        uint256 supply
    ) internal view returns (uint256 shares, uint256 used0, uint256 used1) {
        uint256 dl;
        uint256 idleIn0;
        uint256 idleIn1;
        (shares, dl, idleIn0, idleIn1) = _proportionalAmounts(sqrtP, amount0Max, amount1Max, idle0, idle1, supply);
        (used0, used1) = _amountsFor(sqrtP, tickLower, tickUpper, uint128(dl), true);
        used0 += idleIn0;
        used1 += idleIn1;
    }

    function _pendingFeesNet() internal view returns (uint256 fees0, uint256 fees1) {
        int24 lo = tickLower;
        int24 hi = tickUpper;
        (uint128 liq, uint256 last0, uint256 last1) =
            poolManager.getPositionInfo(poolId, address(this), lo, hi, bytes32(0));
        if (liq == 0) return (0, 0);
        (uint256 inside0, uint256 inside1) = poolManager.getFeeGrowthInside(poolId, lo, hi);
        unchecked {
            fees0 = FullMath.mulDiv(inside0 - last0, liq, FixedPoint128.Q128);
            fees1 = FullMath.mulDiv(inside1 - last1, liq, FixedPoint128.Q128);
        }
        uint256 keep = Constants.BPS - params.performanceFeeBps;
        fees0 = (fees0 * keep) / Constants.BPS;
        fees1 = (fees1 * keep) / Constants.BPS;
    }

    function _liquidity() internal view returns (uint128 liq) {
        (liq,,) = poolManager.getPositionInfo(poolId, address(this), tickLower, tickUpper, bytes32(0));
    }

    // keeps used <= max after round-up
    function _margin(uint256 amountMax) internal pure returns (uint256) {
        return amountMax > 2 ? amountMax - 2 : 0;
    }

    function _hasIdle() internal view returns (bool) {
        (uint256 i0, uint256 i1) = idleBalances();
        return i0 > 0 || i1 > 0;
    }

    function _spot() internal view returns (uint160 sqrtP, int24 tick) {
        (sqrtP, tick,,) = poolManager.getSlot0(poolId);
    }

    function _liquidityFor(uint160 sqrtP, int24 lo, int24 hi, uint256 a0, uint256 a1) internal pure returns (uint128) {
        return RangeMath.liquidityForAmounts(sqrtP, lo, hi, a0, a1);
    }

    function _amountsFor(uint160 sqrtP, int24 lo, int24 hi, uint128 liq, bool roundUp)
        internal
        pure
        returns (uint256, uint256)
    {
        return RangeMath.amountsForTicks(sqrtP, lo, hi, liq, roundUp);
    }

    function _modParams(int24 lo, int24 hi, int256 liquidityDelta)
        internal
        pure
        returns (ModifyLiquidityParams memory)
    {
        return ModifyLiquidityParams({tickLower: lo, tickUpper: hi, liquidityDelta: liquidityDelta, salt: bytes32(0)});
    }

    function _emitSnapshot() internal {
        (uint256 t0, uint256 t1) = getTotalAmounts();
        emit Snapshot(t0, t1, totalSupply(), hook.emaTick(poolId), uint40(block.timestamp));
    }
}
