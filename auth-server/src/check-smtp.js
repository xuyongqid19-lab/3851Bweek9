import './load-env.js';
import { createMailer } from "./mailer.js";

try {
  if ((process.env.RESET_CODE_SECRET || '').length < 32) throw new Error('RESET_CODE_SECRET needs at least 32 characters');
  await createMailer().verify();
  console.log("SMTP connection and authentication succeeded. No test email was sent.");
} catch (error) {
  console.error("SMTP verification failed. Check SMTP_USER, the QQ authorization code, SMTP settings, and network access.");
  if (/^[A-Z_]+$/.test(error.code || "")) console.error("Error code:", error.code);
  process.exitCode = 1;
}
