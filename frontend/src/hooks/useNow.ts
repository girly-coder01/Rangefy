"use client";

import { useEffect, useState } from "react";

// Unix seconds, refreshed on an interval so renders stay pure.
export function useNow(ms = 5000) {
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  useEffect(() => {
    const id = setInterval(() => setNow(Math.floor(Date.now() / 1000)), ms);
    return () => clearInterval(id);
  }, [ms]);
  return now;
}
