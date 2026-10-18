import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
const storage = process.argv[2];
if (!storage) throw new Error('Pasta de dados não informada');
fs.mkdirSync(storage,{recursive:true,mode:0o700});
const dest = path.join(storage,'config.json');
if (fs.existsSync(dest)) { console.log('Configuração existente preservada.'); process.exit(0); }
const exported = spawnSync('/usr/bin/defaults',['export','br.local.CasaMenu','-'],{encoding:'utf8'});
const data = exported.stdout?.match(/<key>inventory<\/key>\s*<data>([\s\S]*?)<\/data>/);
const devices = data ? JSON.parse(Buffer.from(data[1].replace(/\s/g,''),'base64').toString()) : [];
const gree = devices.filter(d => /^climate\.gree_lan_[a-f0-9]{12}$/.test(d.entity ?? '')).map(d=>({mac:d.entity.slice('climate.gree_lan_'.length),name:d.name,speedSteps:5,temperatureSensor:'disabled',minimumTargetTemperature:16,maximumTargetTemperature:30,temperatureStepSize:1,xFanEnabled:false,modifyVerticalSwingPosition:0,fanControlEnabled:true}));
if (!gree.length) throw new Error('Conecte primeiro um Gree no CasaMenu. Nenhum vínculo Gree foi encontrado.');
const mac = crypto.randomBytes(6); mac[0] = 2;
let digits; do { digits = Array.from({length:8},()=>crypto.randomInt(0,10)).join(''); } while (/^(\d)\1+$/.test(digits) || ['12345678','87654321'].includes(digits));
const config = {bridge:{name:'CasaMenu',username:[...mac].map(b=>b.toString(16).padStart(2,'0')).join(':').toUpperCase(),port:51836,pin:digits.slice(0,3)+'-'+digits.slice(3,5)+'-'+digits.slice(5)},accessories:[],platforms:[{name:'CasaMenu HomeKit',platform:'config',port:8581,host:'127.0.0.1',auth:'form',tempUnits:'c'},{name:'Gree da casa',platform:'GREEAirConditioner',disableAutoDetection:true,scanInterval:60,devices:gree}]};
fs.writeFileSync(dest,JSON.stringify(config,null,2),{mode:0o600});
console.log(`Configuração preparada para ${gree.length} aparelho(s). O QR de pareamento aparecerá no painel local.`);
