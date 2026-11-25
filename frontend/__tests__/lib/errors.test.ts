/** @jest-environment node */
import { BaseError } from "viem";
import { humanError } from "@/lib/errors";

describe("humanError", () => {
  it("passes plain errors through", () => {
    expect(humanError(new Error("boom"))).toBe("boom");
  });
  it("uses viem short messages", () => {
    expect(humanError(new BaseError("short one"))).toContain("short one");
  });
});
