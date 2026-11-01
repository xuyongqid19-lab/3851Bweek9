# Global Village - Development Handoff
16 October 2026

## Baseline and scope
This source-only delivery combines the teammate package `GlobalVillage-Team-Merged-Final(2).zip` with the completed Family updates. The latest local working files, including the portable Chat URL correction, are included. Start here rather than using older progress reports. App text added by this work is English.

## Updates
- Family supports multiple groups per user, create/join forms with real name and family role, a primary group, summary cards, activities, manual daily check-ins, member management and a combined recent-update feed.
- Added group-level Family trees: a separate connection code, target preview, relationship label, explicit consent, and requests approved by every affected group's administrator. Requests can be rejected/cancelled and expire after seven days; role, code and topology changes invalidate affected pending requests.
- Added a Family tree entry on the Family page/settings, Tree/Requests/Manage views and a full-screen connection canvas with drag, pinch/zoom, Show all and group details. Connections do not grant access to another family's private records. Administrators can disconnect their group's links; owners can leave the tree. The maximum connected component is 50 groups. Updates require refresh.
- Added SQLite tree tables and transactional approval/disconnection, retaining existing Family records. Added backend and Flutter coverage for permissions, consent, graph rules and the canvas.
- Preserved the incoming Auth, Chat, Community, Profile and recommendation business features. Server entry points accept an optional HOST for local-only tests. API URL resolvers retain opt-in PORTABLE_WEB routing; Chat now uses the same-origin proxy too, avoiding a fixed developer port. Normal development defaults remain unchanged.
- Updated the optional portable builder/supervisor to include the Chat database/service and current Auth dependencies. This ZIP contains their source scripts, not a ready-to-run portable distribution.

## Main files
- `lib/pages/family_page.dart`: Family dashboard and navigation.
- `lib/pages/family_tree_page.dart`, `family_tree_canvas_page.dart`: tree workflow and large canvas.
- `lib/models/family_tree.dart`, `lib/services/family_service.dart`: models and authenticated API calls.
- `family-server/src/tree-store.js`: consent state machine, permissions and graph persistence; `store.js`/`app.js`: lifecycle integration and routes.
- `lib/services/api_config.dart`, `chat_service.dart`, `tools/portable/`, `tools/BuildPortable.py`: optional portable routing and launcher support.
- `DOCUMENTATION.FAMILY.TREE01.1.md` and `DOCUMENTATION.FAMILY.PLN01.1.md`: detailed feature specifications.

## Run from source
Install Flutter and Docker Desktop. From the project root, run each command:

```powershell
docker compose -f docker-compose.yml up -d --build
docker compose -f docker-compose.auth.yml up -d --build
docker compose -f docker-compose.family.yml up -d --build
docker compose -f docker-compose.chat.yml up -d --build
flutter pub get
flutter run -d chrome
```

Default API ports: Community 3000, Auth 3002, Family 3003, Chat 3004. Use the included example environment files and setup guides for your own configuration. Do not set PORTABLE_WEB=true for this ordinary launch; that option requires the portable reverse proxy. Register fresh local accounts. No developer accounts, passwords or databases are included. Node 24.14+ is required if running the Family backend directly outside Docker. Avoid `docker compose down -v` unless intentionally deleting local test data.

## Validation and remaining limits
Previously passed: 34 Family Flutter tests, 35 Family backend tests, 35 Auth unit/local-SMTP tests and one Auth PostgreSQL integration test. The latest Web release build and targeted Chat analyzer passed. On 16 October, the local source stack passed all four service health checks and an actual Chrome login/Chat/tree-canvas check. An independent portable copy previously passed Chinese/space path startup, tree approval, friend/message flows, duplicate startup and restart persistence. These are recorded results, not a fresh full-suite run for this archive.

Eight Flutter UI test failures were reproduced in the incoming teammate baseline: three security-question recovery tests, four email-recovery tests and one Profile/change-password navigation test. They remain unresolved; do not claim the whole app test suite is green. Android devices/APK, external Google OAuth/SMTP and a second physical computer were not verified. This is a family-group graph, not individual genealogy or live cross-family chat.

## Delivery contents
Flutter/Android/Web source, all four backend sources, SQL schemas, dependency lockfiles, tests, configuration examples and setup scripts. Excludes SDKs/runtimes, installed dependencies, generated builds, databases, real environment files, Git metadata, presentations and screenshots. Install dependencies before running. Existing setup documents are retained for reference; this dated handoff describes the current delivery.
