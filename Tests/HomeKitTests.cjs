'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const hap=require('../HomeKit/node_modules/@homebridge/hap-nodejs');
const {CasaMenuIR}=require('../HomeKit/homebridge-casamenu-ir');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'casamenu-hap-')),helper=path.join(dir,'helper.cjs');
fs.writeFileSync(helper,`const fs=require('node:fs');const p=process.argv[2]+'/state',a=process.argv[3],v=process.argv[4];let s={on:false,temperature:23,mode:'cool',fan:'auto'};try{s=JSON.parse(fs.readFileSync(p))}catch{}if(a==='on'||a==='off')s.on=a==='on';else if(a==='temperature')s.temperature=Number(v);else if(a==='mode'||a==='fan')s[a]=v;fs.writeFileSync(p,JSON.stringify(s));console.log(JSON.stringify(s));`);
(async()=>{try{
 const stable=new CasaMenuIR({info(){}},{helperPath:helper,storagePath:dir},{hap});assert.ok(stable.power);assert.equal(stable.getServices().length,2);
 const a=new CasaMenuIR({info(){}},{helperPath:helper,storagePath:dir,experimentalClimate:true},{hap}),C=hap.Characteristic;
 const c=t=>a.climate.getCharacteristic(t);
 assert.equal(await c(C.Active).handleGetRequest(),0);
 await c(C.Active).handleSetRequest(1);assert.equal(await a.getPower(),true);
 await c(C.CoolingThresholdTemperature).handleSetRequest(22);assert.equal((await a.status()).temperature,22);
 await c(C.TargetHeaterCoolerState).handleSetRequest(1);assert.equal((await a.status()).mode,'heat');
 for(const [speed,fan] of [[0,'auto'],[33,'low'],[66,'medium'],[100,'high']]){await c(C.RotationSpeed).handleSetRequest(speed);assert.equal((await a.status()).fan,fan)}
 await a.command('mode','fan_only');await c(C.Active).handleSetRequest(1);assert.equal((await a.status()).mode,'cool');
 assert.equal(await c(C.CurrentTemperature).handleGetRequest(),22);assert.equal(a.modes.length,0);
 await Promise.all([a.setPower(true),a.setPower(false)]);assert.equal(await a.getPower(),false);
 a.helper=path.join(dir,'missing');await assert.rejects(a.setPower(true));assert.equal(a.cached,false);
 console.log('HomeKit PASS: energia, temperatura alvo, modos, velocidades, fila, falhas; temperatura de referência explícita, sem sensor ambiente.');
 }finally{fs.rmSync(dir,{recursive:true,force:true})}})().catch(e=>{console.error(e.message);process.exitCode=1});
