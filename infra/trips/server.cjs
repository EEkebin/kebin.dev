const http = require('node:http');
const crypto = require('node:crypto');
const derive = require('node:util').promisify(crypto.scrypt);
const { PrismaClient } = require('@prisma/client');
const db = new PrismaClient();
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
async function seed() {
  let password = '';
  for await (const piece of process.stdin) password += piece;
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = await derive(password.trim(),salt,64);
  await db.user.create({data:{username:'admin',email:'admin@example.invalid',passwordHash:salt+':'+hash.toString('hex')}});
}
function validTrip(t) {
  const label = s => typeof s==='string' && s.length>0 && s.length<=100;
  return t && Array.isArray(t.days) && t.days.length===3 && t.days.every(d=>Array.isArray(d)&&d.length<=200&&d.every(label)) &&
    Array.isArray(t.packing)&&t.packing.length<=200&&t.packing.every(i=>Array.isArray(i)&&label(i[0])&&typeof i[1]==='boolean');
}
async function handle(req,res) {
  res.setHeader('Cache-Control','no-store');res.setHeader('Content-Type','application/json');
  const reply=(code,data)=>{res.statusCode=code;res.end(JSON.stringify(data));};
  let body={};
  if(req.method==='POST'){
    if(req.headers.origin!=='https://trips.kebin.dev'||req.headers['content-type']!=='application/json')return reply(403,{});
    let raw='';for await(const part of req){raw+=part;if(raw.length>100000)return reply(413,{});}
    try{body=JSON.parse(raw);}catch{return reply(400,{});}
    if(!body||typeof body!=='object')return reply(400,{});
  }
  const route=req.method+' '+req.url;
  const cookie='; Path=/; HttpOnly; Secure; SameSite=Lax';
  if(route==='POST /api/login'){
    if(typeof body.login!=='string'||typeof body.password!=='string'||body.password.length>256)return reply(400,{});
    const user=await db.user.findFirst({where:{OR:[{username:body.login},{email:body.login}]}});
    const [salt,hash]=(user?.passwordHash||'dummy:').split(':');
    const derived=await derive(body.password,salt,64);
    if(!user||!crypto.timingSafeEqual(derived,Buffer.from(hash,'hex')))return reply(401,{});
    const token=crypto.randomBytes(32).toString('hex');
    await db.session.deleteMany({where:{expires:{lt:new Date()}}});
    await db.session.create({data:{tokenHash:digest(token),expires:new Date(Date.now()+86400000),userId:user.id}});
    res.setHeader('Set-Cookie','__Host-waypost='+token+cookie+'; Max-Age=86400');
    return reply(200,{username:user.username,trip:JSON.parse(user.trip)});
  }
  const token=/\b__Host-waypost=([0-9a-f]{64})\b/.exec(req.headers.cookie||'')?.[1];
  const session=token&&await db.session.findUnique({where:{tokenHash:digest(token)},include:{user:true}});
  if(!session||session.expires<=new Date())return reply(401,{});
  if(route==='GET /api/me')return reply(200,{username:session.user.username,trip:JSON.parse(session.user.trip)});
  if(route==='POST /api/logout'){
    await db.session.deleteMany({where:{tokenHash:session.tokenHash}});
    res.setHeader('Set-Cookie','__Host-waypost='+cookie+'; Max-Age=0');return reply(200,{});
  }
  if(route==='POST /api/trip'&&validTrip(body)){
    await db.user.update({where:{id:session.userId},data:{trip:JSON.stringify(body)}});return reply(200,{});
  }
  reply(400,{});
}
if(process.argv[2]==='seed')seed().finally(()=>db.$disconnect());
else http.createServer((req,res)=>handle(req,res).catch(()=>{res.statusCode=500;res.end('{}');})).listen(8197);
