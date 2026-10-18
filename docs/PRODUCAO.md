# CasaMenu como aplicativo de produção

Objetivo: instalar no Mac, abrir, autorizar as conexões e controlar a casa. Terminal, plugins e portais de desenvolvedor não fazem parte da experiência final.

## Fluxo de primeiro uso
1. Abrir CasaMenu e permitir acesso à rede local.
2. Conectar Tuya com autorização no celular; descoberta dos aparelhos e dos comandos realmente disponíveis.
3. Descobrir Gree na mesma rede e escolher os aparelhos/cômodos.
4. Adicionar ao Casa pelo QR HomeKit. Essa autorização Apple é separada da autorização Tuya.
5. Mostrar controles simples e estado claro: encontrado, precisa de autorização, conectado ou sem resposta.

## Camadas e critérios de entrega
- **Distribuição:** aplicativo com componentes necessários incluídos, sem caminhos de desenvolvedor; licenças incluídas; assinatura Developer ID e notarização; instalação limpa validada. Apple Silicon primeiro; compatibilidade Intel só após build/teste correspondente.
- **Dados:** preferências e estado em Application Support; segredos protegidos; nenhuma credencial no instalador; migrações reversíveis; revogar/reconectar conta pelo app.
- **Conectores:** Gree local e Tuya nuvem separados; descoberta por identificador estável; múltiplos aparelhos sem nomes fixos; capacidades reais por aparelho; distinguir comando aceito de estado confirmado.
- **Serviço:** iniciar e recuperar automaticamente, sem terminal; reconectar após Wi-Fi, repouso e renovação de autorização; impedir processos duplicados.
- **Interface:** configuração dentro do CasaMenu, sem painel técnico obrigatório; cômodos, aparelhos e controles suportados; QR com expiração e nova tentativa; erros com uma ação útil.
- **Apple Casa/Siri:** ponte e QR integrados; pareamento confirmado no iPhone; teste de voz por dispositivo; explicar disponibilidade quando o Mac está desligado. Não prometer todos os controles de um fabricante no HomeKit.
- **Alexa:** integração separada; preservar vínculos existentes do usuário; avaliar suporte por dispositivo antes de oferecer conexão. Echo não é central Apple.
- **Validação:** instalação em usuário/Mac limpo, reinício real, troca de rede, repouso/despertar, credencial expirada, perda de internet, múltiplos aparelhos e atualização sem perder pareamento.

## Estado atual — 0.7.0
Aplicativo portátil com runtime Node e dependências incluídos, gerenciamento da ponte sem Terminal e painel de configuração/QR incorporado. Uma ponte existente é reutilizada, com dados e pareamentos preservados. Em instalação nova, a ponte gerenciada acompanha a execução do aplicativo.

A consulta Tuya ainda seleciona um ar do cache e a interface mantém cômodos da instalação piloto. A autorização integrada usa a interface Homebridge em WebKit, não um assistente nativo próprio. Assinatura Developer ID, notarização, testes em outro Mac, reinício e estabilidade prolongada continuam pendentes. Não anunciar a versão como distribuição comercial final.
