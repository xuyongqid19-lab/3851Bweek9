import { randomBytes } from "node:crypto";
import bcrypt from "bcryptjs";
import express from "express";
import { QUESTION_PRESETS, answerDigest, questionSetHash } from "./security-questions.js";
import {
  PasswordSecurityError, passwordGuards, passwordSecurityErrors,
  tokenHash, validToken, validateNewPassword,
} from "./password-security.js";

const INVALID = "Unable to verify this account or answer. Try again or use Email Verification.";
const EXPIRED = "Invalid or expired reset token. Verify your security answer again.";
const LIMITED = () => new PasswordSecurityError(429, "Too many attempts. Please try again in 15 minutes.", 900);
// Equal bcrypt work for unavailable accounts; never derived from a user's answer.
const dummyHash = bcrypt.hashSync(randomBytes(32).toString("hex"), 12);
const freshToken = () => randomBytes(32).toString("hex");

export function createSecurityQuestionReset(dependencies) {
  const { pool } = dependencies;
  const guards = passwordGuards(dependencies);

  async function identify(accountValue, ip) {
    await guards.rateLimit("question-identify-ip", ip);
    const account = typeof accountValue === "string" ? accountValue.trim().toLowerCase() : "";
    if (!account || account.length > 254) throw new PasswordSecurityError(400, "Enter your email address or username.");
    await guards.rateLimit("question-identify-account", account, 10);
    return guards.transaction(async (client) => {
      const result = await client.query(
        `SELECT id, security_question, security_answer_hash, password_hash, session_version FROM users
         WHERE lower(email) = $1 OR lower(username) = $1 LIMIT 2 FOR UPDATE`, [account],
      );
      const candidate = result.rows.length === 1 ? result.rows[0] : null;
      const rows = candidate ? (await client.query("SELECT * FROM auth_security_questions WHERE user_id = $1 ORDER BY slot", [candidate.id])).rows : [];
      const user = candidate?.password_hash && rows.length === 3 ? candidate : null;
      const accountKey = guards.key("question-account", account);
      const challenge = freshToken();
      await client.query(
        `INSERT INTO security_question_challenges (token_hash, user_id, account_key, session_version, question_set_hash, expires_at)
         VALUES ($1, $2, $3, $4, $5, clock_timestamp() + interval '5 minutes')`,
        [tokenHash(challenge), user?.id || null, accountKey, user?.session_version ?? null, user ? questionSetHash(rows) : null],
      );
      // Same status/shape and plausible question for absent, unconfigured and Google-only accounts.
      const offset = parseInt(accountKey.slice(0, 8), 16) % QUESTION_PRESETS.length;
      return { questions: user ? rows.map((row) => row.question) : Array.from({ length: 3 }, (_, i) => QUESTION_PRESETS[(offset + i) % QUESTION_PRESETS.length]), challenge };
    });
  }

  async function verify(challenge, answerValues, ip) {
    await guards.rateLimit("question-verify-ip", ip, 50);
    if (!validToken(challenge) || !Array.isArray(answerValues) || answerValues.length !== 3 ||
        answerValues.some((answer) => typeof answer !== "string" || !answer.trim() || answer.trim().length > 200)) {
      throw new PasswordSecurityError(400, INVALID);
    }
    return guards.transaction(async (client) => {
      const snapshot = (await client.query("SELECT * FROM security_question_challenges WHERE token_hash = $1", [tokenHash(challenge)])).rows[0];
      const user = snapshot?.user_id ? (await client.query("SELECT * FROM users WHERE id = $1 FOR UPDATE", [snapshot.user_id])).rows[0] : null;
      const record = (await client.query(
        "SELECT *, expires_at > clock_timestamp() AS active FROM security_question_challenges WHERE token_hash = $1 FOR UPDATE", [tokenHash(challenge)],
      )).rows[0];
      if (!record?.active || record.verified) return new PasswordSecurityError(400, INVALID);
      const identity = user?.id || record.account_key;
      if (await guards.blocked(client, "question-failures", identity)) return LIMITED();
      const rows = user ? (await client.query("SELECT * FROM auth_security_questions WHERE user_id = $1 ORDER BY slot", [user.id])).rows : [];
      const eligible = user?.password_hash && rows.length === 3 && user.session_version === record.session_version && record.question_set_hash === questionSetHash(rows);
      // Always perform all three bcrypt comparisons; a single wrong answer fails.
      const matches = await Promise.all(answerValues.map((answer, i) => bcrypt.compare(answerDigest(answer), eligible ? rows[i].answer_hash : dummyHash)));
      if (!eligible || !matches.every(Boolean)) {
        if (await guards.failed(client, "question-failures", identity)) return LIMITED();
        return new PasswordSecurityError(400, INVALID);
      }
      const active = await client.query("SELECT token_hash FROM security_question_challenges WHERE token_hash = $1 AND expires_at > clock_timestamp()", [record.token_hash]);
      if (!active.rows.length) return new PasswordSecurityError(400, INVALID);
      await guards.clear(client, "question-failures", identity);
      // A new proof supersedes previous proofs for this user. Answer challenges cannot reset passwords.
      await client.query("DELETE FROM security_question_challenges WHERE user_id = $1 AND verified = true", [user.id]);
      await client.query("DELETE FROM security_question_challenges WHERE token_hash = $1", [record.token_hash]);
      const resetToken = freshToken();
      await client.query(
        `INSERT INTO security_question_challenges (token_hash, user_id, account_key, session_version, question_set_hash, verified, expires_at)
         VALUES ($1, $2, $3, $4, $5, true, clock_timestamp() + interval '5 minutes')`,
        [tokenHash(resetToken), user.id, record.account_key, user.session_version, record.question_set_hash],
      );
      return { resetToken, expiresInSeconds: 300 };
    });
  }

  async function reset(resetToken, password, confirmation, ip) {
    await guards.rateLimit("question-reset-ip", ip, 50);
    validateNewPassword(password, confirmation);
    if (!validToken(resetToken)) throw new PasswordSecurityError(400, EXPIRED);
    return guards.transaction(async (client) => {
      const snapshot = (await client.query("SELECT user_id FROM security_question_challenges WHERE token_hash = $1", [tokenHash(resetToken)])).rows[0];
      const user = snapshot?.user_id ? (await client.query("SELECT * FROM users WHERE id = $1 FOR UPDATE", [snapshot.user_id])).rows[0] : null;
      const record = (await client.query(
        "SELECT *, expires_at > clock_timestamp() AS active FROM security_question_challenges WHERE token_hash = $1 FOR UPDATE", [tokenHash(resetToken)],
      )).rows[0];
      const rows = user ? (await client.query("SELECT * FROM auth_security_questions WHERE user_id = $1 ORDER BY slot", [user.id])).rows : [];
      if (!user?.password_hash || !record?.active || !record.verified || record.session_version !== user.session_version || rows.length !== 3 || record.question_set_hash !== questionSetHash(rows)) {
        return new PasswordSecurityError(400, EXPIRED);
      }
      const hash = await bcrypt.hash(password, 12);
      // Recheck wall-clock expiry after expensive bcrypt work.
      const consumed = await client.query(
        "DELETE FROM security_question_challenges WHERE token_hash = $1 AND expires_at > clock_timestamp() RETURNING token_hash", [record.token_hash],
      );
      if (!consumed.rowCount) return new PasswordSecurityError(400, EXPIRED);
      await client.query("UPDATE users SET password_hash = $1, session_version = session_version + 1, updated_at = now() WHERE id = $2", [hash, user.id]);
      await client.query("DELETE FROM security_question_challenges WHERE user_id = $1", [user.id]);
      await client.query("DELETE FROM password_reset_codes WHERE user_id = $1", [user.id]);
    });
  }
  return { identify, verify, reset };
}

export function securityQuestionResetRouter(dependencies) {
  const router = express.Router();
  const service = createSecurityQuestionReset(dependencies);
  router.post("/security-question/identify", async (req, res, next) => {
    try { res.json(await service.identify(req.body.account, req.ip)); } catch (error) { next(error); }
  });
  router.post("/security-question/verify", async (req, res, next) => {
    try { res.json(await service.verify(req.body.challenge, req.body.answers, req.ip)); } catch (error) { next(error); }
  });
  router.post("/security-question/reset", async (req, res, next) => {
    try {
      await service.reset(req.body.resetToken, req.body.newPassword, req.body.confirmNewPassword, req.ip);
      res.json({ message: "Password Reset Successfully" });
    } catch (error) { next(error); }
  });
  router.use(passwordSecurityErrors);
  return router;
}
