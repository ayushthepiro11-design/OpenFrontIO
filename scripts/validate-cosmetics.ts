import fs from "fs";
import { CosmeticsSchema } from "../src/core/CosmeticSchemas";

const raw = fs.readFileSync("resources/cosmetics.json", "utf-8");
const result = CosmeticsSchema.safeParse(JSON.parse(raw));
if (!result.success) {
  console.error("SCHEMA FAIL:", result.error.issues.slice(0, 5));
  process.exit(1);
}
const d = result.data;
console.log("SCHEMA OK");
console.log("patterns:", Object.keys(d.patterns).length);
console.log("skins:", Object.keys(d.skins ?? {}).length);
console.log("flags:", Object.keys(d.flags).length);
console.log("crowns:", Object.keys(d.crowns ?? {}).length);
console.log("palettes:", Object.keys(d.colorPalettes ?? {}).length);
