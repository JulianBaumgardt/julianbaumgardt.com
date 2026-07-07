(function() {
  "use strict";

  let runBenchmark = null;

  function encodeU32(value) {
    const bytes = [];
    let n = value >>> 0;
    do {
      let byte = n & 0x7f;
      n >>>= 7;
      if (n !== 0) byte |= 0x80;
      bytes.push(byte);
    } while (n !== 0);
    return bytes;
  }

  function encodeI32(value) {
    const bytes = [];
    let n = value | 0;
    let more = true;
    while (more) {
      let byte = n & 0x7f;
      n >>= 7;
      const signBit = byte & 0x40;
      if ((n === 0 && signBit === 0) || (n === -1 && signBit !== 0)) {
        more = false;
      } else {
        byte |= 0x80;
      }
      bytes.push(byte);
    }
    return bytes;
  }

  function ascii(value) {
    return Array.from(value, (char) => char.charCodeAt(0));
  }

  function section(id, data) {
    return [id, ...encodeU32(data.length), ...data];
  }

  function opConst(value) {
    return [0x41, ...encodeI32(value)];
  }

  function buildKernelBytes() {
    const typeSection = [
      0x01,
      0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7f
    ];

    const functionSection = [0x01, 0x00];
    const exportName = ascii("run_benchmark");
    const exportSection = [
      0x01,
      exportName.length, ...exportName,
      0x00, 0x00
    ];

    const instructions = [
      0x20, 0x01, ...opConst(0x9e3779b9), 0x73, 0x21, 0x02,
      0x20, 0x01, ...opConst(0x85ebca6b), 0x73, 0x21, 0x03,
      0x20, 0x01, ...opConst(0xc2b2ae35), 0x73, 0x21, 0x04,
      0x20, 0x01, ...opConst(0x27d4eb2f), 0x73, 0x21, 0x05,
      ...opConst(0), 0x21, 0x06,

      0x02, 0x40,
      0x03, 0x40,
      0x20, 0x06, 0x20, 0x00, 0x4f, 0x0d, 0x01,

      0x20, 0x02,
      ...opConst(1664525),
      0x6c,
      0x20, 0x06,
      0x6a,
      ...opConst(1013904223),
      0x6a,
      ...opConst(13),
      0x77,
      0x21, 0x02,

      0x20, 0x03,
      0x20, 0x02,
      0x20, 0x05,
      0x6a,
      0x73,
      ...opConst(17),
      0x77,
      0x20, 0x06,
      0x6a,
      0x21, 0x03,

      0x20, 0x04,
      0x20, 0x03,
      0x20, 0x06,
      0x73,
      0x6a,
      ...opConst(0x85ebca6b),
      0x6c,
      0x21, 0x04,

      0x20, 0x05,
      0x20, 0x04,
      0x20, 0x02,
      ...opConst(31),
      0x71,
      0x77,
      0x73,
      0x21, 0x05,

      0x20, 0x06,
      ...opConst(1),
      0x6a,
      0x21, 0x06,
      0x0c, 0x00,
      0x0b,
      0x0b,

      0x20, 0x02,
      0x20, 0x03,
      0x73,
      0x20, 0x04,
      0x73,
      0x20, 0x05,
      0x73,
      0x0b
    ];

    const functionBody = [
      0x01, 0x05, 0x7f,
      ...instructions
    ];

    const codeSection = [
      0x01,
      ...encodeU32(functionBody.length),
      ...functionBody
    ];

    return new Uint8Array([
      0x00, 0x61, 0x73, 0x6d,
      0x01, 0x00, 0x00, 0x00,
      ...section(1, typeSection),
      ...section(3, functionSection),
      ...section(7, exportSection),
      ...section(10, codeSection)
    ]);
  }

  async function initKernel() {
    const module = await WebAssembly.compile(buildKernelBytes());
    const instance = await WebAssembly.instantiate(module, {});
    runBenchmark = instance.exports.run_benchmark;

    let check = 0;
    for (let i = 0; i < 4; i += 1) {
      check ^= runBenchmark(250000, 0x12345678 + i);
    }
    return check >>> 0;
  }

  function waitForBarrier(buffer) {
    if (!buffer) return;
    const barrier = new Int32Array(buffer);
    Atomics.add(barrier, 0, 1);
    Atomics.wait(barrier, 1, 0);
  }

  function runJob(message) {
    if (!runBenchmark) {
      throw new Error("Benchmark kernel was not initialized.");
    }

    waitForBarrier(message.barrier || null);

    const startedAt = performance.now();
    const checksum = runBenchmark(message.iterations >>> 0, message.seed >>> 0);
    const durationMs = performance.now() - startedAt;

    self.postMessage({
      type: "result",
      jobId: message.jobId,
      workerIndex: message.workerIndex,
      durationMs,
      checksum: checksum >>> 0
    });
  }

  self.onmessage = async (event) => {
    const message = event.data || {};

    try {
      if (message.type === "init") {
        const warmupChecksum = await initKernel();
        self.postMessage({
          type: "ready",
          workerIndex: message.workerIndex,
          warmupChecksum,
          hasSharedArrayBuffer: typeof SharedArrayBuffer !== "undefined"
        });
        return;
      }

      if (message.type === "run") {
        runJob(message);
      }
    } catch (error) {
      self.postMessage({
        type: "error",
        jobId: message.jobId || null,
        workerIndex: message.workerIndex,
        message: error && error.message ? error.message : String(error)
      });
    }
  };
})();
