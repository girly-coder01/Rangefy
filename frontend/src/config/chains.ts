import { defineChain } from "viem";

export const unichainSepolia = defineChain({
  id: 1301,
  name: "Unichain Sepolia",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: [process.env.NEXT_PUBLIC_UNICHAIN_RPC_URL || "https://sepolia.unichain.org"] },
  },
  blockExplorers: {
    default: { name: "Uniscan", url: "https://sepolia.uniscan.xyz" },
  },
  testnet: true,
});

// anvil: 31337 fresh, 31338 Unichain Sepolia fork (scripts/local-stack.sh)
const localId = Number(process.env.NEXT_PUBLIC_CHAIN_ID || 1301);
export const localChain = defineChain({
  id: localId === 1301 ? 31337 : localId,
  name: "Rangefy Local",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [process.env.NEXT_PUBLIC_RPC_URL || "http://127.0.0.1:8545"] } },
  testnet: true,
});

export const activeChain = localId === 1301 ? unichainSepolia : localChain;

export const explorerUrl = activeChain.blockExplorers?.default.url;
export const explorerTx = (hash: string) => (explorerUrl ? `${explorerUrl}/tx/${hash}` : undefined);
export const explorerAddress = (addr: string) => (explorerUrl ? `${explorerUrl}/address/${addr}` : undefined);
