import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { FamilyStore, FamilyError } from '../src/store.js';
import { familyServer } from '../src/app.js';

const status=n=>e=>e instanceof FamilyError&&e.status===n;
const family=(s,user,name=user)=>s.create(user,{name,realName:user,kinship:'Relative'});
function setup(t,clock){const s=new FamilyStore(':memory:',clock);t.after(()=>s.close());return s;}
function proposal(s,a,b,actor=a.me.userId){
  const code=s.tree.view(b.id,b.me.userId).code;
  const preview=s.tree.preview(a.id,actor,{code});
  return s.tree.send(a.id,actor,{code,snapshot:preview.snapshot,label:'Extended family',message:'Shared family roots',confirmed:true});
}
function approve(s,g,r,user=g.me.userId){return s.tree.decide(g.id,user,r.id,{decision:'approve'});}
function connect(s,a,b){const r=proposal(s,a,b);approve(s,b,r);return r;}

test('two admins explicitly consent, connection survives replay without duplicate events',t=>{
  const s=setup(t),a=family(s,'alice'),b=family(s,'bob');
  const r=proposal(s,a,b);assert.equal(s.tree.view(a.id,'alice').connections.length,0);
  assert.equal(s.tree.view(b.id,'bob').requests[0].myApproval,false);
  assert.equal(approve(s,b,r).status,'accepted');
  const view=s.tree.view(a.id,'alice');assert.equal(view.nodes.length,2);assert.equal(view.connections.length,1);
  const count=s.get('SELECT COUNT(*) AS n FROM events').n;
  approve(s,b,r);assert.equal(s.get('SELECT COUNT(*) AS n FROM events').n,count);
  assert.equal(s.tree.view(a.id,'alice').connections.length,1);
});
test('third-family admission needs every affected group and one rejection blocks it',t=>{
  const s=setup(t),a=family(s,'a'),b=family(s,'b'),c=family(s,'c');connect(s,a,b);
  const r=proposal(s,c,a);assert.equal(approve(s,a,r).status,'pending');
  assert.equal(s.tree.view(c.id,'c').nodes.length,1);
  assert.equal(s.tree.view(b.id,'b').requests[0].requiredCount,3);
  s.tree.decide(b.id,'b',r.id,{decision:'reject',reason:'Please discuss first'});
  assert.throws(()=>approve(s,b,r),status(409));assert.equal(s.tree.view(c.id,'c').nodes.length,1);
  const again=proposal(s,c,a);approve(s,a,again);assert.equal(approve(s,b,again).status,'accepted');
  assert.equal(s.tree.view(c.id,'c').nodes.length,3);
});
test('whole-tree merge needs four approvals and cannot reveal distant node names beforehand',t=>{
  const s=setup(t),a=family(s,'a'),b=family(s,'b','Hidden branch'),c=family(s,'c'),d=family(s,'d');
  connect(s,a,b);connect(s,c,d);const r=proposal(s,a,c);
  const before=s.tree.view(d.id,'d');assert.equal(before.nodes.length,2);
  assert.ok(!JSON.stringify(before.requests).includes('Hidden branch'));
  approve(s,c,r);approve(s,d,r);assert.equal(s.tree.view(c.id,'c').nodes.length,2);
  approve(s,b,r);assert.equal(s.tree.view(d.id,'d').nodes.length,4);
});
test('separate connection codes never grant membership or leak private records',t=>{
  const s=setup(t),a=family(s,'a'),b=family(s,'b');
  s.addRecord(b.id,'b','notes',{title:'Private',note:'Secret medical content'});
  const c=s.tree.view(b.id,'b').code;assert.notEqual(c,b.invite);
  assert.throws(()=>s.preview(c),status(404));assert.throws(()=>s.tree.preview(a.id,'a',{code:b.invite}),status(404));
  const preview=s.tree.preview(a.id,'a',{code:c});assert.deepEqual(Object.keys(preview).sort(),['id','name','requiredApprovals','snapshot']);
  connect(s,a,b);const v=s.tree.view(a.id,'a');
  assert.ok(!JSON.stringify(v).includes('Secret medical content'));assert.equal(v.nodes.find(n=>n.id===b.id).canOpen,false);
  assert.throws(()=>s.detail(b.id,'a'),status(404));assert.throws(()=>s.tree.view(b.id,'a'),status(404));
});
test('ordinary members can view topology but never admin proposals, codes or actions',t=>{
  const s=setup(t),a=family(s,'a'),b=family(s,'b');s.join('member',{invite:a.invite,realName:'Member',kinship:'Cousin'});
  const r=proposal(s,a,b),v=s.tree.view(a.id,'member');assert.equal(v.code,undefined);assert.equal(v.requests,undefined);
  for(const fn of [()=>s.tree.preview(a.id,'member',{code:s.tree.view(b.id,'b').code}),()=>s.tree.rotate(a.id,'member'),()=>s.tree.decide(a.id,'member',r.id,{decision:'reject'}),()=>s.tree.leave(a.id,'member',{version:v.version})])assert.throws(fn,status(403));
  approve(s,b,r);assert.equal(s.tree.view(a.id,'member').nodes.length,2);
  s.leave(a.id,'member');assert.throws(()=>s.tree.view(a.id,'member'),status(404));
});
test('self, reverse duplicate, already-connected and cycles are rejected',t=>{
  const s=setup(t),a=family(s,'a'),b=family(s,'b');
  assert.throws(()=>proposal(s,a,a),status(409));const r=proposal(s,a,b);
  assert.throws(()=>proposal(s,a,b),status(409));assert.throws(()=>proposal(s,b,a),status(409));
  approve(s,b,r);assert.throws(()=>proposal(s,b,a),status(409));
});
test('cancel only by source group; a declined proposal cannot be revived',t=>{
  const s=setup(t),a=family(s,'a'),b=family(s,'b'),c=family(s,'c');const r=proposal(s,a,b);
  assert.throws(()=>s.tree.decide(b.id,'b',r.id,{decision:'cancel'}),status(403));
  assert.throws(()=>s.tree.decide(c.id,'c',r.id,{decision:'approve'}),status(404));
  s.tree.decide(a.id,'a',r.id,{decision:'cancel'});assert.throws(()=>approve(s,b,r),status(409));
  assert.equal(s.tree.view(a.id,'a').requests[0].status,'cancelled');
});
test('expiry uses server time and can be retried as a fresh request',t=>{
  let now='2026-10-15T10:00:00.000Z';const s=setup(t,()=>now),a=family(s,'a'),b=family(s,'b');const r=proposal(s,a,b);
  now='2026-10-22T10:00:00.000Z';assert.throws(()=>approve(s,b,r),status(409));
  assert.equal(s.tree.view(a.id,'a').requests[0].status,'expired');assert.notEqual(proposal(s,a,b).id,r.id);
});
test('rotation invalidates pending codes but retains established links and membership invites',t=>{
  const s=setup(t),a=family(s,'a'),b=family(s,'b'),c=family(s,'c');connect(s,a,b);
  const r=proposal(s,c,b),old=s.tree.view(b.id,'b').code;s.tree.rotate(b.id,'b');
  assert.throws(()=>s.tree.preview(c.id,'c',{code:old}),status(404));assert.throws(()=>approve(s,b,r),status(409));
  assert.equal(s.tree.view(b.id,'b').nodes.length,2);assert.equal(s.preview(b.invite).id,b.id);
});
test('revoked administrator consent invalidates permanently even after reinstatement',t=>{
  const s=setup(t),a=family(s,'a'),b=family(s,'b');
  s.join('helper',{invite:a.invite,realName:'Helper',kinship:'Uncle'});s.role(a.id,'a','helper',{role:'admin'});
  const r=proposal(s,a,b,'helper');s.role(a.id,'a','helper',{role:'member'});s.role(a.id,'a','helper',{role:'admin'});
  assert.throws(()=>approve(s,b,r),status(409));assert.equal(s.tree.view(a.id,'a').requests[0].status,'invalidated');
});
test('topology changes invalidate outstanding proposals and stale confirmation versions',t=>{
  const s=setup(t),a=family(s,'a'),b=family(s,'b'),c=family(s,'c');
  const stale=proposal(s,a,c),first=proposal(s,a,b),before=s.tree.view(a.id,'a');approve(s,b,first);
  assert.throws(()=>approve(s,c,stale),status(409));
  const edge=s.tree.view(a.id,'a').connections[0];assert.throws(()=>s.tree.disconnect(a.id,'a',edge.id,{version:before.version}),status(409));
  assert.equal(s.tree.view(a.id,'a').nodes.length,2);
});
test('bridge withdrawal splits components without private record or family loss',t=>{
  const s=setup(t),a=family(s,'a'),b=family(s,'b'),c=family(s,'c');connect(s,a,b);
  const r=proposal(s,b,c);approve(s,a,r);approve(s,c,r);
  s.addRecord(c.id,'c','notes',{title:'Retained',note:'Keep this record'});
  const v=s.tree.view(a.id,'a'),distant=v.connections.find(e=>e.a!==a.id&&e.b!==a.id);
  assert.throws(()=>s.tree.disconnect(a.id,'a',distant.id,{version:v.version}),status(404));
  const edge=v.connections.find(e=>e.a===a.id||e.b===a.id);assert.deepEqual([...edge.disconnectSizes].sort(),[1,2]);
  s.tree.disconnect(a.id,'a',edge.id,{version:v.version});
  assert.equal(s.tree.view(a.id,'a').nodes.length,1);assert.equal(s.tree.view(c.id,'c').nodes.length,2);
  assert.equal(s.detail(c.id,'c').records.length,1);assert.equal(s.get('SELECT COUNT(*) AS n FROM families').n,3);
});
test('owner bulk leave separates branches; last-member closure invalidates requests',t=>{
  const s=setup(t),a=family(s,'a'),b=family(s,'b'),c=family(s,'c'),d=family(s,'d');connect(s,a,b);
  const r=proposal(s,a,c);approve(s,b,r);approve(s,c,r);
  const pending=proposal(s,d,c);s.join('helper',{invite:a.invite,realName:'Helper',kinship:'Uncle'});s.role(a.id,'a','helper',{role:'admin'});
  assert.throws(()=>s.tree.leave(a.id,'helper',{version:s.tree.view(a.id,'helper').version}),status(403));
  s.tree.leave(a.id,'a',{version:s.tree.view(a.id,'a').version});
  for(const g of [a,b,c])assert.equal(s.tree.view(g.id,g.me.userId).nodes.length,1);
  assert.throws(()=>approve(s,c,pending),status(409));
  const closing=proposal(s,d,c);s.leave(c.id,'c');assert.throws(()=>approve(s,d,closing),status(409));
  assert.equal(s.tree.view(d.id,'d').requests.find(x=>x.id===closing.id).status,'invalidated');
});
test('one user administering two families still performs separate approvals',t=>{
  const s=setup(t),a=family(s,'same','First'),b=family(s,'same','Second');const r=proposal(s,a,b);
  assert.equal(s.tree.view(b.id,'same').requests[0].myApproval,false);approve(s,b,r);
  assert.equal(s.tree.view(b.id,'same').nodes.length,2);
});
test('limits reject missing consent, stale preview and overlong labels',t=>{
  const s=setup(t),a=family(s,'a'),b=family(s,'b');const code=s.tree.view(b.id,'b').code,pre=s.tree.preview(a.id,'a',{code});
  const body={code,snapshot:pre.snapshot,label:'Related',confirmed:true};
  assert.throws(()=>s.tree.send(a.id,'a',{...body,confirmed:false}),status(400));
  assert.throws(()=>s.tree.send(a.id,'a',{...body,snapshot:'stale'}),status(409));
  assert.throws(()=>s.tree.send(a.id,'a',{...body,label:'x'.repeat(81)}),status(400));
  assert.equal(s.get('SELECT COUNT(*) AS n FROM tree_requests').n,0);
});
test('50-group cap and 20-pending cap are checked before writes',t=>{
  const s=setup(t),a=family(s,'a');let previous=a.id;
  for(let i=0;i<49;i++){
    const g=family(s,`g${i}`),[x,y]=[previous,g.id].sort();
    s.run('INSERT INTO tree_connections VALUES(?,?,?,?,?)',`edge${i}`,x,y,'Fixture','2026-10-15');previous=g.id;
  }
  const extra=family(s,'extra');assert.throws(()=>proposal(s,extra,a),status(409));
  const separate=family(s,'separate');
  for(let i=0;i<20;i++)proposal(s,separate,family(s,`pending${i}`));
  assert.throws(()=>proposal(s,separate,extra),status(429));
});
test('legacy records and accepted topology persist on reopen without reseeding',t=>{
  const dir=mkdtempSync(join(tmpdir(),'family-tree-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));const path=join(dir,'family.sqlite');
  let s=new FamilyStore(path);const a=family(s,'a'),b=family(s,'b');s.addRecord(a.id,'a','notes',{title:'Legacy',note:'Private record'});
  s.db.exec('DROP TABLE tree_requests;DROP TABLE tree_connections;DROP TABLE tree_codes;');s.close();
  s=new FamilyStore(path);assert.equal(s.detail(a.id,'a').records.length,1);assert.equal(s.tree.view(a.id,'a').nodes.length,1);connect(s,a,b);s.close();
  s=new FamilyStore(path);assert.equal(s.tree.view(a.id,'a').nodes.length,2);assert.equal(s.tree.view(b.id,'b').requests[0].status,'accepted');s.close();
});
test('failed final write rolls back votes, connection and event together',t=>{
  const s=setup(t),a=family(s,'a'),b=family(s,'b');const r=proposal(s,a,b);
  s.db.exec("CREATE TRIGGER fail_tree_event BEFORE INSERT ON events BEGIN SELECT RAISE(ABORT,'write failure'); END;");
  assert.throws(()=>approve(s,b,r));assert.equal(s.tree.view(a.id,'a').connections.length,0);
  const pending=s.tree.view(b.id,'b').requests[0];assert.equal(pending.status,'pending');assert.equal(pending.myApproval,false);
  s.db.exec('DROP TRIGGER fail_tree_event');assert.equal(approve(s,b,r).status,'accepted');
});
test('HTTP routes enforce identity, rate limits and group scope; spoofed userId is ignored',async t=>{
  const s=setup(t),a=family(s,'a'),b=family(s,'b');const srv=familyServer(s,async header=>{
    if(!['Bearer a','Bearer b'].includes(header))throw new FamilyError(401,'Sign in');return {id:header.slice(7)};
  });await new Promise(r=>srv.listen(0,'127.0.0.1',r));t.after(()=>new Promise(r=>srv.close(r)));
  const base=`http://127.0.0.1:${srv.address().port}`;
  async function call(group,path='',user='a',body){const r=await fetch(`${base}/families/${group}/tree${path}`,{method:body?'POST':'GET',headers:{Authorization:`Bearer ${user}`,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json()};}
  assert.equal((await call(a.id,'','stranger')).status,401);assert.equal((await call(b.id)).status,404);
  const code=(await call(b.id,'','b')).data.code;
  const pre=(await call(a.id,'/preview','a',{code})).data;
  const sent=await call(a.id,'/requests','a',{code,snapshot:pre.snapshot,label:'Family',confirmed:true,userId:'b'});assert.equal(sent.status,200);
  assert.equal((await call(b.id,`/requests/${sent.data.id}`,'a',{decision:'approve'})).status,404);
  assert.equal((await call(b.id,`/requests/${sent.data.id}`,'b',{decision:'approve'})).data.status,'accepted');
  assert.equal((await call(a.id)).data.nodes.length,2);
  let limited;for(let i=0;i<21;i++)limited=await call(a.id,'/preview','a',{code:'WRONG'});
  assert.equal(limited.status,429);
});
