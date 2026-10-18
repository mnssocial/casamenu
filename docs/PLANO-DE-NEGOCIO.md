# CasaMenu — plano de negócio inicial

Versão de trabalho · 18 de outubro de 2026. Valores e metas abaixo são hipóteses para validação, não previsões de vendas nem orçamento aprovado.

## Proposta
Um aplicativo nativo para Mac que simplifica o controle de aparelhos domésticos compatíveis e sua integração com Casa/Siri. O cliente compra conveniência: conectar, escolher o cômodo e usar, com suporte e compatibilidade documentada.

## Cliente inicial
Pessoas que já possuem Mac e iPhone, usam ar-condicionado Gree ou controles infravermelhos Tuya e se frustram com aplicativos fragmentados. Começar com esse nicho; não anunciar suporte universal a qualquer aparelho nem usar “oito dispositivos” como promessa de compatibilidade.

Validar com 15 entrevistas e 10 casas piloto. Perguntas: quais aparelhos e modelos possuem, quanto tempo perdem configurando, quando o Mac fica ligado, quais funções são indispensáveis e quanto pagariam por uma solução confiável. Esses números são metas propostas.

## Produto mínimo comercial
- Instalação única com componentes incluídos e assinatura/notarização.
- Autorização Tuya guiada; descoberta Gree na rede local.
- Inventário por aparelho e capacidade, sem duplicações e sem controles vazios.
- Controle rápido na barra superior e janela principal acessível no Dock.
- Configuração de Casa/Siri pelo aplicativo com QR próprio da ponte.
- Reconexão, atualização e recuperação sem terminal nem gestão de plugins.
- Diagnóstico compreensível e suporte com dados sensíveis protegidos.

Alexa fica numa etapa posterior, com avaliação específica de integração. Não prometer controle remoto quando o Mac estiver desligado. O caminho de controle fora de casa deve ser definido e validado antes de ser vendido.

## Diferenciação e alternativas
Homebridge já integra acessórios que não oferecem HomeKit nativo e dispõe de um amplo ecossistema de plugins. O diferencial comercial proposto é uma experiência nativa, compatibilidade selecionada e suporte, não a invenção de uma ponte. [Homebridge](https://homebridge.io/install/)

Home Assistant oferece uma plataforma ampla, com serviço de nuvem opcional. CasaMenu deve buscar o usuário que prefere poucos passos e uma experiência centrada no Mac. Essa posição é uma hipótese de mercado a validar. [Home Assistant Cloud](https://www.home-assistant.io/cloud/)

## Modelo de receita a testar
Proposta inicial: avaliação gratuita de 14 dias e assinatura por residência, sem cobrança por botão ou por aparelho dentro da lista suportada.

| Oferta experimental | Preço proposto | Objetivo |
|---|---:|---|
| Mensal | R$ 24,90 | Menor compromisso inicial |
| Anual | R$ 199 | Validar disposição a pagar e permanência |
| Configuração assistida opcional | R$ 149 por sessão | Atender exceções; não substituir instalação simples |

Não lançar vários planos antes de conhecer o custo de suporte. Comparar também licença paga com renovação opcional de atualizações; evitar licença vitalícia enquanto houver dependência de APIs que exigem manutenção contínua.

## Economia unitária ilustrativa
Exemplo exclusivamente para planejamento: mensalidade R$ 24,90, reserva agregada hipotética de 12% para processamento, tributos e estornos e R$ 5 por cliente/mês para suporte e operação. Contribuição aproximada: R$ 16,91 por cliente/mês, antes de custos fixos e aquisição.

Com custo fixo hipotético de R$ 10.000/mês, seriam necessários aproximadamente 592 clientes mensais nessa composição para cobrir os custos. Não inclui descontos anuais. Uma mistura com assinaturas anuais reduz a receita mensal equivalente e exige novo cálculo. Confirmar taxas, tributação, tempo de suporte e orçamento de desenvolvimento antes de usar esses números para decisão.

Categorias de custo: desenvolvimento macOS, manutenção de conectores, aparelhos para laboratório, testes em Macs limpos, atendimento, distribuição, monitoramento consentido, pagamento, contabilidade e licenças. O Apple Developer Program informa US$ 99 por ano, sujeito à apresentação local da cobrança. [Apple Developer Program](https://developer.apple.com/programs/)

## Aquisição
Começar com demonstrações reais de instalação e uso em comunidades de Mac e automação residencial, conteúdo sobre modelos suportados e convites para pilotos. Depois testar parcerias com instaladores. Não investir em aquisição em escala antes de medir ativação e suporte.

Funil proposto: visita → verificação de compatibilidade → instalação → primeiro aparelho respondendo → uso recorrente → pagamento. Medir cada passagem, não apenas downloads.

## Plano de execução por critérios
1. **Confiabilidade:** corrigir duplicação, erros e limites; distinguir comando aceito de estado físico; preservar configurações.
2. **Instalação:** validar em pelo menos dois Macs/usuários limpos, sem ferramentas de desenvolvimento nem intervenção técnica.
3. **Piloto:** 10 casas, acompanhamento por 30 dias, lista explícita de modelos testados.
4. **Cobrança:** testar oferta com clientes que tiveram ativação bem-sucedida e registrar cancelamentos e motivo.
5. **Expansão:** acrescentar fabricantes apenas quando os conectores e o suporte forem sustentáveis.

Metas iniciais propostas: pelo menos 80% das instalações compatíveis concluídas sem ajuda, primeiro comando em até 10 minutos, sucesso de comando acima de 99% quando aparelho e rede estão disponíveis, e menos de 20 minutos de suporte por cliente no primeiro mês. Registrar separadamente sucesso de API, confirmação do aparelho e resultado observado; infravermelho sem retorno não comprova execução física.

## Riscos e limites
- Mudanças de APIs e restrições comerciais da Tuya: avaliar termos e alternativas antes da distribuição.
- Licenças dos componentes e marcas: inventário de dependências e revisão antes do lançamento; não sugerir certificação Apple inexistente.
- Dependência do Mac ligado: tornar explícita e avaliar uma central dedicada no futuro se houver demanda.
- Dispositivos sem sensor: a temperatura de referência não pode ser apresentada como medição ambiente nem usada como tal em automações.
- Suporte por modelos: restringir catálogo inicial e criar testes repetíveis.
- Credenciais: não incluir dados pessoais no instalador; prever revogação, migração e remoção.

## O que já foi validado e o que falta
Nesta casa, foram exercitados comandos Gree e Tuya e o usuário confirmou a apresentação do controle do escritório no Casa após ajustes. Isso comprova viabilidade inicial, não prontidão comercial. A instalação limpa, estabilidade prolongada, suporte a várias casas, assinatura/notarização e economia do negócio continuam pendentes.

Próxima decisão: validar o problema e a oferta com o nicho inicial enquanto o produto atinge os critérios de instalação e confiabilidade. Não vender compatibilidade universal nem anunciar lançamento com base apenas neste protótipo.
