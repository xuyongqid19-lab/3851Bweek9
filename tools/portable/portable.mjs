// Windows-only portable supervisor. All processes and data belong to this folder.
import fs from 'node:fs/promises';
import {existsSync,createWriteStream} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {createServer,request as httpRequest} from 'node:http';
import net from 'node:net';
import {randomBytes,createHash} from 'node:crypto';
import {seedDemo} from './seed.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const data=path.join(root,'data'),logs=path.join(root,'logs');
let pgRoot=root,pg=path.join(root,'runtime/postgres/bin');
const stateFile=path.join(data,'running.json');
const instance=createHash('sha256').update(root.toLowerCase()).digest('hex');
const noBrowser=process.argv.includes('--no-browser');
const command=process.argv[2]||'start';
const children=[];
let pgStarted=false,web,closing=false,lock,settings,serverState;
const pause=ms=>new Promise(r=>setTimeout(r,ms));
const json=async file=>JSON.parse(await fs.readFile(file,'utf8'));
const save=async(file,value)=>{const temp=file+'.tmp';await fs.writeFile(temp,JSON.stringify(value,null,2));await fs.rename(temp,file);};
function run(exe,args,env={}){
  return new Promise((resolve,reject)=>{
    const p=spawn(exe,args,{cwd:root,windowsHide:true,env:{...process.env,...env}});let output='';
    p.stdout.on('data',b=>{output+=b.toString();});p.stderr.on('data',b=>{output+=b.toString();});
    p.on('error',reject);p.on('exit',code=>code===0?resolve(output):reject(new Error(`${path.basename(exe)} exited ${code}: ${output.slice(-2500)}`)));
  });
}
async function fetchJson(url,options={}){
  const r=await fetch(url,{...options,signal:AbortSignal.timeout(8000)});
  if(!r.ok)throw new Error(`HTTP ${r.status} at ${new URL(url).pathname}`);
  return r.json();
}
async function running(){
  try{const s=await json(stateFile);if(s.instance!==instance)return null;
    const status=await fetchJson(s.url+'/__launcher/status');return status.instance===instance?s:null;
  }catch{return null;}
}
function openBrowser(url){
  if(noBrowser)return;
  // Windows URL handler, with a generated loopback URL, never shell-interpolated input.
  const p=spawn('rundll32.exe',['url.dll,FileProtocolHandler',url],{windowsHide:true,stdio:'ignore'});
  p.on('error',()=>console.log(`Open ${url} in your browser.`));p.unref();
}
async function freePort(){
  const s=net.createServer();await new Promise((r,j)=>s.once('error',j).listen(0,'127.0.0.1',r));
  const port=s.address().port;await new Promise(r=>s.close(r));return port;
}
async function waitHealth(url,p){
  for(let i=0;i<60;i++){
    if(p.exitCode!==null)throw new Error('A backend exited. See logs.');
    try{const result=await fetchJson(url+'/health');if(result.ok)return;}catch{}
    await pause(250);
  }
  throw new Error('Backend health check timed out. See logs.');
}
function launch(name,env){
  const file=path.join(root,'source',name,'src/index.js');
  const log=createWriteStream(path.join(logs,name+'.log'),{flags:'a'});
  const p=spawn(process.execPath,[file],{cwd:path.dirname(file),windowsHide:true,env:{...process.env,...env},stdio:['ignore','pipe','pipe']});
  p.stdout.pipe(log);p.stderr.pipe(log);children.push(p);p.on('error',e=>console.error(`${name}: ${e.message}`));
  p.on('exit',code=>{log.end();if(!closing&&serverState){console.error(`${name} stopped (${code}); shutting down this session.`);void shutdown(1);}});
  return p;
}
async function shutdown(code=0){
  if(closing)return;closing=true;
  if(web){web.closeAllConnections();await new Promise(r=>web.close(r));}
  for(const child of children)if(child.exitCode===null)child.kill();
  await Promise.all(children.map(p=>p.exitCode!==null?null:new Promise(r=>{p.once('exit',r);setTimeout(r,3000).unref();})));
  if(pgStarted)try{await run(path.join(pg,'pg_ctl.exe'),['-D',path.join(pgRoot,'data/postgres'),'-m','fast','-w','-t','20','stop']);}catch(e){console.error(e.message);code=1;}
  // Remove only launcher state. User databases and credentials are preserved.
  await fs.unlink(stateFile).catch(()=>{});if(lock){await lock.close();await fs.unlink(path.join(data,'launcher.lock')).catch(()=>{});}
  console.log('Stopped. Your records remain in the data folder.');process.exitCode=code;
}
const escapeHtml=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function dashboard(){
 const accounts=settings.demoAccounts.map(u=>`<tr><td>${escapeHtml(u.label)}</td><td><code>${escapeHtml(u.username)}</code></td><td><code>${escapeHtml(u.password)}</code></td></tr>`).join('');
 return `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Global Village Quick Start</title><style>body{font:17px system-ui;max-width:900px;margin:40px auto;padding:0 24px;background:#f5f7fb;color:#17324f}h1{font-size:36px}a{color:#165bbc}table{border-collapse:collapse;width:100%;background:white}td,th{padding:12px;border:1px solid #ccd6e0;text-align:left}code{font-size:15px}li{margin:10px 0}.open{display:inline-block;padding:14px 24px;color:white;background:#165bbc;border-radius:8px;text-decoration:none}small{color:#536578}</style><h1>Global Village Quick Start</h1><p>Auth, Community, Chat and Family are running locally with persistent databases.</p><p><a class="open" href="/">Open the app</a></p><h2>Test accounts</h2><p>Use either account on the app's Login screen. These accounts belong only to this portable copy.</p><table><tr><th>Role</th><th>Username</th><th>Password</th></tr>${accounts}</table><h2>Quick feature check</h2><ol><li>Log in as Demo Parent and open Family. Two sample families should appear.</li><li>Open Chen Family, view the activity and complete your own daily check-in.</li><li>Open Family tree to link groups with administrator approval. Open large tree to view connections, drag and zoom.</li><li>Open Settings to view membership, invites and administrator controls.</li><li>Log in as Demo Uncle in a private browser window to check member permissions.</li><li>Open Community to view activities. Create an activity and check it from the other account.</li></ol><p>Open <b>Check.bat</b> for service, login and database checks. Use <b>Stop.bat</b> or Ctrl+C in the launcher to stop. Keep the launcher window open while testing.</p><p>Core account, Family and Community API functions work without Internet. Maps, Google login and location services may need network or browser permission. This is the actual Web app, not an Android emulator.</p><small>Windows x64 portable test edition. All local records stay in data/. Copy the folder only after stopping it. Never share a used data/ folder unintentionally. Automatic/exercise check-ins are not enabled.</small></html>`;
}
async function serve(req,res){
 try{
  if(!/^((localhost|127\.0\.0\.1)(:\d+)?)$/.test(req.headers.host||'')){res.writeHead(403);return res.end('Local requests only');}
  const url=new URL(req.url,'http://localhost');
  if(req.headers.origin && ![serverState?.url,`http://127.0.0.1:${web.address().port}`].includes(req.headers.origin)){res.writeHead(403);return res.end('Origin denied');}
  res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');
  if(url.pathname==='/__launcher/status'){res.setHeader('Content-Type','application/json');return res.end(JSON.stringify({instance,ready:!!serverState,edition:'portable-20261015'}));}
  if(url.pathname==='/__launcher/stop'){
   if(req.method!=='POST'||req.headers['x-launcher-token']!==serverState?.token){res.writeHead(403);return res.end('Not authorized');}
   res.end('Stopping');setTimeout(()=>void shutdown(),20);return;
  }
  if(url.pathname==='/launcher'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end(dashboard());}
  const proxy=url.pathname.match(/^\/api\/(auth|community|family|chat)(\/.*)?$/);
  if(proxy){
   const upstream=httpRequest({hostname:'127.0.0.1',port:serverState.ports[proxy[1]],path:(proxy[2]||'/')+url.search,method:req.method,headers:{...req.headers,host:`127.0.0.1:${serverState.ports[proxy[1]]}`}},reply=>{res.writeHead(reply.statusCode,reply.headers);reply.pipe(res);});
   upstream.setTimeout(15000,()=>upstream.destroy(new Error('Backend timeout')));
   upstream.on('error',()=>{if(!res.headersSent)res.writeHead(502);res.end('Backend unavailable');});req.pipe(upstream);return;
  }
  if(!['GET','HEAD'].includes(req.method)){res.writeHead(405);return res.end();}
  const webRoot=path.join(root,'web');const name=decodeURIComponent(url.pathname)==='/'?'index.html':decodeURIComponent(url.pathname).slice(1);
  const file=path.resolve(webRoot,name);
  if(!file.startsWith(webRoot+path.sep)){res.writeHead(403);return res.end();}
  const content=await fs.readFile(file);const types={'.html':'text/html; charset=utf-8','.js':'text/javascript','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.ttf':'font/ttf','.css':'text/css'};
  res.setHeader('Content-Type',types[path.extname(file)]||'application/octet-stream');res.end(req.method==='HEAD'?undefined:content);
 }catch(e){if(!res.headersSent)res.writeHead(e.code==='ENOENT'?404:500);res.end('Unable to serve requested resource');}
}
async function main(){
 if(process.platform!=='win32'||process.arch!=='x64')throw new Error('This package needs Windows 10/11 x64.');
 await fs.mkdir(data,{recursive:true});await fs.mkdir(logs,{recursive:true});
 const existing=await running();
 if(command==='stop'){
  if(!existing){console.log('No running launcher for this folder.');return;}
  const r=await fetch(existing.url+'/__launcher/stop',{method:'POST',headers:{'x-launcher-token':existing.token},signal:AbortSignal.timeout(5000)});
  if(!r.ok)throw new Error('The launcher refused the stop request.');console.log('Stop requested.');return;
 }
 if(command==='check'){
  if(!existing)throw new Error('Run Start.bat first.');
  for(const service of ['auth','community','family','chat']){await fetchJson(existing.url+`/api/${service}/health`);console.log(`PASS ${service} database connection`);}
  const config=await json(path.join(data,'settings.json'));const user=config.demoAccounts[0];
  const session=await fetchJson(existing.url+'/api/auth/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({account:user.username,password:user.password})});
  const family=await fetchJson(existing.url+'/api/family/families',{headers:{Authorization:`Bearer ${session.token}`}});
  const community=await fetchJson(existing.url+'/api/community/community/activities',{headers:{Authorization:`Bearer ${session.token}`}});
  console.log(`PASS authenticated Family and Community reads. Family groups: ${family.groups?.length??family.families?.length??'available'}`);
  console.log('All checks passed. UI and external Google/maps still require interactive checks.');return;
 }
 if(existing){console.log('Already running: '+existing.url);openBrowser(existing.url+'/launcher');return;}
 const system=path.join(process.env.SystemRoot,'System32');
 if(!existsSync(path.join(system,'vcruntime140.dll'))||!existsSync(path.join(system,'msvcp140.dll'))){
  throw new Error('Microsoft Visual C++ x64 Runtime is missing. Run Install-Windows-Runtime.bat once, accept its installer license if you agree, then run Start.bat again. The installer is included; no download is required.');
 }
 // Atomic lock prevents two first-run database initializations.
 try{lock=await fs.open(path.join(data,'launcher.lock'),'wx');}
 catch(e){
  if(e.code!=='EEXIST')throw e;
  const old=await json(path.join(data,'launcher.lock')).catch(()=>null);
  if(!old)throw new Error('Launcher lock is incomplete. Retry after the other startup finishes.');
  try{process.kill(old.pid,0);throw new Error('Another launcher is starting. Wait, then run Start.bat again.');}
  catch(error){if(error.code!=='ESRCH')throw error;}
  await fs.unlink(path.join(data,'launcher.lock'));lock=await fs.open(path.join(data,'launcher.lock'),'wx');
 }
 await lock.writeFile(JSON.stringify({pid:process.pid}));
 // PostgreSQL's Windows command-line tools use legacy path encoding internally.
 // Short aliases preserve non-ASCII folder support without changing system settings.
 if(/[^\x00-\x7f]/.test(root)){
  pgRoot=(await run(path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe'),['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(root,'launcher/short-path.ps1'),'-Directory',root])).trim();
  if(/[^\x00-\x7f]/.test(pgRoot))throw new Error('This drive has no ASCII short-path alias. Extract the package into an English-only folder path, then retry.');
  pg=path.join(pgRoot,'runtime/postgres/bin');
 }
 try{await run(path.join(pg,'postgres.exe'),['--version']);}
 catch(e){throw new Error('The bundled PostgreSQL runtime could not start. Run Install-Windows-Runtime.bat to install/repair the Microsoft x64 runtime, then retry. '+e.message);}
 const settingsFile=path.join(data,'settings.json');
 if(existsSync(settingsFile))settings=await json(settingsFile);
 else {settings={dbPassword:randomBytes(24).toString('hex'),jwtSecret:randomBytes(48).toString('hex'),demoAccounts:[{label:'Demo Parent (owner)',username:'demo.parent',password:'Family-'+randomBytes(5).toString('hex')},{label:'Demo Uncle (member)',username:'demo.uncle',password:'Family-'+randomBytes(5).toString('hex')}]};await save(settingsFile,settings);}
 const dbDir=path.join(pgRoot,'data/postgres');
 if(!existsSync(path.join(dbDir,'PG_VERSION'))){
  console.log('Preparing a private local database (first run only)...');
  const pwfile=path.join(pgRoot,'data/init-password.tmp');await fs.writeFile(pwfile,settings.dbPassword);
  try{await run(path.join(pg,'initdb.exe'),['-D',dbDir,'-U','gv_local','--pwfile='+pwfile,'-A','scram-sha-256','--encoding=UTF8','--locale=C']);}
  finally{await fs.unlink(pwfile).catch(()=>{});}
 }
 // Refuse to adopt a surviving old server. Never stop a database belonging to another process.
 try{await run(path.join(pg,'pg_ctl.exe'),['-D',dbDir,'status']);throw new Error('This folder has an active database from an earlier interrupted run. Close that run or restart Windows before retrying.');}
 catch(e){if(!e.message.includes('pg_ctl.exe exited'))throw e;}
 const dbPort=await freePort();
 await run(path.join(pg,'pg_ctl.exe'),['-D',dbDir,'-l',path.join(pgRoot,'logs/postgres.log'),'-o',`-h 127.0.0.1 -p ${dbPort}`,'-w','-t','30','start']);pgStarted=true;
 const psql=['-h','127.0.0.1','-p',String(dbPort),'-U','gv_local','-v','ON_ERROR_STOP=1'];
 const dbEnv={PGPASSWORD:settings.dbPassword};
 for(const [database,folder,table]of[['global_village_auth','auth-server','users'],['global_village','server','community_activities'],['global_village_chat','chat-server','chat_users']]){
  const present=await run(path.join(pg,'psql.exe'),[...psql,'-d','postgres','-tAc',`SELECT 1 FROM pg_database WHERE datname='${database}'`],dbEnv);
  if(!present.trim())await run(path.join(pg,'createdb.exe'),['-h','127.0.0.1','-p',String(dbPort),'-U','gv_local',database],dbEnv);
  const schema=await run(path.join(pg,'psql.exe'),[...psql,'-d',database,'-tAc',`SELECT to_regclass('public.${table}')`],dbEnv);
  if(!schema.trim())await run(path.join(pg,'psql.exe'),[...psql,'-d',database,'--single-transaction','-f',path.join(pgRoot,'source',folder,'db/init.sql')],dbEnv);
 }
 web=createServer((req,res)=>void serve(req,res));
 for(let port=7357;port<=7377;port++){
  try{await new Promise((r,j)=>{const fail=e=>{web.off('listening',ok);j(e);};const ok=()=>{web.off('error',fail);r();};web.once('error',fail);web.once('listening',ok);web.listen(port,'127.0.0.1');});break;}
  catch(e){if(e.code!=='EADDRINUSE'||port===7377)throw e;}
 }
 const url=`http://localhost:${web.address().port}`;
 const ports={auth:await freePort(),community:await freePort(),family:await freePort(),chat:await freePort()};
 const database=name=>`postgres://gv_local:${settings.dbPassword}@127.0.0.1:${dbPort}/${name}`;
 const auth=launch('auth-server',{HOST:'127.0.0.1',PORT:String(ports.auth),DATABASE_URL:database('global_village_auth'),JWT_SECRET:settings.jwtSecret,GOOGLE_WEB_CLIENT_ID:'848686154651-a5lrjn63ggqj83g5ob4bms7imqd6jkth.apps.googleusercontent.com'});
 await waitHealth(`http://127.0.0.1:${ports.auth}`,auth);
 const community=launch('server',{HOST:'127.0.0.1',PORT:String(ports.community),DATABASE_URL:database('global_village'),AUTH_API_ME_URL:`http://127.0.0.1:${ports.auth}/auth/me`});
 const chat=launch('chat-server',{HOST:'127.0.0.1',PORT:String(ports.chat),DATABASE_URL:database('global_village_chat'),AUTH_API_ME_URL:`http://127.0.0.1:${ports.auth}/auth/me`});
 await waitHealth(`http://127.0.0.1:${ports.chat}`,chat);
 const family=launch('family-server',{HOST:'127.0.0.1',PORT:String(ports.family),FAMILY_DB_PATH:path.join(data,'family.sqlite'),AUTH_API_ME_URL:`http://127.0.0.1:${ports.auth}/auth/me`,ALLOWED_ORIGINS:`${url},http://127.0.0.1:${web.address().port}`});
 await Promise.all([waitHealth(`http://127.0.0.1:${ports.community}`,community),waitHealth(`http://127.0.0.1:${ports.family}`,family)]);
 await seedDemo({ports,settings,data});
 serverState={instance,url,ports,token:randomBytes(32).toString('hex'),pid:process.pid};await save(stateFile,serverState);
 console.log(`\nREADY: ${url}/launcher\nKeep this window open. Use Stop.bat or Ctrl+C to stop.\nAll databases and test accounts are private to this folder.\n`);
 openBrowser(url+'/launcher');
}
process.on('SIGINT',()=>void shutdown());process.on('SIGTERM',()=>void shutdown());
main().catch(async e=>{console.error('LAUNCHER ERROR: '+e.message);if(lock)await shutdown(1);else process.exitCode=1;});
