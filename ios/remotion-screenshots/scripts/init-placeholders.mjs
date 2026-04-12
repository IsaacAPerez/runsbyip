#!/usr/bin/env node
// Generates 1x1 solid-color PNGs into public/captures/ so that the
// Remotion pipeline renders end-to-end before real captures are added.
//
// Overwrite these files with your real simulator captures and re-run
// `npm run render-all`.

import { deflateSync, crc32 } from "node:zlib";
import { writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const capturesDir = join(__dirname, "..", "public", "captures");
mkdirSync(capturesDir, { recursive: true });

const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function chunk(type, data) {
  const typeBuf = Buffer.from(type, "ascii");
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const crcInput = Buffer.concat([typeBuf, data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(crcInput), 0);
  return Buffer.concat([len, typeBuf, data, crc]);
}

function solidPng(r, g, b) {
  // IHDR: 1x1, bit depth 8, color type 2 (RGB), compression 0, filter 0, interlace 0
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(1, 0); // width
  ihdr.writeUInt32BE(1, 4); // height
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // color type RGB
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  // Raw scanline: 1 filter byte (0) + RGB triplet
  const raw = Buffer.from([0, r, g, b]);
  const idatData = deflateSync(raw);

  return Buffer.concat([
    PNG_SIG,
    chunk("IHDR", ihdr),
    chunk("IDAT", idatData),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

const files = [
  { name: "sessions-list.png", rgb: [20, 20, 22] },
  { name: "session-detail.png", rgb: [18, 18, 20] },
  { name: "chat.png", rgb: [22, 22, 24] },
];

let wrote = 0;
for (const { name, rgb } of files) {
  const path = join(capturesDir, name);
  if (existsSync(path) && !process.argv.includes("--force")) {
    console.log(`skip  ${name} (already exists, pass --force to overwrite)`);
    continue;
  }
  writeFileSync(path, solidPng(rgb[0], rgb[1], rgb[2]));
  wrote++;
  console.log(`wrote ${name}`);
}

console.log(`\nDone. ${wrote} placeholder(s) written to public/captures/`);
console.log("Replace these files with real simulator captures and re-run `npm run render-all`.");
