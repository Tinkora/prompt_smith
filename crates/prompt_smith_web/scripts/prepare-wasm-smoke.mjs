import { cp, lstat, mkdir, readdir, rm } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const staticSource = join(root, "static");
const packageSource = resolve(process.env.WASM_SMOKE_PACKAGE ?? join(staticSource, "pkg"));
const output = join(root, "smoke");
const requiredPackageFiles = ["prompt_smith_web.js", "prompt_smith_web_bg.wasm"];

const metadata = await lstat(packageSource);
if (!metadata.isDirectory() || metadata.isSymbolicLink()) {
  throw new Error("WASM_SMOKE_PACKAGE must be a real directory");
}

const packageEntries = await readdir(packageSource);
for (const name of requiredPackageFiles) {
  if (!packageEntries.includes(name)) {
    throw new Error(`WASM package is missing ${name}`);
  }
}

await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
await cp(staticSource, output, {
  recursive: true,
  filter: (source) => source === staticSource || !source.startsWith(join(staticSource, "pkg")),
});
await cp(packageSource, join(output, "pkg"), { recursive: true });
