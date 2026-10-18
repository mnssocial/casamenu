# Aplicativo portátil 0.7.0

O pacote inclui Node.js 24.22.0 para macOS arm64, Homebridge, plugins e suas licenças. Não exige Node, npm, Xcode nem uma pasta HomeKit externa no Mac de destino.

Abra CasaMenu.app. Em Apple Casa, use **Preparar conexão** e **Configurar e mostrar QR**. A configuração Homebridge aparece dentro do aplicativo; no primeiro acesso, crie a conta local. Para Tuya, abra as configurações do plugin Tuya without developer account, informe o User Code do Smart Life/Tuya e autorize o QR pelo celular. O QR do Apple Casa é separado.

A ponte existente deste Mac é reutilizada. Não é parada nem substituída pela atualização. Em uma instalação nova, a ponte iniciada pelo CasaMenu acompanha o aplicativo: é encerrada ao sair do app e pode iniciar automaticamente na próxima abertura. O Mac precisa permanecer ligado e acordado.

O pacote não contém credenciais, inventário nem pareamentos pessoais. Dados existentes em Application Support são preservados. É possível preparar uma casa sem aparelhos Gree; o pareamento não é recriado em execuções posteriores.

## Empacotamento reproduzível

1. Baixe o runtime oficial Node 24 para macOS arm64 e confira SHA256 com o arquivo oficial SHASUMS256.txt.
2. Extraia em HomeKit/runtime (bin/node deve existir).
3. Execute ./package.sh. Dependências vêm de package-lock.json; testes rodam antes da distribuição.

A versão utilizada neste pacote tem SHA256 do tar.gz: 6a9724d9b50a5f22b4816cded441b5a8d9ddae546191a5e5b7efa5a5e2ee26d5.

## Limites de entrega

Assinatura local ad hoc, sem Developer ID/notarização. Distribuição comercial e validação em outro Mac/usuário ainda pendentes. A janela integrada usa a interface do Homebridge para autorização e QR; ainda não é um assistente inteiramente desenhado no CasaMenu. O controle infravermelho continua selecionando um aparelho por vez. Alexa e compatibilidade universal não estão implementadas.

Testes não enviam comandos físicos aos aparelhos. A confirmação física de cada comando e o pareamento no iPhone dependem de validação do usuário.
