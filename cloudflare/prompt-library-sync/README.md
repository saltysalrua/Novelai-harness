# NovelAI Harness 词库云同步后端 (Cloudflare Workers + D1)

完全基于 Cloudflare **免费额度（无需绑卡）** 构建：
- **Workers Free**：每天 100,000 次免费请求
- **D1 Free**：5 GB 免费 SQLite 存储空间（同时存放词库 JSON 与分块预览图，预览图按 SHA-256 去重）

---

## 快速部署（约 3 分钟）

### 1. 安装依赖并登录 Cloudflare

需要本机已安装 Node.js (>= 18)：

```bash
cd cloudflare/prompt-library-sync
npm install
npx wrangler login
```

### 2. 创建 D1 数据库并初始化表结构

```bash
npx wrangler d1 create prompt_library_sync
```

命令行会输出一段 `[[d1_databases]]` 配置，把里面的 `database_id` 复制并替换到 `wrangler.toml` 的 `REPLACE_WITH_YOUR_D1_DATABASE_ID` 中。

接着初始化线上数据库表：

```bash
npm run db:init:remote
```

### 3. 设置访问密钥（Token）

生成一个高强度随机密钥（建议 32 位以上随机字符串），写入 Worker Secret：

```bash
npx wrangler secret put SYNC_TOKEN
```

> 切勿把 Token 写死在 `wrangler.toml` 或代码中。

### 4. 部署 Worker

```bash
npm run deploy
```

部署成功后，命令行会输出你的 Worker 地址，例如：
`https://novelai-prompt-library-sync.<your-subdomain>.workers.dev`

> 如果国内网络直连 `*.workers.dev` 不稳定，可以在 Cloudflare Dashboard → Workers → Settings → Domains & Routes 绑定一个自己的自定义域名（同样免费）。

---

## 在客户端中使用

打开 NovelAI Harness 的 **设置 → 常规 → 词库云同步**（或在 **词库 → 管理 → 云同步设置**）：
1. **同步服务地址**：填入你的 Worker 地址（如 `https://novelai-prompt-library-sync.xxx.workers.dev`）
2. **访问密钥 (Token)**：填入刚才设置的 `SYNC_TOKEN`
3. **命名空间 (可选)**：默认 `default`（如果你想隔离多套词库，可填不同名称如 `work` / `nsfw`）
4. 点击 **测试连接** 验证配置，然后即可使用 **双向增量同步**、**强制上传覆盖云端** 或 **强制拉取覆盖本地**。

---

## API 一览

所有 `/api/*` 请求均需携带 `Authorization: Bearer <SYNC_TOKEN>`：

| 方法与路径 | 用途 |
|---|---|
| `GET /api/health?namespace=default` | 健康检查与库统计（条目数、图片数、总字节、最新版本号） |
| `GET /api/sync?namespace=default` | 拉取命名空间下的全部词条与删除墓碑 |
| `POST /api/sync/push` | 提交增量合并 (`mode: "merge"`) 或整库覆盖 (`mode: "replace"`) |
| `POST /api/images/check` | 批量检查 SHA-256 预览图哈希是否已存在于云端 |
| `PUT /api/images/:hash` | 上传缺失的预览图（校验 SHA-256 并按 256 KiB 分块入库） |
| `GET /api/images/:hash` | 下载预览图原始二进制流（带不可变缓存头） |
| `POST /api/images/gc` | 清理未被任何有效词条引用的孤儿预览图 |
