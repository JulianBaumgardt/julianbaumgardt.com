"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = __dirname;
const source = fs.readFileSync(path.join(root, "internet-quality.js"), "utf8");
const html = fs.readFileSync(path.join(root, "internet-quality.html"), "utf8");
const worker = fs.readFileSync(path.join(root, "cloudflare-worker.js"), "utf8");
const wrangler = fs.readFileSync(path.join(root, "wrangler.jsonc"), "utf8");
const homepage = fs.readFileSync(path.join(root, "index.html"), "utf8");
const viewer = fs.readFileSync(path.join(root, "code-viewer.html"), "utf8");

const context = {
  console,
  window: { __INTERNET_QUALITY_EXPOSE_TESTS__: true },
  document: { addEventListener() {}, getElementById() { return null; } },
  Number,
  Math,
  Date,
  DOMException,
  setTimeout,
  clearTimeout
};

vm.createContext(context);
vm.runInContext(source, context, { filename: "internet-quality.js" });
const hooks = context.window.__internetQualityTest;
assert.ok(hooks, "test hooks should be exposed");

assert.equal(hooks.median([30, 10, 20]), 20);
assert.equal(hooks.median([10, 20, 30, 40]), 25);
assert.equal(hooks.percentile([0, 10, 20, 30, 40], 0.1), 4);
assert.equal(hooks.jitter([10, 14, 12, 18]), 4);
assert.equal(hooks.maxDeviationPercent([90, 100, 110]), 10);
assert.equal(hooks.consistencyPercent([50, 100, 100, 100, 100]), 70);
assert.equal(hooks.stabilityLabel(5, 0, 90), "Excellent");
assert.equal(hooks.stabilityLabel(30, 0, 90), "Variable");
assert.equal(hooks.stabilityLabel(5, 4, 90), "Unstable");

const rounds = [
  { idleMs: 20, jitterMs: 3, loadedMs: 60, downloadMbps: 100, consistency: 90, dnsMs: 5, attempts: 10, failures: 0 },
  { idleMs: 22, jitterMs: 4, loadedMs: 70, downloadMbps: 90, consistency: 80, dnsMs: 7, attempts: 10, failures: 1 },
  { idleMs: 24, jitterMs: 5, loadedMs: 80, downloadMbps: 80, consistency: 70, dnsMs: 9, attempts: 10, failures: 0 }
];
const aggregate = hooks.aggregateRounds(rounds);
assert.equal(aggregate.idleMs, 22);
assert.equal(aggregate.loadedMs, 70);
assert.equal(aggregate.downloadMbps, 90);
assert.equal(aggregate.penaltyMs, 48);
assert.equal(aggregate.lossPercent, 100 / 30);
assert.equal(aggregate.rounds, 3);
assert.equal(hooks.assess({ ...aggregate, lossPercent: 0 }).streaming[0], "Excellent");

assert.match(html, /Internet Quality/);
assert.match(html, /Browser limits:/);
assert.match(homepage, /internet-quality\.html/);
assert.match(viewer, /cloudflare-worker\.js/);
assert.match(worker, /MAX_DOWNLOAD_BYTES = 16 \* 1024 \* 1024/);
assert.match(worker, /Cache-Control/);
assert.match(worker, /Content-Encoding/);
assert.match(worker, /crypto\.randomUUID/);
assert.match(wrangler, /julianbaumgardt\.com\/network-test\/\*/);
assert.match(source, /detailsContent\.innerHTML = `<table class="round-table">/, "round details should use the fixed table template");

async function testWorker() {
  const workerContext = {
    URL,
    Response,
    Request,
    Headers,
    ReadableStream,
    Uint8Array,
    Number,
    Math,
    crypto: globalThis.crypto,
    performance,
    fetch: async () => new Response("{}", { status: 200 })
  };
  vm.createContext(workerContext);
  vm.runInContext(worker.replace("export default", "globalThis.workerModule ="), workerContext, { filename: "cloudflare-worker.js" });
  const handler = workerContext.workerModule.fetch;

  const ping = await handler(new Request("https://julianbaumgardt.com/network-test/ping"));
  assert.equal(ping.status, 200);
  assert.equal(await ping.text(), "ok");
  assert.equal(ping.headers.get("cache-control"), "no-store, no-cache, must-revalidate, proxy-revalidate");

  const download = await handler(new Request("https://julianbaumgardt.com/network-test/download?bytes=1048576"));
  assert.equal(download.status, 200);
  assert.equal((await download.arrayBuffer()).byteLength, 1048576);
  assert.equal(download.headers.get("content-encoding"), "identity");

  const capped = await handler(new Request("https://julianbaumgardt.com/network-test/download?bytes=999999999"));
  assert.equal(Number(capped.headers.get("content-length")), 16 * 1024 * 1024);
  await capped.body.cancel();

  const forbidden = await handler(new Request("https://julianbaumgardt.com/network-test/ping", { headers: { Origin: "https://example.com" } }));
  assert.equal(forbidden.status, 403);
}

testWorker().then(() => console.log("internet quality tests passed")).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
