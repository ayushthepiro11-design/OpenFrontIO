import { describe, expect, it } from "vitest";
import { CosmeticsSchema } from "../src/core/CosmeticSchemas";
import cosmeticsFallback from "../resources/cosmetics.json";

// Guards the offline territory-skin bundle: the committed snapshot of the
// live catalog must stay schema-valid, keep its patterns, and keep skin
// URLs local (remote CDN URLs would silently fail with no internet).
describe("bundled offline cosmetics catalog", () => {
  it("parses against CosmeticsSchema", () => {
    const result = CosmeticsSchema.safeParse(cosmeticsFallback);
    expect(result.success).toBe(true);
  });

  it("contains a full pattern library", () => {
    const result = CosmeticsSchema.safeParse(cosmeticsFallback);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(Object.keys(result.data.patterns).length).toBeGreaterThan(100);
    expect(
      Object.keys(result.data.colorPalettes ?? {}).length,
    ).toBeGreaterThan(10);
  });

  it("points all skins at bundled local images", () => {
    const result = CosmeticsSchema.safeParse(cosmeticsFallback);
    expect(result.success).toBe(true);
    if (!result.success) return;
    const skins = Object.values(result.data.skins ?? {});
    expect(skins.length).toBeGreaterThan(0);
    for (const skin of skins) {
      expect(skin.url.startsWith("http")).toBe(false);
    }
  });
});
