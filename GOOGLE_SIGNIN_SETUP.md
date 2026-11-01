# Google Sign-In setup（Web + Android + Auth Database）

Google 登录现已与 Auth API / PostgreSQL 连接。Google 登录成功后，不是直接跳过数据库，而是把 Google ID Token 发送给 Auth API，由后端验证后创建或更新 `users` 记录。

## 1. 安装依赖

```powershell
flutter pub get
```

## 2. Google Cloud Web OAuth

Web OAuth Client 的 Authorized JavaScript origins 至少包含本地演示地址：

```text
http://localhost
http://localhost:7357
```

如果使用 Firebase Hosting，也加入实际 Hosting origin。

当前课程项目使用的 Web Client ID：

```text
848686154651-a5lrjn63ggqj83g5ob4bms7imqd6jkth.apps.googleusercontent.com
```

Client ID 可以出现在前端；不要把 OAuth Client Secret 放进 Flutter 项目或 ZIP。

## 3. 先启动 Auth Database/API

```powershell
docker compose -f docker-compose.auth.yml up -d --build
```

检查：

```powershell
curl.exe http://localhost:3002/health
```

## 4. 本地 Web 运行

```powershell
flutter run -d chrome --web-hostname localhost --web-port 7357 --dart-define=GOOGLE_WEB_CLIENT_ID=848686154651-a5lrjn63ggqj83g5ob4bms7imqd6jkth.apps.googleusercontent.com --dart-define=AUTH_API_BASE_URL=http://localhost:3002
```

流程：

```text
Google button
→ Google account authentication
→ Flutter obtains ID Token
→ POST http://localhost:3002/auth/google
→ Auth API verifies ID Token
→ create/update users row
→ return JWT + user
→ HomePage
```

## 5. Android

Android OAuth credential仍需配置：

```text
Package name: com.example.global_village_app
SHA-1: 使用 android/gradlew.bat signingReport 获取
```

Android 模拟器访问电脑 Auth API 时使用：

```text
http://10.0.2.2:3002
```

代码默认已对应这个端口。

## 6. 注意

- 同一个 Google `sub` 不会重复创建用户。
- 如果同 Email 已有普通账号，Google 登录会关联现有用户。
- Google 用户不保存 Google 密码。
- Firebase Hosting 想真正保存到数据库时，需要公网 Auth API/PostgreSQL，不能依赖开发者电脑 localhost。
