const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = __dirname;
const source = fs.readFileSync(path.join(root, "cpu-benchmark.js"), "utf8");
const html = fs.readFileSync(path.join(root, "cpu-benchmark.html"), "utf8");
const worker = fs.readFileSync(path.join(root, "cpu-worker.js"), "utf8");
const embeddedWorker = html.match(/<script id="cpu-worker-source" type="text\/plain">\n([\s\S]*?)\n  <\/script>/);

assert.ok(embeddedWorker, "embedded worker fallback should exist");

const listeners = new Map();
const objectUrls = [];
const context = {
  console,
  window: {
    __CPU_BENCHMARK_EXPOSE_TESTS__: true,
    setTimeout() {}
  },
  document: {
    addEventListener(name, handler) {
      listeners.set(name, handler);
    },
    getElementById(id) {
      if (id === "cpu-worker-source") {
        return { textContent: embeddedWorker[1] };
      }
      return null;
    }
  },
  navigator: {
    hardwareConcurrency: 8,
    userAgent: "cpu-benchmark-test"
  },
  Blob: class Blob {
    constructor(parts, options) {
      this.parts = parts;
      this.options = options;
    }
  },
  URL: {
    createObjectURL(blob) {
      objectUrls.push(blob);
      return "blob:cpu-benchmark-test-" + objectUrls.length;
    }
  },
  fetch: async () => {
    throw new Error("fetch stub was not configured for this test");
  }
};

context.window.document = context.document;
context.window.navigator = context.navigator;

vm.createContext(context);
vm.runInContext(source, context, { filename: "cpu-benchmark.js" });

const hooks = context.window.__cpuBenchmarkTest;
assert.ok(hooks, "test hooks should be exposed when requested");

assert.equal(hooks.formatNoise(5.54), "±5.5%");
assert.equal(hooks.combineVariance(3, 4), 5);

assert.equal(hooks.maxDeviationPercent([90, 100, 110]), 10);
assert.equal(hooks.maxDeviationPercent([100, 200, 300, 400]), 60);
assert.equal(hooks.maxDeviationPercent([0, 0, 0]), 0);
assert.equal(hooks.maxDeviationPercent([]), 0);

const scoreNoise = hooks.getScoreNoise(
  { workerVariancePercent: 3 },
  { workerVariancePercent: 4 },
  { workerVariancePercent: 12 }
);

assert.equal(scoreNoise.single, 3);
assert.equal(scoreNoise.multi, 4);
assert.equal(scoreNoise.fixed, 12);
assert.equal(scoreNoise.scaling, 5);
assert.equal(scoreNoise.fixedSpeedup, Math.sqrt(153));
assert.notEqual(scoreNoise.fixedSpeedup, scoreNoise.fixed);

const display = hooks.getScoreDisplay(1234.4, 9876.5, 7.441, 4.872, scoreNoise);
const expectedDisplay = {
  singleScore: "1,234",
  multiScore: "9,877",
  scaleScore: "7.44x",
  fixedSpeedupScore: "4.87x",
  singleNoise: "±3.0%",
  multiNoise: "±4.0%",
  scaleNoise: "±5.0%",
  fixedNoise: "±12.4%"
};

for (const [key, value] of Object.entries(expectedDisplay)) {
  assert.equal(display[key], value, key + " display value");
}

const fakeElements = Object.fromEntries(
  Object.keys(display).map((key) => [key, { textContent: "not rendered" }])
);
hooks.renderScoreDisplay(display, fakeElements);

for (const [key, value] of Object.entries(display)) {
  assert.equal(fakeElements[key].textContent, value, key + " should be rendered to the score grid");
  assert.notEqual(fakeElements[key].textContent, "", key + " should not render as a blank badge");
}

assert.ok(source.includes("renderScoreDisplay(scoreDisplay);"), "runBenchmark should use the tested score renderer");
assert.ok(!source.includes("wallVariancePercent"), "wall variance should not be computed when unused");

assert.equal(embeddedWorker[1].trim(), worker.trim(), "embedded worker fallback should match cpu-worker.js");

async function main() {
  hooks.resetWorkerUrl();
  context.fetch = async (url, options) => ({
    ok: true,
    text: async () => worker
  });
  assert.equal(await hooks.getWorkerUrl(), "blob:cpu-benchmark-test-1");
  assert.equal(hooks.getWorkerSourceLabel(), "cpu-worker.js?v=4");
  assert.equal(objectUrls[0].parts[0], worker);

  hooks.resetWorkerUrl();
  context.fetch = async () => ({
    ok: true,
    text: async () => worker + "\n"
  });
  assert.equal(await hooks.getWorkerUrl(), "blob:cpu-benchmark-test-2");
  assert.equal(hooks.getWorkerSourceLabel(), "cpu-worker.js?v=4");

  hooks.resetWorkerUrl();
  context.fetch = async () => ({
    ok: true,
    text: async () => worker + "\n/* drift */"
  });
  assert.equal(await hooks.getWorkerUrl(), "blob:cpu-benchmark-test-3");
  assert.equal(hooks.getWorkerSourceLabel(), "cpu-worker.js?v=4 (fallback mismatch)");

  hooks.resetWorkerUrl();
  context.fetch = async () => {
    throw new Error("network unavailable");
  };
  assert.equal(await hooks.getWorkerUrl(), "blob:cpu-benchmark-test-4");
  assert.equal(hooks.getWorkerSourceLabel(), "embedded fallback");
  assert.equal(objectUrls[3].parts[0], embeddedWorker[1].trim());

  console.log("cpu-benchmark tests passed");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
