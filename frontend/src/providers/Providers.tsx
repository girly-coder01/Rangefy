"use client";

import type { ReactNode } from "react";
import { Toaster } from "sonner";
import { ThemeProvider } from "./ThemeProvider";
import { Web3Provider } from "./Web3Provider";

export function Providers({ children }: { children: ReactNode }) {
  return (
    <ThemeProvider>
      <Web3Provider>
        {children}
        <Toaster richColors position="bottom-right" />
      </Web3Provider>
    </ThemeProvider>
  );
}
