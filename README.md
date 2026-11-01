# Family tree update — 15 October 2026

The October teammate baseline is integrated with a group-based Family tree. Start with the [feature plan](DOCUMENTATION.FAMILY.TREE01.1.md) and [current implementation handoff](DOCUMENTATION.FAMILY.TREE01.REVIEW.md). Family → Family tree provides group connections, administrator proposals, unanimous tree-merge approval and disconnection. The existing September portable ZIP predates this feature; it has not been replaced by this source update.

# Global Village App (week4)

Global Village 社区应用:Flutter 前端 + 四套 Docker 后端服务(登录 Auth / 社区 Community / 家庭 Family / 聊天 Chat,聊天含好友申请与消息数据库)。

## 环境要求

1. [Docker Desktop](https://www.docker.com/products/docker-desktop/) — 已启动运行
2. [Flutter SDK](https://docs.flutter.dev/get-started/install) — `flutter doctor` 无红色错误(需要 Chrome 浏览器)

## 启动步骤(解压后三步)

### 第 1 步:启动全部后端服务(需要 Docker Desktop 已运行)

在项目根目录(本文件夹)依次执行:

```powershell
docker compose -f docker-compose.yml up -d --build
docker compose -f docker-compose.auth.yml up -d --build
docker compose -f docker-compose.family.yml up -d --build
docker compose -f docker-compose.chat.yml up -d --build
```

### 第 2 步:验证服务健康

```powershell
curl.exe http://localhost:3000/health
curl.exe http://localhost:3002/health
curl.exe http://localhost:3003/health
curl.exe http://localhost:3004/health
```

四个都应返回 `{"ok":true,...}`。

### 第 3 步:启动前端

双击 **RunWeb.cmd**(首次运行会自动 `flutter pub get`,并自动打开 Chrome)。

应用地址:http://localhost:7357

## 使用流程

1. 打开应用,先**注册**账号(或使用 Google 登录,Google 登录需要配置 `GOOGLE_SIGNIN_SETUP.md` 中的客户端 ID)
2. 在 Chats 页面点击顶部搜索栏,输入对方的**邮箱 / 用户名 / 姓名**搜索注册用户
3. 点击 **Add** → **Send Request** 发送好友申请
4. 对方登录后,聊天页右上角**铃铛**会显示红色数字角标,点开即可 **Accept**(成为好友)或 **Decline**
5. 成为好友后出现在聊天列表,文字 / 语音消息全部存入 PostgreSQL 数据库,双方实时同步

## 服务与端口一览

| 服务 | 端口 | 说明 |
|---|---|---|
| Community API | http://localhost:3000 | 社区活动 |
| Community PostgreSQL | localhost:5433 | 数据卷 community-db-data |
| Auth API | http://localhost:3002 | 登录 / 注册 / 用户搜索 |
| Auth PostgreSQL | localhost:5434 | Auth Adminer 管理界面 http://localhost:8082 |
| Family API | http://localhost:3003 | 家庭模块 |
| Chat API | http://localhost:3004 | 好友申请 + 聊天消息 |
| Chat PostgreSQL | localhost:5435 | 数据卷 chat-db-data |
| Flutter Web | http://localhost:7357 | 前端 |

## 停止服务

```powershell
docker compose -f docker-compose.yml stop
docker compose -f docker-compose.auth.yml stop
docker compose -f docker-compose.family.yml stop
docker compose -f docker-compose.chat.yml stop
```

> 不要随手运行 `docker compose down -v`,`-v` 会删除数据库数据。

## 其他文档

- `DATABASES_START_AND_INTEGRATION_GUIDE.md` — 数据库结构与集成说明
- `AUTH_DATABASE_SETUP.md` / `GOOGLE_SIGNIN_SETUP.md` — 登录与 Google 登录配置
- `数据库启动与连接操作说明.docx` — 数据库操作说明
