# Conferência para lançamento comercial — 28/10/2026

**Resultado:** o endereço público está no ar, sem login no ChatGPT. As verificações técnicas abaixo passaram e as correções foram preparadas para publicação. A revenda regular ainda depende de backup externo/recuperação completa, identificação do operador e validação em dispositivos. Este documento não é uma certificação de segurança ou de conformidade jurídica.

## Estado observado

- 1 empresa com licença ativa, administrador vinculado, 2 profissionais, 4 serviços e 1 agendamento.
- 2 contas de autenticação e 1 Master. Nenhuma conta ou empresa temporária de teste permaneceu após os testes.
- 14 tabelas públicas, todas com RLS. Privilégios impedem leitura direta por clientes; RPCs verificam sessão, papel e empresa.
- Banco com aproximadamente 13,41 MiB na consulta; o tamanho varia com dados, índices e logs.
- Nenhuma inscrição Push ativa. Há um job de envio de notificações por minuto; não há job de backup.
- Três Edge Functions ativas: envio Push, provisionamento inicial e edição de credenciais pelo Master. Usam autenticação própria e autorização no banco; chaves de serviço permanecem no ambiente Edge.

## Correções desta revisão

1. **Recuperação pelo WhatsApp:** botão “Esqueci minha senha” no login abre o suporte em **(24) 99907-4698**, conforme definido pelo operador. Inclui contexto do painel e e-mail informado, sem senha ou token. Não envia a mensagem nem altera credenciais automaticamente. O botão público de autoativação por e-mail foi retirado; o acesso inicial é fornecido pelo Master/suporte.
2. **Dependências:** atualização de Next para 16.4.1, React/React DOM/React Server DOM para 19.2.8, Vite para 8.1.6 e Zod para 4.6.6, além de correções transitivas fixadas no arquivo de lock. O audit inicial de produção apontou 23 avisos (3 críticos); o audit final completo, incluindo desenvolvimento, retornou zero avisos conhecidos. Isso não garante ausência de vulnerabilidades desconhecidas. A política de idade mínima das demais dependências foi preservada.
3. **Autenticação:** validação explícita de operações e campos, limite de corpo de 20.000 bytes, mensagens controladas para entradas inválidas e limite de tamanho para novas senhas, sem expor o conteúdo de requisições malformadas.
4. **Identidade PWA:** o painel administrativo da empresa também seleciona o manifesto do estabelecimento; o nome personalizado é respeitado e o manifesto não recebe cache persistente da resposta.
5. **Operação:** procedimento de atendimento e entrada de empresas em [support-and-launch.md](support-and-launch.md).

## Verificações concluídas

| Área | Evidência e limite |
|---|---|
| Publicação | Inicial, demonstração, Master, empresa, painel da empresa, termos e privacidade respondem sem login no ChatGPT. O público não recebe identidade do proprietário. |
| Acesso indevido | Sem sessão, são recusados Master, workspace, Financeiro, dispositivos, exportação, cadastro/edição de empresa, credenciais, planos e uploads. Bootstrap anônimo e origem externa recusados. |
| Dados públicos | Catálogo sem clientes, agendamentos, Financeiro, acessos ou CPF/CNPJ da empresa. |
| Isolamento | As suítes transacionais passaram para empresas, papéis, agenda, Financeiro, modelos e dispositivos. Nenhuma tabela pública sem RLS. Não se trata de um pentest externo. |
| Agenda | Reserva, protocolo, preço do servidor, confirmação, reagendamento, liberação do horário anterior, cancelamento, conclusão e recebimento passaram com rollback. A restrição de exclusão impede sobreposição por profissional. Não foi executado teste de carga com 15 empresas simultâneas. |
| Master e planos | Mensal/anual, descrição, exclusão lógica sem perda de licença, edição completa, alteração separada de e-mail comercial/login, proteção de contas Master/compartilhadas e versões antigas passaram. |
| Acessos | Autorização, provisionamento retomável e vínculo de contas antigas passaram no banco. Operações administrativas de Auth foram simuladas nos testes de orquestração; senhas reais de clientes não foram alteradas. |
| Financeiro | Totais em centavos, receitas/despesas, datas, recebimentos sem duplicação, bloqueio de profissional, versões concorrentes, anulação, CSV e auditoria passaram. |
| WhatsApp | Três mensagens, campos automáticos, fuso de Brasília, preços e UTF-8/emojis passaram para modelos padrão e personalizados. A renderização final no aplicativo de cada dispositivo ainda precisa de confirmação. Não houve envio automático de mensagens. |
| PWA | Manifestos geral/empresa, recursos de ícones e Service Worker acessíveis. Testes confirmam exclusão de páginas privadas e APIs do cache offline e identidade do manifesto por empresa, inclusive no painel. Instalação e entrega Push em aparelho físico permanecem pendentes. |
| Backup | Exportação Master inclui negócio, Financeiro e auditoria, com snapshot consistente e limite de 8 MB. Criptografia, integridade e restauração de JSON em tabelas temporárias passaram. Não substitui recuperação completa de Auth, banco e arquivos. |
| Logs operacionais | Consulta agregada de Auth, gateway e Edge Functions nas últimas 24 horas não encontrou respostas HTTP 5xx nos registros com status disponível. Respostas 400/401 incluem recusas esperadas; não foi feita análise forense do conteúdo de mensagens. |
| Dependências e código | Audit final completo sem avisos conhecidos, TypeScript e construção de produção passaram após as atualizações. |

Suítes SQL concluídas com rollback: `verify.sql`, `verify-new-features.sql`, `verify-finance.sql`, `verify-push.sql`, `verify-backup.sql`, `verify-booking-flow.sql`, `verify-plan-details.sql`, `verify-company-access.sql` e `verify-master-company-editor.sql`.

Suítes locais: Financeiro, Push, criptografia de backup, provisionamento, credenciais Master, planos/WhatsApp, três mensagens de atendimento, documentos e prontidão de lançamento. As requisições HTTP de verificação não criam usuários nem enviam e-mails/mensagens.

## Pendências reais para a revenda

1. **Backup e recuperação:** escolher executor e armazenamento externo privado, configurar conexão/chave de forma segura, agendar cópias e testar restauração completa em ambiente separado, incluindo Auth e arquivos. Não há backup automático ativo. Ver [backup-and-recovery.md](backup-and-recovery.md).
2. **Operador e documentos:** informar nome/razão social do responsável comercial, canal de privacidade e decisões de retenção para completar termos/contrato. O número de suporte de acesso já foi informado; não foi inventada identidade jurídica nem política de retenção.
3. **Homologação nos dispositivos usados:** instalar o PWA, ativar o sino, testar uma notificação e conferir emojis nas mensagens reais com um contato controlado. Não é possível conceder a permissão pelo usuário nem comprovar entrega sem um dispositivo inscrito.
4. **Oferta dos planos:** os planos são descritivos; não há bloqueio automático de recursos por plano. Alinhar a oferta comercial ou implementar as restrições antes de vender exclusividade de funcionalidades.

**SMTP:** não é requisito para o fluxo manual de recuperação escolhido. Só será necessário se forem reativadas confirmação/recuperação automáticas por e-mail. Não foi contratado nem configurado um provedor SMTP.

**Avisos do Supabase:** proteção contra senhas vazadas continua desativada; a proteção nativa exige Pro ou superior. Não houve upgrade pago. O Advisor de desempenho apontou apenas índices ainda não utilizados; foram mantidos por suportarem chaves estrangeiras e consultas futuras de um sistema com pouco volume.

**Domínio e cobrança:** domínio próprio é opcional. Licenciamento/pagamentos continuam manuais; o sistema não é um gateway de pagamento. A audiência pública e o domínio atual foram preservados.

## Próximos dados necessários

- Identificação comercial do operador e canal de privacidade.
- Executor/destino privado para backups e acesso seguro à configuração — não enviar senhas ou chaves no chat.
- Um dispositivo do responsável para instalar o PWA e autorizar/testar notificações.
- Decisão sobre recursos iguais para todos os planos ou restrições por assinatura.

Referências oficiais: [produção Supabase](https://supabase.com/docs/guides/deployment/going-into-prod), [backups](https://supabase.com/docs/guides/platform/backups), [senhas](https://supabase.com/docs/guides/auth/password-security), [Next corrigido](https://github.com/advisories/GHSA-2464-fhr4-w9xw), [React Server DOM corrigido](https://github.com/advisories/GHSA-wx67-qw84-cm4g).
