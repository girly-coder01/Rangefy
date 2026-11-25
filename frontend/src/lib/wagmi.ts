import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { http } from "wagmi";
import { activeChain } from "@/config/chains";

export const wagmiConfig = getDefaultConfig({
  appName: "Rangefy",
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || "rangefy-dev", // injected wallets work without one
  chains: [activeChain],
  transports: { [activeChain.id]: http() },
  ssr: true,
});
