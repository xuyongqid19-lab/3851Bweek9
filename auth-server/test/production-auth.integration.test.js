import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";
import net from "node:net";
import pg from "pg";
import jwt from "jsonwebtoken";

// Never run against the project database. This opt-in test uses a disposable database.
const databaseUrl = process.env.AUTH_TEST_DATABASE_URL;
const secret = "isolated-integration-test-jwt-secret";
let pool, child, baseUrl;
const createdIds = [];
async function request(path, body, token, method = "POST") {
  const response = await fetch(`${baseUrl}${path}`, {
    method, headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  return { status: response.status, body: await response.json() };
}
before(async () => {
  if (!databaseUrl) return;
  if (new URL(databaseUrl).pathname !== "/gv_auth_test") throw new Error("Only isolated gv_auth_test is allowed.");
  pool = new pg.Pool({ connectionString: databaseUrl });
  const reservation = net.createServer();
  reservation.listen(0, "127.0.0.1");
  await once(reservation, "listening");
  const port = reservation.address().port;
  await new Promise((resolve) => reservation.close(resolve));
  baseUrl = `http://127.0.0.1:${port}`;
  child = spawn(process.execPath, ["src/index.js"], {
    cwd: fileURLToPath(new URL("..", import.meta.url)), windowsHide: true,
    env: { ...process.env, DATABASE_URL: databaseUrl, PORT: String(port), JWT_SECRET: secret,
      GOOGLE_WEB_CLIENT_ID: "", SMTP_USER: "", SMTP_PASS: "", RESET_CODE_SECRET: "" },
    stdio: ["ignore", "pipe", "pipe"],
  });
  // Drain output without exposing credentials or database parameters.
  child.stdout.resume(); child.stderr.resume();
  for (let attempt = 0; attempt < 100; attempt++) {
    if (child.exitCode !== null) throw new Error("Isolated auth server exited during startup.");
    try { if ((await request("/health", undefined, undefined, "GET")).status === 200) return; } catch (_) {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error("Isolated auth server did not become ready.");
});
after(async () => {
  if (child && child.exitCode === null) { child.kill(); await once(child, "exit"); }
  if (pool) {
    for (const id of createdIds) await pool.query("DELETE FROM users WHERE id = $1", [id]);
    await pool.end();
  }
});

test("real server registration, login, SMTP-independent recovery, JWT revocation, change-password and profile APIs", { skip: !databaseUrl }, async () => {
  const suffix = randomUUID();
  const registration = {
    fullName: "Integration Student", birthDate: "2000-01-01", username: `test-${suffix}`,
    email: `${suffix}@example.com`, phone: "123456789", password: "old-password",
    securityQuestions: [
      { question: "What is your favourite food?", answer: "  Rice  " },
      { question: "What city were you born in?", answer: "London" },
      { question: "What is your childhood nickname?", answer: "Star" },
    ],
  };
  assert.equal((await request("/auth/register", { ...registration, securityQuestions: registration.securityQuestions.slice(0, 2) })).status, 400);
  assert.equal((await request("/auth/register", { ...registration, securityQuestions: [{ question: "Unanswered question?", answer: "" }] })).status, 400);
  const registered = await request("/auth/register", registration);
  assert.equal(registered.status, 201);
  createdIds.push(registered.body.user.id);
  const login = await request("/auth/login", { account: registration.username, password: "old-password" });
  assert.equal(login.status, 200);
  const originalToken = login.body.token;
  assert.equal((await request("/auth/me", undefined, originalToken, "GET")).status, 200);
  assert.equal((await request("/auth/change-password", { currentPassword: "old-password", newPassword: "new-password", confirmNewPassword: "new-password" })).status, 401);
  assert.equal((await request("/auth/forgot-password", { email: registration.email })).status, 503);
  const identified = await request("/auth/security-question/identify", { account: registration.email });
  assert.equal(identified.status, 200);
  assert.deepEqual(identified.body.questions, registration.securityQuestions.map((item) => item.question));
  const verified = await request("/auth/security-question/verify", { challenge: identified.body.challenge, answers: [" RICE ", "London", "Star"] });
  assert.equal(verified.status, 200);
  assert.equal((await request("/auth/security-question/reset", { resetToken: verified.body.resetToken, newPassword: "reset-password", confirmNewPassword: "reset-password" })).status, 200);
  assert.equal((await request("/auth/me", undefined, originalToken, "GET")).status, 401);
  assert.equal((await request("/auth/login", { account: registration.email, password: "old-password" })).status, 401);
  const resetLogin = await request("/auth/login", { account: registration.email, password: "reset-password" });
  assert.equal(resetLogin.status, 200);
  const token = resetLogin.body.token;
  const changeBody = { currentPassword: "reset-password", newPassword: "changed-password", confirmNewPassword: "changed-password" };
  const wrong = await request("/auth/change-password", { ...changeBody, currentPassword: "wrong" }, token);
  assert.equal(wrong.status, 400);
  assert.equal(wrong.body.error, "Current password is incorrect.");
  assert.equal((await request("/auth/change-password", { ...changeBody, confirmNewPassword: "different" }, token)).status, 400);
  assert.equal((await request("/auth/change-password", { ...changeBody, newPassword: "reset-password", confirmNewPassword: "reset-password" }, token)).status, 400);
  const changed = await request("/auth/change-password", { ...changeBody, userId: randomUUID() }, token);
  assert.equal(changed.status, 200);
  assert.equal(changed.body.message, "Password changed successfully. Please sign in again.");
  assert.equal((await request("/auth/me", undefined, token, "GET")).status, 401);
  assert.equal((await request("/auth/login", { account: registration.username, password: "reset-password" })).status, 401);
  const finalLogin = await request("/auth/login", { account: registration.email, password: "changed-password" });
  assert.equal(finalLogin.status, 200);
  const profile = await request("/auth/me", { fullName: "Updated Student" }, finalLogin.body.token, "PATCH");
  assert.equal(profile.status, 200);
  assert.equal(profile.body.user.fullName, "Updated Student");
  assert.equal(profile.body.user.email, registration.email);
  assert.equal((await request("/auth/users/search?q=Updated", undefined, finalLogin.body.token, "GET")).status, 200);
  const googleId = randomUUID();
  createdIds.push(googleId);
  await pool.query("INSERT INTO users (id, full_name, email, auth_provider) VALUES ($1, 'Google Student', $2, 'google')", [googleId, `google-${suffix}@example.com`]);
  const googleToken = jwt.sign({ sub: googleId, version: 0 }, secret, { expiresIn: "5m" });
  const googleResult = await request("/auth/change-password", changeBody, googleToken);
  assert.equal(googleResult.status, 400);
  assert.match(googleResult.body.error, /Google sign-in/);
  assert.equal((await pool.query("SELECT password_hash FROM users WHERE id = $1", [googleId])).rows[0].password_hash, null);
});
