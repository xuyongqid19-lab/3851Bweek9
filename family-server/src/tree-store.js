import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { FamilyError } from './errors.js';

const fail=(status,message)=>{throw new FamilyError(status,message);};
const admin=role=>role==='admin'||role==='owner';
const code=()=>randomBytes(12).toString('hex').toUpperCase();
const clean=(value,label,max,required=true)=>{
  const result=typeof value==='string'?value.trim():'';
  if((required&&!result)||result.length>max)fail(400,`${label} ${result?'is too long':'is required'}.`);
  return result;
};
const unpack=row=>row&&({...row,requiredGroups:JSON.parse(row.requiredGroups),votes:JSON.parse(row.votes)});

/** Group topology only. Membership and private records remain owned by FamilyStore. */
export class FamilyTreeStore {
  constructor(store){
    this.s=store;
    store.db.exec(`
      CREATE TABLE IF NOT EXISTS tree_codes(groupId TEXT PRIMARY KEY REFERENCES families(id) ON DELETE CASCADE,code TEXT UNIQUE NOT NULL);
      CREATE TABLE IF NOT EXISTS tree_connections(id TEXT PRIMARY KEY,a TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,b TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,label TEXT NOT NULL,createdAt TEXT NOT NULL,CHECK(a<b),UNIQUE(a,b));
      CREATE INDEX IF NOT EXISTS tree_connection_b ON tree_connections(b);
      CREATE TABLE IF NOT EXISTS tree_requests(id TEXT PRIMARY KEY,sourceId TEXT NOT NULL,targetId TEXT NOT NULL,sourceName TEXT NOT NULL,targetName TEXT NOT NULL,label TEXT NOT NULL,message TEXT NOT NULL,createdBy TEXT NOT NULL,createdAt TEXT NOT NULL,expiresAt TEXT NOT NULL,status TEXT NOT NULL,reason TEXT NOT NULL DEFAULT '',decidedAt TEXT,targetCode TEXT NOT NULL,snapshot TEXT NOT NULL,requiredGroups TEXT NOT NULL,votes TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS tree_request_status ON tree_requests(status,createdAt);
    `);
  }
  code(groupId){
    this.s.run('INSERT OR IGNORE INTO tree_codes VALUES(?,?)',groupId,code());
    return this.s.get('SELECT code FROM tree_codes WHERE groupId=?',groupId).code;
  }
  role(groupId,userId){return this.s.get('SELECT role FROM members WHERE groupId=? AND userId=?',groupId,userId)?.role;}
  component(groupId,omit){
    if(!this.s.get('SELECT 1 FROM families WHERE id=?',groupId))return {groups:[],edges:[]};
    const seen=new Set([groupId]),queue=[groupId],edges=new Map();
    for(let i=0;i<queue.length;i++){
      for(const e of this.s.all('SELECT * FROM tree_connections WHERE a=? OR b=?',queue[i],queue[i])){
        if(e.id===omit)continue;
        edges.set(e.id,e);
        for(const id of [e.a,e.b])if(!seen.has(id)){seen.add(id);queue.push(id);}
      }
    }
    return {groups:[...seen].sort(),edges:[...edges.values()].sort((a,b)=>a.id.localeCompare(b.id))};
  }
  fingerprint(...components){
    const groups=[...new Set(components.flatMap(c=>c.groups))].sort();
    const edges=[...new Set(components.flatMap(c=>c.edges.map(e=>e.id)))].sort();
    return createHash('sha256').update(JSON.stringify({groups,edges})).digest('hex');
  }
  proposal(sourceId,targetId){
    const a=this.component(sourceId),b=this.component(targetId);
    if(!a.groups.length||!b.groups.length)fail(404,'One of these families no longer exists.');
    if(a.groups.includes(targetId))fail(409,'These families already belong to the same tree.');
    const groups=[...a.groups,...b.groups].sort();
    if(groups.length>50)fail(409,'A family tree can contain at most 50 families.');
    return {groups,snapshot:this.fingerprint(a,b)};
  }
  resolveCode(value){
    const token=clean(value,'Tree connection code',48).toUpperCase();
    const target=this.s.get('SELECT f.id,f.name,c.code FROM tree_codes c JOIN families f ON f.id=c.groupId WHERE c.code=?',token);
    if(!target)fail(404,'Invalid or expired tree connection code.');
    return target;
  }
  preview(groupId,userId,body){
    this.s.member(groupId,userId,['owner','admin']);
    const target=this.resolveCode(body.code),p=this.proposal(groupId,target.id);
    return {id:target.id,name:target.name,requiredApprovals:p.groups.length,snapshot:p.snapshot};
  }
  reason(r){
    if(Date.parse(this.s.clock())>=Date.parse(r.expiresAt))return ['expired','This request expired after seven days.'];
    if(this.s.get('SELECT code FROM tree_codes WHERE groupId=?',r.targetId)?.code!==r.targetCode)return ['invalidated','The destination code changed or the family closed.'];
    if(r.votes.some(v=>!admin(this.role(v.groupId,v.userId))))return ['invalidated','A consenting administrator no longer has permission.'];
    const a=this.component(r.sourceId),b=this.component(r.targetId);
    if(!a.groups.length||!b.groups.length||a.groups.includes(r.targetId)||this.fingerprint(a,b)!==r.snapshot)return ['invalidated','The family tree changed. Send a new request with fresh consent.'];
    return null;
  }
  finish(id,status,reason=''){
    this.s.run('UPDATE tree_requests SET status=?,reason=?,decidedAt=? WHERE id=?',status,reason,this.s.clock(),id);
  }
  refreshPending(){
    for(const row of this.s.all("SELECT * FROM tree_requests WHERE status='pending'")){
      const result=this.reason(unpack(row));if(result)this.finish(row.id,...result);
    }
  }
  requests(groupId){
    return this.s.all(`SELECT r.* FROM tree_requests r WHERE EXISTS(SELECT 1 FROM json_each(r.requiredGroups) WHERE value=?) ORDER BY (status='pending') DESC,createdAt DESC,id DESC`,groupId).map(unpack);
  }
  publicRequest(r,groupId){
    return {id:r.id,sourceId:r.sourceId,targetId:r.targetId,
      sourceName:this.s.get('SELECT name FROM families WHERE id=?',r.sourceId)?.name??r.sourceName,
      targetName:this.s.get('SELECT name FROM families WHERE id=?',r.targetId)?.name??r.targetName,
      label:r.label,message:r.message,createdAt:r.createdAt,expiresAt:r.expiresAt,
      status:r.status,reason:r.reason,decidedAt:r.decidedAt,
      approvedCount:r.votes.length,requiredCount:r.requiredGroups.length,
      myApproval:r.votes.some(v=>v.groupId===groupId),canCancel:groupId===r.sourceId};
  }
  summary(groupId,userId){
    const canManage=admin(this.role(groupId,userId));
    return {familyCount:this.component(groupId).groups.length,
      pendingCount:canManage?this.requests(groupId).filter(r=>r.status==='pending'&&!r.votes.some(v=>v.groupId===groupId)).length:0};
  }
  view(groupId,userId){
    const me=this.s.member(groupId,userId),canManage=admin(me.role);
    this.refreshPending();
    const c=this.component(groupId),version=this.fingerprint(c);
    const nodes=c.groups.map(id=>({id,name:this.s.get('SELECT name FROM families WHERE id=?',id).name,canOpen:!!this.role(id,userId)}));
    const connections=c.edges.map(e=>({...e,...(canManage&&(e.a===groupId||e.b===groupId)?{disconnectSizes:[this.component(e.a,e.id).groups.length,this.component(e.b,e.id).groups.length]}:{})}));
    const result={groupId,role:me.role,nodes,connections,version};
    if(canManage){
      result.code=this.code(groupId);
      const requests=this.requests(groupId);let history=0;
      result.requests=requests.filter(r=>r.status==='pending'||history++<100).map(r=>this.publicRequest(r,groupId));
    }
    return result;
  }
  send(groupId,userId,body){
    this.s.member(groupId,userId,['owner','admin']);
    const label=clean(body.label,'Relationship label',80),message=clean(body.message,'Explanation',500,false);
    if(body.confirmed!==true)fail(400,'Confirm the shared topology and consent notice first.');
    this.refreshPending();
    return this.s.tx(()=>{
      const target=this.resolveCode(body.code),p=this.proposal(groupId,target.id);
      if(body.snapshot!==p.snapshot)fail(409,'The tree changed since preview. Preview the destination again.');
      const pending=this.s.all("SELECT * FROM tree_requests WHERE status='pending'").map(unpack);
      if(pending.some(r=>(r.sourceId===groupId&&r.targetId===target.id)||(r.sourceId===target.id&&r.targetId===groupId)))fail(409,'A request between these families is already pending. Check Requests.');
      if(p.groups.some(id=>pending.filter(r=>r.requiredGroups.includes(id)).length>=20))fail(429,'One of these families already has 20 pending requests. Resolve them first.');
      const id=randomUUID(),now=this.s.clock(),expires=new Date(Date.parse(now)+7*86400000).toISOString();
      const name=this.s.get('SELECT name FROM families WHERE id=?',groupId).name;
      this.s.run(`INSERT INTO tree_requests(id,sourceId,targetId,sourceName,targetName,label,message,createdBy,createdAt,expiresAt,status,targetCode,snapshot,requiredGroups,votes) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
        id,groupId,target.id,name,target.name,label,message,userId,now,expires,'pending',target.code,p.snapshot,JSON.stringify(p.groups),JSON.stringify([{groupId,userId,at:now}]));
      for(const g of p.groups)this.s.event(g,'A family tree connection is awaiting administrator review.');
      return {id,status:'pending'};
    });
  }
  decide(groupId,userId,id,body){
    this.s.member(groupId,userId,['owner','admin']);
    if(!['approve','reject','cancel'].includes(body.decision))fail(400,'Choose approve, reject or cancel.');
    const note=clean(body.reason,'Decision reason',300,false);
    this.refreshPending();
    return this.s.tx(()=>{
      const r=unpack(this.s.get('SELECT * FROM tree_requests WHERE id=?',id));
      if(!r||!r.requiredGroups.includes(groupId))fail(404,'Request not found for this family.');
      if(body.decision==='cancel'&&r.sourceId!==groupId)fail(403,'Only the source family can cancel this request.');
      if(r.status!=='pending'){
        const same={approve:'accepted',reject:'rejected',cancel:'cancelled'}[body.decision];
        if(r.status===same)return {id,status:r.status};
        fail(409,r.reason||`This request is already ${r.status}. Refresh Requests.`);
      }
      const stale=this.reason(r);if(stale)fail(409,stale[1]);
      if(body.decision!=='approve'){
        this.finish(id,body.decision==='reject'?'rejected':'cancelled',note||'The proposal was withdrawn or declined.');
        return {id,status:body.decision==='reject'?'rejected':'cancelled'};
      }
      if(!r.votes.some(v=>v.groupId===groupId))r.votes.push({groupId,userId,at:this.s.clock()});
      this.s.run('UPDATE tree_requests SET votes=? WHERE id=?',JSON.stringify(r.votes),id);
      if(r.votes.length<r.requiredGroups.length)return {id,status:'pending'};
      const p=this.proposal(r.sourceId,r.targetId);
      if(p.snapshot!==r.snapshot)fail(409,'The tree changed. Send a new request.');
      const [a,b]=[r.sourceId,r.targetId].sort();
      this.s.run('INSERT INTO tree_connections VALUES(?,?,?,?,?)',randomUUID(),a,b,r.label,this.s.clock());
      this.finish(id,'accepted');
      for(const g of p.groups)this.s.event(g,'The family tree gained a confirmed connection.');
      return {id,status:'accepted'};
    });
  }
  rotate(groupId,userId){
    this.s.member(groupId,userId,['owner','admin']);
    return this.s.tx(()=>{
      const value=code();this.s.run('INSERT INTO tree_codes VALUES(?,?) ON CONFLICT(groupId) DO UPDATE SET code=excluded.code',groupId,value);
      this.s.run("UPDATE tree_requests SET status='invalidated',reason='The destination connection code changed.',decidedAt=? WHERE targetId=? AND status='pending'",this.s.clock(),groupId);
      return {code:value};
    });
  }
  disconnect(groupId,userId,id,body){
    this.s.member(groupId,userId,['owner','admin']);
    return this.s.tx(()=>{
      const e=this.s.get('SELECT * FROM tree_connections WHERE id=? AND (a=? OR b=?)',id,groupId,groupId);
      if(!e)fail(404,'This family does not have that direct connection.');
      const c=this.component(groupId);
      if(body.version!==this.fingerprint(c))fail(409,'The tree changed. Refresh before disconnecting.');
      this.s.run('DELETE FROM tree_connections WHERE id=?',id);
      for(const g of c.groups)this.s.event(g,'A family tree connection was removed; branches may have separated.');
      this.refreshPending();return {ok:true};
    });
  }
  leave(groupId,userId,body){
    this.s.member(groupId,userId,['owner']);
    return this.s.tx(()=>{
      const c=this.component(groupId);
      if(body.version!==this.fingerprint(c))fail(409,'The tree changed. Refresh before leaving.');
      this.s.run('DELETE FROM tree_connections WHERE a=? OR b=?',groupId,groupId);
      for(const g of c.groups)this.s.event(g,'A family left its tree connections; remaining branches are kept.');
      this.refreshPending();return {ok:true};
    });
  }
  /** Called inside the existing final-member transaction, before the FK cascade. */
  closing(groupId){
    const c=this.component(groupId);
    for(const g of c.groups)if(g!==groupId)this.s.event(g,'A connected family closed; its tree connections were removed.');
    this.s.run(`UPDATE tree_requests SET status='invalidated',reason='A participating family closed.',decidedAt=? WHERE status='pending' AND EXISTS(SELECT 1 FROM json_each(requiredGroups) WHERE value=?)`,this.s.clock(),groupId);
  }
}
