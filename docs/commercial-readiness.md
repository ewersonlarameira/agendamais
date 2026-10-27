# Conferência para lançamento comercial — 27/10/2026

Resultado: base técnica testada, com correção na exportação de dados; liberação comercial completa ainda depende das pendências abaixo. Este relatório não é uma certificação de segurança ou de conformidade jurídica.

## Resultado dos testes

| Área | Resultado e evidência |
|---|---|
| Acesso público | Páginas inicial, demonstração, Master, empresa, painel da empresa, termos e privacidade respondem sem login no ChatGPT. |
| Autorização | Requisições sem sessão não recebem dados Master, workspace, Financeiro, dispositivos ou exportação; bootstrap anônimo e operações internas recusados. |
| Isolamento | Testes transacionais de agenda, Financeiro e Push confirmaram separação de empresas e permissões. Zero tabelas públicas sem RLS. |
| Agendamento | Catálogo sem dados pessoais de clientes, horários, protocolo, recusa de duplicidade e bloqueio de empresa suspensa passaram no teste SQL com rollback. |
| Documentos, planos e WhatsApp | Validação de CPF/CNPJ, exclusão lógica de plano sem perda de licença, persistência de pagamento/modelos, permissões, máscaras, placeholders, fuso e emojis passaram. |
| Financeiro | Valores do servidor, duplicidade, versões concorrentes, validação de pagamento, anulação e auditoria passaram. |
| Push | Opt-in/out, seleção de destinatários, fila, leases, logout, conteúdo e clique do Service Worker passaram nos testes isolados. A entrega em um aparelho real ainda não foi validada. |
| Segurança de senha | O Advisor aponta proteção nativa contra senhas vazadas desativada. O recurso exige Supabase Pro ou superior; não houve contratação ou troca de plano. |
| Exportação de negócio | Corrigida para incluir dados financeiros e auditoria, com acesso exclusivo Master, snapshot consistente e limite de 8 MB. |
| Recuperação parcial | Exportação JSON financeira reconstituída em tabelas temporárias sem perda; criptografia AES-GCM recuperada byte a byte e adulterações recusadas. Não é um teste de recuperação do projeto inteiro. |
| Código | TypeScript e testes de documentos, mensagens, Financeiro, Push e criptografia passaram. |

As suítes `verify.sql`, `verify-new-features.sql`, `verify-finance.sql`, `verify-push.sql` e `verify-backup.sql` foram executadas com sucesso e terminaram em rollback. A suíte de novos recursos usa contas de fixture distintas para Master e administrador, sem retirar permissões de nenhuma conta. Nenhum tenant de fixture permaneceu no banco.

## Pendências para a operação

1. **Dados reais do estabelecimento:** a empresa existente ainda usa e-mail de teste e está sem profissionais, serviços e agendamentos reais. O responsável escolheu enviar os dados para cadastrá-los; ainda não os forneceu. Não foram inventados nomes, preços, contatos ou jornadas.
2. **E-mail de produção:** o responsável informou que ainda não possui SMTP. Definir provedor, remetente e configuração de domínio; depois configurar no Supabase as URLs e os e-mails e testar cadastro, confirmação, recuperação e alteração de senha com contas controladas. Não houve envio de e-mails para terceiros nesta conferência.
3. **Backup automático externo:** ferramentas preparadas, mas conexão PostgreSQL privada, chave de recuperação, executor e destino ainda precisam ser definidos. Não há agendamento de backup ativo. Ver `docs/backup-and-recovery.md`.
4. **Recuperação completa:** executar em projeto isolado após obter a conexão apropriada e definir o destino de teste. O teste parcial de JSON e criptografia não substitui esse ensaio.
5. **Identificação e documentos comerciais:** nome/razão social do responsável pela plataforma, e-mail público de suporte/privacidade e decisões reais de retenção ainda não foram informados. Os textos da aplicação permanecem explicitamente iniciais; foram atualizados para descrever Financeiro e notificações.
6. **Ensaio real em dispositivos:** cadastrar dados reais, instalar o PWA, ativar o sino e usar o teste; depois reservar, reagendar, cancelar e registrar um recebimento com uma conta controlada. Não havia inscrições Push ativas nem mensagens reais entregues na conferência.

Domínio próprio pode ser configurado depois e não impede o uso do endereço público atual. Cobrança de assinatura e registros de pagamentos continuam manuais. WhatsApp abre uma mensagem para revisão e envio pela pessoa; não envia automaticamente.

## Informações solicitadas ao responsável

- Nome ou razão social que responderá pelo Agenda+ e e-mail público de suporte/privacidade.
- Dados reais da empresa: e-mail do administrador, telefone de atendimento, profissionais, serviços, duração, preços e expediente.
- Serviço SMTP a contratar/configurar, remetente desejado e domínio sob controle do responsável.
- Executor/destino privado dos backups e forma segura de disponibilizar as credenciais necessárias. Não enviar senhas ou chaves neste relatório ou no chat.

Referências: [produção Supabase](https://supabase.com/docs/guides/deployment/going-into-prod), [senhas](https://supabase.com/docs/guides/auth/password-security), [backups](https://supabase.com/docs/guides/platform/backups).
