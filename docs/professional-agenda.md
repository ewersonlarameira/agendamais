# Acesso do funcionário à própria agenda

## Criar o acesso

No painel do estabelecimento: **Profissionais → Novo profissional / Editar profissional → Acesso à própria agenda**.

1. Cadastrar o profissional e seus procedimentos normalmente.
2. Marcar **Criar acesso por e-mail e senha ao salvar**.
3. Informar e-mail exclusivo, senha inicial e confirmação. Senhas: pelo menos 10 caracteres e até 72 bytes; botões permitem visualizar os campos.
4. Salvar. A confirmação mostra o e-mail e o link `/<link-do-estabelecimento>/agendaprofissional`, com opção de copiar ambos. Entregar a senha por canal privado.

O cadastro profissional é salvo antes da conta. Se a criação do acesso falhar, o profissional permanece salvo; repetir com o mesmo profissional e e-mail. Uma conta criada em tentativa anterior é reconhecida por metadados definidos pelo servidor e não tem sua senha redefinida. Outros logins, administradores e contas de outras empresas são rejeitados.

## O que o funcionário vê

A página possui somente a agenda e a saída da conta. Exibe nome do cliente, procedimento, data, dia da semana, início/fim e situação do agendamento. Há consulta por dia, semana (a partir da data selecionada) e mês, incluindo registros históricos e cancelados. Atualiza a cada 30 segundos com a tela visível, ao retornar ao app e pelo botão Atualizar.

Somente registros do identificador profissional vinculado ao login são retornados. Alterar o nome não altera o vínculo; nomes iguais não misturam agendas. O servidor ignora identificadores profissionais enviados pelo funcionário e resolve o vínculo pela conta autenticada. Não retorna preços, financeiro, dados cadastrais completos de clientes, contatos, observações internas, modelos de WhatsApp ou cadastros de colegas. O período máximo por consulta é de 93 dias.

Se um profissional entrar no endereço administrativo antigo, a interface o direciona à agenda profissional. O servidor também bloqueia o antigo workspace, alterações de status, pagamento, reagendamento e demais operações administrativas para o papel profissional.

## Revogar

Desativar o profissional ou o acesso em **Configurações → Acessos** bloqueia as próximas consultas, mesmo com uma sessão já aberta. Suspensão da empresa ou licença vencida também bloqueiam a agenda. Edição de login/senha continua pelo Master ou suporte; a página profissional oferece o link de recuperação pelo WhatsApp existente.

Nenhuma conta real é criada automaticamente pela implantação desta funcionalidade. Profissionais existentes podem receber o acesso ao editar seus cadastros. Contas e vínculos profissionais estão incluídos no backup completo existente, sem nova tabela de negócio.

## Verificações

- `node scripts/verify-professional-agenda.mjs`: URL, períodos, separação de senhas dos dados de negócio, validação, criação via Auth no servidor, repetição sem redefinir credenciais e falhas parciais.
- `database/verify-professional-agenda.sql`: transação com rollback; dois profissionais, duas empresas, isolamento, tentativa de trocar identificador, ausência de dados privados, bloqueio de endpoints legados e escritas, revogação, administrador preservado, criação/repetição do vínculo e bloqueio de reaproveitamento de contas privilegiadas. Não deixa usuários, empresas ou atendimentos de teste.

O envio de credenciais ao funcionário é responsabilidade do administrador. A implantação não envia e-mail nem WhatsApp.
