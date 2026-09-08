import http from 'node:http';
import { pathToFileURL } from 'node:url';
import { performance } from 'node:perf_hooks';

const bounds = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5];

export function createApp({ environment = 'local', cloud = 'local', version = 'dev', logger = console.log } = {}) {
  let ready = true;
  const observations = new Map();
  function metrics() {
    const lines = [
      '# HELP app_http_requests_total Completed application HTTP requests, excluding probes and scrapes.',
      '# TYPE app_http_requests_total counter',
    ];
    for (const [labels, item] of observations) lines.push(`app_http_requests_total{${labels}} ${item.count}`);
    lines.push('# HELP app_http_request_duration_seconds Application request duration.', '# TYPE app_http_request_duration_seconds histogram');
    for (const [labels, item] of observations) {
      bounds.forEach((bound, i) => lines.push(`app_http_request_duration_seconds_bucket{${labels},le="${bound}"} ${item.buckets[i]}`));
      lines.push(`app_http_request_duration_seconds_bucket{${labels},le="+Inf"} ${item.count}`,
        `app_http_request_duration_seconds_sum{${labels}} ${item.sum}`,
        `app_http_request_duration_seconds_count{${labels}} ${item.count}`);
    }
    lines.push('# HELP process_resident_memory_bytes Resident memory.', '# TYPE process_resident_memory_bytes gauge',
      `process_resident_memory_bytes ${process.memoryUsage().rss}`, '# HELP process_uptime_seconds Process uptime.',
      '# TYPE process_uptime_seconds gauge', `process_uptime_seconds ${process.uptime()}`);
    return `${lines.join('\n')}\n`;
  }
  const server = http.createServer((req, res) => {
    const start = performance.now();
    let pathname;
    try { pathname = new URL(req.url, 'http://localhost').pathname; }
    catch { res.writeHead(400).end(); return; }
    const known = ['/', '/api/info', '/healthz', '/readyz', '/metrics'].includes(pathname);
    const route = known ? pathname : 'unmatched';
    // Keep cardinality bounded even when clients send arbitrary paths or methods.
    const method = ['GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'].includes(req.method) ? req.method : 'OTHER';
    const operational = ['/healthz', '/readyz', '/metrics'].includes(route);
    res.on('finish', () => {
      const duration = (performance.now() - start) / 1000;
      if (!operational) {
        const labels = `method="${method}",route="${route}",status="${res.statusCode}"`;
        const item = observations.get(labels) ?? { count: 0, sum: 0, buckets: bounds.map(() => 0) };
        item.count += 1;
        item.sum += duration;
        bounds.forEach((bound, i) => { if (duration <= bound) item.buckets[i] += 1; });
        observations.set(labels, item);
      }
      logger(JSON.stringify({ timestamp: new Date().toISOString(), method, route, status: res.statusCode, duration_ms: Math.round(duration * 1000) }));
    });
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Cache-Control', 'no-store');
    const json = (status, body) => {
      res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(req.method === 'HEAD' ? undefined : JSON.stringify(body));
    };
    if (!['GET', 'HEAD'].includes(req.method)) {
      res.setHeader('Allow', 'GET, HEAD');
      return json(405, { error: 'Method not allowed' });
    }
    if (route === '/healthz') return json(200, { status: 'alive' });
    if (route === '/readyz') return json(ready ? 200 : 503, { status: ready ? 'ready' : 'draining' });
    if (route === '/metrics') {
      res.writeHead(200, { 'Content-Type': 'text/plain; version=0.0.4; charset=utf-8' });
      return res.end(req.method === 'HEAD' ? undefined : metrics());
    }
    if (route === '/' || route === '/api/info') return json(200, { service: 'multicloud-demo', environment, cloud, version });
    return json(404, { error: 'Not found' });
  });
  server.requestTimeout = 15_000;
  server.headersTimeout = 10_000;
  return { server, markUnready: () => { ready = false; } };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.PORT ?? 8080);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('PORT must be an integer from 1 to 65535');
  const { server, markUnready } = createApp({
    environment: process.env.APP_ENV, cloud: process.env.CLOUD_PROVIDER, version: process.env.APP_VERSION,
  });
  server.listen(port, '0.0.0.0', () => console.log(JSON.stringify({ event: 'listening', port })));
  let stopping = false;
  const shutdown = () => {
    if (stopping) return;
    stopping = true;
    markUnready();
    // Give endpoint discovery time to remove this pod, then drain existing connections.
    setTimeout(() => server.close(() => process.exit(0)), 5000).unref();
    setTimeout(() => process.exit(1), 25_000).unref();
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}
