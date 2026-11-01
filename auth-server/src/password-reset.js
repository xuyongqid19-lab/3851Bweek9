import { createHmac, randomInt, randomUUID, timingSafeEqual } from "node:crypto";
import bcrypt from "bcryptjs";
import express from "express";

export const REQUEST_MESSAGE = "If this email belongs to an account with a password, a code has been sent. Check your inbox and spam folder.";
const INVALID_CODE = "Invalid or expired code. Request a new code if needed.";

class ResetError extends Error {
  constructor(status, message, retryAfterSeconds) {
    super(message);
    this.status = status;
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

export function normalizeEmail(value) {
  const email = typeof value === "string" ? value.trim().toLowerCase() : "";
  if (email.length > 254 || !/^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$/.test(email)) {
    throw new ResetError(400, "Enter a valid email address.");
  }
  return email;
}

export function createPasswordReset({ pool, mailer, secret }) {
  const digest = (value) => createHmac("sha256", secret).update(value).digest("hex");
  const ensureConfigured = () => {
    if (!mailer.configured || typeof secret !== "string" || secret.length < 32) {
      throw new ResetError(503, "Password reset email is not configured. Please contact the administrator.");
    }
  };

  // Database counters survive restarts and are shared by all API instances.
  async function rateLimit(scope, identity, maximum, seconds) {
    const result = await pool.query(
      `INSERT INTO auth_rate_limits AS limits (key, hits, expires_at)
       VALUES ($1, 1, now() + $2 * interval '1 second')
       ON CONFLICT (key) DO UPDATE SET
         hits = CASE WHEN limits.expires_at <= now() THEN 1 ELSE limits.hits + 1 END,
         expires_at = CASE WHEN limits.expires_at <= now()
           THEN now() + $2 * interval '1 second' ELSE limits.expires_at END
       WHERE limits.expires_at <= now() OR limits.hits < $3
       RETURNING hits`,
      [digest(`${scope}:${identity}`), seconds, maximum],
    );
    if (!result.rowCount) {
      throw new ResetError(429, "Too many attempts. Please wait before trying again.", seconds);
    }
  }

  async function requestCode(emailValue, ip) {
    ensureConfigured();
    const email = normalizeEmail(emailValue);
    await rateLimit("send-ip", ip, 20, 3600);
    await rateLimit("send-email-minute", email, 1, 60);
    await rateLimit("send-email-hour", email, 5, 3600);
    const code = String(randomInt(0, 1000000)).padStart(6, "0");
    const requestId = randomUUID();
    const client = await pool.connect();
    let user;
    try {
      await client.query("BEGIN");
      const result = await client.query(
        "SELECT id, password_hash FROM users WHERE lower(email) = $1 FOR UPDATE", [email],
      );
      user = result.rows[0];
      if (user?.password_hash) {
        await client.query(
          `INSERT INTO password_reset_codes (user_id, request_id, code_hash, expires_at)
           VALUES ($1, $2, $3, now() + interval '10 minutes')
           ON CONFLICT (user_id) DO UPDATE SET request_id = EXCLUDED.request_id,
             code_hash = EXCLUDED.code_hash, expires_at = EXCLUDED.expires_at,
             attempts = 0, delivered = false`,
          [user.id, requestId, digest(`${requestId}:${code}`)],
        );
      }
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
    // Google-only accounts must continue using Google sign-in.
    if (!user?.password_hash) return;
    try {
      await mailer.sendCode(email, code);
      await pool.query(
        "UPDATE password_reset_codes SET delivered = true WHERE user_id = $1 AND request_id = $2",
        [user.id, requestId],
      );
    } catch (error) {
      await pool.query("DELETE FROM password_reset_codes WHERE user_id = $1 AND request_id = $2", [user.id, requestId]);
      // Never log the SMTP credentials, email, reset code, or full SMTP response.
      console.error("Password reset delivery failed:", /^[A-Z_]+$/.test(error.code || "") ? error.code : "DELIVERY_ERROR");
      throw new ResetError(503, "Could not send the email. Please wait 60 seconds and try again, or contact the administrator.");
    }
  }

  async function resetPassword(emailValue, code, password, ip) {
    ensureConfigured();
    const email = normalizeEmail(emailValue);
    await rateLimit("verify-ip", ip, 100, 900);
    if (typeof code !== "string" || !/^\d{6}$/.test(code)) {
      throw new ResetError(400, "Enter the 6-digit code.");
    }
    if (typeof password !== "string" || password.length < 6 || Buffer.byteLength(password, "utf8") > 72) {
      throw new ResetError(400, "Password must have at least 6 characters and at most 72 UTF-8 bytes.");
    }
    const client = await pool.connect();
    let invalid = false;
    try {
      await client.query("BEGIN");
      const users = await client.query(
        "SELECT id FROM users WHERE lower(email) = $1 FOR UPDATE", [email],
      );
      const user = users.rows[0];
      const result = user ? await client.query(
        "SELECT *, expires_at > now() AS active FROM password_reset_codes WHERE user_id = $1 FOR UPDATE", [user.id],
      ) : { rows: [] };
      const reset = result.rows[0];
      if (!reset || !reset.active || !reset.delivered || reset.attempts >= 5) {
        invalid = true;
      } else if (!timingSafeEqual(Buffer.from(reset.code_hash, "hex"), Buffer.from(digest(`${reset.request_id}:${code}`), "hex"))) {
        await client.query("UPDATE password_reset_codes SET attempts = attempts + 1 WHERE user_id = $1", [user.id]);
        invalid = true;
      } else {
        const hash = await bcrypt.hash(password, 12);
        await client.query(
          "UPDATE users SET password_hash = $1, session_version = session_version + 1, updated_at = now() WHERE id = $2",
          [hash, user.id],
        );
        await client.query("DELETE FROM password_reset_codes WHERE user_id = $1", [user.id]);
      }
      // Commit incorrect-attempt counters as well as successful password changes.
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
    if (invalid) throw new ResetError(400, INVALID_CODE);
  }

  return { requestCode, resetPassword };
}

export function passwordResetRouter(dependencies) {
  const router = express.Router();
  const service = createPasswordReset(dependencies);
  // Do not trust client-supplied X-Forwarded-For; Express uses the socket IP by default.
  router.post("/forgot-password", async (req, res, next) => {
    try {
      await service.requestCode(req.body.email, req.ip);
      res.json({ message: REQUEST_MESSAGE, retryAfterSeconds: 60 });
    } catch (error) { next(error); }
  });
  router.post("/reset-password", async (req, res, next) => {
    try {
      await service.resetPassword(req.body.email, req.body.code, req.body.newPassword, req.ip);
      res.json({ message: "Password reset successfully. Please sign in with your new password." });
    } catch (error) { next(error); }
  });
  router.use((error, _req, res, next) => {
    if (!(error instanceof ResetError)) return next(error);
    if (error.retryAfterSeconds) res.set("Retry-After", String(error.retryAfterSeconds));
    res.status(error.status).json({ error: error.message, retryAfterSeconds: error.retryAfterSeconds });
  });
  return router;
}
