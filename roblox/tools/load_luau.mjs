import { execSync } from "node:child_process";
import fs from "node:fs";

const LUAU_ENTRY = "/tmp/luau-wasm/node_modules/luau-web/src/index.js";
if (!fs.existsSync(LUAU_ENTRY)) {
  fs.mkdirSync("/tmp/luau-wasm", { recursive: true });
  execSync(
    "npm install --no-audit --no-fund --prefix /tmp/luau-wasm luau-web",
    { stdio: "inherit" },
  );
}

export const { LuauState } = await import(LUAU_ENTRY);
