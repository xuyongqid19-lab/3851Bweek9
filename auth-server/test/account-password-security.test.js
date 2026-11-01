import assert from "node:assert/strict";
import { after, before, beforeEach, test } from "node:test";
import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { PGlite } from "@electric-sql/pglite";
import pg from "pg";
import bcrypt from "bcryptjs";
import express from "express";
import { createSecurityQuestionReset, securityQuestionResetRouter } from "../src/security-question-reset.js";
import { createChangePassword } from "../src/change-password.js";
import { createSecurityQuestions, securityQuestionsRouter, QUESTION_PRESETS, answerDigest } from "../src/security-questions.js";
import { registrationHandler } from "../src/registration.js";
import { createPasswordReset } from "../src/password-reset.js";
import { tokenHash, boundedBcryptInput } from "../src/password-security.js";

const email = "student@example.com", ip = "127.0.0.1";
const secret = "isolated-test-secret-not-production";
let db, pool, recovery, management, change, user, server, baseUrl;
const answers = ["first school", "rice", "london"];
const wrong = ["wrong", "rice", "london"];
const questionValues = () => QUESTION_PRESETS.slice(0, 3).map((question, i) => ({ question, answer: answers[i] }));
let queue = Promise.resolve();
async function acquire() {
  const previous = queue;
  let release;
  queue = new Promise((resolve) => { release = resolve; });
  await previous;
  return release;
}
async function query(sql, args) {
  const result = await db.query(sql, args);
  return { ...result, rowCount: result.fields?.length ? result.rows.length : result.affectedRows ?? result.rows.length };
}
const auth = () => ({ sub: user.id, version: user.session_version });
const identify = (account = email) => recovery.identify(account, ip);
async function proof(account = email) {
  const identified = await identify(account);
  return recovery.verify(identified.challenge, ["  FIRST SCHOOL  ", "RICE", "london"], ip);
}
const reset = (token, password = "new-password", confirmation = password) => recovery.reset(token, password, confirmation, ip);
const update = (current = "old-password", password = "new-password", confirmation = password, session = auth()) => change(session, current, password, confirmation, ip);
async function currentUser() { return (await pool.query("SELECT * FROM users WHERE id = $1", [user.id])).rows[0]; }
async function expireLimits() { await pool.query("UPDATE auth_rate_limits SET expires_at = now() - interval '1 second'"); }
async function post(path, body) {
  const response = await fetch(`${baseUrl}/auth/security-question/${path}`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
}

before(async () => {
  if (process.env.AUTH_TEST_DATABASE_URL) {
    const url = new URL(process.env.AUTH_TEST_DATABASE_URL);
    if (url.pathname !== "/gv_auth_test") throw new Error("Only the isolated gv_auth_test database is allowed.");
    pool = new pg.Pool({ connectionString: process.env.AUTH_TEST_DATABASE_URL });
  } else {
    db = new PGlite();
    pool = {
      async query(sql, args) { const release = await acquire(); try { return await query(sql, args); } finally { release(); } },
      async connect() { const release = await acquire(); return { query, release }; },
    };
  }
  for (const path of ["../db/init.sql", "../src/reset-schema.sql", "../src/security-question-schema.sql"]) {
    const schema = await readFile(new URL(path, import.meta.url), "utf8");
    const sql = db ? schema.replace("CREATE EXTENSION IF NOT EXISTS pgcrypto;", "") : schema;
    if (db) await db.exec(sql); else await pool.query(sql);
  }
  const migration = await readFile(new URL("../src/security-question-schema.sql", import.meta.url), "utf8");
  if (db) await db.exec(migration); else await pool.query(migration);
  recovery = createSecurityQuestionReset({ pool, secret });
  change = createChangePassword({ pool, secret });
  management = createSecurityQuestions({ pool, secret });
  const app = express();
  app.use(express.json());
  app.use("/auth", securityQuestionResetRouter({ pool, secret }));
  const requireAuth = (req, res, next) => {
    // Isolated HTTP adapter; production JWT middleware stays in index.js.
    if (req.headers.authorization !== "Bearer test-session") return res.status(401).json({ error: "Authentication required." });
    req.auth = auth(); next();
  };
  app.use("/auth", securityQuestionsRouter({ pool, secret, requireAuth }));
  app.post("/auth/register", registrationHandler({ pool, secret,
    clean: (value) => typeof value === "string" ? value.trim() : "",
    parseBirthDate: (value) => value === "2000-01-01" ? value : null,
    publicUser: (row) => ({ id: row.id, email: row.email }),
  }));
  app.use((_error, _req, res, _next) => res.status(500).json({ error: "Server error." }));
  server = await new Promise((resolve) => { const listener = app.listen(0, "127.0.0.1", () => resolve(listener)); });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

beforeEach(async () => {
  await pool.query("TRUNCATE users, password_reset_codes, auth_rate_limits, security_question_challenges CASCADE");
  user = (await pool.query(
    `INSERT INTO users (id, full_name, email, username, password_hash, security_question, security_answer_hash)
     VALUES ($1, 'Student', $2, 'student', $3, 'What is the name of your first school?', $4) RETURNING *`,
    [randomUUID(), email, await bcrypt.hash("old-password", 4), await bcrypt.hash("first school", 4)],
  )).rows[0];
  for (const [index, item] of questionValues().entries()) {
    await pool.query("INSERT INTO auth_security_questions (user_id, slot, question, normalized_question, answer_hash) VALUES ($1,$2,$3,$4,$5)",
      [user.id, index + 1, item.question, item.question.toLowerCase(), await bcrypt.hash(answerDigest(item.answer), 4)]);
  }
});
after(async () => {
  if (server) await new Promise((resolve) => server.close(resolve));
  if (db) await db.close(); else if (pool) await pool.end();
});

test("independent HTTP flow uses normalized bcrypt answer, hashed proof, database password and session version", async () => {
  const identified = await post("identify", { account: " STUDENT " });
  assert.equal(identified.status, 200);
  assert.deepEqual(Object.keys(identified.body).sort(), ["challenge", "questions"]);
  const verified = await post("verify", { challenge: identified.body.challenge, answers: [" FIRST SCHOOL ", "RICE", "london"] });
  assert.equal(verified.status, 200);
  assert.equal(verified.body.expiresInSeconds, 300);
  const records = (await pool.query("SELECT * FROM security_question_challenges")).rows;
  assert.equal(records.length, 1);
  assert.equal(records[0].token_hash, tokenHash(verified.body.resetToken));
  assert.notEqual(records[0].token_hash, verified.body.resetToken);
  const result = await post("reset", { resetToken: verified.body.resetToken, newPassword: "new-password", confirmNewPassword: "new-password" });
  assert.equal(result.status, 200);
  assert.equal(result.body.message, "Password Reset Successfully");
  const updated = await currentUser();
  assert.equal(await bcrypt.compare("old-password", updated.password_hash), false);
  assert.equal(await bcrypt.compare("new-password", updated.password_hash), true);
  assert.equal(updated.session_version, 1);
  assert.equal(updated.security_answer_hash, user.security_answer_hash);
  assert.equal((await pool.query("SELECT * FROM security_question_challenges")).rowCount, 0);
});

test("wrong answers fail; five failures across aliases and challenges temporarily lock the account", async () => {
  const a = await identify(email), b = await identify("student");
  for (let i = 0; i < 5; i++) {
    await assert.rejects(recovery.verify(i % 2 ? a.challenge : b.challenge, wrong, ip), { status: i === 4 ? 429 : 400 });
  }
  const restarted = createSecurityQuestionReset({ pool, secret });
  await assert.rejects(restarted.verify(a.challenge, answers, ip), { status: 429 });
  await expireLimits();
  assert.ok((await recovery.verify(a.challenge, answers, ip)).resetToken);
});

test("successful answer breaks the consecutive failure sequence", async () => {
  const a = await identify();
  for (let i = 0; i < 4; i++) await assert.rejects(recovery.verify(a.challenge, wrong, ip), { status: 400 });
  await recovery.verify(a.challenge, answers, ip);
  const b = await identify();
  await assert.rejects(recovery.verify(b.challenge, wrong, ip), { status: 400 });
});

test("absent, unconfigured and Google-only accounts receive identical plausible response shapes and cannot verify", async () => {
  const missing = await post("identify", { account: "missing@example.com" });
  await pool.query("DELETE FROM auth_security_questions WHERE user_id = $1", [user.id]);
  const unconfigured = await post("identify", { account: email });
  await pool.query("UPDATE users SET password_hash = NULL, security_answer_hash = $1, auth_provider = 'google' WHERE id = $2", [user.security_answer_hash, user.id]);
  const google = await post("identify", { account: email });
  for (const result of [missing, unconfigured, google]) {
    assert.equal(result.status, 200);
    assert.deepEqual(Object.keys(result.body).sort(), ["challenge", "questions"]);
    const rejected = await post("verify", { challenge: result.body.challenge, answers });
    assert.equal(rejected.status, 400);
    assert.equal(rejected.body.error, "Unable to verify this account or answer. Try again or use Email Verification.");
  }
});

test("unverified, forged, missing and expired proofs cannot update a password", async () => {
  const a = await identify();
  await assert.rejects(reset(a.challenge), { status: 400 });
  await assert.rejects(reset("f".repeat(64)), { status: 400 });
  await assert.rejects(reset(undefined), { status: 400 });
  const verified = await proof();
  await pool.query("UPDATE security_question_challenges SET expires_at = now() - interval '1 second'");
  await assert.rejects(reset(verified.resetToken), { status: 400 });
  assert.equal((await currentUser()).password_hash, user.password_hash);
});

test("expired answer challenge cannot be verified", async () => {
  const a = await identify();
  await pool.query("UPDATE security_question_challenges SET expires_at = now() - interval '1 second'");
  await assert.rejects(recovery.verify(a.challenge, answers, ip), { status: 400 });
});

test("legacy single question cannot recover; legacy long current passwords remain compatible", async () => {
  const longPassword = "a".repeat(127) + String.fromCodePoint(128512) + "x".repeat(2048);
  assert.ok(Buffer.byteLength(boundedBcryptInput(longPassword), "utf8") <= 384);
  await pool.query("DELETE FROM auth_security_questions WHERE user_id = $1", [user.id]);
  await pool.query("UPDATE users SET password_hash = $1 WHERE id = $2", [await bcrypt.hash(longPassword, 4), user.id]);
  const a = await identify();
  await assert.rejects(recovery.verify(a.challenge, answers, ip), { status: 400 });
  assert.equal((await management.status(auth())).configured, false);
  await update(longPassword);
  assert.equal(await bcrypt.compare("new-password", (await currentUser()).password_hash), true);
});

test("proof and answer challenge are each one-time; latest proof supersedes older proof", async () => {
  const a = await identify();
  const first = await recovery.verify(a.challenge, answers, ip);
  await assert.rejects(recovery.verify(a.challenge, answers, ip), { status: 400 });
  const second = await proof();
  await assert.rejects(reset(first.resetToken), { status: 400 });
  await reset(second.resetToken);
  await assert.rejects(reset(second.resetToken), { status: 400 });
});

test("concurrent redemptions succeed once", async () => {
  const verified = await proof();
  const results = await Promise.allSettled([reset(verified.resetToken, "password-one"), reset(verified.resetToken, "password-two")]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal((await currentUser()).session_version, 1);
});

test("concurrent wrong answers cannot bypass the fifth-failure lock", async () => {
  const a = await identify();
  const results = await Promise.allSettled(Array.from({ length: 7 }, () => recovery.verify(a.challenge, wrong, ip)));
  assert.equal(results.filter((r) => r.reason?.status === 400).length, 4);
  assert.equal(results.filter((r) => r.reason?.status === 429).length, 3);
});

test("reset validation enforces confirmation, six characters and 72 UTF-8 bytes", async () => {
  const verified = await proof();
  await assert.rejects(reset(verified.resetToken, "short"), { status: 400 });
  await assert.rejects(reset(verified.resetToken, "密".repeat(25)), { status: 400 });
  await assert.rejects(reset(verified.resetToken, "new-password", "different"), { status: 400 });
  await reset(verified.resetToken, "密".repeat(24));
});

test("IP limit persists across instances and does not trust supplied forwarding headers", async () => {
  for (let i = 0; i < 30; i++) await identify(`missing${i}@example.com`);
  await assert.rejects(createSecurityQuestionReset({ pool, secret }).identify("other@example.com", ip), { status: 429 });
  const spoofed = await fetch(`${baseUrl}/auth/security-question/identify`, {
    method: "POST", headers: { "Content-Type": "application/json", "X-Forwarded-For": "192.0.2.1" },
    body: JSON.stringify({ account: "other@example.com" }),
  });
  assert.equal(spoofed.status, 429);
});

test("unauthenticated and stale-session password changes are rejected", async () => {
  await assert.rejects(update("old-password", "new-password", "new-password", null), { status: 401 });
  await pool.query("UPDATE users SET session_version = 1 WHERE id = $1", [user.id]);
  await assert.rejects(update(), { status: 401 });
});

test("incorrect current password never changes the database", async () => {
  await assert.rejects(update("incorrect"), { status: 400, message: "Current password is incorrect." });
  assert.equal((await currentUser()).password_hash, user.password_hash);
});

test("five wrong current passwords cause a temporary limit", async () => {
  for (let i = 0; i < 5; i++) await assert.rejects(update("incorrect"), { status: i === 4 ? 429 : 400 });
  await assert.rejects(update(), { status: 429 });
  await expireLimits();
  await update();
});

test("same password, mismatched confirmation and invalid byte length are rejected", async () => {
  await assert.rejects(update("old-password", "old-password"), { status: 400 });
  await assert.rejects(update("old-password", "new-password", "different"), { status: 400, message: "Passwords do not match." });
  await assert.rejects(update("old-password", "密".repeat(25)), { status: 400 });
  await assert.rejects(update("old-password", "short"), { status: 400 });
});

test("change writes bcrypt password, preserves profile and Google link, increments sessions and invalidates proofs", async () => {
  await pool.query("UPDATE users SET auth_provider = 'local+google', google_sub = 'linked-google' WHERE id = $1", [user.id]);
  const verified = await proof();
  await update();
  const updated = await currentUser();
  assert.equal(await bcrypt.compare("old-password", updated.password_hash), false);
  assert.equal(await bcrypt.compare("new-password", updated.password_hash), true);
  assert.equal(updated.session_version, 1);
  for (const field of ["email", "full_name", "username", "security_answer_hash", "security_question", "interests"]) assert.deepEqual(updated[field], user[field]);
  assert.equal(updated.google_sub, "linked-google");
  assert.equal(updated.auth_provider, "local+google");
  await assert.rejects(reset(verified.resetToken), { status: 400 });
});

test("Google-only change cannot create a local password", async () => {
  await pool.query("UPDATE users SET password_hash = NULL, auth_provider = 'google' WHERE id = $1", [user.id]);
  await assert.rejects(update(), { status: 400, message: "This account uses Google sign-in and has no local password. Please continue with Google." });
  assert.equal((await currentUser()).password_hash, null);
});

test("concurrent change requests using the same JWT succeed once", async () => {
  const results = await Promise.allSettled([update("old-password", "password-one"), update("old-password", "password-two")]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal(results.find((r) => r.status === "rejected").reason.status, 401);
});

test("email reset session changes invalidate security proofs without editing the email reset module", async () => {
  const verified = await proof();
  await pool.query("UPDATE users SET session_version = session_version + 1 WHERE id = $1", [user.id]);
  await assert.rejects(reset(verified.resetToken), { status: 400 });
});

test("database failure rolls back password and token consumption", async () => {
  const verified = await proof();
  await pool.query("CREATE FUNCTION reject_test_password() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'isolated test failure'; END $$");
  await pool.query("CREATE TRIGGER reject_test_password BEFORE UPDATE OF password_hash ON users FOR EACH ROW EXECUTE FUNCTION reject_test_password()");
  try {
    await assert.rejects(reset(verified.resetToken));
    assert.equal((await currentUser()).password_hash, user.password_hash);
    assert.equal((await pool.query("SELECT * FROM security_question_challenges WHERE token_hash = $1", [tokenHash(verified.resetToken)])).rows.length, 1);
  } finally {
    await pool.query("DROP TRIGGER reject_test_password ON users");
    await pool.query("DROP FUNCTION reject_test_password()");
  }
});

async function api(path, body, token = "test-session", method = "POST") {
  const response = await fetch(`${baseUrl}/auth${path}`, {
    method, headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  return { status: response.status, body: await response.json() };
}
const registration = () => ({ fullName: "New Student", birthDate: "2000-01-01", phone: "123456789",
  email: `${randomUUID()}@example.com`, username: randomUUID(), password: "old-password" });

test("registration is optional; complete custom and preset questions are stored as three hashes", async () => {
  for (const securityQuestions of [undefined, [], questionValues().map((item, i) => i === 2 ? { ...item, question: "What is my custom favourite place?" } : item)]) {
    const response = await api("/register", { ...registration(), securityQuestions }, null);
    assert.equal(response.status, 201);
    const rows = (await pool.query("SELECT * FROM auth_security_questions WHERE user_id = $1 ORDER BY slot", [response.body.user.id])).rows;
    assert.equal(rows.length, securityQuestions?.length || 0);
    for (const [i, row] of rows.entries()) {
      assert.equal(row.question, securityQuestions[i].question);
      assert.notEqual(row.answer_hash, answers[i]);
      assert.ok(await bcrypt.compare(answerDigest(answers[i]), row.answer_hash));
    }
    assert.equal(JSON.stringify(response.body).includes("answer"), false);
  }
});

test("partial, empty, duplicate and oversized configurations cannot register or save", async () => {
  const invalid = [null, questionValues().slice(0, 1), questionValues().slice(0, 2),
    [...questionValues(), questionValues()[0]],
    questionValues().map((q, i) => i === 1 ? { ...q, answer: "" } : q),
    questionValues().map((q, i) => i === 1 ? { ...q, question: "  " } : q),
    questionValues().map((q, i) => i === 1 ? { ...q, question: QUESTION_PRESETS[0].toUpperCase().replaceAll(" ", "   ") } : q),
    questionValues().map((q, i) => i === 1 ? { ...q, question: "x".repeat(201) } : q),
    questionValues().map((q, i) => i === 1 ? { ...q, answer: "x".repeat(201) } : q),
  ];
  for (const securityQuestions of invalid) {
    const data = registration();
    assert.equal((await api("/register", { ...data, securityQuestions }, null)).status, 400);
    assert.equal((await pool.query("SELECT id FROM users WHERE email = $1", [data.email])).rows.length, 0);
    await assert.rejects(management.save(auth(), "old-password", securityQuestions, ip), { status: 400 });
  }
  assert.equal((await api("/register", { ...registration(), securityQuestion: QUESTION_PRESETS[0], securityAnswer: "legacy" }, null)).status, 400);
});

test("each answer is mandatory; any single wrong answer fails; forged success flags do nothing", async () => {
  const a = await identify();
  for (let i = 0; i < 3; i++) {
    const attempt = [...answers]; attempt[i] = "incorrect";
    await assert.rejects(recovery.verify(a.challenge, attempt, ip), { status: 400 });
  }
  for (const value of ["first school", [], answers.slice(0, 2), [...answers, "fourth"], ["", "rice", "london"]]) {
    await assert.rejects(recovery.verify(a.challenge, value, ip), { status: 400 });
  }
  assert.equal((await post("verify", { challenge: a.challenge, answer: "first school", verified: true })).status, 400);
  assert.equal((await post("reset", { resetToken: a.challenge, verified: true, newPassword: "new-password", confirmNewPassword: "new-password" })).status, 400);
  assert.ok((await recovery.verify(a.challenge, answers, ip)).resetToken);
});

test("management requires current password, ignores other user IDs and never exposes answers", async () => {
  assert.equal((await api("/security-questions", undefined, null, "GET")).status, 401);
  assert.equal((await api("/security-questions", { currentPassword: "old-password", securityQuestions: questionValues() }, null)).status, 401);
  await assert.rejects(management.save(null, "old-password", questionValues(), ip), { status: 401 });
  await assert.rejects(management.save({ ...auth(), version: 1 }, "old-password", questionValues(), ip), { status: 401 });
  const before = (await pool.query("SELECT * FROM auth_security_questions WHERE user_id = $1 ORDER BY slot", [user.id])).rows;
  assert.equal((await api("/security-questions", { currentPassword: "wrong", securityQuestions: questionValues() })).status, 400);
  assert.deepEqual((await pool.query("SELECT * FROM auth_security_questions WHERE user_id = $1 ORDER BY slot", [user.id])).rows, before);
  const other = (await api("/register", registration(), null)).body.user;
  const saved = await api("/security-questions", { userId: other.id, currentPassword: "old-password",
    securityQuestions: questionValues().map((item, i) => ({ ...item, question: `My custom question number ${i + 1}?` })) });
  assert.equal(saved.status, 200);
  assert.equal((await pool.query("SELECT * FROM auth_security_questions WHERE user_id = $1", [other.id])).rows.length, 0);
  const status = await api("/security-questions", undefined, "test-session", "GET");
  assert.deepEqual(Object.keys(status.body).sort(), ["configured", "hasLocalPassword", "questions"]);
  assert.equal(status.body.configured, true);
  assert.equal(status.body.questions.length, 3);
  assert.equal(JSON.stringify(status.body).includes("answer"), false);
  assert.equal((await currentUser()).password_hash, user.password_hash);
  assert.equal((await currentUser()).session_version, 0);
});

test("first setup works for legacy users; updates revoke challenges and reset proofs", async () => {
  await pool.query("DELETE FROM auth_security_questions WHERE user_id = $1", [user.id]);
  assert.equal((await management.status(auth())).configured, false);
  await management.save(auth(), "old-password", questionValues(), ip);
  const verified = await proof();
  const pending = await identify();
  await management.save(auth(), "old-password", questionValues().map((q) => ({ ...q, answer: "replacement" })), ip);
  await assert.rejects(reset(verified.resetToken), { status: 400 });
  await assert.rejects(recovery.verify(pending.challenge, answers, ip), { status: 400 });
  const next = await identify();
  await assert.rejects(recovery.verify(next.challenge, answers, ip), { status: 400 });
  assert.ok((await recovery.verify(next.challenge, Array(3).fill("replacement"), ip)).resetToken);
  assert.equal((await currentUser()).security_answer_hash, user.security_answer_hash);
});

test("Google-only management cannot bypass current password and wrong passwords are limited", async () => {
  for (let i = 0; i < 5; i++) await assert.rejects(management.save(auth(), "wrong", questionValues(), ip), { status: i === 4 ? 429 : 400 });
  await assert.rejects(management.save(auth(), "old-password", questionValues(), ip), { status: 429 });
  await pool.query("UPDATE users SET password_hash = NULL, auth_provider = 'google' WHERE id = $1", [user.id]);
  assert.equal((await management.status(auth())).hasLocalPassword, false);
  await assert.rejects(management.save(auth(), "anything", questionValues(), ip), { status: 400, message: "This account uses Google sign-in and has no local password. Security questions require a local password." });
  assert.equal((await currentUser()).password_hash, null);
});

test("additive migration is repeatable and preserves legacy users and profile data", async () => {
  const before = await currentUser();
  const schema = await readFile(new URL("../src/security-question-schema.sql", import.meta.url), "utf8");
  assert.equal(/\b(?:DROP\s+TABLE|TRUNCATE|DELETE\s+FROM)\b/i.test(schema), false);
  if (db) await db.exec(schema); else await pool.query(schema);
  assert.deepEqual(await currentUser(), before);
  assert.equal((await pool.query("SELECT * FROM auth_security_questions WHERE user_id = $1", [user.id])).rows.length, 3);
});

test("question save rolls back the entire set and revocation if any insert fails", async () => {
  const before = (await pool.query("SELECT * FROM auth_security_questions WHERE user_id = $1 ORDER BY slot", [user.id])).rows;
  const verified = await proof();
  await pool.query("CREATE FUNCTION reject_test_question() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.slot = 2 THEN RAISE EXCEPTION 'isolated test failure'; END IF; RETURN NEW; END $$");
  await pool.query("CREATE TRIGGER reject_test_question BEFORE INSERT ON auth_security_questions FOR EACH ROW EXECUTE FUNCTION reject_test_question()");
  try {
    await assert.rejects(management.save(auth(), "old-password", questionValues(), ip));
    assert.deepEqual((await pool.query("SELECT * FROM auth_security_questions WHERE user_id = $1 ORDER BY slot", [user.id])).rows, before);
    assert.equal((await pool.query("SELECT * FROM security_question_challenges WHERE token_hash = $1", [tokenHash(verified.resetToken)])).rows.length, 1);
    const data = registration();
    assert.equal((await api("/register", { ...data, securityQuestions: questionValues() }, null)).status, 500);
    assert.equal((await pool.query("SELECT id FROM users WHERE email = $1", [data.email])).rows.length, 0);
  } finally {
    await pool.query("DROP TRIGGER reject_test_question ON auth_security_questions");
    await pool.query("DROP FUNCTION reject_test_question()");
  }
});

test("answer hashes distinguish text beyond bcrypt's 72-byte boundary and custom questions normalize duplicates", async () => {
  const long = "a".repeat(100);
  await management.save(auth(), "old-password", questionValues().map((q, i) => ({ ...q, answer: i === 0 ? `${long}x` : q.answer })), ip);
  const a = await identify();
  await assert.rejects(recovery.verify(a.challenge, [`${long}y`, ...answers.slice(1)], ip), { status: 400 });
  assert.ok((await recovery.verify(a.challenge, [`${long}x`, ...answers.slice(1)], ip)).resetToken);
  await assert.rejects(management.save(auth(), "old-password", [
    { question: "My custom question?", answer: "one" },
    { question: "Ｍｙ custom question?", answer: "two" },
    { question: "Different question?", answer: "three" },
  ], ip), { status: 400, message: "Security questions must be different." });
});

test("a legacy single-question user can still recover using the unchanged email verification service", async () => {
  await pool.query("DELETE FROM auth_security_questions WHERE user_id = $1", [user.id]);
  const sent = [];
  const emailRecovery = createPasswordReset({ pool, secret: secret.repeat(3), mailer: {
    configured: true, async sendCode(to, code) { sent.push({ to, code }); },
  } });
  await emailRecovery.requestCode(email, ip);
  assert.equal(sent.length, 1);
  await emailRecovery.resetPassword(email, sent[0].code, "email-reset-password", ip);
  const updated = await currentUser();
  assert.ok(await bcrypt.compare("email-reset-password", updated.password_hash));
  assert.equal(updated.security_answer_hash, user.security_answer_hash);
  assert.equal((await management.status({ sub: user.id, version: 1 })).configured, false);
});
