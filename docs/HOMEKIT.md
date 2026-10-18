# Ponte Casa/Siri

A ponte deve usar um identificador e código de pareamento gerados localmente. Nunca copie a configuração de uma casa para outra nem publique esses valores no Git.

## Publicação do IR

Depois de autorizar Tuya, acrescente um acessório ao `config.json` privado da ponte. Substitua os caminhos por caminhos absolutos reais; não inclua as reticências literalmente.

```json
{
  "accessory": "CasaMenuIR",
  "name": "Ar do escritório",
  "helperPath": "/caminho/para/CasaMenu/HomeKit/casamenu-tuya.cjs",
  "storagePath": "/caminho/para/dados-privados-da-ponte",
  "experimentalClimate": false
}
```

O padrão publica um interruptor. `experimentalClimate: true` publica um único HeaterCooler com energia, temperatura alvo, auto/frio/quente e velocidade. Desumidificação e ventilação isolada ficam no CasaMenu. Esse controle foi apresentado e aceito pelo usuário no iPhone piloto, mas ainda exige validação ampla.

Sem sensor, `CurrentTemperature` retorna a temperatura ajustada **como referência**, por exigência do serviço HomeKit. Ela não representa uma medição do ambiente. Esta limitação deve ficar visível no onboarding antes de uma distribuição comercial.

## Seleção e duplicação

Para selecionar explicitamente um IR, crie `casamenu-device-selection.json` na pasta privada de dados:

```json
{"infraredDeviceId":"IDENTIFICADOR_DO_SEU_APARELHO"}
```

Se o plugin Tuya publicar acessórios vazios (apenas informações, sem serviços de controle), use `options.deviceOverrides` da plataforma `TuyaNoDeveloperAccount` com o identificador correspondente e `category: "hidden"`. Faça isso somente para entradas verificadas como vazias ou duplicadas. Preserve a publicação do plugin CasaMenu. A seleção por identificador evita perder o IR quando o plugin modifica sua categoria no cache.

## Rede

Na instalação piloto, o anúncio padrão apareceu somente na interface interna. Usar `bridge.advertiser: "bonjour-hap"` e `bridge.bind` com a interface Wi-Fi correta resolveu a descoberta. Não assuma que o nome da interface será igual em outro Mac. Nunca desative firewall ou permissões para contornar o diagnóstico.

## Operação

O script de desenvolvimento roda em primeiro plano. LaunchAgents, runtimes locais e configurações privadas da instalação piloto não são distribuídos neste repositório. Serviço automático e onboarding inteiramente no aplicativo ainda precisam de implementação reproduzível.
