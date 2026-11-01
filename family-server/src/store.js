import { DatabaseSync } from 'node:sqlite';
import { randomBytes, randomUUID } from 'node:crypto';
import { FamilyError } from './errors.js';
import { FamilyTreeStore } from './tree-store.js';

export { FamilyError } from './errors.js';
const fail = (status, message) => { throw new FamilyError(status, message); };
function text(value, label, max = 120, required = true) {
  const v = typeof value === 'string' ? value.trim() : '';
  if ((required && !v) || v.length > max) fail(400, `${label} ${v ? `must be at most ${max} characters` : 'is required'}.`);
  return v;
}
const code = () => randomBytes(9).toString('hex').toUpperCase();

/** Family-only storage. Auth UUIDs are verified by the HTTP boundary, never by client claims. */
export class FamilyStore {
  constructor(path, clock = () => new Date().toISOString()) {
    this.clock = clock;
    this.db = new DatabaseSync(path, { timeout: 5000 });
    try { this.db.exec(`PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL;
      CREATE TABLE IF NOT EXISTS families(id TEXT PRIMARY KEY,name TEXT NOT NULL,description TEXT NOT NULL,invite TEXT UNIQUE NOT NULL,createdAt TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS members(groupId TEXT REFERENCES families(id) ON DELETE CASCADE,userId TEXT NOT NULL,realName TEXT NOT NULL,kinship TEXT NOT NULL,role TEXT NOT NULL CHECK(role IN ('owner','admin','member')),joinedAt TEXT NOT NULL,lastRead INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(groupId,userId));
      CREATE TABLE IF NOT EXISTS preferences(userId TEXT PRIMARY KEY,primaryId TEXT REFERENCES families(id) ON DELETE SET NULL);
      CREATE TABLE IF NOT EXISTS records(id TEXT PRIMARY KEY,groupId TEXT REFERENCES families(id) ON DELETE CASCADE,kind TEXT NOT NULL,body TEXT NOT NULL,createdBy TEXT NOT NULL,createdAt TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY AUTOINCREMENT,groupId TEXT REFERENCES families(id) ON DELETE CASCADE,summary TEXT NOT NULL,createdAt TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS checkins(taskId TEXT REFERENCES records(id) ON DELETE CASCADE,userId TEXT NOT NULL,day TEXT NOT NULL,createdAt TEXT NOT NULL,PRIMARY KEY(taskId,userId,day));
      CREATE INDEX IF NOT EXISTS member_user ON members(userId);
      CREATE INDEX IF NOT EXISTS event_group ON events(groupId,id);
      CREATE INDEX IF NOT EXISTS record_group ON records(groupId,createdAt);`);
      this.tree = new FamilyTreeStore(this);
    } catch (error) { this.db.close(); throw error; }
  }
  close() { this.db.close(); }
  tx(fn) { this.db.exec('BEGIN IMMEDIATE'); try { const result = fn(); this.db.exec('COMMIT'); return result; } catch(e) { this.db.exec('ROLLBACK'); throw e; } }
  get(sql, ...args) { return this.db.prepare(sql).get(...args); }
  all(sql, ...args) { return this.db.prepare(sql).all(...args); }
  run(sql, ...args) { return this.db.prepare(sql).run(...args); }
  member(groupId, userId, roles) {
    const m = this.get('SELECT * FROM members WHERE groupId=? AND userId=?',groupId,userId);
    if (!m) fail(404,'Family not found or you are no longer a member.');
    if (roles && !roles.includes(m.role)) fail(403,'You do not have permission for this action.');
    return m;
  }
  event(groupId, summary) { this.run('INSERT INTO events(groupId,summary,createdAt) VALUES(?,?,?)',groupId,summary,this.clock()); }
  primary(userId) {
    const p = this.get('SELECT primaryId FROM preferences WHERE userId=?',userId)?.primaryId;
    if (p && this.get('SELECT 1 FROM members WHERE groupId=? AND userId=?',p,userId)) return p;
    const next = this.get('SELECT groupId FROM members WHERE userId=? ORDER BY joinedAt,groupId LIMIT 1',userId)?.groupId ?? null;
    this.run('INSERT INTO preferences(userId,primaryId) VALUES(?,?) ON CONFLICT(userId) DO UPDATE SET primaryId=excluded.primaryId',userId,next);
    return next;
  }
  summary(groupId, userId) {
    const me = this.member(groupId,userId);
    const group = this.get('SELECT id,name,description,createdAt FROM families WHERE id=?',groupId);
    const members = this.all('SELECT userId,realName,kinship,role,joinedAt FROM members WHERE groupId=? ORDER BY joinedAt,userId',groupId);
    const records = this.all('SELECT * FROM records WHERE groupId=? ORDER BY createdAt DESC,id',groupId).map(r=>({...r,body:JSON.parse(r.body)}));
    const latest = this.get('SELECT * FROM events WHERE groupId=? ORDER BY id DESC LIMIT 1',groupId) ?? null;
    const unread = this.get('SELECT COUNT(*) AS n FROM events WHERE groupId=? AND id>?',groupId,me.lastRead).n;
    const today = this.clock().slice(0,10);
    const checkins = this.all('SELECT c.* FROM checkins c JOIN records r ON r.id=c.taskId JOIN members m ON m.groupId=r.groupId AND m.userId=c.userId WHERE r.groupId=? AND c.day=?',groupId,today);
    return {...group,me,members,records,latest,unread,checkins,today};
  }
  list(userId) {
    this.tree.refreshPending();
    const primaryId = this.primary(userId);
    const groups = this.all('SELECT groupId FROM members WHERE userId=?',userId).map(m=>this.summary(m.groupId,userId));
    groups.sort((a,b)=>(b.latest?.id??0)-(a.latest?.id??0));
    for(const group of groups) group.treeSummary=this.tree.summary(group.id,userId);
    return {primaryId,groups};
  }
  detail(groupId,userId) {
    const result = this.summary(groupId,userId);
    result.events = this.all('SELECT * FROM events WHERE groupId=? ORDER BY id DESC LIMIT 100',groupId);
    if (result.me.role !== 'member') result.invite = this.get('SELECT invite FROM families WHERE id=?',groupId).invite;
    return result;
  }
  create(userId,body) {
    const name=text(body.name,'Family name',80), description=text(body.description,'Description',500,false);
    const realName=text(body.realName,'Real name',80),kinship=text(body.kinship,'Family relationship',50);
    return this.tx(()=>{
      const id=randomUUID(),now=this.clock();
      this.run('INSERT INTO families VALUES(?,?,?,?,?)',id,name,description,code(),now);
      this.run('INSERT INTO members(groupId,userId,realName,kinship,role,joinedAt) VALUES(?,?,?,?,?,?)',id,userId,realName,kinship,'owner',now);
      this.primary(userId); this.event(id,`${realName} created this family.`);
      return this.detail(id,userId);
    });
  }
  preview(invite) {
    const value=text(invite,'Invite code',30).toUpperCase();
    const group=this.get('SELECT id,name,description FROM families WHERE invite=?',value);
    if(!group) fail(404,'Invalid or expired invite code.');
    return group;
  }
  join(userId,body) {
    const realName=text(body.realName,'Real name',80),kinship=text(body.kinship,'Family relationship',50);
    return this.tx(()=>{
      const g=this.preview(body.invite);
      if(this.get('SELECT 1 FROM members WHERE groupId=? AND userId=?',g.id,userId)) fail(409,'You already belong to this family.');
      const last=this.get('SELECT MAX(id) AS id FROM events WHERE groupId=?',g.id).id??0;
      this.run('INSERT INTO members VALUES(?,?,?,?,?,?,?)',g.id,userId,realName,kinship,'member',this.clock(),last);
      this.primary(userId);this.event(g.id,`${realName} joined the family.`);
      return this.detail(g.id,userId);
    });
  }
  setPrimary(groupId,userId) { this.member(groupId,userId);this.run('INSERT INTO preferences VALUES(?,?) ON CONFLICT(userId) DO UPDATE SET primaryId=excluded.primaryId',userId,groupId);return {primaryId:groupId}; }
  update(groupId,userId,body) {
    this.member(groupId,userId,['owner','admin']);
    const name=text(body.name,'Family name',80),description=text(body.description,'Description',500,false);
    return this.tx(()=>{this.run('UPDATE families SET name=?,description=? WHERE id=?',name,description,groupId);this.event(groupId,'Family information updated.');return this.detail(groupId,userId);});
  }
  rotate(groupId,userId) {
    this.member(groupId,userId,['owner','admin']);
    return this.tx(()=>{const invite=code();this.run('UPDATE families SET invite=? WHERE id=?',invite,groupId);this.event(groupId,'The family invite code was changed.');return {invite};});
  }
  identity(groupId,userId,body) {
    this.member(groupId,userId);
    const realName=text(body.realName,'Real name',80),kinship=text(body.kinship,'Family relationship',50);
    this.run('UPDATE members SET realName=?,kinship=? WHERE groupId=? AND userId=?',realName,kinship,groupId,userId);
    return this.detail(groupId,userId);
  }
  role(groupId,userId,target,body) {
    this.member(groupId,userId,['owner']);const other=this.member(groupId,target);
    if(target===userId) fail(400,'Use ownership transfer instead of changing your own role.');
    if(!['admin','member','owner'].includes(body.role)) fail(400,'Invalid permission role.');
    return this.tx(()=>{
      if(body.role==='owner') this.run("UPDATE members SET role='admin' WHERE groupId=? AND userId=?",groupId,userId);
      this.run('UPDATE members SET role=? WHERE groupId=? AND userId=?',body.role,groupId,target);
      this.tree.refreshPending();
      this.event(groupId,`${other.realName}'s family permissions were updated.`);
      return this.detail(groupId,userId);
    });
  }
  leave(groupId,userId) {
    const me=this.member(groupId,userId);
    return this.tx(()=>{
      const n=this.get('SELECT COUNT(*) AS n FROM members WHERE groupId=?',groupId).n;
      if(me.role==='owner' && n>1) fail(409,'Transfer ownership before leaving this family.');
      this.run('DELETE FROM members WHERE groupId=? AND userId=?',groupId,userId);
      this.tree.refreshPending();
      if(n===1){this.tree.closing(groupId);this.run('DELETE FROM families WHERE id=?',groupId);}else this.event(groupId,`${me.realName} left the family.`);
      return {primaryId:this.primary(userId)};
    });
  }
  read(groupId,userId,lastId) {
    this.member(groupId,userId);
    if(!Number.isSafeInteger(lastId)||lastId<0)fail(400,'Invalid read position.');
    const max=this.get('SELECT MAX(id) AS id FROM events WHERE groupId=?',groupId).id??0;
    this.run('UPDATE members SET lastRead=MAX(lastRead,?) WHERE groupId=? AND userId=?',Math.min(max,lastId),groupId,userId);
    return {ok:true};
  }
  addRecord(groupId,userId,kind,body) {
    const me=this.member(groupId,userId,kind==='notes'||kind==='tasks'?['owner','admin']:undefined);
    if(!['activities','tasks','notes'].includes(kind))fail(404,'Unknown record type.');
    const title=text(body.title,'Title',100);
    let data={title};
    if(kind==='notes') {
      data={...data,note:text(body.note,'Health note',2000),photoTitle:text(body.photoTitle,'Photo description',200,false)};
    } else {
      if(!Array.isArray(body.participantIds)||!body.participantIds.length||body.participantIds.length>100)fail(400,'Select at least one family member.');
      const participantIds=[...new Set(body.participantIds)];
      if(participantIds.some(id=>typeof id!=='string'||!id||id.length>120))fail(400,'Invalid family member ID.');
      for(const id of participantIds)this.member(groupId,id);
      if(kind==='activities') {
        const date=text(body.date,'Date',10);
        if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||!Number.isFinite(Date.parse(date))||new Date(date).toISOString().slice(0,10)!==date)fail(400,'Enter a valid activity date.');
        data={...data,participantIds,date,duration:text(body.duration,'Duration',80),location:text(body.location,'Location',160),goal:text(body.goal,'Goal',300,false),description:text(body.description,'Description',2000,false),requirements:text(body.requirements,'Requirements',1000,false),tags:text(body.tags,'Tags',200,false)};
      } else {
        if(!['autoLogin','manualDaily','exerciseTarget'].includes(body.type))fail(400,'Choose a check-in type.');
        data={...data,participantIds,type:body.type,repeat:text(body.repeat,'Repeat rule',100)};
      }
    }
    return this.tx(()=>{
      const id=randomUUID();this.run('INSERT INTO records VALUES(?,?,?,?,?,?)',id,groupId,kind,JSON.stringify(data),userId,this.clock());
      this.event(groupId,kind==='notes'?`${me.realName} added a health note.`:`${me.realName} created ${kind==='tasks'?'a check-in task':'an activity'}: ${title}`);
      return {id};
    });
  }
  checkIn(groupId,userId,taskId) {
    const me=this.member(groupId,userId);
    const task=this.get("SELECT * FROM records WHERE id=? AND groupId=? AND kind='tasks'",taskId,groupId);
    if(!task)fail(404,'Task not found.');
    const body=JSON.parse(task.body);
    if(body.type!=='manualDaily')fail(400,'Automatic and exercise check-ins are not yet enabled.');
    if(!body.participantIds.includes(userId))fail(403,'This task is not assigned to you.');
    return this.tx(()=>{
      const result=this.run('INSERT OR IGNORE INTO checkins VALUES(?,?,?,?)',taskId,userId,this.clock().slice(0,10),this.clock());
      if(result.changes)this.event(groupId,`${me.realName} checked in: ${body.title}`);
      return {ok:true};
    });
  }
}
