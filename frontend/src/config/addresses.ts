import { zeroAddress, type Address } from "viem";
import { activeChain } from "./chains";
import d1301 from "./deployments/1301.json";
import d31337 from "./deployments/31337.json";
import d31338 from "./deployments/31338.json";

export type Deployment = {
  chainId: number;
  deployBlock: number;
  poolManager: Address;
  hook: Address;
  signalOracle: Address;
  vaultFactory: Address;
  curatorRegistry: Address;
  router: Address;
  lens: Address;
  mWETH: Address;
  mUSDC: Address;
};

const all: Record<number, Deployment> = {
  1301: d1301 as Deployment,
  31337: d31337 as Deployment,
  31338: d31338 as Deployment,
};

export const addresses: Deployment = all[activeChain.id] ?? (d1301 as Deployment);
export const isDeployed = addresses.lens !== zeroAddress;

export const DYNAMIC_FEE_FLAG = 0x800000;
export const TICK_SPACING = 60;

const wethIs0 = BigInt(addresses.mWETH) < BigInt(addresses.mUSDC);

export const tokens = {
  mWETH: { address: addresses.mWETH, symbol: "mWETH", decimals: 18 },
  mUSDC: { address: addresses.mUSDC, symbol: "mUSDC", decimals: 6 },
} as const;

export const pool = {
  wethIsToken0: wethIs0,
  token0: wethIs0 ? tokens.mWETH : tokens.mUSDC,
  token1: wethIs0 ? tokens.mUSDC : tokens.mWETH,
  key: {
    currency0: wethIs0 ? addresses.mWETH : addresses.mUSDC,
    currency1: wethIs0 ? addresses.mUSDC : addresses.mWETH,
    fee: DYNAMIC_FEE_FLAG,
    tickSpacing: TICK_SPACING,
    hooks: addresses.hook,
  },
} as const;
