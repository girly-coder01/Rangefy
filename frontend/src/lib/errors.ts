import { BaseError, ContractFunctionRevertedError, UserRejectedRequestError } from "viem";

const MESSAGES: Record<string, string> = {
  PriceDeviation: "Price moved too far from the EMA reference. Try again in a minute.",
  Cooldown: "This vault rebalanced recently. The cooldown hasn't passed yet.",
  NoRebalanceNeeded: "The vault is already positioned correctly.",
  Slippage: "Amounts moved past your slippage limit. Refresh the preview and retry.",
  DepositsArePaused: "The curator has paused deposits for this vault.",
  InsufficientShares: "Amount too small, or more shares than you hold.",
  ZeroAmount: "Enter an amount.",
  FaucetCooldown: "Faucet already used. You can claim again in 24 hours.",
  NotCurator: "Register as a curator first.",
  OnlyCurator: "Only this vault's curator can do that.",
  PerformanceFeeIncrease: "Performance fee can only be lowered.",
  InvalidParams: "A strategy parameter is out of bounds.",
  InvalidName: "Name must be 3–32 letters, numbers, spaces, - or _.",
  NameTaken: "That curator name is taken.",
  AlreadyRegistered: "This wallet is already a curator.",
  TooLittleReceived: "Output below your minimum. Increase slippage or reduce size.",
  Expired: "Transaction deadline passed.",
};

export function errorName(err: unknown): string | undefined {
  if (!(err instanceof BaseError)) return undefined;
  const reverted = err.walk((e) => e instanceof ContractFunctionRevertedError);
  if (reverted instanceof ContractFunctionRevertedError) return reverted.data?.errorName ?? reverted.reason;
  return undefined;
}

export function humanError(err: unknown): string {
  if (err instanceof BaseError) {
    if (err.walk((e) => e instanceof UserRejectedRequestError)) return "Transaction rejected in wallet.";
    const name = errorName(err);
    if (name && MESSAGES[name]) return MESSAGES[name];
    if (name) return name;
    return err.shortMessage || err.message;
  }
  return err instanceof Error ? err.message : String(err);
}
