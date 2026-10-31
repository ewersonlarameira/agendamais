# Planos na apresentação comercial

A seção `/#planos` apresenta nome, valor por período, renovação e descrição dos planos ativos e não excluídos configurados no Master. Os botões comerciais de planos e o item de menu apontam para essa seção, sem abrir WhatsApp. Descrições são renderizadas como texto, preservando emojis e quebras de linha e sem executar HTML.

`GET /api/plans` consulta a projeção pública `agenda_public_plans`, com credenciais anônimas e cache desativado, mesmo quando há uma sessão inválida ou bloqueada no navegador. A função permite apenas leitura de `id`, `name`, `amount`, `months` e `description`. A tabela plans não recebe acesso direto para o público e os demais dados da plataforma continuam privados.

A página recarrega os planos a cada 15 segundos enquanto visível, ao voltar à aba e ao receber uma notificação BroadcastChannel de edição/exclusão do Master no mesmo domínio. Outros domínios/dispositivos atualizam na próxima consulta (até 15 segundos com a página visível), sem nova publicação. Falhas de consulta exibem mensagem e opção de tentar novamente; planos inativos/excluídos desaparecem na atualização. Não há valores ou listas de benefícios fixos no código da apresentação.

O rodapé informa: “Agenda+ é produzido pelo grupo Automatizei Digital ®”.

`database/verify-public-plans.sql` testa a projeção pública, atualização dos campos comerciais, texto Unicode e multilinha, exclusão de planos inativos/excluídos e preservação dos privilégios das tabelas, com rollback. Não deixa planos de teste nem altera os planos comerciais reais.

## Comparação Profissional e Premium

A seção pública também compara os dois planos ativos pelos nomes. Valores e diferença por período são calculados a partir da mesma resposta pública. As linhas são extraídas das descrições atuais, agrupando benefícios correspondentes; não se mantêm preços ou limites de acessos fixos no componente. O texto de herança do Premium habilita a indicação dos recursos do Profissional incluídos. Benefícios não especificados são rotulados “Não destacado”, sem inferir exclusão ou implementar restrições de acesso. Remover/inativar um dos planos retira a comparação. Atualizações usam o polling e canal já existentes. Tabela semântica com cabeçalhos de linha/coluna e layout de três colunas também no celular.
