import { randomBytes, timingSafeEqual } from 'node:crypto';

// Dependencies are injected so regression tests never contact QQ or save real credentials.
export function createMailSetupApp({ express, sender, initialConnected = false, verifyAndSave }) {
const app = express();
let connected = initialConnected;
let busy = false;
const sessions = new Map();
app.disable('x-powered-by');
app.use((req, res, next) => {
  res.set('Cache-Control', 'no-store');
  res.set('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'");
  // no-referrer can turn a same-origin HTML form POST's Origin into null.
  res.set('Referrer-Policy', 'same-origin');
  res.set('X-Content-Type-Options', 'nosniff');
  const port = req.socket.localPort;
  if (![ `127.0.0.1:${port}`, `localhost:${port}` ].includes(req.headers.host)) {
    return res.status(403).send('不允许的访问地址。');
  }
  next();
});
app.use(express.urlencoded({ extended: false, limit: '2kb' }));
function session(req, res) {
  const now = Date.now();
  for (const [id, value] of sessions) if (value.expires < now) sessions.delete(id);
  const id = /(?:^|;\s*)mail_setup_session=([a-f0-9]{64})(?:;|$)/.exec(req.headers.cookie || '')?.[1];
  return id && sessions.get(id);
}
function newSession(res) {
  if (sessions.size >= 200) sessions.delete(sessions.keys().next().value);
  const id = randomBytes(32).toString('hex');
  const value = { token: randomBytes(32).toString('hex'), expires: Date.now() + 600000, message: '' };
  sessions.set(id, value);
  res.setHeader('Set-Cookie', `mail_setup_session=${id}; HttpOnly; SameSite=Strict; Path=/; Max-Age=600`);
  return value;
}
function page(token, message = '') {
  return `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>连接 QQ 发件邮箱</title>
  <style>body{font-family:system-ui,"Microsoft YaHei",sans-serif;background:#f3f6fa;color:#182330;max-width:520px;margin:8vh auto;padding:24px}main{background:white;border:1px solid #dee5ed;border-radius:16px;padding:28px}h1{font-size:24px}p{line-height:1.8;color:#485569}label{display:block;margin:22px 0 8px}input,button{box-sizing:border-box;width:100%;font-size:16px;padding:14px;border-radius:8px;border:1px solid #bdc9d6}button{margin-top:18px;background:#1767cc;color:white;border:0;cursor:pointer}.notice{padding:12px;background:#edf5ff;border-radius:8px}.small{font-size:13px}</style>
  <main><h1>${connected ? '邮箱已连接' : '连接 QQ 发件邮箱'}</h1>
  <p>发件邮箱：<strong>${sender}</strong></p>
  ${message ? `<p class="notice">${message}</p>` : ''}
  ${connected ? '<p>配置已保存到这台电脑。请回到聊天告诉我“已连接”，剩下的启动和测试由我完成。</p>' : `<p>在 QQ 邮箱完成手机号验证并开启 SMTP 服务后，会显示一段<strong>授权码</strong>。将它粘贴到下方即可。</p>
  <form method="post" action="/connect"><input type="hidden" name="csrf" value="${token}"><label for="code">QQ 邮箱授权码</label><input id="code" name="code" type="password" autocomplete="off" minlength="8" maxlength="128" required placeholder="在这里粘贴授权码"><button type="submit">连接邮箱</button></form>
  <p class="small">授权码只会发送给 QQ 的邮件服务器用于验证，并保存到本机项目配置；请不要填写 QQ 登录密码，也不用发到聊天中。</p>`}</main></html>`;
}

app.get(['/', '/connect'], (req, res) => {
  const state = session(req, res) || newSession(res);
  const message = state.message;
  state.message = '';
  res.type('html').send(page(state.token, message));
});
app.get('/status', (_req, res) => res.json({ connected, version: 'csrf-origin-fix-1', platform: process.platform, address: '127.0.0.1' }));
app.post('/connect', async (req, res) => {
  const origin = req.headers.origin;
  const expectedOrigin = `http://${req.headers.host}`;
  if (req.headers['sec-fetch-site'] === 'cross-site' ||
      (origin && origin !== 'null' && origin !== expectedOrigin)) {
    return res.status(403).send('请求来源不匹配，请从本机邮箱连接页面提交。');
  }
  const state = session(req, res);
  const token = req.body?.csrf;
  if (!state || typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token) ||
      !timingSafeEqual(Buffer.from(token), Buffer.from(state.token))) {
    const fresh = newSession(res);
    fresh.message = '表单已刷新，请重新填写授权码并提交。';
    return res.redirect(303, '/connect');
  }
  const finish = message => { state.message = message; return res.redirect(303, '/connect'); };
  if (busy) return finish('正在连接，请稍候再试。');
  if (connected) return finish('邮箱已经连接。');
  const code = typeof req.body?.code === 'string' ? req.body.code.trim() : '';
  if (!/^[a-zA-Z0-9]{8,128}$/.test(code)) return finish('请粘贴 QQ 邮箱提供的完整授权码。');
  busy = true;
  try {
    await verifyAndSave(code);
    connected = true;
    state.token = randomBytes(32).toString('hex');
    return finish('邮箱连接成功，配置已保存。');
  } catch {
    return finish('连接未成功。请确认已开启 SMTP 服务，粘贴的是该邮箱最新生成的授权码，然后重试。');
  } finally { busy = false; }
});
return app;
}
