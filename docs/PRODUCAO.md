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

## Estado atual
Protótipo funcional neste Mac, não uma versão de produção distribuível. Gree e comandos Tuya do escritório funcionam. Ponte publica quarto, luzes e interruptor do escritório; Casa/Siri ainda sem pareamento validado. Testes automatizados e comandos da ponte passaram; testes de instalação limpa, reinício completo e estabilidade prolongada pendentes.

A consulta Tuya ainda seleciona um ar do cache e a interface mantém nomes fixos desta casa. Isso precisa ser generalizado antes de oferecer instalação para outras casas. O fluxo QR ainda depende do painel Homebridge; deve ser incorporado ao aplicativo. O pacote atual não deve ser anunciado como autossuficiente.
