import { createServer } from 'node:http';
import { FamilyError } from './store.js';

/** No client-supplied UUID is trusted. The existing Auth API owns session validation. */
export function authVerifier(url) {
  return async header => {
    if(!/^Bearer \S+$/.test(header??''))throw new FamilyError(401,'Please sign in to use Family.');
    let response;
    try { response=await fetch(url,{headers:{Authorization:header},signal:AbortSignal.timeout(5000)}); }
    catch { throw new FamilyError(503,'Login service is unavailable. Please try again.'); }
    if(response.status===401||response.status===404)throw new FamilyError(401,'Your session expired. Please sign in again.');
    if(!response.ok)throw new FamilyError(503,'Login service is unavailable.');
    let payload;try {payload=await response.json();}catch{throw new FamilyError(503,'Invalid login service response.');}
    if(typeof payload.user?.id!=='string'||!payload.user.id)throw new FamilyError(401,'Invalid session.');
    return payload.user;
  };
}

export function familyServer(store,verify,{origins=['http://localhost:7357'],logger=console}={}) {
  const attempts=new Map();
  return createServer(async(req,res)=>{
    const origin=req.headers.origin;
    res.setHeader('Content-Type','application/json; charset=utf-8');
    res.setHeader('Cache-Control','no-store');
    res.setHeader('X-Content-Type-Options','nosniff');
    if(origin&&origins.includes(origin)) {res.setHeader('Access-Control-Allow-Origin',origin);res.setHeader('Vary','Origin');}
    res.setHeader('Access-Control-Allow-Headers','Authorization, Content-Type');
    res.setHeader('Access-Control-Allow-Methods','GET, POST, PATCH, PUT, OPTIONS');
    const send=(status,payload)=>{res.writeHead(status);res.end(JSON.stringify(payload));};
    try {
      if(origin&&!origins.includes(origin))throw new FamilyError(403,'This browser origin is not allowed.');
      if(req.method==='OPTIONS'){res.writeHead(204);res.end();return;}
      const path=new URL(req.url,'http://localhost').pathname;
      if(path==='/health'&&req.method==='GET'){store.get('SELECT 1');send(200,{ok:true,service:'family'});return;}
      const user=await verify(req.headers.authorization);
      let body={};
      if(['POST','PATCH','PUT'].includes(req.method)) {
        const chunks=[];let bytes=0;
        for await(const chunk of req){bytes+=chunk.length;if(bytes>32768)throw new FamilyError(413,'Request is too large.');chunks.push(chunk);}
        const raw=Buffer.concat(chunks).toString('utf8');
        try {body=raw?JSON.parse(raw):{};}catch{throw new FamilyError(400,'Invalid JSON.');}
        if(!body||typeof body!=='object'||Array.isArray(body))throw new FamilyError(400,'Invalid request.');
      }
      let result;
      if(path==='/families'&&req.method==='GET')result=store.list(user.id);
      else if(path==='/families'&&req.method==='POST')result=store.create(user.id,body);
      else if(['/families/preview','/families/join'].includes(path)&&req.method==='POST') {
        const now=Date.now();for(const [id,v]of attempts){if(now-v.start>60000)attempts.delete(id);}
        const a=attempts.get(user.id)??{start:now,n:0};a.n++;attempts.set(user.id,a);
        if(a.n>20)throw new FamilyError(429,'Too many invite attempts. Wait one minute.');
        result=path.endsWith('preview')?store.preview(body.invite):store.join(user.id,body);
      } else {
        const parts=path.split('/').filter(Boolean);
        if(parts[0]!=='families'||!parts[1])throw new FamilyError(404,'Not found.');
        const [,id,action,target]=parts;
        if(action==='tree'){
          if(req.method==='POST'&&['preview','requests'].includes(target)&&parts.length===4){
            const now=Date.now();for(const [key,v]of attempts)if(now-v.start>60000)attempts.delete(key);
            const key=`tree:${user.id}`,a=attempts.get(key)??{start:now,n:0};a.n++;attempts.set(key,a);
            if(a.n>20)throw new FamilyError(429,'Too many tree requests. Wait one minute.');
          }
          if(parts.length===3&&req.method==='GET')result=store.tree.view(id,user.id);
          else if(parts.length===4&&req.method==='POST'&&target==='preview')result=store.tree.preview(id,user.id,body);
          else if(parts.length===4&&req.method==='POST'&&target==='requests')result=store.tree.send(id,user.id,body);
          else if(parts.length===5&&req.method==='POST'&&target==='requests')result=store.tree.decide(id,user.id,parts[4],body);
          else if(parts.length===4&&req.method==='POST'&&target==='code')result=store.tree.rotate(id,user.id);
          else if(parts.length===5&&req.method==='POST'&&target==='disconnect')result=store.tree.disconnect(id,user.id,parts[4],body);
          else if(parts.length===4&&req.method==='POST'&&target==='leave')result=store.tree.leave(id,user.id,body);
          else throw new FamilyError(404,'Tree action not found.');
        }
        else if(parts.length===2&&req.method==='GET')result=store.detail(id,user.id);
        else if(parts.length===2&&req.method==='PATCH')result=store.update(id,user.id,body);
        else if(parts.length===3&&req.method==='POST'&&action==='primary')result=store.setPrimary(id,user.id);
        else if(parts.length===3&&req.method==='POST'&&action==='invite')result=store.rotate(id,user.id);
        else if(parts.length===3&&req.method==='POST'&&action==='leave')result=store.leave(id,user.id);
        else if(parts.length===3&&req.method==='POST'&&action==='read')result=store.read(id,user.id,body.lastId);
        else if(parts.length===3&&req.method==='PUT'&&action==='identity')result=store.identity(id,user.id,body);
        else if(parts.length===4&&req.method==='PUT'&&action==='members')result=store.role(id,user.id,target,body);
        else if(parts.length===3&&req.method==='POST'&&['activities','tasks','notes'].includes(action))result=store.addRecord(id,user.id,action,body);
        else if(parts.length===4&&req.method==='POST'&&action==='checkins')result=store.checkIn(id,user.id,target);
        else throw new FamilyError(404,'Not found.');
      }
      send(200,result);
    }catch(e){if(!(e instanceof FamilyError))logger.error('Family request failed:',e.code??e.name);send(e instanceof FamilyError?e.status:500,{error:e instanceof FamilyError?e.message:'Unable to save or load family data. Please retry.'});}
  });
}
