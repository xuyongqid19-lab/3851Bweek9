# QQ 邮箱验证码找回密码：配置与使用

## 已经完成什么

原页面只显示“发送成功”和“重置成功”，不会发邮件或更新数据库。现在已接通：

输入注册邮箱 → QQ SMTP 发送 6 位验证码 → 输入验证码和新密码 → 后端验证 → 更新 PostgreSQL 密码 → 返回登录。

- 验证码有效期 10 分钟，60 秒内不能重复发送，每个邮箱每小时最多请求 5 次。
- 同一个 IP 每小时最多请求发送 20 次，每 15 分钟最多校验 100 次。
- 每个验证码最多输错 5 次；重新发送后旧码失效，成功重置后验证码立即失效。
- 数据库只保存带服务端密钥的验证码摘要；新密码用 bcrypt 哈希保存。
- 重置后，旧登录凭证在 Auth API 上失效；依赖 `/auth/me` 的其他服务也会拒绝这些旧凭证。
- Google 登录关联、本地账号和现有用户资料保留。只有 Google 登录、未设置本地密码的账号，请继续使用 Google 登录。
- 原先没有实现验证的“Security Question”找回入口已移除；注册时保存的安全问题数据仍保留。

**交付时未配置你的 QQ 邮箱授权码，因此还没有向你的真实邮箱发送测试邮件。请完成下面的配置。**

## 1. 把改动放入原项目

推荐先备份原项目代码，再从新项目中合并以下文件；如果你后来修改过同一文件，请比较后合并。

```text
docker-compose.auth.yml
.env.example
.gitignore
auth-server/package.json
auth-server/package-lock.json
auth-server/pnpm-lock.yaml
auth-server/Dockerfile
auth-server/.dockerignore
auth-server/src/index.js
auth-server/src/password-reset.js
auth-server/src/mailer.js
auth-server/src/reset-schema.sql
auth-server/src/check-smtp.js
auth-server/test/password-reset.test.js
lib/services/auth_service.dart
lib/pages/forgot_password_page.dart
test/forgot_password_page_test.dart
QQ_EMAIL_RESET_SETUP.md
```

`.gitignore` 如已存在，请合并新增规则。保留你自己的 Google Client ID、数据库连接配置和 JWT_SECRET；`docker-compose.auth.yml` 的新增内容是 6 个 SMTP/验证码相关环境变量。

认证服务启动时自动执行 `reset-schema.sql`，为现有用户表添加 `session_version`，并创建 `password_reset_codes`、`auth_rate_limits` 表。重复启动不会删除原数据，也不需要重新创建数据库。

## 2. 在 QQ 邮箱开启 SMTP

登录你准备作为“发件人”的 QQ 邮箱，在设置中的账户或账号安全区域找到 POP3/IMAP/SMTP 服务，开启 SMTP，并按页面要求生成授权码。入口名称可能随 QQ 邮箱版本变化；可在 [QQ 邮箱帮助中心](https://service.mail.qq.com/) 搜索“授权码”。

授权码供程序登录 SMTP 使用，请只填入你电脑上的 `.env` 文件。不要把它放进 Flutter 代码、Git、截图或聊天消息。

这个 QQ 邮箱是统一的发件邮箱。用户填写的是自己注册账号时使用的收件邮箱，收件邮箱可以是 QQ、Gmail、163 等，不必和发件邮箱相同。

## 3. 填写项目根目录的 `.env`

在包含 `docker-compose.auth.yml` 的目录打开 PowerShell。首次配置时执行：

```powershell
Copy-Item .env.example .env
notepad .env
```

如果原项目已有 `.env`，请直接编辑并加入下面这些变量，不要覆盖原文件。

```dotenv
SMTP_HOST=smtp.qq.com
SMTP_PORT=465
SMTP_SECURE=true
SMTP_USER=你的QQ号@qq.com
SMTP_PASS=QQ邮箱生成的SMTP授权码
RESET_CODE_SECRET=你自己生成的随机密钥
```

`RESET_CODE_SECRET` 至少 32 个字符。可在 PowerShell 运行以下命令生成，将结果复制到该项：

```powershell
$resetKeyBytes = New-Object byte[] 32
$resetKeyGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$resetKeyGenerator.GetBytes($resetKeyBytes)
[Convert]::ToBase64String($resetKeyBytes)
$resetKeyGenerator.Dispose()
```

保持这份密钥固定；更换它会使已发送的验证码无法继续验证。配置文件应命名为 `.env`，不要保存成 `.env.txt`。

SMTP 主机 `smtp.qq.com`、465 端口和 TLS 配置与 [Nodemailer 的 QQ 服务配置](https://nodemailer.com/smtp/well-known-services) 一致。加密连接实现参见 [SMTP transport 文档](https://nodemailer.com/smtp)。

## 4. 更新并检查认证服务

启动 Docker Desktop，在项目根目录执行：

```powershell
docker compose -f docker-compose.auth.yml up -d --build auth-api
docker compose -f docker-compose.auth.yml exec auth-api npm run check:smtp
```

第一条命令会构建并更新认证服务，同时启动它依赖的数据库。沿用原 Compose 项目名和数据卷。**不要执行 `down -v`，该选项会删除原有数据库数据。**

第二条命令只检查 QQ SMTP 连接与授权，不发送邮件。看到下列提示说明连接和认证通过：

```text
SMTP connection and authentication succeeded. No test email was sent.
```

检查服务是否正常：

```powershell
curl.exe http://localhost:3002/health
```

更新 `.env` 后，需要再次运行上述 `up -d --build auth-api`，让容器使用新的环境变量；仅在电脑上保存文件不会自动更新运行中的容器。

如果不使用 Docker、直接在电脑运行 Node，需要 Node 20.6 或更新版本，并显式加载根目录配置：

```powershell
cd auth-server
npm ci
node --env-file=../.env src/check-smtp.js
node --env-file=../.env src/index.js
```

直接运行还需保留你原来的 `DATABASE_URL`、`GOOGLE_WEB_CLIENT_ID`、`JWT_SECRET` 设置。Node 默认端口为 3001；原 Docker 对外端口为 3002，Flutter 的 `AUTH_API_BASE_URL` 需与实际端口对应。

## 5. 在应用中验收

重新运行 Flutter，继续使用你原来的 Google Client ID 和启动方式。

1. 用自己能收信的邮箱注册一个本地密码账号。现有本地账号也可以，前提是注册邮箱真实可用。
2. 在登录页进入 Forgot Password，填写该账号的注册邮箱，点击 Send Code。
3. 打开发件目标邮箱，在收件箱或垃圾邮件中找到验证码。界面会开始 60 秒倒计时。
4. 填入 6 位验证码、新密码和确认密码，点击 Reset Password。
5. 成功后返回登录页，用新密码登录。旧密码应登录失败。
6. 再次提交同一个验证码应失败；重新发送后只使用最新邮件里的验证码。

为避免直接透露邮箱是否已注册，发送接口的成功文案统一为“如果该邮箱对应有密码的账号，验证码已发送”。不存在的邮箱、纯 Google 账号不会收到重置邮件。

## 常见问题

| 现象 | 排查方法 |
| --- | --- |
| `Password reset email is not configured` | 检查 SMTP_USER、SMTP_PASS、RESET_CODE_SECRET 是否填写；密钥至少 32 字符；重建认证容器。 |
| `EAUTH` 或连接授权失败 | 检查 QQ SMTP 是否开启、授权码是否正确或已撤销、SMTP_USER 是否为生成授权码的邮箱。 |
| `ETIMEDOUT` / `ECONNECTION` | 检查电脑和 Docker 是否能访问 smtp.qq.com:465，以及防火墙/网络限制。 |
| 发送提示成功，但没收到 | 确认该邮箱在 users 表中有本地密码，检查垃圾箱，确认注册邮箱没有拼写错误。SMTP 接收邮件后仍可能延迟或退信。 |
| Too many attempts / HTTP 429 | 等待冷却或限额恢复。多名用户共享同一网络或代理时，也会共享 IP 限额。 |
| Invalid or expired code | 使用最新邮件中的验证码；有效期 10 分钟；输错 5 次或已使用的验证码需重新申请。 |
| 旧登录状态失效 | 重置密码后的预期行为，请重新登录。 |

查看服务日志：

```powershell
docker compose -f docker-compose.auth.yml logs --tail 80 auth-api
```

密码重置的邮件错误日志只记录错误分类，不输出验证码或完整 SMTP 响应。不要公开 `.env` 或容器完整环境信息。

## 测试记录与边界

- 后端：14 项自动测试通过，使用 PGlite 执行 PostgreSQL SQL，覆盖迁移重复执行、密码更新、验证码存储、过期、错误次数、并发重置、限流、Google 关联保留等。
- 邮件：通过本机 SMTP 模拟服务器验证 Nodemailer 的实际发送、收件人、发件人和验证码正文。模拟测试关闭本机 TLS；实际 QQ 配置强制 TLS 并验证证书。
- Flutter：新增 4 项找回密码页面测试，连同原登录启动测试共 5 项通过。
- 当前环境 Docker 服务未运行；未对你的已有数据库进行容器部署，也未使用你的 QQ 账号真实投递。按第 4、5 节完成最终验收。
- 如果以后部署到公网，API 应使用 HTTPS；如有反向代理，应按实际可信代理范围配置 Express，才能正确识别客户端 IP。当前不信任客户端自行填写的转发头。

复跑测试：

```powershell
cd auth-server
npm ci
npm test
cd ..
flutter pub get
flutter test test/forgot_password_page_test.dart test/widget_test.dart
```

其余模块沿用原项目代码，本次没有对这些模块做全面回归。
