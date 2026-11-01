import bcrypt from "bcryptjs";
import { PasswordSecurityError, passwordGuards } from "./password-security.js";
import { validateQuestions, hashQuestions, writeQuestions } from "./security-questions.js";

export function registrationHandler({ pool, secret, clean, parseBirthDate, publicUser }) {
  const guards = passwordGuards({ pool, secret });
  return async (req, res, next) => {
    try {
      const fullName = clean(req.body.fullName);
      const birthDate = parseBirthDate(req.body.birthDate);
      const interest = clean(req.body.interest) || null;
      const username = clean(req.body.username);
      const email = clean(req.body.email).toLowerCase();
      const phone = clean(req.body.phone);
      const password = typeof req.body.password === "string" ? req.body.password : "";
      // Old single-question payloads must not silently become partial configurations.
      if (clean(req.body.securityQuestion) || clean(req.body.securityAnswer)) {
        throw new PasswordSecurityError(400, "Please configure three security questions, or leave them all empty.");
      }
      const questions = validateQuestions(req.body.securityQuestions, { optional: true });

      if (!fullName || !birthDate || !username || !email || !phone || !password) {
        res.status(400).json({ error: "Please complete all required registration fields." });
        return;
      }
      if (password.length < 6) {
        res.status(400).json({ error: "Password must contain at least 6 characters." });
        return;
      }

      const existing = await pool.query(
        `SELECT id, email, username
         FROM users
         WHERE lower(email) = lower($1)
            OR lower(username) = lower($2)
         LIMIT 1`,
        [email, username],
      );
      if (existing.rows.length > 0) {
        const row = existing.rows[0];
        const field = row.email.toLowerCase() === email ? "Email" : "Username";
        res.status(409).json({ error: `${field} is already registered.` });
        return;
      }

      const passwordHash = await bcrypt.hash(password, 12);
      const hashed = await hashQuestions(questions);
      const result = await guards.transaction(async (client) => {
        const inserted = await client.query(
        `INSERT INTO users (
          full_name,
          birth_date,
          interest,
          username,
          email,
          phone,
          password_hash,
          auth_provider
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,'local')
        RETURNING *`,
        [
          fullName,
          birthDate,
          interest,
          username,
          email,
          phone,
          passwordHash,
        ],
      );

        if (hashed.length) await writeQuestions(client, inserted.rows[0].id, hashed);
        return inserted;
      });
      res.status(201).json({ user: publicUser(result.rows[0]) });
    } catch (error) {
      if (error instanceof PasswordSecurityError) {
        res.status(error.status).json({ error: error.message });
        return;
      }
      if (error?.code === "23505") {
        res.status(409).json({ error: "Email or username is already registered." });
        return;
      }
      next(error);
    }
  };
}
