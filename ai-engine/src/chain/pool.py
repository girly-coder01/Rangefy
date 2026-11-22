"""Pool key / id and price ↔ sqrtPriceX96 math for the mWETH/mUSDC Rangefy pool."""

from __future__ import annotations

import math
from dataclasses import dataclass

from eth_abi import encode
from eth_utils import keccak, to_checksum_address

DYNAMIC_FEE_FLAG = 0x800000
Q96 = 2**96
MIN_SQRT_PRICE = 4295128739
MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342


@dataclass(frozen=True)
class PoolKey:
    currency0: str
    currency1: str
    fee: int
    tick_spacing: int
    hooks: str

    @classmethod
    def build(cls, token_a: str, token_b: str, hook: str, tick_spacing: int = 60) -> PoolKey:
        a, b = sorted([to_checksum_address(token_a), to_checksum_address(token_b)], key=lambda x: int(x, 16))
        return cls(a, b, DYNAMIC_FEE_FLAG, tick_spacing, to_checksum_address(hook))

    def as_tuple(self) -> tuple:
        return (self.currency0, self.currency1, self.fee, self.tick_spacing, self.hooks)

    @property
    def pool_id(self) -> bytes:
        """keccak256(abi.encode(PoolKey)) — same as PoolIdLibrary.toId."""
        return keccak(encode(["address", "address", "uint24", "int24", "address"], list(self.as_tuple())))


@dataclass(frozen=True)
class PricedPool:
    """Converts between ETH/USD and the pool's raw sqrt price for mWETH(18)/mUSDC(6)."""

    key: PoolKey
    weth: str
    weth_decimals: int = 18
    usdc_decimals: int = 6

    @property
    def weth_is_token0(self) -> bool:
        return self.key.currency0.lower() == self.weth.lower()

    def raw_price(self, eth_usd: float) -> float:
        """token1 per token0 in smallest units."""
        if self.weth_is_token0:
            return eth_usd * 10 ** (self.usdc_decimals - self.weth_decimals)
        return (1 / eth_usd) * 10 ** (self.weth_decimals - self.usdc_decimals)

    def sqrt_price_x96(self, eth_usd: float) -> int:
        s = int(math.sqrt(self.raw_price(eth_usd)) * Q96)
        return min(max(s, MIN_SQRT_PRICE + 1), MAX_SQRT_PRICE - 1)

    def eth_usd(self, sqrt_price_x96: int) -> float:
        raw = (sqrt_price_x96 / Q96) ** 2
        if self.weth_is_token0:
            return raw / 10 ** (self.usdc_decimals - self.weth_decimals)
        return 1 / (raw / 10 ** (self.weth_decimals - self.usdc_decimals))
