import nodemailer from "nodemailer";

export function createMailer(env = process.env, transportFactory = nodemailer.createTransport) {
  const user = (env.SMTP_USER || "").trim();
  const password = env.SMTP_PASS || "";
  const configured = Boolean(user && password);
  const transport = configured ? transportFactory({
    host: env.SMTP_HOST || "smtp.qq.com",
    port: Number(env.SMTP_PORT || 465),
    secure: (env.SMTP_SECURE || "true") === "true",
    requireTLS: true,
    auth: { user, pass: password },
    connectionTimeout: 10000,
    greetingTimeout: 10000,
    socketTimeout: 15000,
    dnsTimeout: 10000,
    tls: { minVersion: "TLSv1.2" },
    disableFileAccess: true,
    disableUrlAccess: true,
  }) : null;

  return {
    configured,
    async verify() {
      if (!transport) throw new Error("Configure SMTP_USER and SMTP_PASS first.");
      await transport.verify();
    },
    async sendCode(email, code) {
      if (!transport) throw new Error("Email delivery is not configured.");
      const result = await transport.sendMail({
        from: { name: "Global Village", address: user },
        to: { address: email, name: "" },
        subject: "Global Village - Password reset code / 密码重置验证码",
        text: `Your Global Village password reset code is: ${code}\n\n` +
          "This code expires in 10 minutes and can only be used once. " +
          "Do not share it with anyone. If you did not request a password reset, ignore this email.\n\n" +
          `你的密码重置验证码是：${code}\n有效期 10 分钟，仅可使用一次。请勿向他人透露；如非本人操作，请忽略此邮件。`,
      });
      if (!result.accepted?.length) throw new Error("SMTP did not accept the message.");
    },
  };
}
