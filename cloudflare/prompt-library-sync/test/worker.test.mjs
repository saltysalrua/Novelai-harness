import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { handleRequest } from '../src/worker.js';

const schemaSql = fs.readFileSync(
  path.resolve(import.meta.dirname, '../schema.sql'),
  'utf8',
);

function createD1Mock(sql = schemaSql) {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec(sql);

  class BoundStmt {
    constructor(sql, params) {
      this.sql = sql;
      this.params = params;
    }

    async first() {
      const stmt = sqlite.prepare(this.sql);
      const row = stmt.get(...this.params);
      return row ?? null;
    }

    async all() {
      const stmt = sqlite.prepare(this.sql);
      const results = stmt.all(...this.params);
      return { results };
    }

    async run() {
      const stmt = sqlite.prepare(this.sql);
      const info = stmt.run(...this.params);
      return { success: true, meta: info };
    }
  }

  return {
    prepare(sql) {
      return {
        bind(...params) {
          return new BoundStmt(sql, params);
        },
        first() {
          return new BoundStmt(sql, []).first();
        },
        all() {
          return new BoundStmt(sql, []).all();
        },
        run() {
          return new BoundStmt(sql, []).run();
        },
      };
    },
    async batch(statements) {
      const results = [];
      sqlite.exec('BEGIN');
      try {
        for (const s of statements) {
          results.push(await s.run());
        }
        sqlite.exec('COMMIT');
      } catch (err) {
        sqlite.exec('ROLLBACK');
        throw err;
      }
      return results;
    },
  };
}

async function sha256Hex(bytes) {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

const TEST_TOKEN = 'unit-test-sync-token-value';

function makeEnv(db) {
  return {
    DB: db,
    SYNC_TOKEN: TEST_TOKEN,
  };
}

function authedRequest(urlPath, init = {}) {
  const headers = new Headers(init.headers || {});
  headers.set('Authorization', `Bearer ${TEST_TOKEN}`);
  return new Request(`https://sync.example.com${urlPath}`, {
    ...init,
    headers,
  });
}

test('rejects unauthenticated requests and missing server token', async () => {
  const db = createD1Mock();
  const resNoConfig = await handleRequest(
    new Request('https://sync.example.com/api/health'),
    { DB: db, SYNC_TOKEN: '' },
  );
  assert.equal(resNoConfig.status, 500);

  const resUnauth = await handleRequest(
    new Request('https://sync.example.com/api/health'),
    makeEnv(db),
  );
  assert.equal(resUnauth.status, 401);

  const resBadToken = await handleRequest(
    new Request('https://sync.example.com/api/health', {
      headers: { Authorization: 'Bearer wrong-token' },
    }),
    makeEnv(db),
  );
  assert.equal(resBadToken.status, 401);
});

test('health, push merge, timestamp guard, tombstone and replace mode', async () => {
  const env = makeEnv(createD1Mock());

  const health0 = await (await handleRequest(authedRequest('/api/health'), env)).json();
  assert.equal(health0.ok, true);
  assert.equal(health0.activeEntries, 0);
  assert.equal(health0.revision, 0);

  // Push two entries
  const pushRes = await handleRequest(
    authedRequest('/api/sync/push', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        namespace: 'default',
        mode: 'merge',
        entries: [
          {
            id: 'c1',
            title: 'Miku',
            category: '角色',
            prompt: '1girl, hatsune miku',
            negativePrompt: 'bad hands',
            tags: ['vocaloid'],
            isFavorite: true,
            isBuiltin: false,
            createdAt: '2026-11-18T10:00:00.000Z',
            updatedAt: '2026-11-18T10:00:00.000Z',
          },
          {
            id: 'c2',
            title: 'Watercolor',
            category: '风格',
            prompt: '',
            prefixPrompt: 'watercolor style',
            suffixPrompt: 'very aesthetic',
            negativePrompt: '3d, photorealistic',
            tags: [],
            createdAt: '2026-11-18T10:00:00.000Z',
            updatedAt: '2026-11-18T10:00:00.000Z',
          },
          {
            id: 'c3',
            title: 'Kimono',
            category: '服装',
            prompt: 'kimono',
            prefixPrompt: 'ignored prefix',
            suffixPrompt: 'ignored suffix',
            negativePrompt: 'ignored for non-char-or-style',
            tags: [],
            createdAt: '2026-11-18T10:00:00.000Z',
            updatedAt: '2026-11-18T10:00:00.000Z',
          },
        ],
      }),
    }),
    env,
  );
  assert.equal(pushRes.status, 200);
  const pushJson = await pushRes.json();
  assert.equal(pushJson.revision, 1);
  assert.equal(pushJson.appliedCount, 3);

  // Stale merge update must NOT overwrite newer server entry
  const staleRes = await handleRequest(
    authedRequest('/api/sync/push', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        namespace: 'default',
        mode: 'merge',
        entries: [
          {
            id: 'c1',
            title: 'Old Miku',
            category: '角色',
            prompt: 'stale prompt',
            createdAt: '2026-11-18T09:00:00.000Z',
            updatedAt: '2026-11-18T09:00:00.000Z',
          },
        ],
      }),
    }),
    env,
  );
  const staleJson = await staleRes.json();
  assert.equal(staleJson.appliedCount, 0);

  const syncAfterStale = await (await handleRequest(authedRequest('/api/sync'), env)).json();
  assert.equal(syncAfterStale.entries.find((e) => e.id === 'c1').title, 'Miku');
  const c2Synced = syncAfterStale.entries.find((e) => e.id === 'c2');
  assert.equal(c2Synced.prefixPrompt, 'watercolor style');
  assert.equal(c2Synced.suffixPrompt, 'very aesthetic');
  assert.equal(c2Synced.negativePrompt, '3d, photorealistic');
  const c3Synced = syncAfterStale.entries.find((e) => e.id === 'c3');
  assert.equal(c3Synced.prefixPrompt, '');
  assert.equal(c3Synced.suffixPrompt, '');
  assert.equal(c3Synced.negativePrompt, '');

  // Replace mode marks missing active entry as tombstone
  const replaceRes = await handleRequest(
    authedRequest('/api/sync/push', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        namespace: 'default',
        mode: 'replace',
        entries: [
          {
            id: 'c1',
            title: 'Miku Replaced',
            category: '角色',
            prompt: '1girl, hatsune miku, v5',
            createdAt: '2026-11-18T10:00:00.000Z',
            updatedAt: '2026-11-18T11:00:00.000Z',
          },
        ],
      }),
    }),
    env,
  );
  assert.equal(replaceRes.status, 200);

  const syncAfterReplace = await (await handleRequest(authedRequest('/api/sync'), env)).json();
  const c1 = syncAfterReplace.entries.find((e) => e.id === 'c1');
  const c2 = syncAfterReplace.entries.find((e) => e.id === 'c2');
  assert.equal(c1.title, 'Miku Replaced');
  assert.equal(c1.deletedAt, null);
  assert.ok(c2.deletedAt);
});

test('chunked image upload, deduplication, download, and GC', async () => {
  const env = makeEnv(createD1Mock());

  // Build > 256 KiB synthetic PNG payload (triggers multi-chunk D1 storage!)
  const payload = new Uint8Array(300 * 1024);
  payload.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], 0);
  for (let i = 8; i < payload.length; i++) {
    payload[i] = i % 251;
  }
  const hash = await sha256Hex(payload);

  // Check missing
  const check1 = await (
    await handleRequest(
      authedRequest('/api/images/check', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ hashes: [hash] }),
      }),
      env,
    )
  ).json();
  assert.deepEqual(check1.missing, [hash]);
  assert.deepEqual(check1.existing, []);

  // Reject hash mismatch
  const mismatch = await handleRequest(
    authedRequest(`/api/images/${'0'.repeat(64)}`, {
      method: 'PUT',
      body: payload,
    }),
    env,
  );
  assert.equal(mismatch.status, 400);

  // Upload valid chunked image
  const putRes = await handleRequest(
    authedRequest(`/api/images/${hash}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'image/png', 'X-Image-Ext': 'png' },
      body: payload,
    }),
    env,
  );
  assert.equal(putRes.status, 200);
  const putJson = await putRes.json();
  assert.equal(putJson.chunkCount, 2);
  assert.equal(putJson.deduplicated, false);

  // Deduplicated second upload
  const putDup = await (
    await handleRequest(
      authedRequest(`/api/images/${hash}`, {
        method: 'PUT',
        body: payload,
      }),
      env,
    )
  ).json();
  assert.equal(putDup.deduplicated, true);

  // Download and verify exact bytes
  const getRes = await handleRequest(authedRequest(`/api/images/${hash}`), env);
  assert.equal(getRes.status, 200);
  assert.equal(getRes.headers.get('Content-Type'), 'image/png');
  const downloaded = new Uint8Array(await getRes.arrayBuffer());
  assert.equal(downloaded.length, payload.length);
  assert.deepEqual(downloaded, payload);

  // GC deletes unreferenced image
  const gcRes = await (
    await handleRequest(authedRequest('/api/images/gc', { method: 'POST' }), env)
  ).json();
  assert.equal(gcRes.deletedImages, 1);

  const afterGc = await handleRequest(authedRequest(`/api/images/${hash}`), env);
  assert.equal(afterGc.status, 404);
});

test('auto-migrates legacy sync_entries table missing style affix columns', async () => {
  const legacySchema = schemaSql
    .replace(/\s*prefix_prompt TEXT NOT NULL DEFAULT '',?\n/, '\n')
    .replace(/\s*suffix_prompt TEXT NOT NULL DEFAULT '',?\n/, '\n');
  const env = makeEnv(createD1Mock(legacySchema));

  const pushRes = await handleRequest(
    authedRequest('/api/sync/push', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        namespace: 'default',
        mode: 'merge',
        entries: [
          {
            id: 'legacy_style_1',
            title: 'Legacy Style',
            category: '风格',
            prompt: '',
            prefixPrompt: 'artist:legacy',
            suffixPrompt: 'best quality',
            negativePrompt: 'blurry',
            createdAt: '2026-11-18T10:00:00.000Z',
            updatedAt: '2026-11-18T10:00:00.000Z',
          },
        ],
      }),
    }),
    env,
  );
  assert.equal(pushRes.status, 200);

  const syncJson = await (await handleRequest(authedRequest('/api/sync'), env)).json();
  assert.equal(syncJson.entries.length, 1);
  assert.equal(syncJson.entries[0].prefixPrompt, 'artist:legacy');
  assert.equal(syncJson.entries[0].suffixPrompt, 'best quality');
  assert.equal(syncJson.entries[0].negativePrompt, 'blurry');
});

test('syncs preciseReferences & vibeReferences (incl. reference-only entries), migrates legacy schema, and protects images in GC', async () => {
  const legacySchema = schemaSql
    .replace(/\s*references_json TEXT NOT NULL DEFAULT '\[\]',?\n/, '\n')
    .replace(/\s*vibes_json TEXT NOT NULL DEFAULT '\[\]',?\n/, '\n');
  const env = makeEnv(createD1Mock(legacySchema));

  const refBytes = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4]);
  const vibeBytes = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 5, 6, 7, 8]);
  const orphanBytes = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 9, 9, 9, 9]);
  const refHash = await sha256Hex(refBytes);
  const vibeHash = await sha256Hex(vibeBytes);
  const orphanHash = await sha256Hex(orphanBytes);

  for (const [h, b] of [
    [refHash, refBytes],
    [vibeHash, vibeBytes],
    [orphanHash, orphanBytes],
  ]) {
    const put = await handleRequest(
      authedRequest(`/api/images/${h}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'image/png', 'X-Image-Ext': 'png' },
        body: b,
      }),
      env,
    );
    assert.equal(put.status, 200);
  }

  // Push a reference-only entry (empty prompt!) carrying both Precise Ref & Vibe with cached encoding
  const pushRes = await handleRequest(
    authedRequest('/api/sync/push', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        namespace: 'default',
        mode: 'merge',
        entries: [
          {
            id: 'ref_only_1',
            title: 'Inori Reference Sheet',
            category: '角色',
            prompt: '',
            preciseReferences: [
              {
                id: 'p1',
                imageHash: refHash,
                imageExt: 'png',
                fileName: 'inori_sheet.png',
                type: 'character',
                preferSameOutfit: true,
                strength: 1.5,
                fidelity: 1.0,
                informationExtracted: 1.0,
                enabled: true,
              },
            ],
            vibeReferences: [
              {
                id: 'v1',
                displayName: 'Soft Pastel Vibe',
                sourceType: 'naiv4vibe',
                rawImageHash: vibeHash,
                rawImageExt: 'png',
                encodingsByModel: { 'nai-diffusion-4-5-full': 'BASE64_ENC_VECTOR' },
                encodedInfoExtractedByModel: { 'nai-diffusion-4-5-full': 0.85 },
                strength: 0.7,
                informationExtracted: 0.85,
                enabled: true,
              },
            ],
            createdAt: '2026-11-25T10:00:00.000Z',
            updatedAt: '2026-11-25T10:00:00.000Z',
          },
        ],
      }),
    }),
    env,
  );
  assert.equal(pushRes.status, 200);

  const syncJson = await (await handleRequest(authedRequest('/api/sync'), env)).json();
  assert.equal(syncJson.entries.length, 1);
  const synced = syncJson.entries[0];
  assert.equal(synced.preciseReferences.length, 1);
  assert.equal(synced.preciseReferences[0].imageHash, refHash);
  assert.equal(synced.preciseReferences[0].preferSameOutfit, true);
  assert.equal(synced.preciseReferences[0].strength, 1.5);
  assert.equal(synced.vibeReferences.length, 1);
  assert.equal(synced.vibeReferences[0].rawImageHash, vibeHash);
  assert.equal(
    synced.vibeReferences[0].encodingsByModel['nai-diffusion-4-5-full'],
    'BASE64_ENC_VECTOR',
  );

  // GC must delete ONLY orphanHash and keep refHash & vibeHash alive
  const gcJson = await (
    await handleRequest(authedRequest('/api/images/gc', { method: 'POST' }), env)
  ).json();
  assert.equal(gcJson.deletedImages, 1);
  assert.equal((await handleRequest(authedRequest(`/api/images/${refHash}`), env)).status, 200);
  assert.equal((await handleRequest(authedRequest(`/api/images/${vibeHash}`), env)).status, 200);
  assert.equal((await handleRequest(authedRequest(`/api/images/${orphanHash}`), env)).status, 404);
});
