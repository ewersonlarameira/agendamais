# Bloqueio após cinco tentativas incorretas

O login de Master, administrador da empresa e profissional conta falhas por e-mail normalizado, compartilhadas entre todos os domínios e dispositivos. Na quinta resposta `invalid_credentials` do Supabase Auth, o acesso fica bloqueado por tempo indeterminado. E-mails inexistentes têm o mesmo comportamento para não revelar cadastros. Login correto antes do limite zera a contagem; erros de conexão, indisponibilidade ou limite do serviço não contam como senha incorreta.

A contagem fica em tabela operacional privada, não em armazenamento do navegador. Atualizar a página ou trocar de domínio não desbloqueia. Tentativas simultâneas por e-mail são serializadas com ticket e prazo de 90 segundos; uma requisição interrompida pode exigir aguardar esse prazo antes de tentar novamente. Senhas e tokens de autenticação não são enviados às funções de contagem nem aos registros de auditoria.

Ao bloquear, a tela exibe **Solicitar desbloqueio pelo WhatsApp**, para o suporte `(24) 99907-4698`. A mensagem contém pedido de verificação de identidade/desbloqueio, e-mail e endereço do painel, sem senha, token ou parâmetros sensíveis. Ela é preparada para o usuário revisar e enviar; não é enviada automaticamente. O link de esquecimento de senha permanece disponível.

O suporte confere a identidade pelos contatos previamente cadastrados e, com uma conta Master não bloqueada, acessa **Master → Acessos bloqueados → Desbloquear acesso**. A ação pede confirmação, zera as tentativas e gera auditoria, sem alterar a senha. Depois, o usuário atualiza a tela de login e entra com suas credenciais. Uma mensagem de WhatsApp, isoladamente, não autoriza o desbloqueio.

Se o único Master estiver bloqueado, o operador autorizado do projeto deve desbloquear o e-mail pela administração do Supabase (tabela privada `app_private.login_guard`, zerando `failures`, `blocked_at`, `attempt_id` e `attempt_until` para o e-mail verificado) e registrar o atendimento. Não criar um endpoint público de desbloqueio, usar somente o e-mail recebido como prova de identidade, nem compartilhar a chave interna de gateway.

O bloqueio é aplicado no login da plataforma e também nas autorizações de dados (`master`, `role`, gateway, recuperação e destinatários push), impedindo que um token anterior contorne o bloqueio para ler dados da aplicação. Não é uma alteração de senha nem um banimento nativo do Supabase Auth. O estado operacional de tentativas não faz parte do backup de dados de negócio.

## Verificação

- `database/verify-login-lockout.sql`: em transação com rollback, testa limiar de cinco, serialização, bloqueio de sessão e permissões existentes, desbloqueio por outro Master, redefinição em sucesso, falha de conexão sem contagem e rejeição de segredo incorreto.
- `scripts/verify-login-lockout.mjs`: testa a coordenação de login, recusa antes de chamar Auth quando bloqueado, classificação de erros e conteúdo/codificação do WhatsApp.
- Testes anteriores de saída e de entrada explícita continuam passando. Nenhuma conta real é bloqueada e nenhuma mensagem é enviada por essas verificações.
