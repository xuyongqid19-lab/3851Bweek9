# Global Village 团队代码合并报告

日期：2026-10-14。

## 合并基础与结果

用户已确认，以实际上传的 `GlobalVillage_PublicDemo_Handoff_20261014_114423.zip` 为主项目，名称不带 `(1)`。功能来源为 `GlobalVillage-Full-Project-Updated.zip`，仅提取认证相关代码及测试。最终交付为完整项目 `GlobalVillage-Team-Merged-Final.zip`。

没有反向使用旧认证项目作为主项目。使用最初 `week4_community_lan_ready_20260923.zip` 作为共同祖先，把“组员主项目”和“认证功能来源”进行三方代码比较，合并五个共享文件。比较时仅在临时副本中统一换行用于判断，交付时保留主项目的换行风格，不批量格式化页面。

组员主项目全部 **146 个原文件路径保留**；其中五个认证共享文件做必要修改，其余 **141 个原文件逐字节一致**。不会把功能来源的 `.dart_tool`、`build`、旧配置、旧模型、旧 Public Demo 或其他页面复制到主项目。原测试文件全部保留。

两项功能均已接入真实认证后端及 PostgreSQL，已在合并后的实际项目服务器上验证密码更新、旧密码失效、新密码登录、旧 JWT 失效；没有模拟成功。

## 新增的认证代码与测试

从功能来源提取八个此前主项目不存在的文件：

| 文件 | 用途 |
|---|---|
| `lib/pages/change_password_page.dart` | 独立修改密码页面，复用现有认证组件及样式。 |
| `auth-server/src/security-question-reset.js` | 独立安全问题识别、答案验证和密码重置服务/路由。 |
| `auth-server/src/security-question-schema.sql` | 兼容已有数据的增量迁移。 |
| `auth-server/src/change-password.js` | JWT 身份、旧密码验证、事务更新及会话失效。 |
| `auth-server/src/password-security.js` | 有界 bcrypt 输入、密码校验、数据库限速、事务和安全错误处理。 |
| `auth-server/test/account-password-security.test.js` | 21 项认证安全测试。 |
| `auth-server/test/production-auth.integration.test.js` | 实际 index.js 服务器的数据库接口集成测试。 |
| `test/account_password_pages_test.dart` | 五项认证页面组件测试。 |

本次另新增 `test/profile_change_password_entry_test.dart`，检查最新版 Profile 在未保存编辑状态下打开 Change Password，再返回时保留输入和页面状态。该组件测试已写入，但因 Flutter 环境问题未运行，不能称为通过。

另外新增 `.env.server.example`、`TEAM_MERGE_README.md`、本报告和 `merge-review/` 中的差异、校验资料。原 `.env.example` 和所有组员配置文件没有覆盖；新增模板不包含私人凭据。

## 五个共享文件的代码合并

| 文件 | 双方差异和合并方式 |
|---|---|
| `lib/pages/profile_page.dart` | 双方均有改动。保留组员的远程资料 setState 刷新、withValues 样式更新、兴趣/匹配/推荐和 Edit 逻辑；只把认证分支的 import 和 Change Password 按钮、Navigator 跳转加入新版。新增 14 行、删除 0 行。 |
| `lib/pages/forgot_password_page.dart` | 主项目与共同祖先内容一致；加入来源分支的方式切换、问题/答案/凭证状态及重置步骤。原邮件发送、倒计时和邮箱重置方法原样保留，邮件 UI 作为独立选择继续使用。 |
| `lib/pages/register_page.dart` | 主项目与共同祖先一致；仅加入问题/答案同时填写或同时留空的两处验证。四个问题、其他注册 UI 和请求逻辑保留。 |
| `lib/services/auth_service.dart` | 主项目与共同祖先一致；局部加入 identifySecurityQuestion、verifySecurityAnswer、resetPasswordWithSecurityQuestion、changePassword，并给原请求方法增加可选认证请求头。原 Google、登录、注册、邮箱重置、Profile 请求均保留。 |
| `auth-server/src/index.js` | 主项目与共同祖先的代码内容一致；只加入两个路由模块注册、注册配对校验、新表检查及过期挑战清理。原 JWT 中间件、Google、邮箱重置、用户资料和搜索路由保留。 |

三方合并没有留下冲突标记。Profile 是双方同时修改的重点文件，其改动不在同一代码块，按“保留组员主体，仅插入入口”解决。其余四个文件没有团队语义冲突，仍通过代码差异合并认证增量，没有用旧文件未经比较覆盖新版。

## 明确保留的组员代码

- `lib/models/profile_model.dart` 完全采用主项目最新版，数据结构、年龄/日期和匹配相关逻辑没有修改。
- 所有聊天、社区、活动、家庭、兴趣匹配、推荐及相关服务/模型/页面均采用主项目版本。
- `public-gateway/nginx.conf`、`public-gateway/proxy_params`、`docker-compose.public.yml`、Public Demo 开始/停止脚本及 `PUBLIC_DEMO.md` 完整保留。
- 全部原 Docker、依赖配置、锁文件、启动脚本、数据库 SQL、认证邮件模块及测试文件逐字节保留。
- `auth-server/src/password-reset.js` 未修改；QQ 邮箱验证码流程和 SMTP 模块未被安全问题流程替代。
- 不复制认证来源项目的构建缓存、私密配置、旧个人资料模型或旧组员功能。没有重构无关模块，也没有为了测试删代码或删测试。

## 后端连接与数据库兼容

安全问题流程是：邮箱或用户名 → 后端查找/挑战 → trim + lowercase → bcrypt.compare → 五分钟一次性重置凭证 → PostgreSQL 事务验证、更新 bcrypt 密码哈希、增加 session_version → 返回登录。未知、未配置、Google-only 账号使用通用响应，不能凭备用问题创建本地密码。凭证在数据库中只存哈希，失败五次临时限制十五分钟，另有 IP 请求限速，事务防止并发重复消费。

修改密码流程是：现有 Bearer JWT → 原 requireAuth → 用户行锁下复核 session_version → bcrypt 验证旧密码 → 拒绝新旧相同/确认不同/长度不符 → PostgreSQL 更新并增加 session_version → 前端清除 auth_token/auth_user → LoginPage。后端失败不显示成功，不能修改 JWT 所属用户以外的账号。Google-only 用户得到继续使用 Google 的提示。

新增迁移 `auth-server/src/security-question-schema.sql` 只建立挑战/凭证表和索引；服务启动时尝试自动执行。无建表权限时，由现有数据库所有者执行该 SQL 后重启认证服务。复用原 `reset-schema.sql` 的 session_version 和 auth_rate_limits。没有清空、重建、覆盖或实际访问团队项目数据库，也没有改动现有安全问题哈希。

不需要新增生产环境变量或 SMTP 授权码。应在自己的电脑上恢复主项目原来的 `.env` / `.env.server`。Public Demo 已有 `/auth/` 路径转发，可承接新接口，网关配置没有修改。为保留原代理信任规则，后端继续按连接 IP 限速；公共网关下多个访问者可能共享该 IP 级限制，账号错误计数仍独立。

## 本次在合并版运行的测试

| 检查 | 结果与范围 |
|---|---|
| auth-server npm test | 35 项通过、0 失败；包括 21 项新功能和原 14 项邮箱重置回归；真实服务器测试在默认命令中按设计跳过。 |
| 隔离 PostgreSQL 18.4 | 合并版的 21 项安全测试全部通过，使用真实 pg.Pool 多连接，验证并发、过期、单次使用、限速、长输入兼容及事务回滚。 |
| 合并版实际 index.js 集成测试 | 1 项通过：注册/登录、未登录拒绝、SMTP 不可用时独立找回、旧密码及旧 JWT 失效、新密码登录、修改密码、Profile 读取/更新、用户搜索及 Google-only 提示。 |
| 组员 Family 原测试 | 16 项通过、0 失败，未修改该模块。 |
| 全部后端 JS 语法 | 17 个文件通过 node --check；四个 package.json 可解析。 |
| 五套 Docker Compose | 认证、社区、聊天、Family、Public Demo 配置均通过 config --quiet 解析。 |
| Dart 静态语法 | 46 个前端/测试 Dart 文件解析通过；这是 Tree-sitter 语法检查，不是 Flutter 类型分析或编译。 |
| 原文件与合并范围 | 146 个主项目文件路径均保留；141 个非共享文件完全一致；Profile 只新增 14 行；原邮件三个关键方法及原后端逐字保留；原测试均保留。 |

**未实际验证：** Flutter analyze、Flutter test、Flutter Web 页面及 Android，因为本机 Flutter SDK 在启动阶段报 `Failed to canonicalize path ... OS error (5)`，检查没有运行到项目阶段。所有组件测试（包括新增 Profile 返回状态测试）因此不能算通过。

Docker 引擎连接被本环境命名管道权限拒绝，未运行容器整栈、真实 Nginx、Cloudflare 隧道或公开演示发布。Compose 解析和路径保留不等于公开部署成功。真实 Google OAuth、QQ SMTP 及聊天/社区/活动/推荐界面端到端没有执行。Google-only 账号测试不等于实际 Google 登录验证；邮件本地 SMTP 测试不等于真实 QQ 发送。

组员原 `StartPublicDemo.ps1` 的 Web 构建命令没有传入 GOOGLE_WEB_CLIENT_ID，而 LoginPage 使用该构建参数。该既有配置原样保留，不作为此次认证合并的改动。若在公开域名展示 Google 登录，需要本地补齐对应 OAuth 构建参数和授权来源配置，运行说明已注明；本报告不声称该公开 Google 流程已经验证通过。

## 运行及交付

解压完整 ZIP 后进入 `GlobalVillage_PublicDemo`，先看 `TEAM_MERGE_README.md`，恢复本地配置、安装依赖、完成必要迁移并从更新源码构建。Public Demo 继续使用组员原脚本。

`merge-review/profile-page.diff` 展示 Profile 唯一新增代码；`git-diff-stat.txt` 展示认证代码范围；`merge-preservation.json` 与 `shared-file-comparison.json` 记录保护检查及三方比较。`MERGE_MANIFEST.json` 记录来源 ZIP 的 SHA-256、交付文件哈希及完整性。
