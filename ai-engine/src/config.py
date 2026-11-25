"""Runtime configuration, loaded from environment / ai-engine/.env."""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Annotated, Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

ROOT = Path(__file__).resolve().parent.parent
ZERO = "0x0000000000000000000000000000000000000000"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=(ROOT / ".env", ROOT / ".env.addresses"), extra="ignore")

    rpc_url: str = "https://sepolia.unichain.org"
    chain_id: int = 1301

    signal_updater_key: str | None = None
    keeper_key: str | None = None
    mirror_key: str | None = None

    signal_oracle: str = ZERO
    hook: str = ZERO
    factory: str = ZERO
    router: str = ZERO
    lens: str = ZERO
    token0: str = ZERO
    token1: str = ZERO
    pool_tick_spacing: int = 60

    price_source: Literal["coinbase", "binance"] = "coinbase"  # candles
    spot_source: Literal["coinbase", "binance", "coingecko"] | None = None  # mirror price, defaults to price_source
    mirror_deviation_bps: int = 30
    mirror_max_in_token0: int = 2 * 10**18  # mWETH budget per mirror swap (name kept from the env spec)
    mirror_max_in_usdc: int = 6_000 * 10**6  # mUSDC budget per mirror swap
    enable_noise: bool = True

    signal_interval_s: int = 60
    rebalance_interval_s: int = 15
    harvest_interval_s: int = 3600
    mirror_interval_s: int = 20

    api_cors_origins: Annotated[list[str], NoDecode] = Field(default_factory=lambda: ["http://localhost:3000"])
    model_dir: Path = ROOT / "data" / "models"
    db_path: Path = ROOT / "data" / "rangefy.db"

    @field_validator("api_cors_origins", mode="before")
    @classmethod
    def _split_origins(cls, v: object) -> object:
        return [s.strip() for s in v.split(",") if s.strip()] if isinstance(v, str) else v

    @field_validator("model_dir", "db_path", mode="after")
    @classmethod
    def _relative_to_root(cls, v: Path) -> Path:
        return v if v.is_absolute() else ROOT / v


@lru_cache
def get_settings() -> Settings:
    return Settings()
