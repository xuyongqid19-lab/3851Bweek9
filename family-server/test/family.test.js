import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { FamilyStore, FamilyError } from '../src/store.js';
import { familyServer, authVerifier } from '../src/app.js';
import { createServer, request as httpRequest } from 'node:http';

const identity={realName:'Chen Ming',kinship:'Dad'};
const create=(s,user='alice',name='Chen Family')=>s.create(user,{...identity,name,description:'Care and safety'});
function fixture(t){const s=new FamilyStore(':memory:',()=> '2026-09-09T12:00:00.000Z');t.after(()=>s.close());return s;}
const isStatus=(status)=>e=>e instanceof FamilyError&&e.status===status;
function activity(ids=['alice']){return {title:'Family dinner',participantIds:ids,date:'2026-09-13',duration:'2 hours',location:'Home',goal:'Together',description:'Cook together',requirements:'Bring fruit',tags:'Food, Care'};}

test('creation validates both identities and first family becomes primary',t=>{
  const s=fixture(t);
  for(const field of ['realName','kinship','name'])assert.throws(()=>s.create('alice',{...identity,name:'Home',[field]:'  '}),isStatus(400));
  assert.equal(s.list('alice').groups.length,0);
  const g=create(s);assert.equal(g.me.role,'owner');assert.equal(s.list('alice').primaryId,g.id);
  assert.equal(g.members[0].kinship,'Dad');assert.match(g.invite,/^[0-9A-F]{18}$/);
});
test('join preview contains no private member data and cannot be repeated',t=>{
  const s=fixture(t),g=create(s);assert.deepEqual(Object.keys(s.preview(g.invite)).sort(),['description','id','name']);
  const b=s.join('bob',{invite:g.invite,realName:'Bo Chen',kinship:'Uncle'});
  assert.equal(b.me.role,'member');assert.equal(b.invite,undefined);
  assert.throws(()=>s.join('bob',{invite:g.invite,realName:'Bo',kinship:'Uncle'}),isStatus(409));
  assert.equal(s.detail(g.id,'alice').members.length,2);
  assert.throws(()=>s.preview('INVALID'),isStatus(404));
});
test('each user owns their primary selection and per-family identity',t=>{
  const s=fixture(t),a=create(s),b=create(s,'alice','Second');
  s.join('bob',{invite:a.invite,realName:'Bob',kinship:'Dad'});
  s.join('bob',{invite:b.invite,realName:'Bob',kinship:'Uncle'});
  s.setPrimary(b.id,'alice');assert.equal(s.list('alice').primaryId,b.id);assert.equal(s.list('bob').primaryId,a.id);
  assert.equal(s.detail(b.id,'bob').me.kinship,'Uncle');
  assert.throws(()=>s.setPrimary(a.id,'stranger'),isStatus(404));
});
test('record and detail access are isolated across families',t=>{
  const s=fixture(t),a=create(s),b=create(s,'bob','Other');
  s.addRecord(a.id,'alice','activities',activity());
  assert.equal(s.detail(b.id,'bob').records.length,0);
  assert.throws(()=>s.detail(a.id,'bob'),isStatus(404));
  assert.throws(()=>s.addRecord(a.id,'bob','activities',activity()),isStatus(404));
  assert.throws(()=>s.addRecord(a.id,'alice','activities',activity(['bob'])),isStatus(404));
});
test('admin rights are server enforced and invite rotation invalidates old code',t=>{
  const s=fixture(t),g=create(s);s.join('bob',{invite:g.invite,realName:'Bob',kinship:'Grandfather'});
  assert.throws(()=>s.rotate(g.id,'bob'),isStatus(403));
  assert.throws(()=>s.update(g.id,'bob',{name:'Hijack',description:''}),isStatus(403));
  assert.throws(()=>s.role(g.id,'bob','alice',{role:'member'}),isStatus(403));
  assert.throws(()=>s.addRecord(g.id,'bob','notes',{title:'Private',note:'Note'}),isStatus(403));
  s.role(g.id,'alice','bob',{role:'admin'});s.update(g.id,'bob',{name:'Updated',description:''});
  const rotated=s.rotate(g.id,'bob');assert.notEqual(rotated.invite,g.invite);assert.throws(()=>s.preview(g.invite),isStatus(404));
});
test('ownership transfer, leave and primary fallback are atomic',t=>{
  const s=fixture(t),a=create(s),b=create(s,'alice','Second');s.join('bob',{invite:a.invite,realName:'Bob',kinship:'Uncle'});
  assert.throws(()=>s.leave(a.id,'alice'),isStatus(409));assert.equal(s.detail(a.id,'alice').members.length,2);
  s.role(a.id,'alice','bob',{role:'owner'});assert.equal(s.detail(a.id,'bob').me.role,'owner');
  s.leave(a.id,'alice');assert.equal(s.list('alice').primaryId,b.id);assert.throws(()=>s.detail(a.id,'alice'),isStatus(404));
  s.leave(b.id,'alice');assert.equal(s.list('alice').primaryId,null);assert.throws(()=>s.preview(b.invite),isStatus(404));
});
test('read positions are per group and only acknowledge seen updates',t=>{
  const s=fixture(t),a=create(s),b=create(s,'alice','Second');
  const seen=s.detail(a.id,'alice').events[0].id;s.addRecord(a.id,'alice','notes',{title:'Note',note:'Sensitive health information'});
  s.read(a.id,'alice',seen);assert.equal(s.detail(a.id,'alice').unread,1);assert.equal(s.detail(b.id,'alice').unread,1);
  assert.ok(!s.detail(a.id,'alice').latest.summary.includes('Sensitive'));
  s.read(a.id,'alice',9999);assert.equal(s.detail(a.id,'alice').unread,0);
  s.read(a.id,'alice',0);assert.equal(s.detail(a.id,'alice').unread,0);
});
test('manual check-in is idempotent and limited to assigned users',t=>{
  const s=fixture(t),g=create(s);s.join('bob',{invite:g.invite,realName:'Bob',kinship:'Uncle'});
  const r=s.addRecord(g.id,'alice','tasks',{title:'Daily check',type:'manualDaily',repeat:'Every day',participantIds:['alice']});
  s.checkIn(g.id,'alice',r.id);s.checkIn(g.id,'alice',r.id);assert.equal(s.detail(g.id,'alice').checkins.length,1);
  assert.throws(()=>s.checkIn(g.id,'bob',r.id),isStatus(403));
  const auto=s.addRecord(g.id,'alice','tasks',{title:'Auto',type:'autoLogin',repeat:'Every day',participantIds:['alice']});
  assert.throws(()=>s.checkIn(g.id,'alice',auto.id),isStatus(400));
});
test('invalid records do not create events or rows',t=>{
  const s=fixture(t),g=create(s);const before=s.detail(g.id,'alice').events.length;
  assert.throws(()=>s.addRecord(g.id,'alice','activities',{...activity(),date:'2026-02-30'}),isStatus(400));
  assert.throws(()=>s.addRecord(g.id,'alice','activities',{...activity(),participantIds:[]}),isStatus(400));
  assert.throws(()=>s.addRecord(g.id,'alice','activities',{...activity(),participantIds:[{}]}),isStatus(400));
  assert.equal(s.detail(g.id,'alice').events.length,before);assert.equal(s.detail(g.id,'alice').records.length,0);
});
test('records and preferences survive reopening SQLite',t=>{
  const dir=mkdtempSync(join(tmpdir(),'family-test-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));const path=join(dir,'family.db');
  const s=new FamilyStore(path);const g=create(s);s.addRecord(g.id,'alice','activities',activity());s.close();
  const reopened=new FamilyStore(path);assert.equal(reopened.list('alice').primaryId,g.id);assert.equal(reopened.detail(g.id,'alice').records.length,1);reopened.close();
});
test('transaction rolls back both record and event when storage rejects a write',t=>{
  const s=fixture(t),g=create(s);s.db.exec("CREATE TRIGGER reject_event BEFORE INSERT ON events BEGIN SELECT RAISE(ABORT,'disk write test'); END;");
  assert.throws(()=>s.addRecord(g.id,'alice','activities',activity()));assert.equal(s.detail(g.id,'alice').records.length,0);
});
test('corrupt existing database is not silently replaced',t=>{
  const dir=mkdtempSync(join(tmpdir(),'family-corrupt-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));const path=join(dir,'family.db');writeFileSync(path,'corrupt user data');assert.throws(()=>new FamilyStore(path));
});
async function listen(server){await new Promise(r=>server.listen(0,'127.0.0.1',r));return `http://127.0.0.1:${server.address().port}`;}
async function close(server){await new Promise(r=>server.close(r));}
test('HTTP verifies auth boundary, rejects spoofed IDs and disallowed origins',async t=>{
  const s=fixture(t);const seen=[];
  const auth=createServer((req,res)=>{seen.push(req.headers.authorization);res.setHeader('Content-Type','application/json');if(req.headers.authorization==='Bearer valid'){res.end(JSON.stringify({user:{id:'alice'}}));}else{res.writeHead(401);res.end('{}');}});
  const authUrl=await listen(auth);t.after(()=>close(auth));
  const server=familyServer(s,authVerifier(authUrl),{logger:{error(){}}});const url=await listen(server);t.after(()=>close(server));
  const request=(method,path,body,token='valid')=>fetch(url+path,{method,headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},...(body?{body:JSON.stringify(body)}:{})});
  assert.equal((await request('GET','/families',null,'bad')).status,401);
  const g=await (await request('POST','/families',{...identity,name:'HTTP family',userId:'spoof'})).json();
  assert.equal(g.me.userId,'alice');assert.equal(s.list('spoof').groups.length,0);assert.ok(seen.includes('Bearer valid'));
  assert.equal((await fetch(url+'/families',{headers:{Origin:'https://evil.example',Authorization:'Bearer valid'}})).status,403);
  assert.equal((await fetch(url+'/families',{method:'POST',headers:{Authorization:'Bearer valid'},body:'{broken'})).status,400);
});
test('Auth failure never falls back to a demo identity',async t=>{
  const auth=createServer((_req,res)=>{res.writeHead(500);res.end('offline');});const url=await listen(auth);t.after(()=>close(auth));
  await assert.rejects(authVerifier(url)('Bearer valid'),isStatus(503));
  await assert.rejects(authVerifier(url)(''),isStatus(401));
});

test('Unicode names survive HTTP chunks split inside a UTF-8 character',async t=>{
  const s=fixture(t),server=familyServer(s,async()=>({id:'alice'}));
  const url=await listen(server);t.after(()=>close(server));
  const data=Buffer.from(JSON.stringify({name:'陈家',realName:'陈建国',kinship:'舅舅'}));
  const split=data.indexOf(Buffer.from('陈'))+1;
  const result=await new Promise((resolve,reject)=>{
    const req=httpRequest(url+'/families',{method:'POST',headers:{'Content-Type':'application/json'}},res=>{
      const chunks=[];res.on('data',c=>chunks.push(c));res.on('end',()=>resolve({status:res.statusCode,body:JSON.parse(Buffer.concat(chunks))}));
    });
    req.on('error',reject);req.write(data.subarray(0,split));setTimeout(()=>req.end(data.subarray(split)),20);
  });
  assert.equal(result.status,200);assert.equal(result.body.name,'陈家');assert.equal(result.body.me.kinship,'舅舅');
});

test('daily check-ins roll over without counting former members',t=>{
  let now='2026-09-09T23:59:59.000Z';const s=new FamilyStore(':memory:',()=>now);t.after(()=>s.close());
  const g=create(s);s.join('bob',{invite:g.invite,realName:'Bob',kinship:'Uncle'});
  const task=s.addRecord(g.id,'alice','tasks',{title:'Daily',type:'manualDaily',repeat:'Every day',participantIds:['alice','bob']});
  s.checkIn(g.id,'alice',task.id);s.checkIn(g.id,'bob',task.id);assert.equal(s.detail(g.id,'alice').checkins.length,2);
  s.leave(g.id,'bob');assert.equal(s.detail(g.id,'alice').checkins.length,1);
  now='2026-09-10T00:00:01.000Z';assert.equal(s.detail(g.id,'alice').checkins.length,0);
  s.checkIn(g.id,'alice',task.id);assert.equal(s.detail(g.id,'alice').checkins.length,1);
});
