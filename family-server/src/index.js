import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { FamilyStore } from './store.js';
import { authVerifier,familyServer } from './app.js';

const db=resolve(process.env.FAMILY_DB_PATH??'data/family.sqlite');
mkdirSync(dirname(db),{recursive:true});
const store=new FamilyStore(db);
const server=familyServer(store,authVerifier(process.env.AUTH_API_ME_URL??'http://localhost:3002/auth/me'),{
  origins:(process.env.ALLOWED_ORIGINS??'http://localhost:7357').split(',').map(s=>s.trim()),
});
server.listen(Number(process.env.PORT??3003),process.env.HOST??'127.0.0.1',()=>console.log('Family API ready on port '+(process.env.PORT??3003)));
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>server.close(()=>{store.close();process.exit(0);}));
