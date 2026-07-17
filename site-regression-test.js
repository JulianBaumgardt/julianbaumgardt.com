"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const root = __dirname;
const htmlFiles = fs.readdirSync(root).filter((fileName) => fileName.endsWith(".html"));

for (const fileName of htmlFiles) {
  const source = fs.readFileSync(path.join(root, fileName), "utf8");
  assert.match(source, /<html\s+lang="en">/i, `${fileName} should declare its language`);
  assert.match(source, /<meta\s+name="viewport"/i, `${fileName} should include a responsive viewport`);
  assert.match(source, /site-typography\.css/, `${fileName} should load the shared accessibility styles`);

  const ids = Array.from(source.matchAll(/\sid="([^"]+)"/g), (match) => match[1]);
  assert.equal(new Set(ids).size, ids.length, `${fileName} should not contain duplicate IDs`);

  const references = Array.from(source.matchAll(/\s(?:href|src)="([^"]+)"/g), (match) => match[1]);
  for (const reference of references) {
    if (/^(?:https?:|mailto:|data:|#)/i.test(reference)) continue;
    const localPath = reference.split(/[?#]/)[0];
    if (!localPath) continue;
    assert.ok(fs.existsSync(path.join(root, localPath)), `${fileName} references missing file ${localPath}`);
  }
}

const headers = fs.readFileSync(path.join(root, "_headers"), "utf8");
assert.match(headers, /Content-Security-Policy:/);
assert.match(headers, /script-src[^;]*'wasm-unsafe-eval'/, "CSP should allow WebAssembly compilation without enabling general unsafe-eval");
assert.match(headers, /frame-ancestors 'none'/);
assert.match(headers, /Cross-Origin-Opener-Policy: same-origin/);
assert.match(headers, /Cross-Origin-Embedder-Policy: require-corp/);

const cpuBenchmarkPage = fs.readFileSync(path.join(root, "cpu-benchmark.html"), "utf8");
assert.doesNotMatch(cpuBenchmarkPage, /\.topbar,\s*\.hero\s*\{\s*display:\s*grid/, "CPU benchmark mobile layout should keep the top bar on one row");

const internetTesterPage = fs.readFileSync(path.join(root, "internet-quality.html"), "utf8");
assert.doesNotMatch(internetTesterPage, /\.topbar\s*\{[^}]*display:\s*grid/, "Internet Tester mobile layout should keep the top bar on one row");

const homePage = fs.readFileSync(path.join(root, "index.html"), "utf8");
assert.match(homePage, /<title>Julian Baumgardt — Software Projects<\/title>/, "Homepage should use a descriptive search title");
assert.match(homePage, /<section class="sites"[^>]*data-nosnippet/, "Homepage navigation should not be used as a search-result snippet");

const optimiserPath = path.join(root, "w11-optimiser", "w11-optimiser.ps1");
const optimiser = fs.readFileSync(optimiserPath, "utf8");
const manifest = JSON.parse(fs.readFileSync(path.join(root, "w11-optimiser", "w11-optimiser.manifest.json"), "utf8"));
const version = optimiser.match(/\$ScriptVersion = "([^"]+)"/)[1];
const actualHash = crypto.createHash("sha256").update(fs.readFileSync(optimiserPath)).digest("hex");

assert.equal(manifest.version, version, "optimiser manifest version should match the script");
assert.equal(manifest.sha256.toLowerCase(), actualHash, "optimiser manifest hash should match the script");
const escapedVersion = version.replace(/\./g, "\\.");
assert.match(fs.readFileSync(path.join(root, "w11-optimiser", "w11-optimiser-launcher.cmd"), "utf8"), new RegExp(`version ${escapedVersion}`));
assert.match(fs.readFileSync(path.join(root, "w11-optimiser", "w11-optimiser-readme.md"), "utf8"), new RegExp("Current release: `" + escapedVersion + "`"));

console.log("site regression tests passed");
