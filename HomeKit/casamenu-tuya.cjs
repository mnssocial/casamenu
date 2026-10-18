const fs = require('fs'), path = require('path');
const timer = setTimeout(()=>{process.stdout.write(JSON.stringify({error:'A Tuya demorou para responder.'}));process.exit(1)},15000);
const base = process.argv[2];
const action = process.argv[3] || 'status';
const quiet = {debug(){},info(){},warn(){},error(){},log(){}};
(async()=>{
 const name=fs.readdirSync(base).find(n=>n.startsWith('tuya-ha-qr-auth.')&&n.endsWith('.json'));
 if(!name) throw Error('Conecte sua conta Tuya primeiro.');
 const authPath=path.join(base,name), auth=JSON.parse(fs.readFileSync(authPath));
 const API=require('./node_modules/homebridge-tuya-without-developer-account/dist/cloud/api/TuyaHACloudAPI').default;
 const api=new API(auth.userCode,auth.terminalId,auth.endpoint,auth.tokenInfo,quiet,false,tokenInfo=>{auth.tokenInfo=tokenInfo;fs.writeFileSync(authPath,JSON.stringify(auth),{mode:0o600})});
 const cached=fs.readdirSync(path.join(base,'persist')).find(n=>n.startsWith('TuyaDeviceList.'));
 const devices=JSON.parse(fs.readFileSync(path.join(base,'persist',cached)));
 let selection={};try{selection=JSON.parse(fs.readFileSync(path.join(base,'casamenu-device-selection.json')))}catch{}
 const device=selection.infraredDeviceId ? devices.find(d=>d.id===selection.infraredDeviceId) : devices.find(d=>d.category==='infrared_ac');
 if(!device) throw Error('Nenhum ar infravermelho encontrado na conta.');
 const spec=await api.get(`/v1.1/m/life/${device.id}/specifications`);
 if(!spec.success) throw Error('Não foi possível consultar as funções do ar.');
 const functions=spec.result.functions||[];
 const lastPath=path.join(base,'casamenu-ir-last-command.json');
 let last={};try{last=JSON.parse(fs.readFileSync(lastPath))}catch{}
 if(action!=='status'){
  const {code,value}=require('./tuya-command.cjs')(action,process.argv[4],functions);
  const r=await api.post(`/v1.1/m/thing/${device.id}/commands`,null,{commands:[{code,value}]});
  if(!r.success||r.result!==true)throw Error('A Tuya não confirmou o envio do comando.');
  if(action==='temperature')last.temperature=value;else if(action==='mode')last.mode=value;else if(action==='fan')last.wind=value;else last.on=action==='on';
  last.sentAt=Date.now();fs.writeFileSync(lastPath,JSON.stringify(last),{mode:0o600});
 }
 const details=await api.get('/v1.0/m/life/ha/devices/detail',{devIds:device.id});
 const raw=details.success&&Array.isArray(details.result)?details.result[0]:null;
 const status=Array.isArray(raw?.status)?Object.fromEntries(raw.status.map(s=>[s.code,s.value])):raw?.status||{};
 console.log(JSON.stringify({name:device.name,on:typeof status.power==='boolean'?status.power:last.on??false,temperature:Number(status.temp??last.temperature??23),mode:['cool','heat','auto','fan_only','dry'][status.mode??last.mode??0],fan:['auto','low','medium','high'][status.wind??last.wind??0],codes:functions.map(f=>f.code),estimated:typeof status.power!=='boolean'}));
})().catch(e=>{console.log(JSON.stringify({error:e.message}));process.exitCode=1}).finally(()=>clearTimeout(timer));
