import type { NextConfig } from "next";

// Optional x402 peers of @coinbase/cdp-sdk (via wagmi's Base Account connector). Never loaded.
const EMPTY = "./src/lib/stubs/empty.js";
const optionalPeers = [
  "@x402/core/client",
  "@x402/evm",
  "@x402/evm/exact/client",
  "@x402/evm/upto/client",
  "@x402/svm/exact/client",
];

const nextConfig: NextConfig = {
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
    resolveAlias: Object.fromEntries(optionalPeers.map((m) => [m, EMPTY])),
  },
};

export default nextConfig;
