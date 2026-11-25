-- NovelAI Harness 词库云同步 Cloudflare D1 数据库初始化脚本
-- 执行方式：
--   本地开发: npx wrangler d1 execute prompt_library_sync --local --file=./schema.sql
--   线上部署: npx wrangler d1 execute prompt_library_sync --remote --file=./schema.sql

-- 命名空间元数据与单调递增版本号
CREATE TABLE IF NOT EXISTS sync_meta (
  namespace TEXT PRIMARY KEY,
  revision INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
);

-- 词库条目表（含软删除墓碑 deleted_at）
CREATE TABLE IF NOT EXISTS sync_entries (
  namespace TEXT NOT NULL,
  id TEXT NOT NULL,
  title TEXT NOT NULL,
  category TEXT NOT NULL,
  prompt TEXT NOT NULL,
  negative_prompt TEXT NOT NULL DEFAULT '',
  prefix_prompt TEXT NOT NULL DEFAULT '',
  suffix_prompt TEXT NOT NULL DEFAULT '',
  tags_json TEXT NOT NULL DEFAULT '[]',
  is_favorite INTEGER NOT NULL DEFAULT 0,
  is_builtin INTEGER NOT NULL DEFAULT 0,
  preview_hash TEXT,
  preview_ext TEXT,
  references_json TEXT NOT NULL DEFAULT '[]',
  vibes_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  revision INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (namespace, id)
);

CREATE INDEX IF NOT EXISTS idx_sync_entries_ns_rev
  ON sync_entries (namespace, revision);

CREATE INDEX IF NOT EXISTS idx_sync_entries_preview_hash
  ON sync_entries (preview_hash);

-- 预览图元信息表（按 SHA-256 内容寻址去重）
CREATE TABLE IF NOT EXISTS sync_images (
  hash TEXT PRIMARY KEY,
  mime_type TEXT NOT NULL,
  ext TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  chunk_count INTEGER NOT NULL,
  created_at TEXT NOT NULL
);

-- 预览图分块表（每块 <= 256 KiB Base64，彻底规避 D1 单行 1MB 限制）
CREATE TABLE IF NOT EXISTS sync_image_chunks (
  hash TEXT NOT NULL,
  chunk_index INTEGER NOT NULL,
  data_b64 TEXT NOT NULL,
  PRIMARY KEY (hash, chunk_index)
);
