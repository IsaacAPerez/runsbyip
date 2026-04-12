#!/usr/bin/env node
// Renders every App Store screenshot composition to out/<id>.png
// in a single command.

import { spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(__dirname, "..");
const outDir = join(projectRoot, "out");
mkdirSync(outDir, { recursive: true });

const SCREENS = ["sessions-list", "session-detail", "chat"];
const SIZES = ["69", "65"];

const entry = join(projectRoot, "src", "index.ts");

for (const screen of SCREENS) {
  for (const size of SIZES) {
    const id = `${screen}-${size}`;
    const output = join(outDir, `${id}.png`);
    console.log(`→ rendering ${id}`);
    const result = spawnSync(
      "npx",
      ["remotion", "still", entry, id, output, "--log=error"],
      { cwd: projectRoot, stdio: "inherit" }
    );
    if (result.status !== 0) {
      console.error(`✗ failed: ${id}`);
      process.exit(result.status ?? 1);
    }
  }
}

console.log("\n✓ All stills rendered to out/");
