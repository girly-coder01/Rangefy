"""Transaction sending: one nonce manager per key, EIP-1559 fees, retries with fee bump."""

from __future__ import annotations

import threading
import time
from dataclasses import dataclass

import structlog
from eth_account import Account
from web3 import Web3
from web3.exceptions import ContractCustomError, ContractLogicError, TimeExhausted

log = structlog.get_logger()


@dataclass
class TxResult:
    ok: bool
    tx_hash: str | None
    gas_used: int | None = None
    error: str | None = None
    reverted: bool = False  # estimate/simulation reverted (expected condition, not an infra failure)


class TxSender:
    """One key, local nonce tracking, thread-safe."""

    def __init__(self, w3: Web3, private_key: str, retries: int = 3, bump: float = 1.25,
                 receipt_timeout: float = 90.0) -> None:
        self.w3 = w3
        self.account = Account.from_key(private_key)
        self.address = self.account.address
        self.retries = retries
        self.bump = bump
        self.receipt_timeout = receipt_timeout
        self._lock = threading.Lock()
        self._nonce: int | None = None

    def _next_nonce(self) -> int:
        chain_nonce = self.w3.eth.get_transaction_count(self.address, "pending")
        self._nonce = max(chain_nonce, self._nonce or 0)
        return self._nonce

    def _fees(self, multiplier: float) -> tuple[int, int]:
        base = self.w3.eth.get_block("latest").get("baseFeePerGas", 0) or 0
        prio = max(int(self.w3.eth.max_priority_fee * multiplier), 1)
        return int(base * 2 * multiplier) + prio, prio

    def send(self, fn, label: str = "") -> TxResult:
        """`fn` is a bound web3 contract function (e.g. `vault.functions.rebalance()`)."""
        with self._lock:
            try:
                gas = int(fn.estimate_gas({"from": self.address}) * 1.2)
            except (ContractLogicError, ContractCustomError) as e:
                return TxResult(False, None, error=f"estimate reverted: {e}", reverted=True)

            multiplier = 1.0
            last_err = ""
            nonce = self._next_nonce()
            for attempt in range(self.retries):
                max_fee, prio = self._fees(multiplier)
                tx = fn.build_transaction({
                    "from": self.address, "nonce": nonce, "gas": gas, "chainId": self.w3.eth.chain_id,
                    "maxFeePerGas": max_fee, "maxPriorityFeePerGas": prio, "type": 2,
                })
                try:
                    signed = self.account.sign_transaction(tx)
                    h = self.w3.eth.send_raw_transaction(signed.raw_transaction)
                    receipt = self.w3.eth.wait_for_transaction_receipt(h, timeout=self.receipt_timeout)
                    self._nonce = nonce + 1
                    ok = receipt["status"] == 1
                    log.info("tx.mined", label=label, tx=h.hex(), ok=ok, gas=receipt["gasUsed"])
                    return TxResult(ok, h.hex(), receipt["gasUsed"], None if ok else "reverted on-chain")
                except TimeExhausted as e:
                    last_err = f"timeout: {e}"
                except ValueError as e:  # underpriced / nonce too low / replacement errors
                    last_err = str(e)
                    if "nonce too low" in last_err.lower():
                        nonce = self._next_nonce()
                log.warning("tx.retry", label=label, attempt=attempt + 1, error=last_err)
                multiplier *= self.bump
                time.sleep(1)
            return TxResult(False, None, error=last_err)
