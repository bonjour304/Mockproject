// Test cho stage Test cua Jenkins: goi /api/health ma khong can DB
const test = require('node:test');
const assert = require('node:assert');
const { app, pool } = require('../src/app');

test('GET /api/health tra ve ok', async () => {
  const server = app.listen(0);
  const { port } = server.address();
  const res = await fetch(`http://127.0.0.1:${port}/api/health`);
  assert.strictEqual(res.status, 200);
  assert.deepStrictEqual(await res.json(), { status: 'ok' });
  server.close();
  await pool.end();
});
