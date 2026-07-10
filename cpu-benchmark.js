(function() {
  "use strict";

  const WORKLOADS = {
    quick: { label: "Quick", iterations: 12000000, rounds: 3 },
    standard: { label: "Standard", iterations: 42000000, rounds: 5 },
    heavy: { label: "Heavy", iterations: 100000000, rounds: 5 }
  };

  const REFERENCE_ITERATIONS_PER_SECOND = 100000000;
  const WORKER_URL = "cpu-worker.js?v=4";
  const MAX_WORKERS = 32;
  const VERIFY_ITERATIONS = 1000000;
  const VERIFY_SEED = 0xc0ffee42;
  const WARMUP_ROUNDS = 1;
  const ROUND_SETTLE_MS = 80;
  const PHASE_SETTLE_MS = 350;
  const WORKER_STARTUP_TIMEOUT_MS = 15000;
  const WORKER_BATCH_TIMEOUT_MS = 90000;

  const state = {
    workers: [],
    pending: new Map(),
    jobId: 0,
    running: false,
    cancelled: false,
    backgroundedDuringRun: false,
    visibilityListener: null,
    workerBlobUrl: null,
    workerSource: "unknown"
  };

  const elements = {};

  function $(id) {
    return document.getElementById(id);
  }

  function formatScore(value) {
    if (!Number.isFinite(value) || value <= 0) return "--";
    return Math.round(value).toLocaleString();
  }

  function formatMs(value) {
    if (!Number.isFinite(value)) return "--";
    return `${value.toFixed(value < 100 ? 2 : 1)} ms`;
  }

  function formatNumber(value, digits) {
    if (!Number.isFinite(value)) return "--";
    return value.toLocaleString(undefined, {
      maximumFractionDigits: digits,
      minimumFractionDigits: digits
    });
  }

  function formatRate(iterations, wallMs) {
    if (!Number.isFinite(wallMs) || wallMs <= 0) return "--";
    return `${formatNumber((iterations / (wallMs / 1000)) / 1000000, 1)} M/s`;
  }

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function median(values) {
    const sorted = values.slice().sort((a, b) => a - b);
    const middle = Math.floor(sorted.length / 2);
    if (sorted.length % 2 === 1) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  function maxDeviationPercent(values) {
    const center = median(values);
    if (!Number.isFinite(center) || center <= 0) return 0;
    const spread = Math.max(...values.map((value) => Math.abs(value - center)));
    return (spread / center) * 100;
  }

  function formatNoise(value) {
    if (!Number.isFinite(value)) return "--";
    return `±${formatNumber(value, 1)}%`;
  }

  function getReportedHardwareConcurrency() {
    return navigator.hardwareConcurrency || 1;
  }

  function clampWorkerCount(value) {
    const numeric = Number.parseInt(value, 10);
    if (!Number.isFinite(numeric)) return 1;
    return Math.max(1, Math.min(MAX_WORKERS, numeric));
  }

  function getHardwareConcurrency() {
    return clampWorkerCount(getReportedHardwareConcurrency());
  }

  function getWorkerCapText(workerCount) {
    const reported = getReportedHardwareConcurrency();
    if (reported > MAX_WORKERS) return `limited to ${workerCount} of ${reported}`;
    return `not capped (${reported} reported)`;
  }

  function setStatus(text) {
    elements.status.textContent = text;
  }

  function setProgress(value) {
    const clamped = Math.max(0, Math.min(1, value));
    elements.progressBar.style.transform = `scaleX(${clamped})`;
  }

  function setMetric(id, value) {
    const element = elements.metrics[id];
    if (element) element.textContent = value;
  }

  function sleep(ms) {
    return new Promise((resolve) => window.setTimeout(resolve, ms));
  }

  function withTimeout(promise, timeoutMs, message) {
    let timeoutId = null;
    const timeout = new Promise((resolve, reject) => {
      timeoutId = window.setTimeout(() => reject(new Error(message)), timeoutMs);
    });

    return Promise.race([promise, timeout]).finally(() => {
      if (timeoutId !== null) window.clearTimeout(timeoutId);
    });
  }

  function scoreFor(iterations, wallMs) {
    const perSecond = iterations / (wallMs / 1000);
    return (perSecond / REFERENCE_ITERATIONS_PER_SECOND) * 1000;
  }

  function xorChecksums(results) {
    return results.reduce((acc, result) => (acc ^ result.checksum) >>> 0, 0);
  }

  function combineVariance(...values) {
    return Math.sqrt(values.reduce((sum, value) => sum + value * value, 0));
  }

  function getScoreNoise(single, multi, fixed) {
    return {
      single: single.workerVariancePercent,
      multi: multi.workerVariancePercent,
      scaling: combineVariance(single.workerVariancePercent, multi.workerVariancePercent),
      fixed: fixed.workerVariancePercent,
      fixedSpeedup: combineVariance(single.workerVariancePercent, fixed.workerVariancePercent)
    };
  }

  function getScoreDisplay(singleScore, multiScore, scaling, fixedSpeedup, scoreNoise) {
    return {
      singleScore: formatScore(singleScore),
      multiScore: formatScore(multiScore),
      scaleScore: `${formatNumber(scaling, 2)}x`,
      fixedSpeedupScore: `${formatNumber(fixedSpeedup, 2)}x`,
      singleNoise: formatNoise(scoreNoise.single),
      multiNoise: formatNoise(scoreNoise.multi),
      scaleNoise: formatNoise(scoreNoise.scaling),
      fixedNoise: formatNoise(scoreNoise.fixedSpeedup)
    };
  }

  function renderScoreDisplay(display, targetElements = elements) {
    for (const [key, value] of Object.entries(display)) {
      targetElements[key].textContent = value;
    }
  }

  function resetResults() {
    elements.singleScore.textContent = "--";
    elements.multiScore.textContent = "--";
    elements.scaleScore.textContent = "--";
    elements.fixedSpeedupScore.textContent = "--";
    elements.singleNoise.textContent = "";
    elements.multiNoise.textContent = "";
    elements.scaleNoise.textContent = "";
    elements.fixedNoise.textContent = "";
    setMetric("singleTime", "--");
    setMetric("multiWall", "--");
    setMetric("fixedWall", "--");
    setMetric("workersUsed", "--");
    setMetric("workerCap", "--");
    setMetric("workload", "--");
    setMetric("startMode", "--");
    setMetric("visibility", "--");
    setMetric("verification", "--");
    setMetric("workerSource", "--");
    renderDetailsEmpty();
    setProgress(0);
  }

  function renderDetailsEmpty() {
    if (!elements.detailsContent) return;
    elements.detailsContent.innerHTML = '<div class="details-empty">No completed run yet.</div>';
  }

  function detailRows(rows) {
    return rows.map(([label, value]) => `
      <div class="details-row">
        <span>${escapeHtml(label)}</span>
        <strong>${escapeHtml(value)}</strong>
      </div>
    `).join("");
  }

  function getEnvironmentRows(summary) {
    const uaData = navigator.userAgentData;
    const browser = uaData && uaData.brands
      ? uaData.brands.map((brand) => `${brand.brand} ${brand.version}`).join(", ")
      : navigator.userAgent;
    const platform = uaData && uaData.platform ? uaData.platform : navigator.platform || "Unknown";
    const mobile = uaData ? (uaData.mobile ? "Yes" : "No") : "Unknown";

    return [
      ["Browser", browser],
      ["Platform", platform],
      ["Mobile", mobile],
      ["Reported CPUs", String(getReportedHardwareConcurrency() || "Unknown")],
      ["Workers Used", String(summary.workerCount)],
      ["Worker Cap", summary.workerCap],
      ["Worker Source", summary.workerSource],
      ["Start Mode", summary.startMode],
      ["Visibility", summary.backgroundedDuringRun ? "Backgrounded During Run" : "Foreground For Run"],
      ["Cross-Origin Isolated", window.crossOriginIsolated ? "Yes" : "No"]
    ];
  }

  function renderRoundRows(phases) {
    const rows = [];
    for (const phase of phases) {
      const warmupRuns = Array.isArray(phase.warmupRuns) ? phase.warmupRuns : [];
      const measuredRuns = Array.isArray(phase.runs) ? phase.runs : [];
      const warmupRows = warmupRuns.map((run) => ({ run, label: "Warm Up" }));
      const measuredRows = measuredRuns.map((run, index) => ({ run, label: String(index + 1) }));
      for (const row of warmupRows.concat(measuredRows)) {
        rows.push(`
          <tr>
            <td>${escapeHtml(phase.label)}</td>
            <td>${escapeHtml(row.label)}</td>
            <td>${escapeHtml(formatMs(row.run.wallMs))}</td>
            <td>${escapeHtml(formatMs(row.run.workerMs))}</td>
          </tr>
        `);
      }
    }

    return `
      <table class="round-table">
        <thead>
          <tr>
            <th>Phase</th>
            <th>Run</th>
            <th>Wall</th>
            <th>Worker</th>
          </tr>
        </thead>
        <tbody>${rows.join("")}</tbody>
      </table>
    `;
  }

  function renderRunDetails(summary) {
    if (!elements.detailsContent) return;

    elements.detailsContent.innerHTML = `
      <div class="details-block">
        <h2>Environment</h2>
        <div class="details-list">
          ${detailRows(getEnvironmentRows(summary))}
        </div>
      </div>
      <div class="details-block">
        <h2>Scoring</h2>
        <div class="details-list">
          ${detailRows([
            ["Baseline", `${REFERENCE_ITERATIONS_PER_SECOND.toLocaleString()} iter/s = 1000`],
            ["Single Rate", formatRate(summary.baseIterations, summary.single.workerMs)],
            ["Multi Rate", formatRate(summary.baseIterations * summary.workerCount, summary.multi.workerMs)],
            ["Scaling", `${formatNumber(summary.scaling, 2)}x`],
            ["Efficiency", `${formatNumber(summary.efficiency * 100, 1)}%`],
            ["Fixed Speedup", `${formatNumber(summary.fixedSpeedup, 2)}x`],
            ["Single Noise", formatNoise(summary.scoreNoise.single)],
            ["Multi Noise", formatNoise(summary.scoreNoise.multi)],
            ["Scaling Noise", formatNoise(summary.scoreNoise.scaling)],
            ["Fixed Noise", formatNoise(summary.scoreNoise.fixed)],
            ["Fixed Speedup Noise", formatNoise(summary.scoreNoise.fixedSpeedup)],
            ["Single Wall", formatMs(summary.single.wallMs)],
            ["Multi Wall", formatMs(summary.multi.wallMs)],
            ["Fixed Wall", formatMs(summary.fixed.wallMs)],
            ["Verification", `0x${summary.verification.checksum.toString(16).padStart(8, "0")}`],
            ["Single Checksum", `0x${summary.single.checksum.toString(16).padStart(8, "0")}`],
            ["Fixed Checksum", `0x${summary.fixed.checksum.toString(16).padStart(8, "0")}`],
            ["Multi Checksum", `0x${summary.multi.checksum.toString(16).padStart(8, "0")}`]
          ])}
        </div>
      </div>
      <div class="details-block wide">
        <h2>Timing Rounds</h2>
        ${renderRoundRows([
          { label: "Single", warmupRuns: summary.single.warmupRuns, runs: summary.single.runs },
          { label: "Fixed", warmupRuns: summary.fixed.warmupRuns, runs: summary.fixed.runs },
          { label: "Multi", warmupRuns: summary.multi.warmupRuns, runs: summary.multi.runs }
        ])}
      </div>
    `;
  }

  function stopWorkers(reason) {
    if (reason) {
      for (const pending of state.pending.values()) {
        pending.reject(reason);
      }
    }
    state.pending.clear();

    for (const worker of state.workers) {
      worker.terminate();
    }
    state.workers = [];
  }

  async function getWorkerUrl() {
    if (state.workerBlobUrl) return state.workerBlobUrl;

    try {
      const response = await fetch(WORKER_URL, { cache: "no-store" });
      if (!response.ok) throw new Error(`Worker fetch failed: ${response.status}`);
      const source = await response.text();
      const embeddedSource = document.getElementById("cpu-worker-source");
      if (embeddedSource && source.trim() !== embeddedSource.textContent.trim()) {
        state.workerSource = `${WORKER_URL} (fallback mismatch)`;
      } else {
        state.workerSource = WORKER_URL;
      }
      const blob = new Blob([source], { type: "text/javascript" });
      state.workerBlobUrl = URL.createObjectURL(blob);
      return state.workerBlobUrl;
    } catch (error) {
      state.workerSource = "embedded fallback";
    }

    const embeddedSource = document.getElementById("cpu-worker-source");
    if (!embeddedSource) {
      throw new Error("No worker source available.");
    }

    const blob = new Blob([embeddedSource.textContent.trim()], { type: "text/javascript" });
    state.workerBlobUrl = URL.createObjectURL(blob);
    return state.workerBlobUrl;
  }

  function rejectPendingForWorker(index, message) {
    const suffix = `:${index}`;
    for (const [key, pending] of state.pending) {
      if (key.endsWith(suffix)) {
        state.pending.delete(key);
        pending.reject(new Error(message));
      }
    }
  }

  function createWorker(index, workerUrl) {
    const worker = new Worker(workerUrl);

    worker.onmessage = (event) => {
      const message = event.data || {};

      if (message.type === "ready") {
        const pending = state.pending.get(`ready:${message.workerIndex}`);
        if (pending) {
          state.pending.delete(`ready:${message.workerIndex}`);
          pending.resolve(message);
        }
        return;
      }

      if (message.type === "result") {
        const pending = state.pending.get(`job:${message.jobId}:${message.workerIndex}`);
        if (pending) {
          state.pending.delete(`job:${message.jobId}:${message.workerIndex}`);
          pending.resolve(message);
        }
        return;
      }

      if (message.type === "error") {
        const key = message.jobId
          ? `job:${message.jobId}:${message.workerIndex}`
          : `ready:${message.workerIndex}`;
        const pending = state.pending.get(key);
        if (pending) {
          state.pending.delete(key);
          pending.reject(new Error(message.message || "Worker failed."));
        }
      }
    };

    worker.onerror = (error) => {
      if (error && typeof error.preventDefault === "function") error.preventDefault();
      rejectPendingForWorker(index, error.message || "Worker crashed unexpectedly.");
    };

    worker.onmessageerror = () => {
      rejectPendingForWorker(index, "Worker sent an unreadable message.");
    };

    return worker;
  }

  async function initializeWorkers(count) {
    stopWorkers();
    const workerUrl = await getWorkerUrl();
    const readyPromises = [];

    for (let index = 0; index < count; index += 1) {
      const worker = createWorker(index, workerUrl);
      state.workers.push(worker);
      readyPromises.push(new Promise((resolve, reject) => {
        state.pending.set(`ready:${index}`, { resolve, reject });
      }));
      worker.postMessage({ type: "init", workerIndex: index });
    }

    return withTimeout(
      Promise.all(readyPromises),
      WORKER_STARTUP_TIMEOUT_MS,
      "Workers did not start in time. Check that this browser allows Web Workers, then try again."
    );
  }

  function waitForBarrierReady(view, count) {
    return new Promise((resolve) => {
      function check() {
        if (Atomics.load(view, 0) >= count) {
          resolve();
        } else {
          window.setTimeout(check, 0);
        }
      }
      check();
    });
  }

  async function runWorkerBatch(workerCount, iterationsByWorker, phaseName, options) {
    const config = options || {};
    const jobId = ++state.jobId;
    const canUseBarrier = typeof SharedArrayBuffer !== "undefined" && window.crossOriginIsolated;
    const useBarrier = config.useBarrier === false ? false : canUseBarrier;
    const barrier = useBarrier ? new SharedArrayBuffer(8) : null;
    const barrierView = barrier ? new Int32Array(barrier) : null;
    const promises = [];
    let startedAt = 0;

    for (let index = 0; index < workerCount; index += 1) {
      promises.push(new Promise((resolve, reject) => {
        state.pending.set(`job:${jobId}:${index}`, { resolve, reject });
      }));
    }

    if (!barrierView) startedAt = performance.now();

    for (let index = 0; index < workerCount; index += 1) {
      state.workers[index].postMessage({
        type: "run",
        jobId,
        workerIndex: index,
        iterations: iterationsByWorker[index],
        seed: config.seeds ? config.seeds[index] >>> 0 : (0x12345678 + jobId * 97 + index * 65537) >>> 0,
        barrier
      });
    }

    const resultsPromise = Promise.all(promises);

    if (barrierView) {
      await withTimeout(
        Promise.race([
          waitForBarrierReady(barrierView, workerCount),
          resultsPromise.then(
            () => undefined,
            (error) => { throw error; }
          )
        ]),
        WORKER_STARTUP_TIMEOUT_MS,
        "Workers did not reach the synchronized start in time."
      );
    }

    if (barrierView) {
      startedAt = performance.now();
      Atomics.store(barrierView, 1, 1);
      Atomics.notify(barrierView, 1, workerCount);
    }

    const results = await withTimeout(
      resultsPromise,
      WORKER_BATCH_TIMEOUT_MS,
      "A benchmark round took too long. The run was stopped before the page became unresponsive."
    );
    const wallMs = performance.now() - startedAt;

    return {
      phaseName,
      wallMs,
      workerMs: Math.max(...results.map((result) => result.durationMs)),
      checksum: xorChecksums(results),
      results,
      startMode: barrierView ? "Atomics barrier" : "postMessage"
    };
  }

  async function runMedianBatch(workerCount, iterationsByWorker, rounds, progressStart, progressSpan, phaseName) {
    const runs = [];
    const warmupRuns = [];
    const totalRounds = rounds + WARMUP_ROUNDS;

    for (let round = 0; round < totalRounds; round += 1) {
      if (state.cancelled) throw new Error("Benchmark cancelled.");
      const isWarmup = round < WARMUP_ROUNDS;
      const measuredRound = round - WARMUP_ROUNDS + 1;
      setStatus(isWarmup ? `${phaseName} Warm Up` : `${phaseName} ${measuredRound}/${rounds}`);
      const run = await runWorkerBatch(workerCount, iterationsByWorker, phaseName);
      if (isWarmup) {
        warmupRuns.push(run);
      } else {
        runs.push(run);
        setProgress(progressStart + progressSpan * (measuredRound / rounds));
      }
      await sleep(ROUND_SETTLE_MS);
    }

    const medianWorker = median(runs.map((run) => run.workerMs));
    const medianWall = median(runs.map((run) => run.wallMs));
    const selected = runs.reduce((closest, run) => {
      return Math.abs(run.workerMs - medianWorker) < Math.abs(closest.workerMs - medianWorker) ? run : closest;
    }, runs[0]);

    return {
      wallMs: medianWall,
      workerMs: medianWorker,
      workerVariancePercent: maxDeviationPercent(runs.map((run) => run.workerMs)),
      checksum: selected.checksum,
      startMode: selected.startMode,
      warmupRuns,
      runs
    };
  }

  async function settlePhase(label) {
    if (state.cancelled) throw new Error("Benchmark cancelled.");
    setStatus(`Settling ${label}`);
    await sleep(PHASE_SETTLE_MS);
  }

  function startVisibilityTracking() {
    state.backgroundedDuringRun = document.hidden;
    state.visibilityListener = () => {
      if (document.hidden && state.running) state.backgroundedDuringRun = true;
    };
    document.addEventListener("visibilitychange", state.visibilityListener);
  }

  function stopVisibilityTracking() {
    if (!state.visibilityListener) return;
    document.removeEventListener("visibilitychange", state.visibilityListener);
    state.visibilityListener = null;
  }

  function updateControls(isRunning) {
    state.running = isRunning;
    elements.runButton.disabled = isRunning;
    elements.stopButton.disabled = !isRunning;
    elements.workerInput.disabled = isRunning;
    elements.workloadSelect.disabled = isRunning;
  }

  async function runBenchmark() {
    if (state.running) return;

    const workerCount = clampWorkerCount(elements.workerInput.value);
    const workload = WORKLOADS[elements.workloadSelect.value] || WORKLOADS.standard;
    const baseIterations = workload.iterations;

    state.cancelled = false;
    updateControls(true);
    resetResults();
    startVisibilityTracking();

    try {
      setStatus("Preparing Workers");
      setMetric("workersUsed", workerCount.toLocaleString());
      setMetric("workerCap", getWorkerCapText(workerCount));
      setMetric("workload", `${workload.label} / ${baseIterations.toLocaleString()} iterations`);
      setMetric("visibility", document.hidden ? "Started In Background" : "Foreground");

      await initializeWorkers(workerCount);
      setProgress(0.04);

      setStatus("Verifying Kernel");
      const verification = await runWorkerBatch(
        1,
        [VERIFY_ITERATIONS],
        "Verification",
        { seeds: [VERIFY_SEED], useBarrier: false }
      );
      setMetric("verification", `0x${verification.checksum.toString(16).padStart(8, "0")}`);
      setProgress(0.08);

      await settlePhase("Single Thread Run");
      const single = await runMedianBatch(
        1,
        [baseIterations],
        workload.rounds,
        0.08,
        0.25,
        "Single Thread Run"
      );

      const fixedTotalIterations = [];
      let remaining = baseIterations;
      for (let index = 0; index < workerCount; index += 1) {
        const share = Math.floor(baseIterations / workerCount);
        const iterations = index === workerCount - 1 ? remaining : share;
        fixedTotalIterations.push(iterations);
        remaining -= iterations;
      }

      await settlePhase("Fixed Work Run");
      const fixed = await runMedianBatch(
        workerCount,
        fixedTotalIterations,
        workload.rounds,
        0.33,
        0.25,
        "Fixed Work Multi Thread Run"
      );

      await settlePhase("Throughput Run");
      const throughputIterations = Array.from({ length: workerCount }, () => baseIterations);
      const multi = await runMedianBatch(
        workerCount,
        throughputIterations,
        workload.rounds,
        0.58,
        0.38,
        "Throughput Multi Thread Run"
      );

      const singleScore = scoreFor(baseIterations, single.workerMs);
      const multiScore = scoreFor(baseIterations * workerCount, multi.workerMs);
      const scaling = multiScore / singleScore;
      const efficiency = scaling / workerCount;
      const fixedSpeedup = single.workerMs / fixed.workerMs;
      const scoreNoise = getScoreNoise(single, multi, fixed);
      const scoreDisplay = getScoreDisplay(singleScore, multiScore, scaling, fixedSpeedup, scoreNoise);
      const checksum = verification.checksum;

      renderScoreDisplay(scoreDisplay);
      setMetric("singleTime", formatMs(single.workerMs));
      setMetric("multiWall", formatMs(multi.workerMs));
      setMetric("fixedWall", formatMs(fixed.workerMs));
      setMetric("startMode", multi.startMode);
      setMetric("visibility", state.backgroundedDuringRun ? "Backgrounded During Run" : "Foreground");
      setMetric("workerSource", state.workerSource);
      renderRunDetails({
        workerCount,
        workload,
        baseIterations,
        verification,
        single,
        fixed,
        multi,
        startMode: multi.startMode,
        workerSource: state.workerSource,
        workerCap: getWorkerCapText(workerCount),
        backgroundedDuringRun: state.backgroundedDuringRun,
        scaling,
        efficiency,
        fixedSpeedup,
        scoreNoise,
        checksum
      });
      setProgress(1);
      setStatus("Complete");
    } catch (error) {
      if (state.cancelled) {
        setStatus("Cancelled");
      } else {
        setStatus(error && error.message ? error.message : "Benchmark Failed");
      }
    } finally {
      stopVisibilityTracking();
      stopWorkers();
      updateControls(false);
    }
  }

  function stopBenchmark() {
    if (!state.running) return;
    state.cancelled = true;
    setStatus("Stopping");
    stopWorkers(new Error("Benchmark cancelled."));
    updateControls(false);
  }

  function init() {
    elements.status = $("status");
    elements.progressBar = $("progress-bar");
    elements.runButton = $("run-benchmark");
    elements.stopButton = $("stop-benchmark");
    elements.workerInput = $("worker-count");
    elements.workloadSelect = $("workload-select");
    elements.singleScore = $("single-score");
    elements.multiScore = $("multi-score");
    elements.scaleScore = $("scale-score");
    elements.fixedSpeedupScore = $("fixed-speedup-score");
    elements.singleNoise = $("single-noise");
    elements.multiNoise = $("multi-noise");
    elements.scaleNoise = $("scale-noise");
    elements.fixedNoise = $("fixed-noise");
    elements.detailsContent = $("details-content");
    elements.metrics = {
      singleTime: $("single-time"),
      multiWall: $("multi-wall"),
      fixedWall: $("fixed-wall"),
      workersUsed: $("workers-used"),
      workerCap: $("worker-cap"),
      workload: $("workload-used"),
      startMode: $("start-mode"),
      visibility: $("visibility-state"),
      verification: $("verification-checksum"),
      workerSource: $("worker-source")
    };

    elements.workerInput.value = String(getHardwareConcurrency());
    elements.workerInput.max = String(MAX_WORKERS);
    elements.workerInput.title = getWorkerCapText(getHardwareConcurrency());
    elements.runButton.addEventListener("click", runBenchmark);
    elements.stopButton.addEventListener("click", stopBenchmark);
    resetResults();
    setStatus("Ready");
  }

  if (typeof window !== "undefined" && window.__CPU_BENCHMARK_EXPOSE_TESTS__) {
    window.__cpuBenchmarkTest = {
      combineVariance,
      formatNoise,
      getScoreDisplay,
      getScoreNoise,
      getWorkerSourceLabel: () => state.workerSource,
      getWorkerUrl,
      maxDeviationPercent,
      renderScoreDisplay,
      resetWorkerUrl: () => {
        state.workerBlobUrl = null;
        state.workerSource = "unknown";
      }
    };
  }

  document.addEventListener("DOMContentLoaded", init);
})();
