'use strict';
const {execFile}=require('node:child_process');
const path=require('node:path');
function run(helper,storage,action,value){
 return new Promise((resolve,reject)=>execFile(process.execPath,[helper,storage,action,...(value===undefined?[]:[String(value)])],{timeout:20000,maxBuffer:128*1024},(error,stdout)=>{
  let result;try{result=JSON.parse(stdout)}catch{return reject(Error('CasaMenu não recebeu uma resposta válida da Tuya.'))}
  if(error||result.error)return reject(Error(result.error||'Falha ao consultar Tuya.'));
  resolve(result);
 }));
}
class CasaMenuIR {
 constructor(log,config,api){
  this.log=log;this.api=api;this.config=config;this.pending=Promise.resolve();this.snapshot=null;this.cached=null;this.cachedAt=0;
  this.helper=config.helperPath||path.resolve(__dirname,'../casamenu-tuya.cjs');this.storage=config.storagePath||api.user.storagePath();
  const {Service,Characteristic:C}=api.hap;
  this.info=new Service.AccessoryInformation().setCharacteristic(C.Manufacturer,'CasaMenu').setCharacteristic(C.Model,'Tuya IR - sem sensor, temperatura de referência').setCharacteristic(C.SerialNumber,'casamenu-office-ir');
  if(config.experimentalClimate !== true) {
   this.power=new Service.Switch(config.name||'Ar do escritório');
   this.power.getCharacteristic(C.On).onGet(()=>this.getPower()).onSet(value=>this.setPower(Boolean(value)));
   return;
  }
  this.climate=new Service.HeaterCooler(config.name||'Ar do escritório','office-climate');
  const bind=(type,get,set,props)=>{const c=this.climate.getCharacteristic(type);if(props)c.setProps(props);c.onGet(async()=>get(await this.status()));if(set)c.onSet(set);};
  bind(C.Active,s=>s.on?C.Active.ACTIVE:C.Active.INACTIVE,async v=>{if(v===C.Active.ACTIVE){const s=await this.status();if(!['cool','heat','auto'].includes(s.mode))await this.command('mode','cool')}await this.setPower(v===C.Active.ACTIVE)});
  // No ambient sensor is available. This is explicitly a setpoint reference,
  // not telemetry; no thermostat automation may use it as a room measurement.
  this.climate.getCharacteristic(C.CurrentTemperature).onGet(async()=> (await this.status()).temperature);

  bind(C.CurrentHeaterCoolerState,s=>s.on?C.CurrentHeaterCoolerState.IDLE:C.CurrentHeaterCoolerState.INACTIVE);
  bind(C.TargetHeaterCoolerState,s=>({heat:1,cool:2}[s.mode]??0),v=>this.command('mode',({0:'auto',1:'heat',2:'cool'})[v]),{validValues:[0,1,2]});
  for(const t of [C.CoolingThresholdTemperature,C.HeatingThresholdTemperature])bind(t,s=>s.temperature,v=>this.command('temperature',v),{minValue:16,maxValue:30,minStep:1});
  bind(C.RotationSpeed,s=>({auto:0,low:33,medium:66,high:100}[s.fan]??0),v=>this.command('fan',v===0?'auto':v<=33?'low':v<=66?'medium':'high'),{minValue:0,maxValue:100,minStep:1});
  this.climate.setCharacteristic(C.TemperatureDisplayUnits,C.TemperatureDisplayUnits.CELSIUS);
  this.modes=[];

 }
 async status(){if(this.snapshot&&Date.now()-this.cachedAt<5000)return this.snapshot;const s=await run(this.helper,this.storage,'status');this.accept(s);return s}
 accept(s){this.snapshot=s;this.cached=Boolean(s.on);this.cachedAt=Date.now()}
 async command(action,value){const task=this.pending.catch(()=>{}).then(async()=>{const s=await run(this.helper,this.storage,action,value);this.accept(s);this.log.info('Tuya aceitou comando: '+action)});this.pending=task;return task}
 async getPower(){return Boolean((await this.status()).on)}
 async setPower(value){return this.command(value?'on':'off')}
 getServices(){return this.power ? [this.info,this.power] : [this.info,this.climate,...this.modes]}
}
module.exports=api=>api.registerAccessory('homebridge-casamenu-ir','CasaMenuIR',CasaMenuIR);
module.exports.CasaMenuIR=CasaMenuIR;
