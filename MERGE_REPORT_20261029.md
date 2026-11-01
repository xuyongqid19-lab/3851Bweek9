# Global Village 合并报告（2026-10-29）

## 合并来源

| 压缩包 | 定位 |
|---|---|
| `GlobalVillage_Community_Auth_Merged_20261029.zip` | 最新主线（10-29）：家谱树、附近的人四档范围、社区蓝白改版、密保/找回密码合并、api_config 便携路由、便携版工具 |
| `GlobalVillage_PublicDemo.zip` | 公网演示分支（基于 10-14 交接包 + 认证功能合并）：完整群聊、好友资料页、群邀请页、抽屉导航、公网演示脚本 |

两包为同一项目的两条团队分支，各有对方没有的功能。本合并以 **20261029 主线为基础**，把 PublicDemo 分支独有的功能全部移植回来，形成功能完整的单一工程 `GlobalVillage/`。

## 从 PublicDemo 恢复的功能（20261029 主线缺失）

1. **群聊（完整链路）**
   - 前端：`lib/services/chat_service.dart`（建群/群消息/邀请/已读/退群/解散 + `fetchAllConversations`）、`lib/models/chat_model.dart`（`groupId`/`memberCount`/`groupCreatorId`/`senderName`）、`lib/pages/chat_detail_page.dart`（群信息、群主判定、拉人建群入口）、`lib/pages/home_page.dart`（单聊+群聊合并列表）、`lib/widgets/chat_widgets.dart`（完整列表/组件）
   - 后端：`chat-server/src/index.js` 的 8 个 `/chat/groups*` 接口 + `chat-server/db/init.sql` 的 `group_chats`/`group_members`/`group_messages` 表
2. **好友资料页**：`lib/pages/friend_profile_page.dart`；配套恢复后端 `auth-server/src/index.js` 的 `GET /auth/users/:id` 接口和前端 `AuthService.fetchUserById`
3. **群邀请页**：`lib/pages/group_invite_page.dart`
4. **抽屉导航**：`lib/widgets/app_drawer.dart`（含改密码、密保管理入口），由 `home_page.dart` 使用
5. **完整主题**：`lib/theme/app_theme.dart` 采用成员超集版（保留渐变色系），20261029 的四个基础色全部包含，双方代码均可编译
6. **公网演示/本地脚本与配置**：`.env.server`（含真实 SMTP/JWT 密钥，仅本机使用，已被 .gitignore 排除，勿提交或外发）、`tools/StartAuthPreview.ps1`、`tools/StartLocal.ps1`、`tools/serve-web.mjs`
7. **历史记录**：`CHECK_AND_HANDOFF_REPORT.md`、`TEAM_MERGE_REPORT.md`、`merge-review/`、`week4.code-workspace`、`*.iml`

## 手工合并（双方改动叠加）的文件

| 文件 | 合并方式 |
|---|---|
| `lib/services/chat_service.dart` | PublicDemo 群聊版 + 20261029 的 `api_config` 便携路由 |
| `lib/services/auth_service.dart` | 20261029 版（含 `fetchMatchCandidates`）+ 恢复 `fetchUserById` |
| `chat-server/src/index.js` | PublicDemo 群聊接口版 + 20261029 的 `HOST` 环境变量 |
| `auth-server/src/index.js` | 20261029 版（含 `/auth/match/candidates`）+ 恢复 `GET /auth/users/:id` |

## 其余差异文件的处理

- 20261029 版更新（直接采用）：`community_page`（四档范围/范围圈/蓝白配色）、`family_page` + family-server 全部（家谱树）、`profile_page`/`profile_model`（密保管理+兴趣匹配）、`nearby_people_service`、测试文件、全部文档、Google Client ID（`848686154651-...`，当前有效配置）、`docker-compose.*`、启动脚本
- 未采用 PublicDemo 生成物：`.flutter-plugins-dependencies`、`.flutter-run-stdout.txt`、`.flutter-run-stderr.txt`（可由 `flutter pub get` 再生）

## 验证结果（本机实测）

| 检查 | 结果 |
|---|---|
| `flutter pub get` | 通过（pubspec.lock 与原版完全一致） |
| `flutter analyze` | 0 错误 0 警告（仅 4 条两版共有的 info 级 lint） |
| `flutter test` | **82/82 全部通过** |
| auth-server `npm test` | **45 通过**，1 项需真实服务的集成测试按预期跳过 |
| family-server `npm test` | **35/35 通过** |
| 全部 JS（含 tools/portable）`node --check` | 通过 |
| Dart import / AppTheme / ChatService / AuthService 交叉引用一致性 | 通过 |

## 注意事项

- **中文路径限制**：当前文件夹路径含中文时，`flutter analyze` 等工具会崩溃（LSP 路径解析 bug，项目文档亦有记载）。如需运行/构建，请把 `GlobalVillage/` 复制到纯 ASCII 路径，或使用 `tools/portable/short-path.ps1`。本次验证即通过 ASCII 路径副本完成。
- `.env.server` 含真实密钥：仅本机使用，勿提交、勿随包外发（`.gitignore` 已正确排除）。
- 端口约定不变：Community 3000 / Auth 3002 / Family 3003 / Chat 3004。
- Node 直接跑 family-server 需 24.14+（本机 v24.14.0 满足）。
