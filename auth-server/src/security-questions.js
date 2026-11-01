import bcrypt from "bcryptjs";
import express from "express";
import { PasswordSecurityError, passwordGuards, passwordSecurityErrors, boundedBcryptInput, tokenHash } from "./password-security.js";

export const QUESTION_PRESETS = [
  "What is the name of your first school?",
  "What is your favourite food?",
  "What city were you born in?",
  "What is your childhood nickname?",
  "What was the name of your first pet?",
];
export const normalizeQuestion = (value) => value.normalize("NFKC").trim().replace(/\s+/gu, " ");
export const answerDigest = (value) => tokenHash(value.normalize("NFKC").trim().replace(/\s+/gu, " ").toLowerCase());
export const questionSetHash = (rows) => tokenHash(JSON.stringify(rows.map((row) => [row.slot, row.question, row.answer_hash])));

export function validateQuestions(value, { optional = false } = {}) {
  if (optional && (value === undefined || (Array.isArray(value) && value.length === 0))) return [];
  if (!Array.isArray(value) || value.length !== 3) {
    throw new PasswordSecurityError(400, "Provide three different security questions and all three answers, or leave the optional registration section empty.");
  }
  const questions = value.map((item) => {
    const question = typeof item?.question === "string" ? normalizeQuestion(item.question) : "";
    const answer = typeof item?.answer === "string" ? item.answer.trim() : "";
    if (question.length < 5 || question.length > 200) throw new PasswordSecurityError(400, "Each security question must contain 5 to 200 characters.");
    if (!answer || answer.length > 200) throw new PasswordSecurityError(400, "Each security answer must contain 1 to 200 characters.");
    return { question, answer };
  });
  if (new Set(questions.map((item) => item.question.toLowerCase())).size !== 3) {
    throw new PasswordSecurityError(400, "Security questions must be different.");
  }
  return questions;
}

export async function hashQuestions(questions) {
  return Promise.all(questions.map(async (item) => ({ question: item.question, answerHash: await bcrypt.hash(answerDigest(item.answer), 12) })));
}

// Caller must hold the users row lock (or own the newly inserted user) in a transaction.
export async function writeQuestions(client, userId, questions) {
  await client.query("DELETE FROM auth_security_questions WHERE user_id = $1", [userId]);
  for (const [index, item] of questions.entries()) {
    await client.query(
      "INSERT INTO auth_security_questions (user_id, slot, question, normalized_question, answer_hash) VALUES ($1,$2,$3,$4,$5)",
      [userId, index + 1, item.question, item.question.toLowerCase(), item.answerHash],
    );
  }
  await client.query("DELETE FROM security_question_challenges WHERE user_id = $1", [userId]);
}

export function createSecurityQuestions(dependencies) {
  const { pool } = dependencies;
  const guards = passwordGuards(dependencies);
  async function status(auth) {
    if (!auth?.sub) throw new PasswordSecurityError(401, "Authentication required.");
    const user = (await pool.query("SELECT password_hash, session_version FROM users WHERE id = $1", [auth.sub])).rows[0];
    if (!user || (auth.version || 0) !== user.session_version) throw new PasswordSecurityError(401, "Session expired. Please sign in again.");
    // Deliberate allowlist: neither answers nor hashes ever leave this API.
    const rows = (await pool.query("SELECT slot, question FROM auth_security_questions WHERE user_id = $1 ORDER BY slot", [auth.sub])).rows;
    return { configured: rows.length === 3, hasLocalPassword: Boolean(user.password_hash), questions: rows.map((row) => row.question) };
  }
  async function save(auth, currentPassword, value, ip) {
    if (!auth?.sub) throw new PasswordSecurityError(401, "Authentication required.");
    await guards.rateLimit("question-manage-ip", ip);
    const questions = validateQuestions(value);
    const current = typeof currentPassword === "string" ? boundedBcryptInput(currentPassword) : "";
    if (!current) throw new PasswordSecurityError(400, "Enter your current password.");
    return guards.transaction(async (client) => {
      const user = (await client.query("SELECT * FROM users WHERE id = $1 FOR UPDATE", [auth.sub])).rows[0];
      if (!user || (auth.version || 0) !== user.session_version) return new PasswordSecurityError(401, "Session expired. Please sign in again.");
      if (!user.password_hash) return new PasswordSecurityError(400, "This account uses Google sign-in and has no local password. Security questions require a local password.");
      if (await guards.blocked(client, "question-manage-failures", user.id)) return new PasswordSecurityError(429, "Too many attempts. Please try again in 15 minutes.", 900);
      if (!await bcrypt.compare(current, user.password_hash)) {
        const limited = await guards.failed(client, "question-manage-failures", user.id);
        return new PasswordSecurityError(limited ? 429 : 400, limited ? "Too many attempts. Please try again in 15 minutes." : "Current password is incorrect.", limited ? 900 : undefined);
      }
      await writeQuestions(client, user.id, await hashQuestions(questions));
      await guards.clear(client, "question-manage-failures", user.id);
    });
  }
  return { status, save };
}

export function securityQuestionsRouter(dependencies) {
  const router = express.Router();
  const service = createSecurityQuestions(dependencies);
  router.get("/security-questions", dependencies.requireAuth, async (req, res, next) => {
    try { res.json(await service.status(req.auth)); } catch (error) { next(error); }
  });
  router.post("/security-questions", dependencies.requireAuth, async (req, res, next) => {
    try {
      await service.save(req.auth, req.body.currentPassword, req.body.securityQuestions, req.ip);
      res.json({ message: "Security questions saved successfully." });
    } catch (error) { next(error); }
  });
  router.use(passwordSecurityErrors);
  return router;
}
