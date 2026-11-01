// Opt-in checks against this portable copy. Writes synthetic records only.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {randomBytes} from 'node:crypto';
const root=path.resolve(process.argv[2]);
const state=JSON.parse(await fs.readFile(path.join(root,'data/running.json'),'utf8'));
const settings=JSON.parse(await fs.readFile(path.join(root,'data/settings.json'),'utf8'));
async function api(service,route,method='GET',body,token){
 const r=await fetch(state.url+`/api/${service}`+route,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(10000)});
 return {status:r.status,data:r.status===204?null:await r.json()};
}
const users=[];
for(const account of settings.demoAccounts){
 const result=await api('auth','/auth/login','POST',{account:account.username,password:account.password});
 assert.equal(result.status,200);users.push(result.data);
}
const [parent,uncle]=users;
const f=(user,route,method='GET',body)=>api('family',route,method,body,user?.token);
assert.equal((await f(null,'/families')).status,401);
const initial=(await f(parent,'/families')).data.groups;
assert.equal(initial.filter(g=>g.name==='Chen Family').length,1);
assert.equal(initial.filter(g=>g.name==='Grandparents Family').length,1);
const stamp=randomBytes(5).toString('hex');
const created=await f(parent,'/families','POST',{name:`Portable check ${stamp}`,realName:'Demo Tester',kinship:'Dad'});
assert.equal(created.status,200);const g=created.data;
assert.equal((await f(uncle,`/families/${g.id}`)).status,404);
assert.equal((await f(uncle,'/families/join','POST',{invite:g.invite,realName:'Second Tester',kinship:'Uncle'})).status,200);
assert.equal((await f(uncle,`/families/${g.id}`,'PATCH',{name:'Not allowed'})).status,403);
const task=await f(parent,`/families/${g.id}/tasks`,'POST',{title:'Portable check',type:'manualDaily',repeat:'Every day',participantIds:[parent.user.id]});
assert.equal(task.status,200);
assert.equal((await f(uncle,`/families/${g.id}/checkins/${task.data.id}`,'POST',{})).status,403);
for(let i=0;i<2;i++)assert.equal((await f(parent,`/families/${g.id}/checkins/${task.data.id}`,'POST',{})).status,200);
assert.equal((await f(parent,`/families/${g.id}`)).data.checkins.length,1);
const activity={title:`Portable Community ${stamp}`,dateTime:'Tomorrow 10 AM',location:'Local Park',category:'social',description:'Synthetic portable check',latitude:39.7827,longitude:-89.6491,groupName:'Portable group'};
const c=await api('community','/community/activities','POST',activity,parent.token);
assert.equal(c.status,201);const cId=c.data.activity?.id||c.data.id;assert.ok(cId);
assert.equal((await api('community',`/community/activities/${cId}`,'PUT',{...activity,title:'Updated portable activity'},parent.token)).status,200);
// Teammate API returns 204 even when ownership prevents deletion. Check state too.
assert.equal((await api('community',`/community/activities/${cId}`,'DELETE',undefined,uncle.token)).status,204);
assert.equal((await api('community',`/community/activities/${cId}/attendees`,'POST',{},uncle.token)).status,204);
const activityList=await api('community','/community/activities','GET',undefined,parent.token);
assert.ok((activityList.data.activities||activityList.data).some(a=>a.id===cId&&a.attendees.includes('Robert Chen')));
const stat=await fetch(state.url+'/__launcher/status');assert.equal(stat.status,200);
assert.equal((await fetch(state.url+'/__launcher/stop',{method:'POST'})).status,403);
assert.equal((await fetch(state.url+'/launcher',{headers:{Origin:'https://untrusted.example'}})).status,403);
assert.equal((await fetch(state.url+'/%2e%2e%5cdata%5csettings.json')).status,403);
await fs.writeFile(path.join(root,'data/smoke-record.json'),JSON.stringify({familyId:g.id,communityId:cId}));
console.log('PASS real login, seeded families, create/join, access isolation, duplicate check-in, Community create/update/join, ownership checks, cross-origin and traversal protection.');
