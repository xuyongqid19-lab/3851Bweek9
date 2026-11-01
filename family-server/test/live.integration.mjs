// Opt-in local integration check. Creates synthetic accounts and family records.
// Run only with the local development Auth, Community and Family services running.
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';

const auth = 'http://127.0.0.1:3002';
const family = 'http://127.0.0.1:3003';
const community = 'http://127.0.0.1:3000';
async function call(base, path, { method = 'GET', body, token } = {}) {
  const response = await fetch(base + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
    signal: AbortSignal.timeout(12000),
  });
  return { status: response.status, data: await response.json() };
}
for (const base of [auth, family, community]) {
  assert.equal((await call(base, '/health')).status, 200, `Service is unavailable: ${base}`);
}
const runId = randomBytes(5).toString('hex');
const users = [];
for (const label of ['parent', 'uncle']) {
  const username = `family.check.${label}.${runId}`;
  const password = randomBytes(24).toString('base64url');
  const registration = await call(auth, '/auth/register', { method: 'POST', body: {
    fullName: `Test ${label}`, birthDate: '01/01/1990', interest: 'Family', username,
    email: `${username}@example.test`, phone: '10000000000', password,
    securityQuestion: 'Local integration test', securityAnswer: randomBytes(16).toString('hex'),
  }});
  assert.equal(registration.status, 201, 'Registration failed');
  const login = await call(auth, '/auth/login', { method: 'POST', body: { account: username, password } });
  assert.equal(login.status, 200, 'Login failed');
  users.push(login.data);
}
const [parent, uncle] = users;
const as = (user, path, method = 'GET', body) => call(family, path, { method, body, token: user.token });
const main = await as(parent, '/families', 'POST', { name: `Integration ${runId}`, description: 'Synthetic local data', realName: '陈建国', kinship: '爸爸' });
assert.equal(main.status, 200);
const id = main.data.id;
const second = await as(uncle, '/families', 'POST', { name: `Second ${runId}`, realName: '陈建民', kinship: '舅舅' });
assert.equal(second.status, 200);
assert.equal((await as(parent, `/families/${second.data.id}`)).status, 404);
const preview = await as(uncle, '/families/preview', 'POST', { invite: main.data.invite });
assert.deepEqual(Object.keys(preview.data).sort(), ['description', 'id', 'name']);
const join = { invite: main.data.invite, realName: '陈建民', kinship: '舅舅' };
assert.equal((await as(uncle, '/families/join', 'POST', join)).status, 200);
assert.equal((await as(uncle, '/families/join', 'POST', join)).status, 409);
assert.equal((await as(uncle, `/families/${id}`, 'PATCH', { name: 'Not allowed' })).status, 403);
const task = await as(parent, `/families/${id}/tasks`, 'POST', {
  title: 'Manual daily', type: 'manualDaily', repeat: 'Every day', participantIds: [parent.user.id],
});
assert.equal(task.status, 200);
assert.equal((await as(uncle, `/families/${id}/checkins/${task.data.id}`, 'POST', {})).status, 403);
const repeated = await Promise.all(Array.from({ length: 4 }, () => as(parent, `/families/${id}/checkins/${task.data.id}`, 'POST', {})));
assert.ok(repeated.every(r => r.status === 200));
const detail = await as(parent, `/families/${id}`);
assert.equal(detail.data.checkins.length, 1);
assert.equal(detail.data.me.realName, '陈建国');
assert.equal((await as(uncle, '/families')).data.primaryId, second.data.id);
assert.equal((await call(community, '/community/activities', { token: parent.token })).status, 200);
console.log(`PASS: live Auth/Community/Family integration (${runId}); synthetic records remain in the local databases. No credentials printed.`);
