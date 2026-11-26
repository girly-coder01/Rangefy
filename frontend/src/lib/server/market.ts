import "server-only";

// ETH/USD from CoinGecko, cached for 30s by Next's fetch cache.
export async function ethUsd(): Promise<number> {
  const res = await fetch("https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd", {
    next: { revalidate: 30 },
    signal: AbortSignal.timeout(8000),
  });
  if (!res.ok) throw new Error(`coingecko ${res.status}`);
  const data = (await res.json()) as { ethereum?: { usd?: number } };
  const p = data.ethereum?.usd;
  if (!p) throw new Error("coingecko: no price");
  return p;
}
