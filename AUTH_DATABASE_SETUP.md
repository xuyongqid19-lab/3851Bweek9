# Global Village 登录/注册数据库操作说明（Auth）

这套认证数据库与 Community 数据库分开运行，不会修改 Community、Chat、Family、Friends、Profile、Home 等其他模块的数据。

## 1. Auth 这套服务是什么

- PostgreSQL 16：保存账号
- Node.js + Express：注册、普通登录、Google 登录 API
- bcrypt：密码/安全问题答案哈希
- Google ID Token verification：后端验证 Google 登录
- JWT：登录成功后的会话 token
- Adminer：网页查看数据库

Auth 容器与端口：

| 服务 | 宿主机端口 | 容器端口 | 用途 |
|---|---:|---:|---|
| `global-village-auth-api` | `3002` | `3001` | 登录/注册 API |
| `global-village-auth-db` | `5434` | `5432` | PostgreSQL |
| `global-village-auth-adminer` | `8082` | `8080` | 数据库网页管理 |

数据库：

- Database: `global_village_auth`
- Username: `global_village_auth`
- Password: `global_village_auth`

> 这些账号密码仅用于本地课程开发。若以后部署到公网，请更换数据库密码与 JWT_SECRET。

## 2. 第一次启动 Auth 数据库

先启动 Docker Desktop，然后在项目根目录运行：

```powershell
docker compose -f docker-compose.auth.yml up -d --build
```

查看状态：

```powershell
docker compose -f docker-compose.auth.yml ps
```

测试 Auth API：

```powershell
curl.exe http://localhost:3002/health
```

正常应返回：

```json
{"ok":true,"service":"global-village-auth-api"}
```

## 3. 本地启动 Flutter Web

```powershell
flutter pub get
```

Google 登录需要 Web OAuth Client ID：

```powershell
flutter run -d chrome --web-hostname localhost --web-port 7357 --dart-define=GOOGLE_WEB_CLIENT_ID=848686154651-a5lrjn63ggqj83g5ob4bms7imqd6jkth.apps.googleusercontent.com --dart-define=AUTH_API_BASE_URL=http://localhost:3002
```

`AUTH_API_BASE_URL` 不填写时，当前代码默认 Web 使用 `http://localhost:3002`；Android 模拟器默认使用 `http://10.0.2.2:3002`。

## 4. 当前已实现的账号功能

- 普通注册写入 PostgreSQL
- Email/Username + Password 登录
- 错误账号或密码会被拒绝
- 重复 Email/Username 无法再次注册
- 密码使用 bcrypt hash 保存，不保存明文密码
- Google 登录后由后端验证 ID Token，再写入/更新 `users`
- 同一个 Google 账号重复登录不会重复创建记录
- 本地账号与同 Email 的 Google 身份可关联成同一条用户记录
- 登录成功后保存 JWT 与用户信息到 Flutter `SharedPreferences`

## 5. 查看 Auth 数据库

浏览器打开：

```text
http://localhost:8082
```

Adminer 登录：

- System: `PostgreSQL`
- Server: `auth-db`
- Username: `global_village_auth`
- Password: `global_village_auth`
- Database: `global_village_auth`

然后打开 `users` 表。

也可以直接进入 psql：

```powershell
docker exec -it global-village-auth-db psql -U global_village_auth -d global_village_auth
```

查看用户：

```sql
SELECT id, full_name, username, email, auth_provider, google_sub, created_at, last_login_at
FROM users
ORDER BY created_at DESC;
```

## 6. 停止/再次启动

停止（保留数据）：

```powershell
docker compose -f docker-compose.auth.yml stop
```

再次启动：

```powershell
docker compose -f docker-compose.auth.yml start
```

移除容器但保留 volume：

```powershell
docker compose -f docker-compose.auth.yml down
```

重新创建：

```powershell
docker compose -f docker-compose.auth.yml up -d --build
```

### 不要随便执行

```powershell
docker compose -f docker-compose.auth.yml down -v
```

`-v` 会删除 Auth 的 PostgreSQL volume，也就是删除已经注册的用户数据。

## 7. 数据库结构文件

项目额外包含：

```text
auth-database/auth_schema.sql
```

它只包含 `users` 表结构和索引，不包含任何真实测试用户数据。

通常不需要手动导入，因为首次启动 `docker-compose.auth.yml` 时会自动执行：

```text
auth-server/db/init.sql
```

## 8. 忘记密码与真实邮件

`Forgot Password` 已接入 Auth API 和 PostgreSQL，使用 QQ SMTP 发送验证码并在验证成功后更新密码。请先按 `QQ_EMAIL_RESET_SETUP.md` 填写 `.env` 并重建认证服务。真实投递需要你自己的 QQ 邮箱 SMTP 授权码。纯 Google 登录账号继续使用 Google 登录。

Firebase Hosting 上的网页也无法直接访问某台个人电脑上的 `localhost:3002`。若最终要让老师手机/其他电脑通过公网网站注册登录，需要把 Auth API + PostgreSQL 部署到公网，然后把 `AUTH_API_BASE_URL` 改成公网 HTTPS API。

## 9. 两套数据库怎么同时运行

请继续阅读根目录：

```text
DATABASES_START_AND_INTEGRATION_GUIDE.md
```

里面说明 Auth 与 Community 的启动区别，以及两者如何通过 `user_id` / Auth API 进行集成。
