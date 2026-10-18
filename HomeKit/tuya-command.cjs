function command(action,input,functions) {
 let code,value;
 if(action==='on'||action==='off'){code=action==='on'?'PowerOn':'PowerOff';value=code;}
 else if(action==='temperature'){code='T';value=Number(input);if(!Number.isInteger(value)||value<16||value>30)throw Error('Temperatura inválida.');}
 else if(action==='mode'){code='M';value={cool:0,heat:1,auto:2,fan_only:3,dry:4}[input];if(value===undefined)throw Error('Modo inválido.');}
 else if(action==='fan'){code='F';value={auto:0,low:1,medium:2,high:3}[input];if(value===undefined)throw Error('Ventilação inválida.');}
 else throw Error('Função ainda não validada.');
 if(!functions.some(f=>f.code===code))throw Error('Esta função não está disponível neste ar.');
 return {code,value};
}
module.exports=command;
