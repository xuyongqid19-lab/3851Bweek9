import { createHash, createHmac } from "node:crypto";

export class PasswordSecurityError extends Error {
  constructor(status, message, retryAfterSeconds) {
    super(message);
    this.status = status;
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

export const tokenHash = (token) => createHash("sha256").update(token).digest("hex");
export const validToken = (token) => typeof token === "string" && /^[a-f0-9]{64}$/.test(token);

export function boundedBcryptInput(value) {
  // bcrypt uses only the first 72 UTF-8 bytes. Keep enough complete UTF-16 units
  // to preserve those bytes while bounding bcrypt input to at most 384 bytes.
  // Avoid introducing a dangling high surrogate at the truncation boundary.
  return value.slice(0, 128).replace(/[\uD800-\uDBFF]$/, "");
}

export function validateNewPassword(password, confirmation) {
  if (typeof password !== "string" || password.length < 6 || Buffer.byteLength(password, "utf8") > 72) {
    throw new PasswordSecurityError(400, "Password must have at least 6 characters and at most 72 UTF-8 bytes.");
  }
  if (password !== confirmation) throw new PasswordSecurityError(400, "Passwords do not match.");
}

export function passwordGuards({ pool, secret }) {
  const key = (scope, identity) => createHmac("sha256", secret).update(`${scope}:${identity}`).digest("hex");
  async function rateLimit(scope, identity, maximum = 30, seconds = 900) {
    const result = await pool.query(
      `INSERT INTO auth_rate_limits AS limits (key, hits, expires_at)
       VALUES ($1, 1, now() + $2 * interval '1 second')
       ON CONFLICT (key) DO UPDATE SET
         hits = CASE WHEN limits.expires_at <= now() THEN 1 ELSE limits.hits + 1 END,
         expires_at = CASE WHEN limits.expires_at <= now()
           THEN now() + $2 * interval '1 second' ELSE limits.expires_at END
       WHERE limits.expires_at <= now() OR limits.hits < $3 RETURNING hits`,
      [key(scope, identity), seconds, maximum],
    );
    if (!result.rowCount) throw new PasswordSecurityError(429, "Too many attempts. Please try again in 15 minutes.", seconds);
  }
  // Call these only while holding the corresponding users row lock.
  async function blocked(client, scope, identity) {
    const result = await client.query(
      "SELECT hits FROM auth_rate_limits WHERE key = $1 AND expires_at > clock_timestamp()",
      [key(scope, identity)],
    );
    return (result.rows[0]?.hits || 0) >= 5;
  }
  async function failed(client, scope, identity) {
    const result = await client.query(
      `INSERT INTO auth_rate_limits AS limits (key, hits, expires_at)
       VALUES ($1, 1, clock_timestamp() + interval '15 minutes')
       ON CONFLICT (key) DO UPDATE SET
         hits = CASE WHEN limits.expires_at <= clock_timestamp() THEN 1 ELSE limits.hits + 1 END,
         expires_at = CASE WHEN limits.expires_at <= clock_timestamp() OR limits.hits = 4
           THEN clock_timestamp() + interval '15 minutes' ELSE limits.expires_at END RETURNING hits`,
      [key(scope, identity)],
    );
    return result.rows[0].hits >= 5;
  }
  async function clear(client, scope, identity) {
    await client.query("DELETE FROM auth_rate_limits WHERE key = $1", [key(scope, identity)]);
  }
  async function transaction(action) {
    const client = await pool.connect();
    let result;
    try {
      await client.query("BEGIN");
      result = await action(client);
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally { client.release(); }
    // Expected failures are returned so failed-attempt counters are committed.
    if (result instanceof PasswordSecurityError) throw result;
    return result;
  }
  return { key, rateLimit, blocked, failed, clear, transaction };
}

export function passwordSecurityErrors(error, _req, res, next) {
  if (!(error instanceof PasswordSecurityError)) {
    // Do not pass database/bcrypt errors to the legacy logger: they may contain parameters.
    console.error("Password security operation failed.");
    return res.status(500).json({ error: "Server error. Please try again." });
  }
  if (error.retryAfterSeconds) res.set("Retry-After", String(error.retryAfterSeconds));
  res.status(error.status).json({ error: error.message, retryAfterSeconds: error.retryAfterSeconds });
}
