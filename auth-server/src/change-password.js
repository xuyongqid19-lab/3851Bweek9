import bcrypt from "bcryptjs";
import express from "express";
import { PasswordSecurityError, passwordGuards, passwordSecurityErrors, validateNewPassword, boundedBcryptInput } from "./password-security.js";

export function createChangePassword(dependencies) {
  const guards = passwordGuards(dependencies);
  return async function changePassword(auth, currentPassword, newPassword, confirmation, ip) {
    await guards.rateLimit("change-password-ip", ip);
    if (!auth?.sub) throw new PasswordSecurityError(401, "Authentication required.");
    validateNewPassword(newPassword, confirmation);
    const currentInput = typeof currentPassword === "string" ? boundedBcryptInput(currentPassword) : "";
    if (!currentInput) {
      throw new PasswordSecurityError(400, "Enter your current password.");
    }
    return guards.transaction(async (client) => {
      const user = (await client.query("SELECT * FROM users WHERE id = $1 FOR UPDATE", [auth.sub])).rows[0];
      // Middleware checks before the transaction; check again under the lock to close the race.
      if (!user || (auth.version || 0) !== user.session_version) return new PasswordSecurityError(401, "Session expired. Please sign in again.");
      if (!user.password_hash) return new PasswordSecurityError(400, "This account uses Google sign-in and has no local password. Please continue with Google.");
      if (await guards.blocked(client, "change-password-failures", user.id)) {
        return new PasswordSecurityError(429, "Too many attempts. Please try again in 15 minutes.", 900);
      }
      if (!await bcrypt.compare(currentInput, user.password_hash)) {
        const limited = await guards.failed(client, "change-password-failures", user.id);
        return new PasswordSecurityError(limited ? 429 : 400, limited ? "Too many attempts. Please try again in 15 minutes." : "Current password is incorrect.", limited ? 900 : undefined);
      }
      await guards.clear(client, "change-password-failures", user.id);
      if (await bcrypt.compare(newPassword, user.password_hash)) return new PasswordSecurityError(400, "New password must be different from your current password.");
      const hash = await bcrypt.hash(newPassword, 12);
      await client.query("UPDATE users SET password_hash = $1, session_version = session_version + 1, updated_at = now() WHERE id = $2", [hash, user.id]);
      await client.query("DELETE FROM security_question_challenges WHERE user_id = $1", [user.id]);
      await client.query("DELETE FROM password_reset_codes WHERE user_id = $1", [user.id]);
    });
  };
}

export function changePasswordRouter(dependencies) {
  const router = express.Router();
  const changePassword = createChangePassword(dependencies);
  router.post("/change-password", dependencies.requireAuth, async (req, res, next) => {
    try {
      await changePassword(req.auth, req.body.currentPassword, req.body.newPassword, req.body.confirmNewPassword, req.ip);
      res.json({ message: "Password changed successfully. Please sign in again." });
    } catch (error) { next(error); }
  });
  router.use(passwordSecurityErrors);
  return router;
}
