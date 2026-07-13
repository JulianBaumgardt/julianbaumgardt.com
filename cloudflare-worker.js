const MAX_DOWNLOAD_BYTES = 32 * 1024 * 1024;
const DEFAULT_DOWNLOAD_BYTES = 1024 * 1024;
const CHUNK_BYTES = 256 * 1024;
const PRIMARY_ORIGIN = "https://julianbaumgardt.com";
const ALLOWED_ORIGINS = new Set([PRIMARY_ORIGIN, "https://www.julianbaumgardt.com"]);
const headers = {
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Cache-Control": "no-store, no-cache, must-revalidate, proxy-revalidate",
  "CDN-Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff"
};

function responseHeaders(request, extra) {
  const requestOrigin = request.headers.get("Origin");
  const allowOrigin = ALLOWED_ORIGINS.has(requestOrigin) ? requestOrigin : PRIMARY_ORIGIN;
  return new Headers({
    ...headers,
    "Access-Control-Allow-Origin": allowOrigin,
    "Timing-Allow-Origin": allowOrigin,
    "Vary": "Origin",
    ...extra
  });
}

function isAllowedRequest(request) {
  const origin = request.headers.get("Origin");
  return !origin || ALLOWED_ORIGINS.has(origin);
}

function rateLimitKey(request, scope) {
  const clientIp = request.headers.get("CF-Connecting-IP") || "unknown";
  return `${scope}:${clientIp}`;
}

function rateLimitedResponse(request) {
  return new Response("Rate limit exceeded", {
    status: 429,
    headers: responseHeaders(request, { "Content-Type": "text/plain; charset=utf-8", "Retry-After": "60" })
  });
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

async function handleDns(request) {
  const nonce = crypto.randomUUID().replace(/-/g, "");
  const url = `https://cloudflare-dns.com/dns-query?name=${nonce}.invalid&type=A`;
  const started = performance.now();
  const upstream = await fetch(url, { headers: { Accept: "application/dns-json" }, cf: { cacheTtl: 0, cacheEverything: false } });
  await upstream.arrayBuffer();
  const resolverMs = performance.now() - started;
  return Response.json({ resolverMs, scope: "Cloudflare edge resolver" }, { headers: responseHeaders(request, { "Content-Type": "application/json; charset=utf-8" }) });
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: responseHeaders(request) });
    if (request.method !== "GET") return new Response("Method not allowed", { status: 405, headers: responseHeaders(request) });
    if (!isAllowedRequest(request)) return new Response("Forbidden", { status: 403, headers: responseHeaders(request) });

    const requestLimit = await env.REQUEST_LIMITER.limit({ key: rateLimitKey(request, "request") });
    if (!requestLimit.success) return rateLimitedResponse(request);

    const url = new URL(request.url);
    if (url.pathname === "/network-test/ping") {
      return new Response("ok", { headers: responseHeaders(request, { "Content-Type": "text/plain; charset=utf-8", "Server-Timing": "edge;dur=0" }) });
    }

    if (url.pathname === "/network-test/download") {
      const downloadLimit = await env.DOWNLOAD_LIMITER.limit({ key: rateLimitKey(request, "download") });
      if (!downloadLimit.success) return rateLimitedResponse(request);
      const rawBytes = url.searchParams.get("bytes");
      const requested = rawBytes === null ? DEFAULT_DOWNLOAD_BYTES : Number.parseInt(rawBytes, 10);
      const totalBytes = Math.max(64 * 1024, Math.min(MAX_DOWNLOAD_BYTES, Number.isFinite(requested) ? requested : DEFAULT_DOWNLOAD_BYTES));
      return new Response(createDownloadStream(totalBytes), {
        headers: responseHeaders(request, { "Content-Type": "application/octet-stream", "Content-Length": String(totalBytes), "Content-Encoding": "identity" })
      });
    }

    if (url.pathname === "/network-test/dns") {
      try { return await handleDns(request); }
      catch (_) { return new Response("DNS timing unavailable", { status: 503, headers: responseHeaders(request) }); }
    }

    return new Response("Not found", { status: 404, headers: responseHeaders(request) });
  }
};
