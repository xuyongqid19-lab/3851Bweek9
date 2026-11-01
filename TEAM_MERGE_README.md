# Global Village 团队合并版运行说明

本项目以你确认的组员最新版 `GlobalVillage_PublicDemo_Handoff_20261014_114423.zip` 为基础，保留 Public Demo、聊天、社区、活动、个人资料、兴趣匹配及推荐代码，再以代码合并方式加入安全问题找回和登录后修改密码。不是旧项目覆盖版，也不是更新文件补丁包。

完整合并说明、文件清单、冲突处理及测试结果见 `TEAM_MERGE_REPORT.md`。逐文件完整性校验见 `merge-review/MERGE_MANIFEST.json`。

## 恢复本地私密配置

本包没有包含真实 `.env` 或 `.env.server`。不要从旧功能来源 ZIP 复制环境配置；在自己电脑上恢复组员主项目原来的私密配置即可。

- Public Demo 和原数据服务脚本需要项目根目录 `.env.server`。优先在本地复制你自己的现有文件；没有文件时可把新增 `.env.server.example` 复制为 `.env.server`，填写自己的 SMTP_USER、SMTP_PASS、RESET_CODE_SECRET、JWT_SECRET。
- 原 `.env.example`、所有 Docker 文件保持组员版本不变。新增模板不包含真实邮箱授权码、数据库密码或 JWT 密钥。
- 已有数据库继续使用原账号、密码、数据库名和数据卷。Docker 连接地址沿用组员配置，不会因新增模板而自动改变数据库密码。
- 如果直接运行认证 Node 进程，使用主项目原有 `.env` 或进程环境提供 DATABASE_URL、JWT_SECRET、PORT 等。项目已有 load-env 逻辑保持不变。
- 两个新功能不需要额外生产环境变量或新的 SMTP 授权码。安全问题独立找回、登录后修改密码不依赖 SMTP；邮箱验证码找回继续依赖原 QQ SMTP 配置。
- 保持原 JWT_SECRET 和 RESET_CODE_SECRET，可继续使用原配置。模板 REPLACE/your 值必须由你自己替换，不能直接使用。

## 数据库增量迁移

新增脚本：`auth-server/src/security-question-schema.sql`。

认证服务启动时检查新表，缺失时尝试自动执行该 SQL。它仅新增安全问题挑战/一次性凭证表及索引，不删除用户，不覆盖原安全问题及答案哈希。继续复用原 session_version、auth_rate_limits、bcrypt 和 PostgreSQL 事务。

数据库运行账号没有建表权限时，由数据库所有者在现有认证数据库执行该脚本后重启认证服务。原 `reset-schema.sql` 提供的基础认证结构如已存在，无需重复操作。不要清空数据库、重新建立 users 或删除原 Docker 数据卷。

## 本地运行

安装原项目需要的 Flutter、Chrome、Docker Desktop/Compose；若直接运行 Family 后端，Node.js 需满足原模块的 24.14 或更高版本要求。依赖配置和锁文件没有改变。

在项目根目录填好配置并启动 Docker Desktop后执行原服务启动方式。需要启动完整的四套后端时，可分别执行：

```powershell
docker compose --env-file .env.server -f docker-compose.auth.yml up -d --build
docker compose -f docker-compose.yml up -d --build
docker compose --env-file .env.server -f docker-compose.chat.yml up -d --build
docker compose --env-file .env.server -f docker-compose.family.yml up -d --build
flutter pub get
.\RunWeb.cmd
```

前端从更新后的源码构建。认证、社区、Family、聊天继续使用主项目原来的 3002、3000、3003、3004 端口，Web 使用原来的 7357。Android 服务地址按原模拟器/局域网配置设置，Android 本次未实际运行。

## Public Demo

`public-gateway/`、`docker-compose.public.yml`、`StartPublicDemo.*`、`StopPublicDemo.*` 和 `PUBLIC_DEMO.md` 全部保留组员原始内容。恢复 `.env.server`、准备 Docker 与 cloudflared 后，仍按 `PUBLIC_DEMO.md` 使用 `StartPublicDemo.cmd`。脚本会重建 Flutter Web，使用当前公开地址作为各服务的基础地址。

网关已有 `/auth/` 转发，可以承接新增加的安全问题和修改密码路径；不需要重新设计网关。此次没有创建公开隧道、公开发布站点或更改组员的部署设置。

**已有 Google 演示配置限制：** 组员原 Public Demo 构建脚本没有传入 `GOOGLE_WEB_CLIENT_ID`，而 LoginPage 从该构建参数读取 Client ID。该脚本原样保留；若要在公开域名展示 Google 登录，需要在本地完成相应 OAuth 授权来源配置，并在 Web 构建时加入与认证后端一致的公开 Client ID。临时演示域名也需要符合你自己的 OAuth 配置。本次没有真实 Google OAuth 运行验证，不声称公开 Google 登录已验证通过。

## 新功能手动检查

1. 注册时问题和答案同时填写，或同时留空；仅填其中一个应被拒绝。
2. Login → Forgot Password，分别选择 Email Verification 和 Security Question。邮件方法继续使用六位码；安全问题方法输入邮箱或用户名、回答问题、设置新密码，全程不要求邮件验证码。
3. 答错不能进入密码更新；连续五次失败临时限制十五分钟。凭证五分钟有效、只能使用一次；切换方式清除敏感输入。
4. 重置后旧密码不能登录，新密码可以登录；旧 JWT 调用受保护接口被拒绝。
5. 登录 → Profile → My Profile → Change Password，测试错误旧密码、新旧相同、确认不同、长度超限；失败不显示成功。正确修改后清除本地登录并返回 Login。
6. 在 Profile 编辑姓名但不保存，进入 Change Password 后返回，检查未保存输入和页面状态仍在。Edit、Interest Match、Recommended、聊天、社区及活动继续使用主项目页面。
7. 用 Google-only 账号验证修改密码提示，不应因此创建新的本地密码。

## 本地补做检查

```powershell
flutter analyze
flutter test
Push-Location auth-server
npm ci
npm test
Pop-Location
Push-Location family-server
npm test
Pop-Location
```

`AUTH_TEST_DATABASE_URL` 只用于测试，并且必须是独立可清空的 `gv_auth_test`。不要连接团队项目数据。真实 PostgreSQL 测试和真实服务器测试应分开运行，避免测试表相互清理；生产运行不需要该变量。

本次实际测试情况见合并报告。没有为通过测试删除组员的代码或测试文件；没有把静态语法检查当作 Flutter 编译、界面或公开部署成功。
