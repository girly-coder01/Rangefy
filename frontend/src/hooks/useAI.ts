"use client";

import { useQuery } from "@tanstack/react-query";
import {
  AI_API_URL,
  aiGet,
  type BacktestResponse,
  type ForecastResponse,
  type Health,
  type MirrorStatus,
  type SignalPoint,
} from "@/lib/ai";

const opts = { enabled: !!AI_API_URL, refetchInterval: 30_000, retry: 1 } as const;

export const useAIHealth = () => useQuery({ queryKey: ["ai", "health"], queryFn: () => aiGet<Health>("/health"), ...opts });
export const useForecast = () =>
  useQuery({ queryKey: ["ai", "forecast"], queryFn: () => aiGet<ForecastResponse>("/forecast"), ...opts });
export const useBacktest = () =>
  useQuery({
    queryKey: ["ai", "backtest"],
    queryFn: () => aiGet<BacktestResponse>("/model/backtest"),
    ...opts,
    refetchInterval: false,
  });
export const useMirror = () =>
  useQuery({ queryKey: ["ai", "mirror"], queryFn: () => aiGet<MirrorStatus>("/mirror/status"), ...opts });
export const useSignalHistory = (hours = 24) =>
  useQuery({
    queryKey: ["ai", "history", hours],
    queryFn: () => aiGet<{ points: SignalPoint[] }>("/signal/history", { hours }),
    ...opts,
  });
