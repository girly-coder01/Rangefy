"""Mirrors contracts/src/libraries/Constants.sol."""

import math

LN_TICK = math.log(1.0001)  # one Uniswap tick in log-price
MINUTES_PER_DAY = 1440

# Contract bounds (SignalOracle._post)
MIN_SIGMA_TICKS = 20
MAX_SIGMA_TICKS = 5_000
MAX_DRIFT_TICKS = 2_000
MAX_CONFIDENCE_BPS = 10_000
MAX_SIGNAL_AGE_S = 15 * 60

# Regime enum order in ISignalOracle.sol
REGIMES = ("Calm", "Normal", "High", "Extreme")
REGIME_QUANTILES = (0.30, 0.70, 0.95)
