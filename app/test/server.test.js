import { test } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createApp } from '../src/server.js';

async function fixture(t) {
  const app = createApp({ environment: 'test', cloud: 'aws', version: 'abc123', logger: () => {} });
  app.server.listen(0, '127.0.0.1');
  await once(app.server, 'listening');
  t.after(() => new Promise(resolve => { app.server.close(resolve); app.server.closeAllConnections(); }));
  return { ...app, request: (path, init) => fetch(`http://127.0.0.1:${app.server.address().port}${path}`, init) };
}

test('exposes the deployed version and environment', async t => {
  const { request } = await fixture(t);
  const response = await request('/api/info');
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { service: 'multicloud-demo', environment: 'test', cloud: 'aws', version: 'abc123' });
});

test('readiness fails while draining, but liveness remains healthy', async t => {
  const { request, markUnready } = await fixture(t);
  assert.equal((await request('/readyz')).status, 200);
  markUnready();
  assert.equal((await request('/readyz')).status, 503);
  assert.equal((await request('/healthz')).status, 200);
});

test('rejects writes and unknown routes, and supports HEAD without a body', async t => {
  const { request } = await fixture(t);
  assert.equal((await request('/missing')).status, 404);
  const post = await request('/', { method: 'POST' });
  assert.equal(post.status, 405);
  assert.equal(post.headers.get('allow'), 'GET, HEAD');
  const head = await request('/', { method: 'HEAD' });
  assert.equal(head.status, 200);
  assert.equal(await head.text(), '');
});

test('exports bounded counters and cumulative histogram buckets without counting probes', async t => {
  const { request } = await fixture(t);
  await request('/');
  await request('/healthz');
  await request('/readyz');
  for (let i = 0; i < 3; i++) await request(`/unknown-${i}?secret=not-a-label`);
  const response = await request('/metrics');
  assert.match(response.headers.get('content-type'), /version=0.0.4/);
  const metrics = await response.text();
  assert.match(metrics, /app_http_requests_total\{method="GET",route="\/",status="200"\} 1/);
  assert.match(metrics, /route="unmatched",status="404"\} 3/);
  assert.doesNotMatch(metrics, /unknown-|secret|route="\/healthz"|route="\/readyz"|route="\/metrics"/);
  const buckets = metrics.split('\n').filter(line => line.startsWith('app_http_request_duration_seconds_bucket{') && line.includes('route="/"'));
  const counts = buckets.map(line => Number(line.split(' ').at(-1)));
  assert.equal(counts.at(-1), 1);
  assert.ok(counts.every((count, i) => i === 0 || count >= counts[i - 1]));
  assert.match(metrics, /process_resident_memory_bytes [1-9][0-9]*/);
});
