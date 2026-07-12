const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = __dirname;
const source = fs.readFileSync(path.join(root, "cpu-benchmark.js"), "utf8");
const html = fs.readFileSync(path.join(root, "cpu-benchmark.html"), "utf8");
const worker = fs.readFileSync(path.join(root, "cpu-worker.js"), "utf8");
const headers = fs.readFileSync(path.join(root, "_headers"), "utf8");
const embeddedWorker = html.match(/<script id="cpu-worker-source" type="text\/plain">\n([\s\S]*?)\n  <\/script>/);

assert.ok(embeddedWorker, "embedded worker fallback should exist");

const listeners = new Map();
const objectUrls = [];
const scheduledTimers = new Map();
let nextTimerId = 1;
const context = {
  console,
  window: {
    __CPU_BENCHMARK_EXPOSE_TESTS__: true,
    setTimeout(handler) {
      const id = nextTimerId;
      nextTimerId += 1;
      scheduledTimers.set(id, handler);
      return id;
    },
    clearTimeout(id) {
      scheduledTimers.delete(id);
    }
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

assert.equal(hooks.formatSpread(5.54), "±5.5%");

assert.equal(hooks.maxDeviationPercent([90, 100, 110]), 10);
assert.equal(hooks.maxDeviationPercent([100, 200, 300, 400]), 60);
assert.equal(hooks.maxDeviationPercent([0, 0, 0]), 0);
assert.equal(hooks.maxDeviationPercent([]), 0);

assert.deepEqual(
  Array.from(hooks.pairedRatios([10, 20, 30], [2, 4, 5])),
  [5, 5, 6]
);

assert.deepEqual(Array.from(hooks.getRotatingPhaseOrder(0)), ["single", "fixed", "multi"]);
assert.deepEqual(Array.from(hooks.getRotatingPhaseOrder(1)), ["fixed", "multi", "single"]);
assert.deepEqual(Array.from(hooks.getRotatingPhaseOrder(2)), ["multi", "single", "fixed"]);
assert.deepEqual(Array.from(hooks.getRotatingPhaseOrder(3)), ["single", "fixed", "multi"]);

const scoreSpread = hooks.getScoreSpread(
  { workerDeviationPercent: 3 },
  { workerDeviationPercent: 4 },
  { workerDeviationPercent: 12 },
  [4, 5, 6],
  [2, 2.5, 3]
);

assert.equal(scoreSpread.single, 3);
assert.equal(scoreSpread.multi, 4);
assert.equal(scoreSpread.fixed, 12);
assert.equal(scoreSpread.scaling, 20);
assert.equal(scoreSpread.fixedSpeedup, 20);

const display = hooks.getScoreDisplay(1234.4, 9876.5, 7.441, 4.872, scoreSpread);
const expectedDisplay = {
  singleScore: "1,234",
  multiScore: "9,877",
  scaleScore: "7.44x",
  fixedSpeedupScore: "4.87x",
  singleSpread: "±3.0%",
  multiSpread: "±4.0%",
  scaleSpread: "±20.0%",
  fixedSpread: "±20.0%"
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

const stopFunction = source.match(/function stopBenchmark\(\) \{[\s\S]*?\n  \}/);
assert.ok(stopFunction, "stopBenchmark should exist");
assert.ok(!stopFunction[0].includes("updateControls(false)"), "Stop must not enable Run before the active run unwinds");

assert.match(headers, /Cross-Origin-Opener-Policy: same-origin/);
assert.match(headers, /Cross-Origin-Embedder-Policy: require-corp/);

assert.equal(embeddedWorker[1].trim(), worker.trim(), "embedded worker fallback should match cpu-worker.js");

async function main() {
  const barrier = new Int32Array(new SharedArrayBuffer(8));
  const barrierWait = hooks.createBarrierWait(barrier, 1);
  assert.equal(scheduledTimers.size, 1, "barrier wait should schedule one poll");
  barrierWait.cancel();
  assert.equal(scheduledTimers.size, 0, "cancelling barrier wait should clear its poll");

  const workerMessages = [];
  const workerContext = {
    performance,
    self: {
      postMessage(message) {
        workerMessages.push(message);
      }
    }
  };
  vm.createContext(workerContext);
  vm.runInContext(worker, workerContext, { filename: "cpu-worker.js" });
  await workerContext.self.onmessage({ data: { type: "init", workerIndex: 0 } });
  const ready = workerMessages.shift();
  assert.equal(ready.type, "ready");
  assert.equal(ready.warmupChecksum, hooks.expectedWarmupChecksum);

  await workerContext.self.onmessage({
    data: {
      type: "run",
      jobId: 1,
      workerIndex: 0,
      iterations: 1000000,
      seed: 0xc0ffee42
    }
  });
  const verification = workerMessages.shift();
  assert.equal(verification.type, "result");
  assert.equal(verification.checksum, hooks.expectedVerifyChecksum);

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
