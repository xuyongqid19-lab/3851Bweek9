# Family 多家庭群组功能策划案

Version: 0.6. Updated: 2026-10-15. FAM01–FAM12 are implemented, including the expanded Family tree canvas. The [Family Tree specification](DOCUMENTATION.FAMILY.TREE01.1.md) was completed and shown before implementation. Current validation and inherited teammate issues: [Family Tree review](DOCUMENTATION.FAMILY.TREE01.REVIEW.md). Previous portable delivery: [DOCUMENTATION.INTEGRATION.0916.md](DOCUMENTATION.INTEGRATION.0916.md).

本方案将现有单家庭演示升级为多家庭管理：用户可以创建和加入多个家庭，在每个家庭登记自己的真实姓名和亲属称谓；首页优先展示主要家庭的活动、打卡和成员状态，下方按群组汇总其他家庭的最近消息。本文是本项目 Family 产品范围、需求编码和开发进度的当前统一入口，不代表整个课程项目的总策划。

## 1 范围和规范

需求来源：用户本次关于创建、加入、多家庭管理、主要家庭和消息首页的要求。下文标注“建议”的规则是本版设计默认值，可在后续需求变化时调整。

采用用户提供的《开发标准.Ver0.1.docx》（GDL01.4，verFTB 1.4）和《节源开流准则.Ver0.1.docx》（EFF01.4，ver1.4）的开发流程、最小上下文、预算、验证和真实性要求。原文件属于 FTB 项目，其中 Windows 陪伴对象、Inochi2D、语音及私人素材授权等产品专属内容不迁移到 COMP3851；当前产品目标以用户的 Family 要求为准。

两份 DOCX 声明另有权威 Markdown，但该源未随本项目提供；当前采用所提供发行物，不虚构原版 Markdown，也不改写来源文件。最小权威集为两份准则、本文和本次目标源码；不另建重复进度总表。规则来源保留在用户本次附件中。

0.1 为策划文档任务；本次 0.2 为用户授权的三小时整合与开发任务，涉及 Flutter、账号边界和持久化，采用跨区完整验证。保留组员源包和原项目备份，以新版 Auth/Community 包为合并主版本。阶段预算及实际验证统一记录在 DOCUMENTATION.INTEGRATION.0909.md；不将文档检查替代代码、后端或平台验证。

## 2 现有基础

代码证据：[Family 页面](lib/pages/family_page.dart)、[群组模型](lib/models/family_group.dart)、[API 服务](lib/services/family_service.dart)、[Family 存储](family-server/src/store.js)、[首页入口](lib/pages/home_page.dart)。

原版包含单家庭详情、任务、健康备注和活动，使用静态 ValueNotifier 与示例数据。本版已改为账号验证后的 Family API 与 SQLite 持久化；旧 family_model.dart 留作原版参考，当前页面不调用其示例数据。账号与社区沿用组员的 PostgreSQL 服务；Family 使用独立数据库，复用 Auth /auth/me 返回的稳定 userId。

## 3 功能编码和范围

| 编码 | 功能 | 本版目标 | 当前状态 |
| --- | --- | --- | --- |
| FAM01 | 创建家庭 | 创建表单、身份登记、成为群主 | 已实现 |
| FAM02 | 加入家庭 | 邀请码、家庭预览、身份登记、加入结果 | 已实现 |
| FAM03 | 多家庭和设置 | 群组切换、独立权限、设置主要家庭 | 已实现 |
| FAM04 | Family 首页 | 主要家庭摘要、其他家庭消息列表 | 已实现 |
| FAM05 | 家庭详情衔接 | 活动、任务、成员、备注按群组隔离 | 已实现；增加本人手动每日打卡 |
| FAM06 | 数据与验证 | 持久化、失败状态、跨群隔离测试 | 已实现；详见整合交付记录 |
| FAM07 | Family tree navigation | Group nodes, connected topology, full-screen pan/zoom canvas and Family entry points | Implemented; TREE01 §1–2 |
| FAM08 | Connection proposals | Separate codes, per-group consent and whole-tree merge approvals | Implemented; TREE01 §3 |
| FAM09 | Tree permissions | Current-role enforcement and private-record isolation | Verified; TREE01 §4 |
| FAM10 | Tree lifecycle | Disconnect, leave, branch splitting and family closure | Verified; TREE01 §5 |
| FAM11 | Tree persistence/API | Additive SQLite storage and authenticated routes | Verified; TREE01 §6–7 |
| FAM12 | Tree acceptance | End-to-end, security, persistence and regression checks | Family checks passed; inherited team UI failures recorded in TREE01 review |

首版聚焦这些功能。完整即时聊天、图片上传、运动设备接入、自动打卡执行和推送通知不纳入本次新增范围；已有相关展示仍应保留，并准确显示其实现状态。

## 4 创建和加入子页面

### 创建家庭

入口：Family 首页右上角“＋”→“创建家庭”。

必填：家庭名称、本人真实姓名、在这个家庭中的亲属身份及称谓（如爸爸、爷爷、舅舅）。建议将身份和称谓做为一个“家庭称谓”字段，提供常见选项和“自定义”，避免重复填写同义内容。真实姓名与称谓分别展示，例如“陈建国 · 舅舅”。

家庭简介为选填；本版头像固定使用名称首字占位，不提供图片上传。群组 ID 和邀请码由系统生成，成员数与创建时间自动记录。首版无需收集身份证号、住址等额外资料；必填姓名属于本人填写，不宣称已经完成实名核验。

提交前校验去除空格后的必填项；保存成功后进入新群组详情，失败保留表单并显示重试入口，连续点击不得重复创建。建议创建者默认为群主；用户还没有任何家庭时，首个创建成功的家庭自动成为主要家庭，否则保留原主要家庭。

### 加入家庭

入口：Family 首页“＋”→“加入家庭”→输入邀请码→显示群名、头像与简介→填写真实姓名及该家庭称谓→提交加入。

加入页面必须再次明确显示并确认本人姓名和本群称谓；姓名可从本人资料预填，称谓按群独立填写。预览阶段不展示成员姓名、健康备注、打卡等私密内容。

建议首版使用有效邀请码直接加入，邀请码视为加入凭证，管理员可重置使旧码失效；审批制留作后续扩展。加入成功默认普通成员；同一用户不得重复加入同一群组。无效或失效邀请码显示明确错误，不创建成员记录。首个加入成功的家庭也适用自动设为主要家庭规则。

## 5 多家庭管理和群组设置

一个用户可以同时属于多个家庭，在不同家庭拥有不同称谓和权限，例如在家庭 A 是“爸爸／群主”，在家庭 B 是“舅舅／成员”。亲属身份不决定管理权限。

| 设置 | 普通成员 | 管理员 | 群主 |
| --- | --- | --- | --- |
| 修改自己在本群的称谓 | 可以 | 可以 | 可以 |
| 设为自己的主要家庭 | 可以 | 可以 | 可以 |
| 编辑群名与简介、重置邀请码 | 不可以 | 可以 | 可以 |
| 授予或撤销管理员 | 不可以 | 不可以 | 可以 |

主要家庭是用户个人偏好，不是群组全局标记，也不是管理员专属设置。每位有群组的用户恰有一个主要家庭；设置新主要家庭时同时替换旧选择，不影响其他用户。首页查看另一家庭不会自动改变主要家庭。

建议首版支持退出家庭：普通成员退出前提示确认；群主须先转让群主身份，有其他成员时不得直接退出。最后一名成员可确认退出并关闭空群。若退出主要家庭，按加入时间选择最早的剩余家庭作为主要家庭，并给出提示；没有剩余家庭则进入空状态。退出后不得继续读取该群私密记录。

## 6 首页布局与导航

按用户指定的 Instagram 和 X 消息页方向采用“头像、名称、最新消息、时间、未读提示”的列表结构；这是布局借鉴，不声称复刻这些产品当前版本。整体继续使用项目现有英文界面文案和公共主题。

```text
Family                                  ＋

[头像] Tan Family       主要家庭          设置
       3 位成员 · 我的称谓 Dad
       家庭简介

[近期活动摘要]       点击 → 本群活动列表
[今日打卡摘要]       点击 → 本群打卡任务与记录
[成员状态摘要]       点击 → 本群成员状态

其他家庭
[头像] Chen Family                14:30  ●2
       舅舅创建了周日聚餐
[头像] Grandparents               昨天
       爷爷添加了一条健康备注

           原有底部导航 Family 选中
```

上方主要家庭区域约占首屏上半部，随设备和字体大小自然伸展；页面整体滚动，不固定半屏高度。三个摘要卡片可纵向排列，避免窄屏小字或溢出。卡片分别显示最近一项活动及日期、今日打卡完成概况、成员状态概况；数据没有实际执行来源时显示“暂无打卡记录”，不得把演示状态算成真实完成率。

下方其他家庭每个群组只占一条消息框，不按活动、打卡或成员状态拆成多条。按最新动态时间降序排列；显示群头像、群名、最新一条可见动态摘要、时间和未读数。健康类摘要仅提示“添加了健康备注”，不直接暴露正文。

点击消息框进入该家庭详情，在详情内查看活动、打卡、成员状态和统一动态记录；保留返回首页入口。首版消息指群组内业务动态，不暗示已有即时聊天。打开动态列表后更新该用户在该群的已读位置，其他群未读状态不变。新建活动、任务和备注等成功保存后才生成动态，避免保存失败却出现消息。

空状态：没有家庭时展示“创建家庭／加入家庭”；只有主要家庭时，下方提示“暂无其他家庭”；群组无消息时显示“暂无新动态”。加载显示进度，失败显示错误及重试，不将加载失败伪装成空数据。本版不保存离线私密缓存；表单请求失败时保留当前输入。

## 7 数据与改造方案

保留 Flutter 和原有主导航，不引入大型框架。SQLite 关系如下，具体字段以 store.js 为准。

| 数据 | 关键字段和约束 |
| --- | --- |
| 家庭群组 | id、name、description、invite、createdAt；群主记录在 members.role |
| 家庭成员关系 | groupId、userId、realName、kinshipLabel、permissionRole、joinedAt；groupId 与 userId 唯一 |
| 用户家庭偏好 | userId、primaryGroupId；只能指向本人已加入的群 |
| 群组动态 | id、groupId、summary、createdAt；详情返回最近 100 条 |
| 已读位置 | userId、groupId、lastReadEventId；分别保存 |
| 原有业务记录 | 活动、打卡任务、健康记录增加 groupId；人员关联使用 userId，不使用“爸爸”等称谓作唯一键 |

所有群组读取、修改、导航都携带 groupId，服务端确认当前用户有本群权限。活动详情、成员选择、任务新增和健康备注使用当前群数据。历史示例数据不迁入真实用户家庭；新账号从无家庭状态开始。

FamilyService 集中负责 HTTP 请求，FamilyStore 负责成员关系、偏好和动态事务，页面负责展示与输入。新增 family_group.dart，重写 family_page.dart；home_page.dart、共享主题和 BottomNav 保持组员版本。

Family API 为多个客户端共享的服务端存储，逐请求验证 Auth Bearer token，不接受客户端冒充 userId。两个实际注册账号已通过本机 PostgreSQL/Auth/Community/Family 联调。不同设备须连接同一服务地址；本机回环地址不等同于公网部署。手动每日打卡按 UTC 日期唯一记录，自动登录和运动目标类型只保存配置并标示尚未启用。成员状态代表打卡记录，不代表实时在线、定位或健康诊断。

## 8 开发顺序和验收

阶段一：确认账号和存储条件，完成多群组数据、身份关系、持久化、创建和加入闭环。阶段二：完成个人主要家庭设置、首页摘要和其他家庭消息列表，接通旧页面。阶段三：完成权限、退出、数据隔离、异常恢复和回归验证。涉及账号、后端或持久化边界时重新分类为跨区任务，执行完整验证；不在文档任务中提前宣称这些条件已满足。

验收用例：

1. 创建或加入时缺少真实姓名或家庭称谓不能提交；自定义“舅舅”等称谓可保存，失败后输入仍在。
2. 同一用户加入两个家庭，称谓与权限分别显示；重复加入不增加成员数，无效邀请码不会泄露群组私密内容。
3. 任意已加入家庭可设为个人主要家庭；首页随之更新，始终只有一个主要家庭，其他用户设置不受影响。
4. 三个摘要卡片进入正确家庭的对应子页；在 A 群新增活动、任务或备注不会出现在 B 群。
5. 每个其他家庭始终只有一条消息框，按最新动态排序；进入动态列表后仅该群未读状态更新。
6. 重启后恢复群组、身份、主要家庭和记录；损坏或读取失败显示错误并保护原数据，不静默重置。
7. 普通成员无法越权修改群资料或授予管理员；退出后无权读取原群，主要家庭回退符合规则。
8. 无家庭、单家庭、无动态、窄屏、大字体及失败状态均可操作，原有聊天、社区和个人资料导航不受影响。
9. 若交付真实多用户版，以两个独立账号／客户端验证创建、加入、权限和同步；本地测试替身不能替代此项。

已执行 Family 定向测试、整项目 Flutter 测试、静态分析、Web/APK 构建及权限／离线失败验证。SDK 已部署，具体版本见 DOCUMENTATION.DEVENV.1.md，最终结果及平台限制见 DOCUMENTATION.INTEGRATION.0909.md。

## 9 本次交付状态

本版交付整合源码、Family API、测试及运行说明，FAM01–FAM06 的首版范围已实现。本文各节“建议”规则已作为首版默认行为落地。未承诺即时聊天、推送、头像上传、实名核验、自动或运动设备打卡。后续修改以此整合目录为基准，避免回到旧单家庭演示文件覆盖组员成果。

### Portable validation delivery (16 September 2026)

The user requested integration of `Global_Village_Community_Completed.zip` and a BAT launcher for checking functionality on this and other computers. The Windows x64 portable package runs the actual Web app and Auth/Community/Family services with separate local databases and synthetic demo accounts. A portable build resolves API URLs through a local same-origin proxy. Family scope and server permissions are unchanged. This is a Web preview, not an Android emulator. Requirements, merge decisions and verified limits are maintained in `DOCUMENTATION.INTEGRATION.0916.md`.
