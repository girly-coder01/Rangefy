// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolState} from "../../src/interfaces/IRangefyHook.sol";
import {VolatilityOracle} from "../../src/libraries/VolatilityOracle.sol";
import {Constants} from "../../src/libraries/Constants.sol";

contract VolatilityOracleHarness {
    using VolatilityOracle for PoolState;

    PoolState public s;

    function init(int24 tick, uint256 ts) external {
        s.initialize(tick, ts);
    }

    function update(int24 tick, uint256 ts) external {
        s.update(tick, ts);
    }

    function setVar(uint128 v) external {
        s.varPerSecWad = v;
    }

    function state() external view returns (PoolState memory) {
        return s;
    }

    function preview(int24 tick, uint256 ts) external view returns (PoolState memory) {
        return VolatilityOracle.preview(s, tick, ts);
    }

    function ema() external view returns (int24) {
        return VolatilityOracle.emaTick(s);
    }

    function sigma() external view returns (uint32) {
        return VolatilityOracle.sigmaTicks(s);
    }
}

contract VolatilityOracleTest is Test {
    VolatilityOracleHarness h;
    uint256 constant T = 1_000_000;

    function setUp() public {
        h = new VolatilityOracleHarness();
        h.init(100, T);
    }

    function test_initialize_seeds() public view {
        PoolState memory s = h.state();
        assertEq(s.lastTick, 100);
        assertEq(s.emaTickX1000, 100_000);
        assertEq(s.varPerSecWad, Constants.DEFAULT_VAR_PER_SEC_WAD);
        assertEq(s.lastUpdate, T);
        assertEq(h.sigma(), 300 - 1); // sqrt floors: 300² * WAD / 86400 loses precision → 299
    }

    function test_update_sameTimestampIsNoop() public {
        h.update(5000, T);
        PoolState memory s = h.state();
        assertEq(s.lastTick, 100);
        assertEq(s.emaTickX1000, 100_000);
    }

    function test_update_emaMovesByAlpha() public {
        // dt = 60s → alpha = 60/300 = 0.2; ema = 100 + 0.2 * (600 - 100) = 200
        h.update(600, T + 60);
        assertEq(h.state().emaTickX1000, 200_000);
        assertEq(h.ema(), 200);
        assertEq(h.state().lastTick, 600);
    }

    function test_update_alphaSaturatesAtOne() public {
        h.update(-700, T + 10_000);
        assertEq(h.ema(), -700);
    }

    function test_update_varianceGrowsWithLargeMoves() public {
        uint128 before = h.state().varPerSecWad;
        h.update(100 + 2000, T + 60);
        assertGt(h.state().varPerSecWad, before);
    }

    function test_update_varianceDecaysWhenFlat() public {
        uint128 before = h.state().varPerSecWad;
        h.update(100, T + 600);
        assertLt(h.state().varPerSecWad, before);
    }

    function test_update_varianceMath() public {
        h.setVar(0);
        // move 60 ticks in 60s → sample = 3600 * WAD / 60 = 60 WAD; beta = 60/3600 → var = 1 WAD
        h.update(160, T + 60);
        assertApproxEqAbs(h.state().varPerSecWad, 1e18, 100); // beta truncates: 999999999999999960
    }

    function test_emaTick_roundsTowardNegativeInfinity() public {
        h.init(-1, T);
        h.update(0, T + 1); // ema = -1000 + (1/300)*1000 = -996.67 → -996 (x1000 int math) → tick -1
        assertEq(h.ema(), -1);
    }

    function test_sigma_clampsToBounds() public {
        h.setVar(0);
        assertEq(h.sigma(), Constants.MIN_SIGMA_TICKS);
        h.setVar(type(uint128).max);
        assertEq(h.sigma(), Constants.MAX_SIGMA_TICKS);
    }

    function test_preview_matchesUpdateWithoutWriting() public {
        PoolState memory p = h.preview(900, T + 120);
        PoolState memory before = h.state();
        assertEq(before.emaTickX1000, 100_000); // not written
        h.update(900, T + 120);
        PoolState memory a = h.state();
        assertEq(p.emaTickX1000, a.emaTickX1000);
        assertEq(p.varPerSecWad, a.varPerSecWad);
        assertEq(p.lastTick, a.lastTick);
    }

    function testFuzz_update_emaStaysBetweenOldAndNew(int24 tick, uint32 dt) public {
        tick = int24(bound(tick, -887_272, 887_272));
        dt = uint32(bound(dt, 1, 30 days));
        h.update(tick, T + dt);
        int24 e = h.ema();
        (int24 lo, int24 hi) = tick < 100 ? (tick, int24(100)) : (int24(100), tick);
        assertGe(e, lo - 1);
        assertLe(e, hi);
    }
}
