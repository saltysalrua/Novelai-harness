/**
 * NovelAI Harness 词库云同步 Cloudflare Worker (Free Tier + D1)
 *
 * 特性：
 * - 零绑卡免费方案：仅依赖 Cloudflare Workers + D1 SQLite (5GB 免费空间)
 * - 预览图按 SHA-256 内容寻址去重，并分块存储 (每块 256 KiB) 规避 D1 单行 1MB 限制
 * - 支持双向增量合并 (基于 id + updated_at / deleted_at 墓碑) 与强制覆盖
 * - Bearer Token 鉴权 (常量时间 SHA-256 比较，未配置 SYNC_TOKEN 时拒绝服务)
 */

const MAX_IMAGE_BYTES = 8 * 1024 * 1024; // 8 MiB
const IMAGE_CHUNK_BYTES = 256 * 1024; // 256 KiB -> Base64 ~342 KiB (< 1 MB D1 限制)
const SQL_IN_BATCH_SIZE = 50; // D1 单条 SQL 绑定参数上限 100，保守按 50 分片
const D1_BATCH_STATEMENTS = 50;

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type, X-Image-Ext',
  'Access-Control-Max-Age': '86400',
};

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      ...CORS_HEADERS,
    },
  });
}

function errorResponse(message, status = 400, code = 'BAD_REQUEST') {
  return jsonResponse({ ok: false, error: message, code }, status);
}

function isValidSha256(value) {
  return typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
}

function normalizeNamespace(raw) {
  const value = (typeof raw === 'string' ? raw : '').trim();
  if (!value) return 'default';
  if (value.length > 64 || !/^[a-zA-Z0-9._-]+$/.test(value)) {
    return null;
  }
  return value;
}

function parseTimestampMs(iso) {
  if (typeof iso !== 'string' || !iso.trim()) return null;
  const ms = Date.parse(iso);
  return Number.isFinite(ms) ? ms : null;
}

function normalizeIsoString(raw, fallbackIso) {
  const ms = parseTimestampMs(raw);
  if (ms === null) return fallbackIso;
  return new Date(ms).toISOString();
}

async function timingSafeTokenEqual(expected, actual) {
  const encoder = new TextEncoder();
  const [hashA, hashB] = await Promise.all([
    crypto.subtle.digest('SHA-256', encoder.encode(expected)),
    crypto.subtle.digest('SHA-256', encoder.encode(actual)),
  ]);
  const bytesA = new Uint8Array(hashA);
  const bytesB = new Uint8Array(hashB);
  let diff = expected.length ^ actual.length;
  for (let i = 0; i < bytesA.length; i++) {
    diff |= bytesA[i] ^ bytesB[i];
  }
  return diff === 0;
}

async function authorize(request, env) {
  const configuredToken = typeof env.SYNC_TOKEN === 'string' ? env.SYNC_TOKEN.trim() : '';
  if (!configuredToken) {
    return errorResponse(
      'Worker 未配置 SYNC_TOKEN Secret，请先执行 wrangler secret put SYNC_TOKEN',
      500,
      'SERVER_NOT_CONFIGURED',
    );
  }
  const authHeader = request.headers.get('Authorization') || '';
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    return errorResponse('缺少有效的 Bearer Token', 401, 'UNAUTHORIZED');
  }
  const incomingToken = match[1].trim();
  const ok = await timingSafeTokenEqual(configuredToken, incomingToken);
  if (!ok) {
    return errorResponse('同步密钥验证失败', 401, 'UNAUTHORIZED');
  }
  return null;
}

async function sha256Hex(buffer) {
  const digest = await crypto.subtle.digest('SHA-256', buffer);
  const bytes = new Uint8Array(digest);
  let hex = '';
  for (let i = 0; i < bytes.length; i++) {
    hex += bytes[i].toString(16).padStart(2, '0');
  }
  return hex;
}

function bytesToBase64(bytes) {
  let binary = '';
  const sliceSize = 0x8000;
  for (let i = 0; i < bytes.length; i += sliceSize) {
    const slice = bytes.subarray(i, i + sliceSize);
    binary += String.fromCharCode(...slice);
  }
  return btoa(binary);
}

function base64ToBytes(b64) {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function detectImageFormat(bytes, extHint, contentTypeHint) {
  if (
    bytes.length >= 8 &&
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47 &&
    bytes[4] === 0x0d &&
    bytes[5] === 0x0a &&
    bytes[6] === 0x1a &&
    bytes[7] === 0x0a
  ) {
    return { mimeType: 'image/png', ext: 'png' };
  }
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return { mimeType: 'image/jpeg', ext: 'jpg' };
  }
  if (
    bytes.length >= 12 &&
    bytes[0] === 0x52 &&
    bytes[1] === 0x49 &&
    bytes[2] === 0x46 &&
    bytes[3] === 0x46 &&
    bytes[8] === 0x57 &&
    bytes[9] === 0x45 &&
    bytes[10] === 0x42 &&
    bytes[11] === 0x50
  ) {
    return { mimeType: 'image/webp', ext: 'webp' };
  }
  if (bytes.length >= 4 && bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x38) {
    return { mimeType: 'image/gif', ext: 'gif' };
  }

  const cleanExt = (extHint || '').trim().toLowerCase().replace(/^\./, '');
  if (cleanExt === 'jpg' || cleanExt === 'jpeg') {
    return { mimeType: 'image/jpeg', ext: 'jpg' };
  }
  if (cleanExt === 'webp') {
    return { mimeType: 'image/webp', ext: 'webp' };
  }
  if (cleanExt === 'gif') {
    return { mimeType: 'image/gif', ext: 'gif' };
  }
  if (cleanExt === 'png') {
    return { mimeType: 'image/png', ext: 'png' };
  }

  const ct = (contentTypeHint || '').toLowerCase();
  if (ct.includes('jpeg')) return { mimeType: 'image/jpeg', ext: 'jpg' };
  if (ct.includes('webp')) return { mimeType: 'image/webp', ext: 'webp' };
  if (ct.includes('gif')) return { mimeType: 'image/gif', ext: 'gif' };
  return { mimeType: 'image/png', ext: 'png' };
}

function parseJsonArrayField(raw) {
  if (typeof raw !== 'string' || !raw.trim()) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function sanitizeOptionalHash(raw) {
  if (typeof raw !== 'string') return null;
  const clean = raw.trim().toLowerCase();
  return isValidSha256(clean) ? clean : null;
}

function sanitizeOptionalExt(raw, hasHash) {
  if (!hasHash || typeof raw !== 'string') return null;
  const clean = raw.trim().toLowerCase().replace(/^\./, '');
  return clean ? clean.slice(0, 16) : null;
}

function sanitizePreciseReferences(rawList) {
  if (!Array.isArray(rawList)) return [];
  const allowedTypes = new Set(['character', 'character&style', 'style', 'costume', 'outfit']);
  const out = [];
  for (let i = 0; i < rawList.length && out.length < 32; i++) {
    const item = rawList[i];
    if (!item || typeof item !== 'object') continue;
    const imageHash = sanitizeOptionalHash(item.imageHash);
    if (!imageHash) continue;
    const imageExt = sanitizeOptionalExt(item.imageExt, true) || 'png';
    const rawType = typeof item.type === 'string' ? item.type.trim() : 'character&style';
    const type = rawType === 'outfit' ? 'costume' : allowedTypes.has(rawType) ? rawType : 'character&style';
    const id =
      typeof item.id === 'string' && item.id.trim()
        ? item.id.trim().slice(0, 128)
        : `ref_${i}`;
    const fileName =
      typeof item.fileName === 'string' && item.fileName.trim()
        ? item.fileName.trim().slice(0, 200)
        : null;
    const strength = Number.isFinite(Number(item.strength)) ? Number(item.strength) : 1.0;
    const fidelity = Number.isFinite(Number(item.fidelity)) ? Number(item.fidelity) : 1.0;
    const informationExtracted = Number.isFinite(Number(item.informationExtracted))
      ? Number(item.informationExtracted)
      : 1.0;
    out.push({
      id,
      imageHash,
      imageExt,
      ...(fileName ? { fileName } : {}),
      type,
      preferSameOutfit:
        typeof item.preferSameOutfit === 'boolean'
          ? item.preferSameOutfit
          : type === 'character&style',
      strength,
      fidelity,
      informationExtracted,
      enabled: typeof item.enabled === 'boolean' ? item.enabled : true,
    });
  }
  return out;
}

function sanitizeVibeReferences(rawList) {
  if (!Array.isArray(rawList)) return [];
  const allowedSources = new Set(['rawImage', 'naiv4vibe', 'naiv4vibebundle', 'pngEmbedded']);
  const out = [];
  for (let i = 0; i < rawList.length && out.length < 32; i++) {
    const item = rawList[i];
    if (!item || typeof item !== 'object') continue;
    const rawImageHash = sanitizeOptionalHash(item.rawImageHash);
    const rawImageExt = sanitizeOptionalExt(item.rawImageExt, Boolean(rawImageHash));
    const thumbnailHash = sanitizeOptionalHash(item.thumbnailHash);
    const thumbnailExt = sanitizeOptionalExt(item.thumbnailExt, Boolean(thumbnailHash));
    const encodingsByModel = {};
    if (item.encodingsByModel && typeof item.encodingsByModel === 'object' && !Array.isArray(item.encodingsByModel)) {
      for (const [k, v] of Object.entries(item.encodingsByModel)) {
        const key = String(k).trim();
        const val = typeof v === 'string' ? v.trim() : '';
        if (key && val) {
          encodingsByModel[key] = val;
        }
      }
    }
    const encodedInfoExtractedByModel = {};
    if (
      item.encodedInfoExtractedByModel &&
      typeof item.encodedInfoExtractedByModel === 'object' &&
      !Array.isArray(item.encodedInfoExtractedByModel)
    ) {
      for (const [k, v] of Object.entries(item.encodedInfoExtractedByModel)) {
        const key = String(k).trim();
        const num = Number(v);
        if (key && Number.isFinite(num)) {
          encodedInfoExtractedByModel[key] = num;
        }
      }
    }
    if (!rawImageHash && Object.keys(encodingsByModel).length === 0) continue;
    const id =
      typeof item.id === 'string' && item.id.trim()
        ? item.id.trim().slice(0, 128)
        : `vibe_${i}`;
    const displayName =
      typeof item.displayName === 'string' && item.displayName.trim()
        ? item.displayName.trim().slice(0, 200)
        : 'Vibe';
    const rawSource = typeof item.sourceType === 'string' ? item.sourceType.trim() : 'rawImage';
    const sourceType = allowedSources.has(rawSource) ? rawSource : 'rawImage';
    const strength = Number.isFinite(Number(item.strength)) ? Number(item.strength) : 0.6;
    const rawInfo = Number(item.informationExtracted);
    const informationExtracted = Number.isFinite(rawInfo)
      ? Math.min(1.0, Math.max(0.01, rawInfo))
      : 1.0;
    out.push({
      id,
      displayName,
      sourceType,
      ...(rawImageHash ? { rawImageHash, rawImageExt: rawImageExt || 'png' } : {}),
      ...(thumbnailHash ? { thumbnailHash, thumbnailExt: thumbnailExt || 'png' } : {}),
      ...(Object.keys(encodingsByModel).length > 0 ? { encodingsByModel } : {}),
      ...(Object.keys(encodedInfoExtractedByModel).length > 0
        ? { encodedInfoExtractedByModel }
        : {}),
      strength,
      informationExtracted,
      enabled: typeof item.enabled === 'boolean' ? item.enabled : true,
    });
  }
  return out;
}

function mapRowToEntry(row) {
  let tags = [];
  if (typeof row.tags_json === 'string' && row.tags_json.trim()) {
    try {
      const parsed = JSON.parse(row.tags_json);
      if (Array.isArray(parsed)) {
        tags = parsed.map((t) => String(t));
      }
    } catch {
      tags = [];
    }
  }

  return {
    id: row.id,
    title: row.title,
    category: row.category,
    prompt: row.prompt,
    negativePrompt: row.negative_prompt ?? '',
    prefixPrompt: row.prefix_prompt ?? '',
    suffixPrompt: row.suffix_prompt ?? '',
    tags,
    isFavorite: Boolean(row.is_favorite),
    isBuiltin: Boolean(row.is_builtin),
    previewHash: row.preview_hash || null,
    previewExt: row.preview_ext || null,
    preciseReferences: parseJsonArrayField(row.references_json),
    vibeReferences: parseJsonArrayField(row.vibes_json),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at || null,
    revision: Number(row.revision ?? 0),
  };
}

const migratedEntryColumnDbs = new WeakSet();

async function addColumnIfMissing(db, sql) {
  try {
    await db.prepare(sql).run();
  } catch (err) {
    const msg = String(err?.message || err || '').toLowerCase();
    if (!msg.includes('duplicate column')) {
      throw err;
    }
  }
}

async function ensureEntrySchemaColumns(db) {
  if (migratedEntryColumnDbs.has(db)) return;
  const { results } = await db.prepare('PRAGMA table_info(sync_entries)').all();
  const cols = new Set((results || []).map((r) => r.name));
  if (!cols.has('prefix_prompt')) {
    await addColumnIfMissing(
      db,
      "ALTER TABLE sync_entries ADD COLUMN prefix_prompt TEXT NOT NULL DEFAULT ''",
    );
  }
  if (!cols.has('suffix_prompt')) {
    await addColumnIfMissing(
      db,
      "ALTER TABLE sync_entries ADD COLUMN suffix_prompt TEXT NOT NULL DEFAULT ''",
    );
  }
  if (!cols.has('references_json')) {
    await addColumnIfMissing(
      db,
      "ALTER TABLE sync_entries ADD COLUMN references_json TEXT NOT NULL DEFAULT '[]'",
    );
  }
  if (!cols.has('vibes_json')) {
    await addColumnIfMissing(
      db,
      "ALTER TABLE sync_entries ADD COLUMN vibes_json TEXT NOT NULL DEFAULT '[]'",
    );
  }
  migratedEntryColumnDbs.add(db);
}

async function executeBatches(db, statements) {
  for (let i = 0; i < statements.length; i += D1_BATCH_STATEMENTS) {
    const slice = statements.slice(i, i + D1_BATCH_STATEMENTS);
    if (slice.length > 0) {
      await db.batch(slice);
    }
  }
}

async function allocateNamespaceRevision(db, namespace, serverNow) {
  await db
    .prepare(
      'INSERT INTO sync_meta (namespace, revision, updated_at) VALUES (?, 0, ?) ON CONFLICT(namespace) DO NOTHING',
    )
    .bind(namespace, serverNow)
    .run();

  const updated = await db
    .prepare(
      'UPDATE sync_meta SET revision = revision + 1, updated_at = ? WHERE namespace = ? RETURNING revision',
    )
    .bind(serverNow, namespace)
    .first();

  return Number(updated?.revision ?? 1);
}

async function handleHealth(url, env) {
  const namespace = normalizeNamespace(url.searchParams.get('namespace'));
  if (!namespace) {
    return errorResponse('namespace 格式无效', 400, 'INVALID_NAMESPACE');
  }

  const [metaRow, entryStats, imageStats] = await Promise.all([
    env.DB.prepare('SELECT revision, updated_at FROM sync_meta WHERE namespace = ?')
      .bind(namespace)
      .first(),
    env.DB.prepare(
      `SELECT
         SUM(CASE WHEN deleted_at IS NULL THEN 1 ELSE 0 END) AS active_count,
         SUM(CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END) AS tombstone_count
       FROM sync_entries
       WHERE namespace = ?`,
    )
      .bind(namespace)
      .first(),
    env.DB.prepare(
      `SELECT
         COUNT(*) AS image_count,
         COALESCE(SUM(size_bytes), 0) AS image_bytes
       FROM sync_images`,
    ).first(),
  ]);

  return jsonResponse({
    ok: true,
    namespace,
    revision: Number(metaRow?.revision ?? 0),
    activeEntries: Number(entryStats?.active_count ?? 0),
    tombstoneEntries: Number(entryStats?.tombstone_count ?? 0),
    imageCount: Number(imageStats?.image_count ?? 0),
    imageBytes: Number(imageStats?.image_bytes ?? 0),
    serverTime: new Date().toISOString(),
  });
}

async function handleGetSync(url, env) {
  const namespace = normalizeNamespace(url.searchParams.get('namespace'));
  if (!namespace) {
    return errorResponse('namespace 格式无效', 400, 'INVALID_NAMESPACE');
  }

  await ensureEntrySchemaColumns(env.DB);

  const sinceRaw = url.searchParams.get('since_rev');
  const sinceRev = sinceRaw !== null ? Number.parseInt(sinceRaw, 10) : null;

  const metaRow = await env.DB.prepare('SELECT revision FROM sync_meta WHERE namespace = ?')
    .bind(namespace)
    .first();

  const query =
    sinceRev !== null && Number.isFinite(sinceRev) && sinceRev >= 0
      ? env.DB.prepare(
          'SELECT * FROM sync_entries WHERE namespace = ? AND revision > ? ORDER BY revision ASC, id ASC',
        ).bind(namespace, sinceRev)
      : env.DB.prepare(
          'SELECT * FROM sync_entries WHERE namespace = ? ORDER BY revision ASC, id ASC',
        ).bind(namespace);

  const { results } = await query.all();
  return jsonResponse({
    ok: true,
    namespace,
    revision: Number(metaRow?.revision ?? 0),
    entries: (results || []).map(mapRowToEntry),
    serverTime: new Date().toISOString(),
  });
}

function validatePushEntry(raw, fallbackIso) {
  if (!raw || typeof raw !== 'object') {
    return { error: '条目必须是 JSON 对象' };
  }
  const id = typeof raw.id === 'string' ? raw.id.trim() : '';
  if (!id || id.length > 200) {
    return { error: '条目 id 无效' };
  }
  const deletedAt =
    raw.deletedAt !== null && raw.deletedAt !== undefined && String(raw.deletedAt).trim() !== ''
      ? normalizeIsoString(raw.deletedAt, fallbackIso)
      : null;

  const title = typeof raw.title === 'string' ? raw.title : '';
  const category = typeof raw.category === 'string' && raw.category.trim() ? raw.category.trim() : '其他';
  const prompt = typeof raw.prompt === 'string' ? raw.prompt : '';

  const catLower = category.trim().toLowerCase();
  const isChar = catLower === '角色' || catLower === 'character';
  const isStyle = catLower === '风格' || catLower === '画风' || catLower === 'style';

  const negativePrompt = (isChar || isStyle) && typeof raw.negativePrompt === 'string' ? raw.negativePrompt : '';
  const prefixPrompt = isStyle && typeof raw.prefixPrompt === 'string' ? raw.prefixPrompt : '';
  const suffixPrompt = isStyle && typeof raw.suffixPrompt === 'string' ? raw.suffixPrompt : '';

  const preciseReferences = deletedAt === null ? sanitizePreciseReferences(raw.preciseReferences) : [];
  const vibeReferences = deletedAt === null ? sanitizeVibeReferences(raw.vibeReferences) : [];

  const hasPromptContent = isStyle
    ? Boolean(prompt.trim() || prefixPrompt.trim() || suffixPrompt.trim() || negativePrompt.trim())
    : Boolean(prompt.trim());
  const hasContent = hasPromptContent || preciseReferences.length > 0 || vibeReferences.length > 0;

  if (deletedAt === null && (!title.trim() || !hasContent)) {
    return { error: `条目 ${id} 缺少 title 或 prompt` };
  }

  const tags = Array.isArray(raw.tags) ? raw.tags.map((t) => String(t)) : [];
  const previewHash =
    raw.previewHash && isValidSha256(String(raw.previewHash).toLowerCase())
      ? String(raw.previewHash).toLowerCase()
      : null;
  const previewExt =
    previewHash && typeof raw.previewExt === 'string' && raw.previewExt.trim()
      ? raw.previewExt.trim().toLowerCase().replace(/^\./, '')
      : null;

  const createdAt = normalizeIsoString(raw.createdAt, fallbackIso);
  const updatedAt = normalizeIsoString(raw.updatedAt, fallbackIso);

  return {
    entry: {
      id,
      title,
      category,
      prompt,
      negativePrompt,
      prefixPrompt,
      suffixPrompt,
      tagsJson: JSON.stringify(tags),
      isFavorite: raw.isFavorite ? 1 : 0,
      isBuiltin: raw.isBuiltin ? 1 : 0,
      previewHash,
      previewExt,
      referencesJson: JSON.stringify(preciseReferences),
      vibesJson: JSON.stringify(vibeReferences),
      createdAt,
      updatedAt,
      deletedAt,
    },
  };
}

function prepareUpsertEntry(db, namespace, e, nextRevision) {
  return db
    .prepare(
      `INSERT INTO sync_entries (
         namespace, id, title, category, prompt, negative_prompt, prefix_prompt, suffix_prompt, tags_json,
         is_favorite, is_builtin, preview_hash, preview_ext, references_json, vibes_json,
         created_at, updated_at, deleted_at, revision
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(namespace, id) DO UPDATE SET
         title = excluded.title,
         category = excluded.category,
         prompt = excluded.prompt,
         negative_prompt = excluded.negative_prompt,
         prefix_prompt = excluded.prefix_prompt,
         suffix_prompt = excluded.suffix_prompt,
         tags_json = excluded.tags_json,
         is_favorite = excluded.is_favorite,
         is_builtin = excluded.is_builtin,
         preview_hash = excluded.preview_hash,
         preview_ext = excluded.preview_ext,
         references_json = excluded.references_json,
         vibes_json = excluded.vibes_json,
         created_at = excluded.created_at,
         updated_at = excluded.updated_at,
         deleted_at = excluded.deleted_at,
         revision = excluded.revision`,
    )
    .bind(
      namespace,
      e.id,
      e.title,
      e.category,
      e.prompt,
      e.negativePrompt,
      e.prefixPrompt,
      e.suffixPrompt,
      e.tagsJson,
      e.isFavorite,
      e.isBuiltin,
      e.previewHash,
      e.previewExt,
      e.referencesJson,
      e.vibesJson,
      e.createdAt,
      e.updatedAt,
      e.deletedAt,
      nextRevision,
    );
}

async function fetchExistingTimestamps(db, namespace, ids) {
  const map = new Map();
  for (let i = 0; i < ids.length; i += SQL_IN_BATCH_SIZE) {
    const chunk = ids.slice(i, i + SQL_IN_BATCH_SIZE);
    const placeholders = chunk.map(() => '?').join(', ');
    const { results } = await db
      .prepare(
        `SELECT id, updated_at, deleted_at FROM sync_entries WHERE namespace = ? AND id IN (${placeholders})`,
      )
      .bind(namespace, ...chunk)
      .all();
    for (const row of results || []) {
      const effectiveIso = row.deleted_at || row.updated_at;
      const ms = parseTimestampMs(effectiveIso) ?? 0;
      map.set(row.id, ms);
    }
  }
  return map;
}

async function handlePushSync(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return errorResponse('请求体必须是合法 JSON', 400, 'INVALID_JSON');
  }

  const namespace = normalizeNamespace(body?.namespace);
  if (!namespace) {
    return errorResponse('namespace 格式无效', 400, 'INVALID_NAMESPACE');
  }

  await ensureEntrySchemaColumns(env.DB);

  const mode = body?.mode === 'replace' ? 'replace' : 'merge';
  const rawEntries = Array.isArray(body?.entries) ? body.entries : null;
  if (!rawEntries) {
    return errorResponse('entries 必须是数组', 400, 'INVALID_ENTRIES');
  }

  const serverNow = new Date().toISOString();
  const normalized = [];
  const dedupById = new Map();
  for (const item of rawEntries) {
    const checked = validatePushEntry(item, serverNow);
    if (checked.error) {
      return errorResponse(checked.error, 400, 'INVALID_ENTRY');
    }
    dedupById.set(checked.entry.id, checked.entry);
  }
  for (const entry of dedupById.values()) {
    normalized.push(entry);
  }

  const nextRevision = await allocateNamespaceRevision(env.DB, namespace, serverNow);
  const statements = [];
  let appliedCount = 0;

  if (mode === 'replace') {
    const { results: existingRows } = await env.DB.prepare(
      'SELECT id FROM sync_entries WHERE namespace = ? AND deleted_at IS NULL',
    )
      .bind(namespace)
      .all();

    const incomingActiveIds = new Set(
      normalized.filter((e) => e.deletedAt === null).map((e) => e.id),
    );

    for (const row of existingRows || []) {
      if (!incomingActiveIds.has(row.id)) {
        statements.push(
          env.DB.prepare(
            `UPDATE sync_entries
             SET deleted_at = ?, updated_at = ?, preview_hash = NULL, preview_ext = NULL,
                 references_json = '[]', vibes_json = '[]', revision = ?
             WHERE namespace = ? AND id = ?`,
          ).bind(serverNow, serverNow, nextRevision, namespace, row.id),
        );
        appliedCount++;
      }
    }

    for (const e of normalized) {
      statements.push(prepareUpsertEntry(env.DB, namespace, e, nextRevision));
      appliedCount++;
    }
  } else {
    const existingTs = await fetchExistingTimestamps(
      env.DB,
      namespace,
      normalized.map((e) => e.id),
    );

    for (const e of normalized) {
      const incomingMs = parseTimestampMs(e.deletedAt || e.updatedAt) ?? 0;
      const existingMs = existingTs.get(e.id);
      if (existingMs !== undefined && incomingMs < existingMs) {
        continue;
      }
      statements.push(prepareUpsertEntry(env.DB, namespace, e, nextRevision));
      appliedCount++;
    }
  }

  await executeBatches(env.DB, statements);

  return jsonResponse({
    ok: true,
    namespace,
    mode,
    revision: nextRevision,
    appliedCount,
    serverTime: serverNow,
  });
}

async function handleImageCheck(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return errorResponse('请求体必须是合法 JSON', 400, 'INVALID_JSON');
  }

  const rawHashes = Array.isArray(body?.hashes) ? body.hashes : null;
  if (!rawHashes) {
    return errorResponse('hashes 必须是数组', 400, 'INVALID_HASHES');
  }

  const uniqueHashes = [];
  const seen = new Set();
  for (const h of rawHashes) {
    const clean = typeof h === 'string' ? h.trim().toLowerCase() : '';
    if (!isValidSha256(clean)) {
      return errorResponse(`无效的 SHA-256 哈希: ${String(h)}`, 400, 'INVALID_HASH');
    }
    if (!seen.has(clean)) {
      seen.add(clean);
      uniqueHashes.push(clean);
    }
  }

  const existingSet = new Set();
  for (let i = 0; i < uniqueHashes.length; i += SQL_IN_BATCH_SIZE) {
    const chunk = uniqueHashes.slice(i, i + SQL_IN_BATCH_SIZE);
    const placeholders = chunk.map(() => '?').join(', ');
    const { results } = await env.DB.prepare(
      `SELECT hash FROM sync_images WHERE hash IN (${placeholders})`,
    )
      .bind(...chunk)
      .all();
    for (const row of results || []) {
      existingSet.add(row.hash);
    }
  }

  const existing = [];
  const missing = [];
  for (const h of uniqueHashes) {
    if (existingSet.has(h)) existing.push(h);
    else missing.push(h);
  }

  return jsonResponse({ ok: true, existing, missing });
}

async function handleImagePut(hashParam, request, env) {
  const hash = hashParam.toLowerCase();
  if (!isValidSha256(hash)) {
    return errorResponse('无效的图片 SHA-256 哈希', 400, 'INVALID_HASH');
  }

  const existing = await env.DB.prepare('SELECT hash, size_bytes FROM sync_images WHERE hash = ?')
    .bind(hash)
    .first();
  if (existing) {
    return jsonResponse({
      ok: true,
      hash,
      sizeBytes: Number(existing.size_bytes),
      deduplicated: true,
    });
  }

  const buffer = await request.arrayBuffer();
  if (buffer.byteLength === 0) {
    return errorResponse('图片内容不能为空', 400, 'EMPTY_IMAGE');
  }
  if (buffer.byteLength > MAX_IMAGE_BYTES) {
    return errorResponse(`图片大小超过 ${MAX_IMAGE_BYTES / (1024 * 1024)} MiB 限制`, 413, 'IMAGE_TOO_LARGE');
  }

  const actualHash = await sha256Hex(buffer);
  if (actualHash !== hash) {
    return errorResponse('图片内容 SHA-256 校验不匹配', 400, 'HASH_MISMATCH');
  }

  const bytes = new Uint8Array(buffer);
  const { mimeType, ext } = detectImageFormat(
    bytes,
    request.headers.get('X-Image-Ext'),
    request.headers.get('Content-Type'),
  );
  const chunkCount = Math.ceil(bytes.length / IMAGE_CHUNK_BYTES);
  const createdAt = new Date().toISOString();

  const statements = [];
  for (let i = 0; i < chunkCount; i++) {
    const start = i * IMAGE_CHUNK_BYTES;
    const end = Math.min(start + IMAGE_CHUNK_BYTES, bytes.length);
    const b64 = bytesToBase64(bytes.subarray(start, end));
    statements.push(
      env.DB.prepare(
        'INSERT OR REPLACE INTO sync_image_chunks (hash, chunk_index, data_b64) VALUES (?, ?, ?)',
      ).bind(hash, i, b64),
    );
  }

  // 元信息最后写入，防止未写完分块时被并发判定为已存在
  statements.push(
    env.DB.prepare(
      `INSERT OR REPLACE INTO sync_images (hash, mime_type, ext, size_bytes, chunk_count, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    ).bind(hash, mimeType, ext, bytes.length, chunkCount, createdAt),
  );

  await executeBatches(env.DB, statements);

  return jsonResponse({
    ok: true,
    hash,
    mimeType,
    ext,
    sizeBytes: bytes.length,
    chunkCount,
    deduplicated: false,
  });
}

async function handleImageGet(hashParam, env) {
  const hash = hashParam.toLowerCase();
  if (!isValidSha256(hash)) {
    return errorResponse('无效的图片 SHA-256 哈希', 400, 'INVALID_HASH');
  }

  const meta = await env.DB.prepare(
    'SELECT mime_type, size_bytes, chunk_count FROM sync_images WHERE hash = ?',
  )
    .bind(hash)
    .first();
  if (!meta) {
    return errorResponse('图片不存在', 404, 'NOT_FOUND');
  }

  const { results } = await env.DB.prepare(
    'SELECT data_b64 FROM sync_image_chunks WHERE hash = ? ORDER BY chunk_index ASC',
  )
    .bind(hash)
    .all();

  const chunks = results || [];
  if (chunks.length !== Number(meta.chunk_count)) {
    return errorResponse('图片分块数据不完整', 500, 'CORRUPT_IMAGE');
  }

  const decodedParts = chunks.map((c) => base64ToBytes(c.data_b64));
  const totalBytes = decodedParts.reduce((acc, part) => acc + part.length, 0);
  const combined = new Uint8Array(totalBytes);
  let offset = 0;
  for (const part of decodedParts) {
    combined.set(part, offset);
    offset += part.length;
  }

  return new Response(combined, {
    status: 200,
    headers: {
      'Content-Type': meta.mime_type || 'image/png',
      'Content-Length': String(combined.length),
      'Cache-Control': 'public, max-age=31536000, immutable',
      ETag: `"${hash}"`,
      ...CORS_HEADERS,
    },
  });
}

async function handleImageGc(env) {
  await ensureEntrySchemaColumns(env.DB);
  const { results: activeRows } = await env.DB.prepare(
    `SELECT preview_hash, references_json, vibes_json FROM sync_entries
     WHERE deleted_at IS NULL`,
  ).all();

  const referencedHashes = new Set();
  for (const row of activeRows || []) {
    if (row.preview_hash) referencedHashes.add(String(row.preview_hash).toLowerCase());
    for (const ref of parseJsonArrayField(row.references_json)) {
      if (ref && typeof ref.imageHash === 'string' && ref.imageHash) {
        referencedHashes.add(ref.imageHash.toLowerCase());
      }
    }
    for (const vibe of parseJsonArrayField(row.vibes_json)) {
      if (vibe && typeof vibe.rawImageHash === 'string' && vibe.rawImageHash) {
        referencedHashes.add(vibe.rawImageHash.toLowerCase());
      }
      if (vibe && typeof vibe.thumbnailHash === 'string' && vibe.thumbnailHash) {
        referencedHashes.add(vibe.thumbnailHash.toLowerCase());
      }
    }
  }

  const { results: imageRows } = await env.DB.prepare('SELECT hash FROM sync_images').all();
  const orphanHashes = (imageRows || [])
    .map((r) => String(r.hash).toLowerCase())
    .filter((h) => !referencedHashes.has(h));
  if (orphanHashes.length === 0) {
    return jsonResponse({ ok: true, deletedImages: 0 });
  }

  const statements = [];
  for (let i = 0; i < orphanHashes.length; i += SQL_IN_BATCH_SIZE) {
    const chunk = orphanHashes.slice(i, i + SQL_IN_BATCH_SIZE);
    const placeholders = chunk.map(() => '?').join(', ');
    statements.push(
      env.DB.prepare(`DELETE FROM sync_image_chunks WHERE hash IN (${placeholders})`).bind(...chunk),
      env.DB.prepare(`DELETE FROM sync_images WHERE hash IN (${placeholders})`).bind(...chunk),
    );
  }
  await executeBatches(env.DB, statements);

  return jsonResponse({ ok: true, deletedImages: orphanHashes.length });
}

export async function handleRequest(request, env) {
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  const authError = await authorize(request, env);
  if (authError) return authError;

  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, '') || '/';

  if (request.method === 'GET' && path === '/api/health') {
    return handleHealth(url, env);
  }
  if (request.method === 'GET' && path === '/api/sync') {
    return handleGetSync(url, env);
  }
  if (request.method === 'POST' && path === '/api/sync/push') {
    return handlePushSync(request, env);
  }
  if (request.method === 'POST' && path === '/api/images/check') {
    return handleImageCheck(request, env);
  }
  if (request.method === 'POST' && path === '/api/images/gc') {
    return handleImageGc(env);
  }

  const imageMatch = path.match(/^\/api\/images\/([a-fA-F0-9]{64})$/);
  if (imageMatch) {
    if (request.method === 'PUT') {
      return handleImagePut(imageMatch[1], request, env);
    }
    if (request.method === 'GET') {
      return handleImageGet(imageMatch[1], env);
    }
  }

  return errorResponse('未找到对应接口', 404, 'NOT_FOUND');
}

export default {
  async fetch(request, env) {
    try {
      return await handleRequest(request, env);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return errorResponse(`服务器内部错误: ${message}`, 500, 'INTERNAL_ERROR');
    }
  },
};
