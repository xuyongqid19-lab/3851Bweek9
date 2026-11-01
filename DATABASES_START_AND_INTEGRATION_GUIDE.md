# Global Village 两套数据库：启动区别与连接说明

这份项目当前包含两套独立数据库。它们可以同时运行，但用途不同。

## 一、先分清两个 Docker Compose 文件

### A. Community（另一位组员负责）

文件：

```text
docker-compose.yml
```

对应：

| 项目 | 地址/端口 |
|---|---|
| Community API | `http://localhost:3000` |
| Community PostgreSQL | `localhost:5433` |
| Database | `global_village` |
| DB user/password | `global_village` / `global_village` |
| 数据 volume | `community-db-data` |

主要表：

- `community_activities`
- `activity_attendees`
- `nearby_locations`

启动：

```powershell
docker compose -f docker-compose.yml up -d --build
```

测试：

```powershell
curl.exe http://localhost:3000/health
```

停止：

```powershell
docker compose -f docker-compose.yml stop
```

### B. Auth / Login / Register（Wang Zuzan 负责）

文件：

```text
docker-compose.auth.yml
```

对应：

| 项目 | 地址/端口 |
|---|---|
| Auth API | `http://localhost:3002` |
| Auth PostgreSQL | `localhost:5434` |
| Auth Adminer | `http://localhost:8082` |
| Database | `global_village_auth` |
| DB user/password | `global_village_auth` / `global_village_auth` |
| 数据 volume | `auth-db-data` |

主要表：

- `users`

启动：

```powershell
docker compose -f docker-compose.auth.yml up -d --build
```

测试：

```powershell
curl.exe http://localhost:3002/health
```

停止：

```powershell
docker compose -f docker-compose.auth.yml stop
```

> Auth compose 已使用独立 Compose project name `global-village-auth-stack`，用于减少与 Community compose 在同一文件夹运行时的相互干扰。

---

## 二、两套数据库一起启动

确保 Docker Desktop 已启动，在项目根目录依次运行：

```powershell
docker compose -f docker-compose.yml up -d --build
```

```powershell
docker compose -f docker-compose.auth.yml up -d --build
```

检查：

```powershell
docker ps
```

正常应同时看到类似：

```text
global-village-community-api     3000
global-village-community-db      5433
global-village-auth-api          3002
global-village-auth-db           5434
global-village-auth-adminer      8082
```

两个健康检查都应通过：

```powershell
curl.exe http://localhost:3000/health
curl.exe http://localhost:3002/health
```

---

## 三、Flutter 当前怎么同时使用两套后端

Community 页面当前调用：

```text
http://localhost:3000
```

Auth 调用：

```text
http://localhost:3002
```

本地 Web 推荐启动命令：

```powershell
flutter run -d chrome --web-hostname localhost --web-port 7357 --dart-define=GOOGLE_WEB_CLIENT_ID=848686154651-a5lrjn63ggqj83g5ob4bms7imqd6jkth.apps.googleusercontent.com --dart-define=AUTH_API_BASE_URL=http://localhost:3002
```

因此“同时使用两套数据库”并不是把两个 PostgreSQL 强行合并，而是：

```text
Flutter App
   ├─ 登录/注册/当前用户  → Auth API 3002 → Auth DB 5434
   └─ Community 活动/附近位置 → Community API 3000 → Community DB 5433
```

这样最不容易互相破坏。

---

## 四、Community 和登录用户的连接方式

### 当前状态（重要）

Community API 已经通过 Auth API 识别当前登录用户，不再使用演示硬编码用户。

Auth 数据库里的每个用户都有唯一 UUID：

```text
users.id
```

Community 的表已经有可用于关联的字段：

```text
community_activities.created_by_user_id
activity_attendees.user_id
nearby_locations.user_id
```

Community API 会把 Auth 的 `users.id` 写进这些字段。

### 推荐连接方式：通过 Auth API，不要让 Community 直接读 Auth PostgreSQL

登录成功后 Flutter 已保存：

```text
auth_token
auth_user
```

推荐流程：

```text
1. 用户登录
2. Auth API 返回 JWT + user.id
3. Flutter 调 Community API 时带：Authorization: Bearer <auth_token>
4. Community API 用该 token 向 Auth API 查询 /auth/me
5. Auth API 返回真实 user.id / fullName
6. Community API 把 user.id 存进 created_by_user_id / activity_attendees.user_id
```

附近的人功能也走同一套登录态：

```text
1. 用户登录
2. 打开 Nearby People
3. Flutter 每 5 分钟把当前位置发到 POST /community/nearby/people
4. Community API 验证 token，写入/更新 nearby_locations
5. nearby_locations 每个用户只保留一条记录，expires_at 为 5 分钟后
6. 查询当前位置网格 + 周围 8 个网格，最多取 100 个候选
7. API 再做精确距离计算，只返回 500 m 内最多 10 个结果
```

Auth 当前已有接口：

```http
GET /auth/me
Authorization: Bearer <JWT>
```

本机 Windows + Docker Desktop 环境中，如果 Community API 容器需要调用宿主机暴露的 Auth API，可使用：

```text
http://host.docker.internal:3002/auth/me
```

例如逻辑上：

```text
Community API
   ↓ Authorization token
http://host.docker.internal:3002/auth/me
   ↓
返回用户：id / fullName / email
   ↓
Community DB 保存 users.id
```

### 为什么不建议数据库直接连数据库

不建议 Community API 直接查询 `global_village_auth` PostgreSQL，因为这样两个模块会强耦合：Auth 改表结构时 Community 也容易坏。

推荐：

```text
Community → Auth API → Auth DB
```

而不是：

```text
Community → 直接访问 Auth DB
```

---

## 五、如果只是要在数据库里关联用户

两个 PostgreSQL 是独立数据库，所以不能直接建立跨数据库 Foreign Key。

Community 表可以继续保存 Auth UUID 文本，例如：

```text
Auth users.id:
6f31dbe2-....
```

写到：

```text
community_activities.created_by_user_id
activity_attendees.user_id
```

需要显示用户名时，通过 Auth API 根据当前登录用户查询，或者后续新增安全的 User API。

---

## 六、不要混淆的命令

启动 Community：

```powershell
docker compose -f docker-compose.yml up -d --build
```

启动 Auth：

```powershell
docker compose -f docker-compose.auth.yml up -d --build
```

不要为了“清理”随便运行：

```powershell
docker compose down -v
```

特别是 `-v` 会删除数据库数据。

如果只想停自己的 Auth：

```powershell
docker compose -f docker-compose.auth.yml stop
```

如果只想停 Community：

```powershell
docker compose -f docker-compose.yml stop
```

---

## 七、手机 / Android 模拟器

Android 模拟器访问电脑本机服务不能使用 `localhost`，而使用：

```text
Auth API:      http://10.0.2.2:3002
Community API: http://10.0.2.2:3000
```

真机则不能直接用 `10.0.2.2`。真机测试需要电脑局域网 IP 或把 API 部署到公网。

---

## 八、最终公网部署

Firebase Hosting 只托管 Flutter Web 静态前端。它不能自动把本机 Docker 数据库变成公网数据库。

最终如果需要老师手机、组员电脑、公开网站共享同一套数据，需要分别部署：

```text
Auth API + Auth PostgreSQL
Community API + Community PostgreSQL
```

然后把前端 API 地址改成 HTTPS 公网地址。
