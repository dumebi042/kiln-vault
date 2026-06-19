import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const bundleDir = process.argv[2];
if (!bundleDir) {
  console.error("usage: node scripts/reconstruct-verified-sources.mjs <sourcify-json-dir>");
  process.exit(1);
}

const wanted = new Map();
const origins = new Map();
const conflicts = [];

function normalizedOutputPath(sourcePath) {
  const marker = "/sources/";
  const rel = sourcePath.includes(marker)
    ? sourcePath.slice(sourcePath.indexOf(marker) + marker.length)
    : sourcePath;

  if (rel.startsWith("src/")) return rel;
  if (rel.startsWith("lib/openzeppelin-contracts/")) return path.posix.join("verified", rel);
  if (rel.startsWith("lib/openzeppelin-contracts-upgradeable/")) return path.posix.join("verified", rel);
  return null;
}

for (const jsonFile of fs.readdirSync(bundleDir).filter((f) => f.endsWith(".json")).sort()) {
  const pkg = JSON.parse(fs.readFileSync(path.join(bundleDir, jsonFile), "utf8"));
  for (const item of pkg.files ?? []) {
    if (!item?.path?.endsWith(".sol") || typeof item.content !== "string") continue;

    const rel = normalizedOutputPath(item.path);
    if (!rel) continue;

    const previous = wanted.get(rel);
    if (previous !== undefined && previous !== item.content) {
      conflicts.push({
        path: rel,
        previousOrigin: origins.get(rel),
        nextOrigin: jsonFile,
        previousHash: crypto.createHash("sha256").update(previous).digest("hex"),
        nextHash: crypto.createHash("sha256").update(item.content).digest("hex"),
      });
      continue;
    }

    wanted.set(rel, item.content);
    origins.set(rel, jsonFile);
  }
}

for (const [rel, content] of [...wanted.entries()].sort()) {
  const dest = path.join(process.cwd(), rel);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, content);
}

const outDir = path.dirname(path.dirname(bundleDir));
fs.writeFileSync(path.join(outDir, "reconstructed-files.txt"), [...wanted.keys()].sort().join("\n") + "\n");
fs.writeFileSync(path.join(outDir, "reconstruction-conflicts.json"), JSON.stringify(conflicts, null, 2) + "\n");

console.log(`wrote=${wanted.size}`);
console.log(`conflicts=${conflicts.length}`);
