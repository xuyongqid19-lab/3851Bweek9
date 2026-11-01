import fs from 'node:fs/promises';
import path from 'node:path';

/** Seed only a new portable installation, using the same authenticated public APIs. */
export async function seedDemo({ports,settings,data}) {
 const marker=path.join(data,'demo-seeded.json');
 try{await fs.access(marker);return;}catch{}
 async function call(service,route,method='GET',body,token){
  const r=await fetch(`http://127.0.0.1:${ports[service]}${route}`,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(10000)});
  const result=await r.json();if(!r.ok)throw new Error(`Demo preparation failed: ${service} ${route} (${r.status})`);return result;
 }
 const users=[];
 for(const account of settings.demoAccounts){
  try{users.push(await call('auth','/auth/login','POST',{account:account.username,password:account.password}));}
  catch{
   await call('auth','/auth/register','POST',{fullName:account.username==='demo.parent'?'James Chen':'Robert Chen',birthDate:'01/01/1990',interest:'Family',username:account.username,email:account.username+'@example.test',phone:'10000000000',password:account.password,securityQuestion:'Local demo only',securityAnswer:account.password});
   users.push(await call('auth','/auth/login','POST',{account:account.username,password:account.password}));
  }
 }
 const [parent,uncle]=users;
 const as=(u,r,m='GET',b)=>call('family',r,m,b,u.token);
 // Resume interrupted first-run seeding without duplicating family groups or records.
 const list=await as(parent,'/families');
 const groups=list.groups||list.families||[];
 let group=groups.find(g=>g.name==='Chen Family');
 if(group)group=await as(parent,`/families/${group.id}`);
 else group=await as(parent,'/families','POST',{name:'Chen Family',description:'Local demo for activities and daily care.',realName:'James Chen',kinship:'Dad'});
 const uncleList=await as(uncle,'/families');
 if(!(uncleList.groups||uncleList.families||[]).some(g=>g.id===group.id))await as(uncle,'/families/join','POST',{invite:group.invite,realName:'Robert Chen',kinship:'Uncle'});
 if(!groups.some(g=>g.name==='Grandparents Family'))await as(parent,'/families','POST',{name:'Grandparents Family',description:'A second family for checking the combined update feed.',realName:'James Chen',kinship:'Son'});
 const detail=await as(parent,`/families/${group.id}`);
 const records=detail.records||[];
 if(!records.some(r=>r.kind==='tasks'))await as(parent,`/families/${group.id}/tasks`,'POST',{title:'Daily safety check',type:'manualDaily',repeat:'Every day',participantIds:[parent.user.id,uncle.user.id]});
 if(!records.some(r=>r.kind==='activities'))await as(parent,`/families/${group.id}/activities`,'POST',{title:'Family dinner',date:new Date(Date.now()+86400000*2).toISOString().slice(0,10),duration:'2 hours',location:'Home',description:'Prepare a meal and catch up.',participantIds:[parent.user.id,uncle.user.id]});
 if(!records.some(r=>r.kind==='notes'))await as(parent,`/families/${group.id}/notes`,'POST',{title:'Demo health note',note:'Sample record only. Keep hydrated and take regular breaks.'});
 await as(parent,`/families/${group.id}/primary`,'POST',{});
 await fs.writeFile(marker,JSON.stringify({version:1,createdAt:new Date().toISOString()}));
 console.log('Prepared two real local test accounts and sample families.');
}
