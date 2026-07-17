(function() {
  "use strict";

  const PROFILES = {
    light: { label: "Light", rounds: 2, downloadRounds: 1, probes: 6, downloads: 2, bytesPerDownload: 16 * 1024 * 1024, estimatedMb: 32 },
    standard: { label: "Standard", rounds: 3, downloadRounds: 2, probes: 8, downloads: 2, bytesPerDownload: 32 * 1024 * 1024, estimatedMb: 128 },
    thorough: { label: "Thorough", rounds: 5, downloadRounds: 3, probes: 10, downloads: 3, bytesPerDownload: 32 * 1024 * 1024, estimatedMb: 288 }
  };

  const PROBE_TIMEOUT_MS = 4000;
  const DOWNLOAD_TIMEOUT_MS = 120000;
  const DOWNLOAD_RAMP_BYTES = 512 * 1024;
  const state = { running: false, cancelled: false, controllers: new Set(), backgrounded: false, visibilityHandler: null };
  const elements = {};

  function $(id) { return document.getElementById(id); }
  function median(values) {
    const clean = values.filter(Number.isFinite).slice().sort((a, b) => a - b);
    if (!clean.length) return NaN;
    const middle = Math.floor(clean.length / 2);
    return clean.length % 2 ? clean[middle] : (clean[middle - 1] + clean[middle]) / 2;
  }

  function percentile(values, fraction) {
    const clean = values.filter(Number.isFinite).slice().sort((a, b) => a - b);
    if (!clean.length) return NaN;
    const index = (clean.length - 1) * fraction;
    const lower = Math.floor(index);
    const upper = Math.ceil(index);
    if (lower === upper) return clean[lower];
    return clean[lower] + (clean[upper] - clean[lower]) * (index - lower);
  }

  function jitter(values) {
    if (values.length < 2) return 0;
    const changes = [];
    for (let i = 1; i < values.length; i += 1) changes.push(Math.abs(values[i] - values[i - 1]));
    return median(changes);
  }

  function maxDeviationPercent(values) {
    const clean = values.filter(Number.isFinite);
    const center = median(clean);
    if (!Number.isFinite(center) || center <= 0) return 0;
    return Math.max(...clean.map((value) => Math.abs(value - center))) / center * 100;
  }

  function consistencyPercent(samples) {
    const clean = samples.filter((value) => Number.isFinite(value) && value > 0);
    if (!clean.length) return NaN;
    const center = median(clean);
    const low = percentile(clean, 0.1);
    return Math.max(0, Math.min(100, low / center * 100));
  }

  function stabilityLabel(spread, loss, consistency) {
    if (loss >= 3 || spread >= 45 || consistency < 45) return "Unstable";
    if (loss >= 1 || spread >= 25 || consistency < 65) return "Variable";
    if (spread >= 12 || consistency < 82) return "Good";
    return "Excellent";
  }

  function formatMs(value, decimals) { return Number.isFinite(value) ? `${value.toFixed(decimals == null ? (value < 100 ? 1 : 0) : decimals)} ms` : "--"; }
  function formatMbps(value) { return Number.isFinite(value) ? `${value.toFixed(value < 100 ? 1 : 0)} Mbps` : "--"; }
  function formatPercent(value) { return Number.isFinite(value) ? `${value.toFixed(1)}%` : "--"; }
  function formatBytes(value) {
    if (!Number.isFinite(value) || value < 0) return "--";
    return `${(value / (1024 * 1024)).toFixed(value < 100 * 1024 * 1024 ? 1 : 0)} MiB`;
  }
  function endpoint(path) { return `/network-test/${path}`; }
  function setStatus(text) { elements.status.textContent = text; }
  function setProgress(value) {
    const clamped = Math.max(0, Math.min(1, value));
    elements.progressBar.style.transform = `scaleX(${clamped})`;
    elements.progress.setAttribute("aria-valuenow", String(Math.round(clamped * 100)));
  }
  function abortError() { return new DOMException("Test stopped.", "AbortError"); }
  function ensureActive() { if (state.cancelled) throw abortError(); }
  function endpointError(prefix, response) {
    const error = new Error(`${prefix} returned ${response.status}.`);
    error.status = response.status;
    return error;
  }

  async function timedFetch(url, timeoutMs) {
    ensureActive();
    const controller = new AbortController();
    state.controllers.add(controller);
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    const started = performance.now();
    try {
      const response = await fetch(url, { cache: "no-store", signal: controller.signal });
      if (!response.ok) throw endpointError("Endpoint", response);
      await response.arrayBuffer();
      return performance.now() - started;
    } finally {
      clearTimeout(timeout);
      state.controllers.delete(controller);
    }
  }

  async function runProbe() {
    try {
      const ms = await timedFetch(`${endpoint("ping")}?t=${Date.now()}-${Math.random()}`, PROBE_TIMEOUT_MS);
      return { ok: true, ms };
    } catch (error) {
      if (state.cancelled) throw abortError();
      if (error && error.status === 429) throw error;
      return { ok: false, ms: NaN };
    }
  }

  async function measureDns() {
    const controller = new AbortController();
    state.controllers.add(controller);
    const timeout = setTimeout(() => controller.abort(), PROBE_TIMEOUT_MS * 2);
    try {
      const response = await fetch(`${endpoint("dns")}?t=${Date.now()}-${Math.random()}`, { cache: "no-store", signal: controller.signal });
      if (!response.ok) throw endpointError("DNS endpoint", response);
      const result = await response.json();
      return Number(result.resolverMs);
    } catch (error) {
      if (state.cancelled) throw abortError();
      if (error && error.status === 429) throw error;
      return NaN;
    } finally {
      clearTimeout(timeout);
      state.controllers.delete(controller);
    }
  }

  async function readDownload(bytes, sampleSink) {
    const controller = new AbortController();
    state.controllers.add(controller);
    const timeout = setTimeout(() => controller.abort("download-timeout"), DOWNLOAD_TIMEOUT_MS);
    let received = 0;
    let measuredBytes = 0;
    let sampleBytes = 0;
    let measurementStarted = NaN;
    let sampleStarted = NaN;

    try {
      const url = `${endpoint("download")}?bytes=${bytes}&t=${Date.now()}-${Math.random()}`;
      const response = await fetch(url, { cache: "no-store", signal: controller.signal });
      if (!response.ok) throw endpointError("Download endpoint", response);
      if (!response.body) throw new Error("Download response did not contain a readable stream.");
      const reader = response.body.getReader();
      while (true) {
        ensureActive();
        const result = await reader.read();
        if (result.done) break;
        received += result.value.byteLength;
        const now = performance.now();

        if (!Number.isFinite(measurementStarted)) {
          if (received >= DOWNLOAD_RAMP_BYTES) {
            measurementStarted = now;
            sampleStarted = now;
          }
          continue;
        }

        measuredBytes += result.value.byteLength;
        sampleBytes += result.value.byteLength;
        const elapsed = now - sampleStarted;
        if (elapsed >= 250) {
          sampleSink.push((sampleBytes * 8) / (elapsed / 1000) / 1000000);
          sampleBytes = 0;
          sampleStarted = now;
        }
      }
      const ended = performance.now();
      if (!Number.isFinite(measurementStarted)) measurementStarted = ended;
      if (sampleBytes > 0 && ended - sampleStarted >= 75) sampleSink.push((sampleBytes * 8) / ((ended - sampleStarted) / 1000) / 1000000);
      const durationMs = Math.max(0.01, ended - measurementStarted);
      return {
        receivedBytes: received,
        bytes: measuredBytes,
        durationMs,
        startedAt: measurementStarted,
        endedAt: ended,
        mbps: (measuredBytes * 8) / (durationMs / 1000) / 1000000
      };
    } finally {
      clearTimeout(timeout);
      state.controllers.delete(controller);
    }
  }

  async function measureUnderLoad(profile) {
    const throughputSamples = [];
    const downloads = Array.from({ length: profile.downloads }, () => readDownload(profile.bytesPerDownload, throughputSamples));
    let finished = false;
    const completion = Promise.all(downloads).finally(() => { finished = true; });
    void completion.catch(() => {});
    const loadedProbes = [];

    await new Promise((resolve) => setTimeout(resolve, 80));
    while (!finished && loadedProbes.length < 24) {
      loadedProbes.push(await runProbe());
      if (!finished) await new Promise((resolve) => setTimeout(resolve, 80));
    }
    const downloadResults = await completion;
    if (!loadedProbes.length) loadedProbes.push(await runProbe());
    const totalBytes = downloadResults.reduce((sum, item) => sum + item.bytes, 0);
    const wallMs = Math.max(0.01, Math.max(...downloadResults.map((item) => item.endedAt)) - Math.min(...downloadResults.map((item) => item.startedAt)));
    if (throughputSamples.length < 3) throughputSamples.push(...downloadResults.map((item) => item.mbps));
    return {
      mbps: (totalBytes * 8) / (wallMs / 1000) / 1000000,
      receivedBytes: downloadResults.reduce((sum, item) => sum + item.receivedBytes, 0),
      durationMs: wallMs,
      throughputSamples,
      probes: loadedProbes
    };
  }

  async function runRound(profile, index, total, measureLoad) {
    setStatus(`Round ${index + 1} Of ${total} · Idle Latency`);
    const idleProbes = [];
    for (let i = 0; i < profile.probes; i += 1) {
      idleProbes.push(await runProbe());
      setProgress((index + (i + 1) / profile.probes * 0.35) / total);
      if (i + 1 < profile.probes) await new Promise((resolve) => setTimeout(resolve, 70));
    }

    setStatus(`Round ${index + 1} Of ${total} · Resolver`);
    const dnsMs = await measureDns();
    setProgress((index + 0.43) / total);
    let loaded = { mbps: NaN, receivedBytes: 0, durationMs: NaN, throughputSamples: [], probes: [] };
    if (measureLoad) {
      setStatus(`Round ${index + 1} Of ${total} · Download Under Load`);
      loaded = await measureUnderLoad(profile);
    }
    setProgress((index + 1) / total);

    const idleSuccess = idleProbes.filter((item) => item.ok).map((item) => item.ms);
    const loadedSuccess = loaded.probes.filter((item) => item.ok).map((item) => item.ms);
    const attempts = idleProbes.length + loaded.probes.length;
    const failures = idleProbes.concat(loaded.probes).filter((item) => !item.ok).length;
    return {
      idleMs: median(idleSuccess),
      jitterMs: jitter(idleSuccess),
      loadedMs: median(loadedSuccess),
      downloadMbps: loaded.mbps,
      downloadBytes: loaded.receivedBytes,
      downloadDurationMs: loaded.durationMs,
      downloadSamples: loaded.throughputSamples.length,
      consistency: consistencyPercent(loaded.throughputSamples),
      dnsMs,
      attempts,
      failures
    };
  }

  function aggregateRounds(rounds) {
    const idleValues = rounds.map((round) => round.idleMs);
    const loadedValues = rounds.map((round) => round.loadedMs);
    const downloadValues = rounds.map((round) => round.downloadMbps);
    const jitterValues = rounds.map((round) => round.jitterMs);
    const consistencyValues = rounds.map((round) => round.consistency);
    const attempts = rounds.reduce((sum, round) => sum + round.attempts, 0);
    const failures = rounds.reduce((sum, round) => sum + round.failures, 0);
    const result = {
      idleMs: median(idleValues),
      loadedMs: median(loadedValues),
      downloadMbps: median(downloadValues),
      jitterMs: median(jitterValues),
      consistency: median(consistencyValues),
      dnsMs: median(rounds.map((round) => round.dnsMs)),
      lossPercent: attempts ? failures / attempts * 100 : 0,
      idleSpread: maxDeviationPercent(idleValues),
      loadedSpread: maxDeviationPercent(loadedValues),
      downloadSpread: maxDeviationPercent(downloadValues),
      downloadBytes: rounds.reduce((sum, round) => sum + (Number.isFinite(round.downloadBytes) ? round.downloadBytes : 0), 0),
      downloadDurationMs: median(rounds.map((round) => round.downloadDurationMs)),
      downloadSamples: rounds.reduce((sum, round) => sum + (round.downloadSamples || 0), 0),
      rounds: rounds.length
    };
    result.penaltyMs = result.loadedMs - result.idleMs;
    result.stability = stabilityLabel(Math.max(result.idleSpread, result.downloadSpread), result.lossPercent, result.consistency);
    return result;
  }

  function measurementQuality(result, backgrounded) {
    if (backgrounded || result.lossPercent >= 3 || result.downloadSpread >= 45 || result.downloadDurationMs < 750 || result.downloadSamples < 3) return "Low";
    if (result.lossPercent > 0 || result.downloadSpread >= 25 || result.downloadDurationMs < 1500 || result.downloadSamples < 6) return "Fair";
    return "High";
  }

  function render(result, rounds, backgrounded) {
    elements.latencyScore.textContent = formatMs(result.idleMs);
    elements.downloadScore.textContent = formatMbps(result.downloadMbps);
    elements.loadedScore.textContent = formatMs(result.loadedMs);
    elements.stabilityScore.textContent = result.stability;
    elements.latencySpread.textContent = `±${result.idleSpread.toFixed(1)}% across rounds`;
    elements.downloadSpread.textContent = `±${result.downloadSpread.toFixed(1)}% across rounds`;
    elements.loadedSpread.textContent = `±${result.loadedSpread.toFixed(1)}% across rounds`;
    elements.stabilityNote.textContent = `${formatPercent(result.consistency)} download consistency`;
    elements.jitterMetric.textContent = formatMs(result.jitterMs);
    elements.lossMetric.textContent = formatPercent(result.lossPercent);
    elements.consistencyMetric.textContent = formatPercent(result.consistency);
    elements.penaltyMetric.textContent = `+${formatMs(Math.max(0, result.penaltyMs))}`;
    elements.dnsMetric.textContent = formatMs(result.dnsMs);
    elements.roundsMetric.textContent = String(result.rounds);
    elements.dataMetric.textContent = formatBytes(result.downloadBytes);
    elements.qualityMetric.textContent = measurementQuality(result, backgrounded);

    elements.detailsContent.innerHTML = `<table class="round-table"><thead><tr><th>Round</th><th>Idle</th><th>Jitter</th><th>Download</th><th>Loaded</th><th>Consistency</th><th>DNS</th><th>Failed probes</th></tr></thead><tbody>${rounds.map((round, index) => `<tr><td>${index + 1}</td><td>${formatMs(round.idleMs)}</td><td>${formatMs(round.jitterMs)}</td><td>${formatMbps(round.downloadMbps)}</td><td>${formatMs(round.loadedMs)}</td><td>${formatPercent(round.consistency)}</td><td>${formatMs(round.dnsMs)}</td><td>${round.failures} / ${round.attempts}</td></tr>`).join("")}</tbody></table>`;
  }

  function resetResults() {
    const scoreIds = ["latencyScore", "downloadScore", "loadedScore", "stabilityScore", "jitterMetric", "lossMetric", "consistencyMetric", "penaltyMetric", "dnsMetric", "roundsMetric", "dataMetric", "qualityMetric"];
    const noteIds = ["latencySpread", "downloadSpread", "loadedSpread", "stabilityNote"];
    for (const id of scoreIds) elements[id].textContent = "--";
    for (const id of noteIds) elements[id].textContent = "Not tested";
    elements.detailsContent.innerHTML = '<div class="details-empty">No completed run yet.</div>';
  }

  function updateControls(running) {
    elements.run.disabled = running;
    elements.stop.disabled = !running;
    elements.profile.disabled = running;
  }

  function stopTest() {
    if (!state.running) return;
    state.cancelled = true;
    for (const controller of state.controllers) controller.abort();
    setStatus("Stopping");
  }

  async function runTest() {
    if (state.running) return;
    state.running = true;
    state.cancelled = false;
    state.backgrounded = false;
    updateControls(true);
    resetResults();
    setProgress(0);
    const profile = PROFILES[elements.profile.value];
    const rounds = [];
    state.visibilityHandler = () => { if (document.hidden) state.backgrounded = true; };
    document.addEventListener("visibilitychange", state.visibilityHandler);

    try {
      await timedFetch(`${endpoint("ping")}?warmup=${Date.now()}`, PROBE_TIMEOUT_MS);
      for (let index = 0; index < profile.rounds; index += 1) {
        rounds.push(await runRound(profile, index, profile.rounds, index < profile.downloadRounds));
      }
      const result = aggregateRounds(rounds);
      render(result, rounds, state.backgrounded);
      const quality = measurementQuality(result, state.backgrounded);
      setStatus(state.backgrounded
        ? "Complete · Tab Was Backgrounded; Rerun For Best Accuracy"
        : `Complete · ${quality} Measurement Confidence`);
    } catch (error) {
      if (error && error.name === "AbortError" && state.cancelled) setStatus("Stopped");
      else if (error && String(error.message).includes("429")) setStatus("Rate Limit Reached · Please Wait One Minute");
      else if (error && error.name === "AbortError") setStatus("Download Timed Out · Try The Light Test Or Check Your Connection");
      else setStatus("Test Service Unavailable · Try Again Shortly");
    } finally {
      state.running = false;
      for (const controller of state.controllers) controller.abort();
      state.controllers.clear();
      if (state.visibilityHandler) document.removeEventListener("visibilitychange", state.visibilityHandler);
      state.visibilityHandler = null;
      updateControls(false);
    }
  }

  function init() {
    const ids = ["status", "progress", "progress-bar", "profile-select", "run-test", "stop-test", "latency-score", "download-score", "loaded-score", "stability-score", "latency-spread", "download-spread", "loaded-spread", "stability-note", "jitter-metric", "loss-metric", "consistency-metric", "penalty-metric", "dns-metric", "rounds-metric", "data-metric", "quality-metric", "details-content"];
    for (const id of ids) elements[id.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = $(id);
    elements.profile = $("profile-select");
    elements.run = $("run-test");
    elements.stop = $("stop-test");
    elements.run.addEventListener("click", runTest);
    elements.stop.addEventListener("click", stopTest);
  }

  if (typeof window !== "undefined" && window.__INTERNET_QUALITY_EXPOSE_TESTS__) {
    window.__internetQualityTest = { median, percentile, jitter, maxDeviationPercent, consistencyPercent, stabilityLabel, measurementQuality, aggregateRounds, profiles: PROFILES };
  }

  if (typeof document !== "undefined") document.addEventListener("DOMContentLoaded", init);
})();
