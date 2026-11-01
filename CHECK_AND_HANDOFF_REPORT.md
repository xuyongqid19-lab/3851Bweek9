# 项目检查与移交报告

检查对象：`3851B_with_auth_docker_database`

## 已确认正常

- Auth PostgreSQL 与 Community PostgreSQL 使用不同数据库、不同端口、不同 volume。
- Community: API `3000`，PostgreSQL `5433`。
- Auth: API `3002`，PostgreSQL `5434`，Adminer `8082`。
- `auth-server/src/index.js` 与 `server/src/index.js` 通过 Node.js 语法检查。
- Auth `users` 表具有 Email、Username、Google `sub` 唯一索引。
- 普通密码使用 bcrypt hash。
- Google ID Token 在后端使用 Google library 验证。
- Auth API 已提供 `/auth/me`，方便后续其他模块获取当前用户。
- Auth schema 文件不包含真实用户数据。

## 检查时发现并已修正

1. `docker-compose.auth.yml` 已使用 `3002 / 5434 / 8082`，但旧说明文档仍写 `3001 / 8081`。
   - 已更新说明。
2. `lib/services/auth_service.dart` 的默认地址仍指向 `3001`。
   - 已改为 Web `localhost:3002`、Android Emulator `10.0.2.2:3002`。
3. Auth 与 Community compose 位于同一个项目目录，默认 Compose project name 容易产生 orphan 提示/误操作风险。
   - 只在 `docker-compose.auth.yml` 增加独立 project name `global-village-auth-stack`；没有修改 Community compose。
4. 原项目包含本机生成的 `.dart_tool/`、`build/`、`android/local.properties`、`.vscode/settings.json` 等缓存/机器路径。
   - 移交 ZIP 中删除这些可再生成的本机文件，避免队友电脑路径冲突并减少压缩包体积。

## 已知限制（不是本次数据库故障）

- `Forgot Password` 仍是演示逻辑，没有真实邮件验证码/数据库密码重置。
- Community API 目前仍使用 `demo-current-user` / `Ying Haozhe`，尚未接 Auth 的真实当前用户。
- Firebase Hosting 上的前端无法直接连接开发者个人电脑的 `localhost:3002`。
- 本地数据库密码和 JWT secret 是开发配置，若部署公网必须更换。
- CORS 当前为开发阶段开放配置，公网部署时应限制允许域名。

## Community 文件保护

本次整理没有修改：

- `docker-compose.yml`
- `server/`
- `lib/pages/community_page.dart`

也没有修改 Chat、Family、Friends、Profile、Home 的业务代码。

详细的双数据库启动与后续集成方式请看：

```text
DATABASES_START_AND_INTEGRATION_GUIDE.md
```
