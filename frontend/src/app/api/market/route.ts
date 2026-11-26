import { NextResponse } from "next/server";
import { ethUsd } from "@/lib/server/market";

export async function GET() {
  try {
    return NextResponse.json({ ethUsd: await ethUsd(), source: "coingecko" });
  } catch (e) {
    return NextResponse.json({ error: (e as Error).message }, { status: 502 });
  }
}
