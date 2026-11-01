// Opt-in: writes synthetic accounts and groups to a loopback-only test stack.
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
if(process.env.ALLOW_WRITE_SYNTHETIC_TEST_DATA!=='1')throw new Error('Set ALLOW_WRITE_SYNTHETIC_TEST_DATA=1 for an isolated local test stack.');
const auth=process.env.AUTH_TEST_BASE_URL,family=process.env.FAMILY_TEST_BASE_URL;
for(const url of [auth,family])if(!url||!['localhost','127.0.0.1'].includes(new URL(url).hostname))throw new Error('Explicit loopback Auth and Family test URLs are required.');
async function request(base,path,body,token,method=body?'POST':'GET'){
 const r=await fetch(base+path,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(12000)});
 return {status:r.status,data:await r.json()};
}
const suffix=randomBytes(5).toString('hex'),accounts=[];
for(const name of ['Alice','Bob','Carol','David','Member']){
 const username=`tree.${name.toLowerCase()}.${suffix}`,password='Tree-'+randomBytes(16).toString('hex');
 const r=await request(auth,'/auth/register',{fullName:`Tree Test ${name}`,username,email:`${username}@example.test`,password,birthDate:'1990-01-01',phone:'123456789',securityQuestion:null,securityAnswer:null});
 assert.equal(r.status,201,'Synthetic registration');
 const login=await request(auth,'/auth/login',{account:username,password});assert.equal(login.status,200);
 accounts.push({name,username,password,token:login.data.token,id:login.data.user.id});
}
const as=(i,path,body,method)=>request(family,path,body,accounts[i].token,method);
const groups=[];
for(let i=0;i<4;i++){
 const r=await as(i,'/families',{name:`${accounts[i].name} Home`,realName:accounts[i].name,kinship:'Relative'});assert.equal(r.status,200);groups.push(r.data);
}
const tree=async(i,g=groups[i])=>(await as(i,`/families/${g.id}/tree`)).data;
async function propose(i,a,j,b){const destination=await tree(j,b);const p=await as(i,`/families/${a.id}/tree/preview`,{code:destination.code});assert.equal(p.status,200);
 const r=await as(i,`/families/${a.id}/tree/requests`,{code:destination.code,snapshot:p.data.snapshot,label:'Extended family',message:'Synthetic local integration test',confirmed:true});assert.equal(r.status,200);return r.data;}
async function approve(i,g,r){const result=await as(i,`/families/${g.id}/tree/requests/${r.id}`,{decision:'approve'});assert.equal(result.status,200);return result.data;}
const first=await propose(0,groups[0],1,groups[1]);assert.equal((await tree(1)).nodes.length,1);assert.equal((await approve(1,groups[1],first)).status,'accepted');
const second=await propose(2,groups[2],3,groups[3]);await approve(3,groups[3],second);
const merge=await propose(0,groups[0],2,groups[2]);
assert.equal((await approve(2,groups[2],merge)).status,'pending');assert.equal((await approve(3,groups[3],merge)).status,'pending');
assert.equal((await tree(0)).nodes.length,2);assert.equal((await approve(1,groups[1],merge)).status,'accepted');
assert.equal((await tree(3)).nodes.length,4);
assert.equal((await as(0,`/families/${groups[2].id}`)).status,404,'Linked users cannot read private group details');
assert.equal((await as(4,'/families/join',{invite:groups[0].invite,realName:'Member',kinship:'Cousin'})).status,200);
const member=await tree(4,groups[0]);assert.equal(member.nodes.length,4);assert.equal(member.code,undefined);assert.equal(member.requests,undefined);
assert.equal((await as(4,`/families/${groups[0].id}/tree/code`,{})).status,403);
const before=await tree(0);const edge=before.connections.find(e=>[e.a,e.b].includes(groups[2].id)&&[e.a,e.b].includes(groups[0].id));
assert.equal((await as(0,`/families/${groups[0].id}/tree/disconnect/${edge.id}`,{version:before.version})).status,200);
assert.equal((await tree(0)).nodes.length,2);assert.equal((await tree(2)).nodes.length,2);
assert.equal((await as(4,`/families/${groups[0].id}/leave`,{})).status,200);assert.equal((await as(4,`/families/${groups[0].id}/tree`)).status,404);
// Independent groups for the subsequent real browser workflow.
const browserGroups=[];
for(const [i,name]of [[0,'Chen Home'],[1,'Grandparents Home']]){
 const r=await as(i,'/families',{name,realName:accounts[i].name,kinship:i===0?'Dad':'Grandfather'});assert.equal(r.status,200);browserGroups.push(r.data);
 await as(i,`/families/${r.data.id}/primary`,{});
}
const browserCode=(await tree(1,browserGroups[1])).code;
if(process.env.TREE_TEST_PRIVATE_OUTPUT)await writeFile(process.env.TREE_TEST_PRIVATE_OUTPUT,JSON.stringify({accounts,browserGroups,browserCode},null,2));
console.log('PASS: real Auth registration/login, four-group unanimous tree merge, private-data isolation, member permissions, bridge split and revoked access. Synthetic data retained only in the isolated test stack.');
