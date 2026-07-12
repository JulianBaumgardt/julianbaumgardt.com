const MAX_DOWNLOAD_BYTES = 16 * 1024 * 1024;
const CHUNK_BYTES = 256 * 1024;
const headers = {
  "Access-Control-Allow-Origin": "https://julianbaumgardt.com",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Cache-Control": "no-store, no-cache, must-revalidate, proxy-revalidate",
  "CDN-Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Timing-Allow-Origin": "https://julianbaumgardt.com"
};

function responseHeaders(extra) {
  return new Headers({ ...headers, ...extra });
}

function isAllowedRequest(request) {
  const origin = request.headers.get("Origin");
  return !origin || origin === "https://julianbaumgardt.com" || origin === "https://www.julianbaumgardt.com";
}

function createDownloadStream(totalBytes) {
  const chunk = new Uint8Array(CHUNK_BYTES);
  let sent = 0;
  return new ReadableStream({
    pull(controller) {
      const remaining = totalBytes - sent;
      if (remaining <= 0) {
        controller.close();
        return;
      }
      const size = Math.min(remaining, chunk.byteLength);
      controller.enqueue(size === chunk.byteLength ? chunk : chunk.subarray(0, size));
      sent += size;
    }
  });
}

async function handleDns() {
  const nonce = crypto.randomUUID().replace(/-/g, "");
  const url = `https://cloudflare-dns.com/dns-query?name=${nonce}.invalid&type=A`;
  const started = performance.now();
  const upstream = await fetch(url, { headers: { Accept: "application/dns-json" }, cf: { cacheTtl: 0, cacheEverything: false } });
  await upstream.arrayBuffer();
  const resolverMs = performance.now() - started;
  return Response.json({ resolverMs, scope: "Cloudflare edge resolver" }, { headers: responseHeaders({ "Content-Type": "application/json; charset=utf-8" }) });
}

export default {
  async fetch(request) {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: responseHeaders() });
    if (request.method !== "GET") return new Response("Method not allowed", { status: 405, headers: responseHeaders() });
    if (!isAllowedRequest(request)) return new Response("Forbidden", { status: 403, headers: responseHeaders() });

    const url = new URL(request.url);
    if (url.pathname === "/network-test/ping") {
      return new Response("ok", { headers: responseHeaders({ "Content-Type": "text/plain; charset=utf-8", "Server-Timing": "edge;dur=0" }) });
    }

    if (url.pathname === "/network-test/download") {
      const requested = Number.parseInt(url.searchParams.get("bytes") || "0", 10);
      const totalBytes = Math.max(64 * 1024, Math.min(MAX_DOWNLOAD_BYTES, Number.isFinite(requested) ? requested : 1024 * 1024));
      return new Response(createDownloadStream(totalBytes), {
        headers: responseHeaders({ "Content-Type": "application/octet-stream", "Content-Length": String(totalBytes), "Content-Encoding": "identity" })
      });
    }

    if (url.pathname === "/network-test/dns") {
      try { return await handleDns(); }
      catch (_) { return new Response("DNS timing unavailable", { status: 503, headers: responseHeaders() }); }
    }

    return new Response("Not found", { status: 404, headers: responseHeaders() });
  }
};
