import assert from "node:assert/strict";
import { after, before, beforeEach, test } from "node:test";
import { readFile } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";
import bcrypt from "bcryptjs";
import express from "express";
import nodemailer from "nodemailer";
import { SMTPServer } from "smtp-server";
import { createMailer } from "../src/mailer.js";
import { createPasswordReset, passwordResetRouter, REQUEST_MESSAGE } from "../src/password-reset.js";

const secret = "test-only-secret-".repeat(4);
const email = "student@example.com";
const ip = "127.0.0.1";
let db, pool, service, sent, server, baseUrl;
let deliveryFails = false;
let queue = Promise.resolve();

// PGlite executes real PostgreSQL SQL in-process. Serialize its one connection;
// production uses pg.Pool with the same query/connect/release interface.
async function acquire() {
  const previous = queue;
  let release;
  queue = new Promise((resolve) => { release = resolve; });
  await previous;
  return release;
}
async function query(sql, args) {
  const result = await db.query(sql, args);
  return { ...result, rowCount: result.affectedRows ?? result.rows.length };
}

const mailer = {
  configured: true,
  async sendCode(to, code) {
    if (deliveryFails) throw new Error("Simulated SMTP outage");
    sent.push({ to, code });
  },
};
const latestCode = () => sent.at(-1).code;
async function expireLimits() {
  await pool.query("UPDATE auth_rate_limits SET expires_at = now() - interval '1 second'");
}
async function post(path, body) {
  const response = await fetch(`${baseUrl}/auth/${path}`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json(), headers: response.headers };
}

before(async () => {
  db = new PGlite();
  pool = {
    async query(sql, args) {
      const release = await acquire();
      try { return await query(sql, args); } finally { release(); }
    },
    async connect() { const release = await acquire(); return { query, release }; },
  };
  const schema = await readFile(new URL("../db/init.sql", import.meta.url), "utf8");
  // gen_random_uuid is built into PostgreSQL; PGlite does not need pgcrypto.
  await db.exec(schema.replace("CREATE EXTENSION IF NOT EXISTS pgcrypto;", ""));
  const migration = await readFile(new URL("../src/reset-schema.sql", import.meta.url), "utf8");
  await db.exec(migration);
  await db.exec(migration); // Existing database startup must be repeatable.
  service = createPasswordReset({ pool, mailer, secret });
  const app = express();
  app.use(express.json());
  app.use("/auth", passwordResetRouter({ pool, mailer, secret }));
  app.use((error, _req, res, _next) => res.status(500).json({ error: error.message }));
  server = await new Promise((resolve) => {
    const listener = app.listen(0, "127.0.0.1", () => resolve(listener));
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

beforeEach(async () => {
  sent = [];
  deliveryFails = false;
  await db.exec("TRUNCATE users, password_reset_codes, auth_rate_limits CASCADE");
  await pool.query(
    "INSERT INTO users (full_name, email, password_hash) VALUES ('Student', $1, $2)",
    [email, await bcrypt.hash("old-password", 4)],
  );
});

after(async () => {
  if (server) await new Promise((resolve) => server.close(resolve));
  if (db) await db.close();
});

test("HTTP flow delivers a six-digit code, changes password, invalidates sessions, and consumes code", async () => {
  const request = await post("forgot-password", { email: " STUDENT@EXAMPLE.COM " });
  assert.equal(request.status, 200);
  assert.equal(request.body.message, REQUEST_MESSAGE);
  assert.equal(request.body.retryAfterSeconds, 60);
  assert.equal("code" in request.body, false);
  assert.match(latestCode(), /^\d{6}$/);
  const stored = (await pool.query("SELECT * FROM password_reset_codes")).rows[0];
  assert.notEqual(stored.code_hash, latestCode());
  assert.equal(stored.code_hash.length, 64);
  assert.equal(stored.delivered, true);
  const result = await post("reset-password", { email, code: latestCode(), newPassword: "new-password" });
  assert.equal(result.status, 200);
  const user = (await pool.query("SELECT * FROM users")).rows[0];
  assert.equal(await bcrypt.compare("new-password", user.password_hash), true);
  assert.equal(await bcrypt.compare("old-password", user.password_hash), false);
  assert.equal(user.session_version, 1);
  assert.equal((await pool.query("SELECT * FROM password_reset_codes")).rowCount, 0);
  const replay = await post("reset-password", { email, code: latestCode(), newPassword: "other-password" });
  assert.equal(replay.status, 400);
});

test("unknown and Google-only addresses receive the same response without sending mail", async () => {
  const missing = await post("forgot-password", { email: "missing@example.com" });
  await pool.query("UPDATE users SET password_hash = NULL, auth_provider = 'google'");
  const google = await post("forgot-password", { email });
  assert.equal(missing.status, 200);
  assert.deepEqual(missing.body, google.body);
  assert.equal(sent.length, 0);
});

test("linked Google accounts can reset their existing local password without losing the link", async () => {
  await pool.query("UPDATE users SET auth_provider = 'local+google', google_sub = 'google-subject'");
  await service.requestCode(email, ip);
  await service.resetPassword(email, latestCode(), "new-password", ip);
  const user = (await pool.query("SELECT * FROM users")).rows[0];
  assert.equal(user.google_sub, "google-subject");
  assert.equal(user.auth_provider, "local+google");
});

test("60-second cooldown rejects duplicate and parallel sends", async () => {
  const responses = await Promise.all([post("forgot-password", { email }), post("forgot-password", { email })]);
  assert.deepEqual(responses.map((r) => r.status).sort(), [200, 429]);
  assert.equal(sent.length, 1);
  assert.equal(responses.find((r) => r.status === 429).headers.get("retry-after"), "60");
});

test("five wrong guesses lock this code even if the next guess is correct", async () => {
  await service.requestCode(email, ip);
  const wrong = latestCode() === "000000" ? "111111" : "000000";
  for (let attempt = 0; attempt < 5; attempt++) {
    await assert.rejects(service.resetPassword(email, wrong, "new-password", ip), { status: 400 });
  }
  assert.equal((await pool.query("SELECT attempts FROM password_reset_codes")).rows[0].attempts, 5);
  await assert.rejects(service.resetPassword(email, latestCode(), "new-password", ip), { status: 400 });
});

test("expired and not-yet-delivered codes cannot reset a password", async () => {
  await service.requestCode(email, ip);
  await pool.query("UPDATE password_reset_codes SET delivered = false");
  await assert.rejects(service.resetPassword(email, latestCode(), "new-password", ip), { status: 400 });
  await pool.query("UPDATE password_reset_codes SET delivered = true, expires_at = now() - interval '1 second'");
  await assert.rejects(service.resetPassword(email, latestCode(), "new-password", ip), { status: 400 });
});

test("a reissued code invalidates the old code", async () => {
  await service.requestCode(email, ip);
  const oldCode = latestCode();
  await expireLimits();
  await service.requestCode(email, ip);
  // Random codes can coincide; force a distinct second request if that occurs.
  if (latestCode() === oldCode) { await expireLimits(); await service.requestCode(email, ip); }
  assert.notEqual(latestCode(), oldCode);
  await assert.rejects(service.resetPassword(email, oldCode, "new-password", ip), { status: 400 });
  await service.resetPassword(email, latestCode(), "new-password", ip);
});

test("a code cannot reset a different account", async () => {
  await service.requestCode(email, ip);
  await assert.rejects(service.resetPassword("someone@example.com", latestCode(), "new-password", ip), { status: 400 });
  const user = (await pool.query("SELECT * FROM users")).rows[0];
  assert.equal(await bcrypt.compare("old-password", user.password_hash), true);
});

test("simultaneous redemptions succeed only once", async () => {
  await service.requestCode(email, ip);
  const results = await Promise.allSettled([
    service.resetPassword(email, latestCode(), "password-one", ip),
    service.resetPassword(email, latestCode(), "password-two", ip),
  ]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal((await pool.query("SELECT session_version FROM users")).rows[0].session_version, 1);
});

test("SMTP failure produces an error and leaves no usable reset code", async () => {
  deliveryFails = true;
  const result = await post("forgot-password", { email });
  assert.equal(result.status, 503);
  assert.equal((await pool.query("SELECT * FROM password_reset_codes")).rowCount, 0);
});

test("missing SMTP configuration and invalid inputs are rejected", async () => {
  const unavailable = createPasswordReset({ pool, mailer: { configured: false }, secret });
  await assert.rejects(unavailable.requestCode(email, ip), { status: 503 });
  const weakSecret = createPasswordReset({ pool, mailer, secret: "short" });
  await assert.rejects(weakSecret.requestCode(email, ip), { status: 503 });
  assert.equal((await post("forgot-password", { email: "bad\r\naddress" })).status, 400);
  assert.equal((await post("forgot-password", { email: "first@example.com,second@example.com" })).status, 400);
  assert.equal((await post("reset-password", { email, code: "123456", newPassword: "123" })).status, 400);
  assert.equal((await post("reset-password", { email, code: "123456", newPassword: "密".repeat(25) })).status, 400);
  assert.equal((await post("reset-password", { email, code: "no-code", newPassword: "new-password" })).status, 400);
});

test("email hourly limit remains in effect across service restarts", async () => {
  for (let index = 0; index < 5; index++) {
    await service.requestCode(email, ip);
    await pool.query("UPDATE auth_rate_limits SET expires_at = now() - interval '1 second' WHERE expires_at < now() + interval '61 seconds'");
  }
  const restarted = createPasswordReset({ pool, mailer, secret });
  await assert.rejects(restarted.requestCode(email, ip), { status: 429, retryAfterSeconds: 3600 });
});

test("IP limits stop bulk send and verify requests", async () => {
  for (let i = 0; i < 20; i++) await service.requestCode(`missing${i}@example.com`, ip);
  await assert.rejects(service.requestCode("another@example.com", ip), { status: 429 });
  for (let i = 0; i < 100; i++) {
    await assert.rejects(service.resetPassword(email, "123456", "new-password", ip), { status: 400 });
  }
  await assert.rejects(service.resetPassword(email, "123456", "new-password", ip), { status: 429 });
});

test("Nodemailer delivers the email through a local SMTP server", async () => {
  let envelope, content = "";
  const smtp = new SMTPServer({
    disabledCommands: ["STARTTLS"],
    onAuth(auth, _session, callback) {
      if (auth.username !== "sender@qq.com" || auth.password !== "test-authorization") {
        return callback(new Error("Invalid test credentials"));
      }
      callback(null, { user: auth.username });
    },
    onData(stream, session, callback) {
      envelope = session.envelope;
      stream.on("data", (chunk) => { content += chunk; });
      stream.on("end", () => callback());
    },
  });
  await new Promise((resolve) => smtp.listen(0, "127.0.0.1", resolve));
  try {
    const transport = createMailer({ SMTP_USER: "sender@qq.com", SMTP_PASS: "test-authorization" }, (options) => {
      assert.equal(options.host, "smtp.qq.com");
      assert.equal(options.secure, true);
      assert.equal(options.port, 465);
      assert.equal(options.requireTLS, true);
      // Only this isolated test disables TLS for its loopback SMTP simulator.
      return nodemailer.createTransport({ ...options, host: "127.0.0.1", port: smtp.server.address().port,
        secure: false, requireTLS: false, ignoreTLS: true });
    });
    await transport.verify();
    await transport.sendCode(email, "654321");
    assert.equal(envelope.mailFrom.address, "sender@qq.com");
    assert.equal(envelope.rcptTo[0].address, email);
    assert.match(content, /654321/);
    assert.match(content, /10 minutes/);
  } finally { await new Promise((resolve) => smtp.close(resolve)); }
});
