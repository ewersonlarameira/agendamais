# Atendimento de acesso e entrada de empresas

## Recuperação manual de senha

Canal definido pelo operador: WhatsApp **(24) 99907-4698**, no formato internacional `5524999074698`.

1. O usuário toca em **Esqueci minha senha** abaixo do formulário de login. A conversa abre com a solicitação, e-mail informado e endereço do painel. Nenhuma senha, token de sessão ou parâmetro de recuperação é incluído.
2. O suporte confirma o vínculo com a empresa e a autorização do solicitante pelos contatos previamente cadastrados. A mensagem recebida, isoladamente, não autoriza a troca.
3. No Master, abrir **Empresas → Editar empresa → Acessos → Login e senha** e definir a nova senha. Não consultar, pedir ou registrar a senha anterior.
4. Orientar o usuário sobre as novas credenciais e sobre a opção de alterá-las em **Configurações → Acessos**. Os registros de auditoria do sistema não contêm a senha.
5. Contas compartilhadas com outras empresas e contas Master são protegidas contra alteração nesse editor. O proprietário deve tratar esses casos pelo procedimento administrativo do Supabase, sem alterar credenciais de terceiros pelo cadastro de outra empresa.

O botão prepara a conversa; não envia mensagens nem redefine credenciais automaticamente. A recuperação pelo WhatsApp não depende de SMTP. As APIs legadas de confirmação por e-mail só devem ser usadas após configurar um remetente apropriado. O botão público de autoativação por e-mail foi removido do login; a senha inicial é entregue pelo Master/suporte.

## Nova empresa

- Conferir nome, responsável, documento, telefone, e-mail comercial, e-mail de login e link desejado.
- Cadastrar a empresa com o plano, datas de licença, valor e situação do pagamento corretos. A senha inicial é definida no cadastro.
- Entrar como administrador dessa empresa; preencher endereço, contatos públicos, logo/cores, expediente, profissionais e serviços reais.
- Autorizar novos usuários pelo e-mail e, quando necessário, definir a senha inicial pelo Master. Definir vínculo profissional e permissões antes do primeiro acesso.
- Fazer uma reserva controlada, conferir o preço e o horário, confirmar, reagendar, cancelar e verificar os registros. Combinar previamente o teste com a empresa para não confundir clientes reais.
- Instalar o PWA em aparelho compatível, permitir notificações pelo sino e executar o teste do próprio dispositivo. A permissão deve ser concedida pelo usuário.
- Revisar uma mensagem de WhatsApp com emojis no dispositivo efetivamente usado pelo atendimento. O teste de codificação não comprova a renderização de todas as versões do WhatsApp.

## Condições antes da revenda regular

- Operador identificado nos termos/contrato e canal de privacidade definido.
- Backup externo periódico e recuperação completa testada em ambiente separado, incluindo Auth e arquivos.
- Política comercial alinhada ao produto: atualmente os planos não restringem automaticamente os recursos. Se a oferta prometer exclusividade por plano, implementar a regra antes da contratação.
- Processo de suporte, cobrança manual, suspensão e reativação acordados com o cliente.

O site público atual dispensa login no ChatGPT. Domínio próprio é opcional; a segurança do painel usa o login do próprio Agenda+.
