import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const file = fileURLToPath(new URL('../../.env', import.meta.url));
if (existsSync(file)) {
  if (typeof process.loadEnvFile !== 'function') throw new Error('Loading local .env requires Node 20.12 or newer; alternatively supply variables using your existing launcher.');
  process.loadEnvFile(file);
}
