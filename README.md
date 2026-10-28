# Agenda+ V1

Aplicação SaaS multiempresa para barbearias. React 19, TypeScript e Vinext em Cloudflare Workers pelo Sites; Supabase PostgreSQL, Auth e Storage. Interface em português do Brasil; fuso America/Sao_Paulo.

## Rotas

- `/`: demonstração administrativa em memória, identificada como exemplo.
- `/demo`: simulação do agendamento público, sem gravar dados.
- `/master`: autenticação, configuração inicial e painel Master.
- `/:slug`: catálogo e agendamento público real.
- `/:slug/admin`: administração do estabelecimento.
- `/privacidade` e `/termos`: textos iniciais, com identificação e retenção a completar antes da operação comercial.

## Dados e autorização

Projeto Supabase exclusivo: `iktpbxfaygcvjkrajycy`, região São Paulo. Nenhum dado da Lumina’s ou do AgendaMais foi utilizado ou alterado.

O banco aplica RLS em todas as tabelas públicas. Os clientes não têm acesso direto às tabelas; o gateway RPC chama uma função privilegiada no esquema não exposto `app_private`, com autorização explícita em cada operação. Não usa `user_metadata` para permissões. Vínculos administrativos dependem de e-mail confirmado em `auth.users`. O Master possui associação explícita em `platform_admins`. Profissionais recebem apenas sua agenda e os clientes relacionados.

O primeiro Master é configurado com o e-mail recebido pelo cabeçalho confiável do Sites no ambiente inicialmente privado. Uma chave secreta de gateway, armazenada no runtime e em tabela privada, protege o bootstrap e a reserva pública. O bootstrap fecha após o primeiro Master. Não tornar o Site público antes de concluir essa configuração.

O campo `tenant_id` e chaves estrangeiras compostas impedem referências de agendamentos a cadastros de outras empresas. Uma exclusion constraint sobre intervalos semiabertos impede sobreposição por profissional inclusive com concorrência. O servidor calcula preço e duração e consulta jornada, intervalos, datas sem expediente, prazo máximo e antecedência. Os status Cancelado e Não compareceu liberam a faixa de horário. Bloqueios usam a mesma tabela e constraint.

E-mails autorizados são cadastrados pelo administrador; cada usuário cria a própria senha e confirma seu e-mail. Cookies de sessão são HttpOnly, SameSite=Lax e Secure em HTTPS. O navegador e o runtime do Site não usam chave de serviço Supabase; as Edge Functions utilizam a credencial protegida do próprio serviço. A chave publishable no código é pública por definição. Login e recuperação usam a API Supabase Auth; os limites nativos desse serviço continuam aplicáveis. Upload usa a sessão do usuário, políticas por pasta `tenant_id`, validação de assinatura PNG/JPEG e limite de 2 MB. O bucket contém somente branding público.

## Configuração de Auth antes da operação

No Supabase Authentication > URL Configuration, definir o Site URL com o endereço publicado e permitir `https://agenda-plus.ewersonlarameira.chatgpt.site/**`. O conector utilizado não possui operação para alterar essa configuração. Depois de vincular domínio próprio, adicionar o novo endereço também. Configurar SMTP de produção: o serviço de e-mail padrão do Supabase tem limitações de destinatários e envio e não é adequado para comercialização.

No Site, abrir `/master` e escolher “Configuração inicial do proprietário”. Definir a senha e confirmar o e-mail. Depois entrar, definir os valores dos planos e cadastrar as empresas. Nenhuma senha padrão é criada. As empresas iniciam sem clientes, profissionais e serviços fictícios.

## Banco e verificação

`database/schema.sql` documenta a estrutura para um banco novo. A chave de gateway não está nesse arquivo e deve ser configurada separadamente. As alterações reais possuem histórico de migrations no Supabase.

`database/verify.sql` é um teste transacional com rollback. Ele cria fixtures temporárias, verifica catálogo sem dados pessoais, geração de horários, reserva com protocolo, recusa de duplicidade, isolamento entre empresas e bloqueio de empresa suspensa. Nenhuma fixture permanece gravada.

Validações realizadas: TypeScript, build de produção, testes transacionais e Advisors de segurança. Informações de índices ainda não utilizados são esperadas em banco recém-criado.

## PWA

Manifesto por estabelecimento com nome, início e logo quando disponível; ícones Agenda+ 192 e 512 como fallback. Service Worker versão 3 cacheia somente ícones estáticos. Sessões, clientes, catálogos, disponibilidade e reservas não são armazenados em cache. Não se confirmam reservas offline. No iOS, a instalação depende de “Adicionar à Tela de Início”.

## Backup e recuperação

O Master oferece exportação JSON consistente dos dados de negócio, incluindo Financeiro, modelos de WhatsApp e auditoria, com limite de 8 MB (não inclui contas/senhas Auth, arquivos binários, segredos, dispositivos Push ou estrutura do banco). Para recuperação completa, usar backup PostgreSQL e Storage do Supabase e manter o código versionado. Configurar periodicidade, retenção e armazenamento externo conforme o plano contratado; esta versão não cria uma rotina automática de backup. Testar restauração em projeto isolado antes de depender do procedimento. Nunca importar um JSON diretamente no navegador como restauração de produção sem validar vínculos, IDs e autorização.

## Limites de lançamento

- Domínio `agendamos.com.br` ainda é uma referência, sem DNS configurado nesta entrega.
- O Site atual está público e dispensa login ChatGPT; os painéis exigem login do Agenda+. Novas instalações podem começar privadas até preparar o Master.
- Pagamentos são registrados manualmente; não há cobrança recorrente ou envio automático de WhatsApp.
- Termos e privacidade precisam da identificação do operador, canal de contato e prazos de retenção.
- Backups automáticos, SMTP comercial e monitoração externa precisam de configuração operacional.
- A agenda oferece listagens por dia, semana e mês; não há arrastar/soltar ou grade mensal.
- Não há busca pública de nome por telefone: reutilização acontece internamente no banco, sem revelar o cadastro.
- Recuperação de senha depende da configuração de URL e de entrega de e-mail do Supabase.

## Desenvolvimento

`npm run dev`, `npm run build`, `node node_modules/typescript/bin/tsc --noEmit`. Publicação utiliza os helpers oficiais Sites e `.openai/hosting.json`. A variável secreta `AGENDA_GATEWAY_SECRET` existe apenas no runtime hospedado e na tabela privada; não incluir em arquivos de código, arquivos locais ou logs.

O primeiro acesso detecta a ausência do Master e abre automaticamente a configuração inicial apenas para o e-mail do proprietário vinculado no runtime por `AGENDA_OWNER_EMAIL`. A senha é confirmada no formulário, e a resposta de confirmação de e-mail permanece visível. Não criar a conta do usuário por scripts nem definir senha padrão.

## Atualização: celular, planos, documentos e WhatsApp

Aplique `database/schema.sql` e depois `database/mobile-messages-additions.sql` para reproduzir o banco em um projeto novo. A atualização hospedada é aditiva: não substitui o gateway original. A exclusão de planos é lógica (`deleted_at` e `active=false`), com auditoria; licenças existentes permanecem vinculadas. O servidor omite planos excluídos das novas contratações.

O formulário Master permite CPF ou CNPJ e valida os dígitos, inclusive no formato alfanumérico do CNPJ, conforme o [manual técnico da Receita Federal](https://www.gov.br/receitafederal/pt-br/centrais-de-conteudo/publicacoes/documentos-tecnicos/cnpj/manual-dv-cnpj.pdf). O documento não aparece no catálogo público. Cadastros antigos podem completar o documento ao gerenciar a empresa.

Cada agendamento armazena `payment_method` (A combinar, Pix, Dinheiro, Cartão de débito ou Cartão de crédito). A seleção pública é uma indicação: não realiza cobrança. Os modelos de confirmação, reagendamento e cancelamento ficam no menu WhatsApp e no atalho Mensagens de cada cliente. As mensagens usam os dados salvos da agenda, incluindo pagamento, e aceitam personalização pelo administrador. Modelos privados ficam em tabela com RLS e acesso por RPC autorizado. O botão abre uma conversa com texto pronto; a pessoa revisa e envia no WhatsApp. Nenhuma mensagem é enviada automaticamente pela plataforma.

Em telas pequenas, as tabelas viram cartões, controles têm altura mínima de 44–48 px e os campos usam fonte 16 px. As páginas foram conferidas em quadros de 360 e 390 px, com medição de ausência de rolagem horizontal; a reserva pública e o formulário CPF/CNPJ usam o mesmo estilo móvel. As rotas temporárias de QA não fazem parte da publicação.

Verificações específicas: `node --experimental-strip-types scripts/verify-new-features.mjs` e `database/verify-new-features.sql` (fixtures transacionais e rollback). Cobrem documentos, exclusão de plano vinculado sem perda de licença, pagamento, templates, isolamento de empresas e permissões. O hash da função central do gateway permaneceu igual após a atualização.

## Identidade visual neon

As cinco paletas mantêm seus identificadores anteriores e passam a usar fundos escuros com acentos neon: Black Gold (dourado), Ocean Blue (ciano), Emerald (verde), Urban Red (vermelho rosado) e Classic Barber (âmbar). O mesmo tema atende painel e página pública. `lib/theme.ts` centraliza as cores e o contraste dos botões; `app/neon.css` reúne os estilos. A seção Aparência inclui uma prévia antes de salvar. As cores personalizadas continuam disponíveis e o manifesto PWA acompanha o fundo da paleta do estabelecimento. Brilhos são estáticos, sem animações pulsantes, preservando os tamanhos de texto e os controles móveis já existentes.


## Financeiro e navegação

Ordem do painel do estabelecimento: Agenda, Clientes, Profissionais, Procedimentos, WhatsApp, Financeiro e Configurações. No celular, o menu inferior permite rolagem horizontal com controles de tamanho legível. O símbolo A+ foi removido; cabeçalhos e ícones utilizam a marca agenda+ por extenso.

Para reproduzir o banco, aplique também `database/finance-additions.sql` depois das duas estruturas anteriores. A migration adiciona somente a tabela financeira e sua RPC autorizada; não modifica os gateways de agendamento ou autenticação. RLS bloqueia acesso direto; a função privada exige sessão, administrador da empresa (ou Master), tenant e licença ativa. Profissionais e visitantes não recebem acesso ao financeiro.

O Financeiro registra receitas e despesas, categorias, vencimentos, pagamentos, forma de pagamento e observações. Possui filtros de período/tipo/situação/busca, indicadores de caixa, contas a receber e a pagar, fluxo diário e receitas por forma de pagamento. Pagos usam a data efetiva de pagamento; pendentes usam vencimento. O resultado é a movimentação registrada no período, não um saldo bancário conciliado. A previsão da agenda fica separada dos serviços concluídos a receber. O período consultado é limitado a 366 dias; o histórico permanece armazenado e pode ser consultado por outros intervalos.

Atendimentos sem lançamento aparecem na aba Atendimentos. O servidor usa o preço salvo no agendamento e uma restrição única impede dois lançamentos ativos para a mesma reserva. Não há baixa automática ao concluir o serviço. Recebimentos antecipados são possíveis; cancelamentos exigem revisão do lançamento e eventual reembolso manual como despesa. Valores são integrais por atendimento nesta versão, sem parcelamento ou baixa parcial. Taxas, comissões e despesas devem ser lançadas manualmente. O registro não realiza cobrança ou transferência bancária.

Edições e baixas verificam a versão do lançamento para evitar sobreposição de alterações simultâneas. Anulações preservam a linha original e a auditoria, removendo seu efeito dos totais; não estornam valores bancários. O CSV exporta os lançamentos do período e filtros atuais, com proteção contra fórmulas de planilha. A exportação JSON do Master inclui o livro financeiro e a auditoria na versão atual. CSV continua disponível no Financeiro. Recuperação completa também exige cópia PostgreSQL, Auth e dos binários do Storage.

Verificações: `node scripts/verify-finance.mjs` cobre cálculos em centavos, datas de caixa, deduplicação de recebíveis, anulação, fuso e CSV. `database/verify-finance.sql` usa fixtures transacionais com rollback e verifica persistência, preço do servidor, duplicidade, isolamento, permissões de profissional, empresa suspensa, concorrência de versões, validação e auditoria. Dados demonstrativos ficam em memória e não são gravados na produção.


## Notificações Push no PWA

O sino do cabeçalho está disponível para os usuários do estabelecimento. O administrador também encontra a opção em Configurações → Notificações. A ativação é individual por aparelho e empresa e exige um clique para solicitar a permissão do sistema. No iPhone/iPad é necessário instalar na Tela de Início e usar iOS/iPadOS 16.4 ou posterior. A demonstração exibe uma prévia e não solicita permissão nem cria inscrições reais.

Cada novo agendamento, público ou administrativo, gera avisos para os administradores inscritos e para o profissional responsável inscrito. Bloqueios de horário e simples alterações/reagendamentos não geram avisos de novo agendamento. A notificação contém nome do cliente, procedimento, data DD/MM/AAAA, dia da semana e hora de Brasília; não inclui telefone, documento ou observações. O usuário é informado de que o conteúdo pode aparecer na tela bloqueada. O toque abre a agenda da empresa na data correspondente. O envio é Web Push criptografado (`aes128gcm`) e funciona mesmo com o PWA fechado, conforme suporte/conexão/permissões do sistema. Não há garantia de exibição imediata em modo Foco, restrições de bateria ou ausência de rede.

`database/push-additions.sql` deve ser aplicado após as estruturas anteriores. Adiciona inscrições isoladas por empresa/usuário, uma fila privada e um trigger AFTER INSERT na tabela de agendamentos. A criação da reserva não depende do sucesso do provedor de Push. O dispatcher usa `pg_net` e a Edge Function `agenda-push`, com `pg_cron` para retentativas a cada minuto somente quando há itens disponíveis. Há lease por entrega, até 6 tentativas, expiração após 24 horas e retenção operacional de 7 dias. Não há notificações retroativas. Destinatários são revalidados antes de retirar os itens da fila; empresas inativas, usuários sem vínculo e outros profissionais não recebem os avisos. Respostas 404/410 desativam a inscrição expirada; falhas temporárias geram nova tentativa. O sistema de notificações usa entrega pelo menos uma vez e a tag por agendamento evita duplicação visual em uma retentativa.

A função `agenda-push` usa `npm:web-push@3.6.7`; seu código está em `supabase/functions/agenda-push`. As tabelas públicas seguem RLS sem acesso direto de anon/authenticated. A RPC de dispositivos permite somente os próprios registros e destinos Push conhecidos (Google, Apple, Mozilla e Microsoft). A RPC do dispatcher é exclusiva de `service_role`. A função Edge possui autenticação própria com assinatura HMAC-SHA256, nonce aleatório e validade de 60 segundos, derivada de segredo de 256 bits que nunca é colocado nos cabeçalhos da fila de transporte: `verify_jwt=false` porque a chamada é de sistema/pg_net, não uma sessão de usuário. Requisições sem assinatura válida ou expiradas são recusadas antes de consultar a fila. Os cabeçalhos do pg_net contêm somente assinatura transitória, timestamp e nonce; as permissões internas da extensão são gerenciadas pelo Supabase. A credencial Supabase de serviço vem somente do ambiente protegido da Edge Function e nunca passa para o navegador ou para o runtime do Site.

As chaves VAPID e os parâmetros do dispatcher são provisionados separadamente em `app_private.secrets`: `push_vapid_public`, `push_vapid_private`, `push_dispatch`, `push_origin` e `push_function_url`. Os valores privados não constam no repositório. Para outra instalação, gerar um par P-256/VAPID e um segredo aleatório de 32 bytes; definir a origem HTTPS do PWA e o endereço da Edge Function. Não trocar o par VAPID sem planejar nova inscrição dos dispositivos. Publicar a função no projeto Supabase correspondente e configurar explicitamente o caminho de `deno.json` ao atualizar pelo conector.

Desativar interrompe os avisos da empresa naquele aparelho. Encerrar todas as sessões desativa as inscrições do usuário em todos os dispositivos antes do logout; o mesmo navegador pode reativá-las ao entrar novamente. Um botão de teste envia somente para a própria inscrição e tem limite de um teste por minuto. A exportação JSON de negócio do Master não inclui inscrições/filas; use backup PostgreSQL para recuperação operacional completa.

Verificação: `node scripts/verify-push.mjs` testa conteúdo completo, fuso, dia da semana, destinos permitidos, exibição pelo Service Worker, tags e clique seguro. `database/verify-push.sql` testa opt-in/out, isolamento de empresas/profissionais, ausência de segredos na resposta, trigger somente de novos agendamentos, leases concorrentes, logout e privilégios usando fixtures com rollback. A Edge Function publicada respondeu 401 sem credencial/com credencial inválida e 200 com a autenticação de serviço; a geração criptográfica foi validada dentro do próprio runtime sem enviar mensagens. A entrega em um aparelho real depende da ativação e do botão de teste nesse aparelho; não foi solicitada permissão no navegador de QA.

## Conferência comercial e correção do backup Master

O acesso público sem login ChatGPT foi ativado e verificado. Painéis e APIs de dados continuam dependentes de autenticação do Agenda+.

Aplique também `database/backup-additions.sql` em instalações novas. A exportação Master passa a usar `agenda_backup_export`, com fotografia consistente e limite de 8 MB, incluindo Financeiro, auditoria e modelos de WhatsApp. Substitui a exportação JSON anterior, que não incluía todos esses dados. Os avisos anteriores sobre exclusão do Financeiro descrevem a versão antiga. Auth, binários do Storage, segredos e inscrições/filas Push continuam excluídos da cópia de negócio.

## Planos: renovação e descrição

Aplique `database/plan-details-additions.sql` após as atualizações anteriores. Em Master → Planos, novos planos permitem renovação mensal (1 mês) ou anual (12 meses), valor total por período e descrição de até 4.000 caracteres. As quebras de linha são preservadas nos cartões. Planos antigos com outro período podem mantê-lo durante a edição. O cadastro de empresa usa a duração do plano para sugerir o vencimento. A cobrança continua manual; editar um plano não altera valores nem vencimentos das licenças existentes. Os campos também integram a exportação de dados de negócio.

`database/verify-plan-details.sql` verifica persistência, edição anual, descrição com emojis e quebras de linha, leitura no Master, compatibilidade com planos antigos, preservação de licenças e autorização. Os dados de teste são revertidos com rollback.

## Empresas: acesso inicial definido pelo Master

Aplique `database/company-access-additions.sql` e publique `supabase/functions/agenda-company-access` antes da atualização da interface. Master → Empresas → Nova empresa exige e-mail, senha inicial e confirmação da senha. O Master recebe uma confirmação com o link do painel, e-mail e senha oculta, além de um botão para copiar os dados. A senha fica apenas no formulário e nessa confirmação em memória; ao fechar, não pode ser consultada novamente. Não existe opção de login com Google.

A conta é criada pela API administrativa do Supabase Auth, com e-mail confirmado pelo provisionamento do Master, para acesso imediato. A Edge Function valida a sessão com Auth e a permissão Master no banco; a chave de serviço permanece exclusivamente no ambiente Edge. O fluxo não troca a sessão do Master pela do cliente. Senhas seguem diretamente para Auth e nunca para RPCs de negócio, auditoria ou backups JSON. As demais ativações de profissionais autorizados continuam disponíveis por e-mail e senha.

O e-mail de uma conta existente não pode ter sua senha sobrescrita ao criar outra empresa. Uma interrupção após criar Auth pode deixar um acesso pendente, ainda sem permissão de empresa; o mesmo Master pode retomar usando o mesmo e-mail e link. Metadados administrativos permitem concluir sem duplicar a empresa nem recriar a conta. Nesse caso, a confirmação informa que vale a senha da primeira tentativa, sem exibir a senha digitada na repetição. Não são enviados e-mails nem mensagens automaticamente.

`scripts/verify-company-access.mjs` verifica a orquestração com serviços simulados. `database/verify-company-access.sql` testa permissões, isolamento, proteção de contas existentes e retomada, com rollback dos dados de teste. A criação e o primeiro login de uma conta Auth real não foram testados nesta atualização: a revisão automática bloqueou o teste persistente sem limpeza no ambiente de produção.

## Compartilhar planos pelo WhatsApp

No Master → Planos, use “Compartilhar planos pelo WhatsApp” para montar uma proposta com vários planos, ou “Enviar este plano” no cartão para compartilhar uma opção. Somente planos ativos e não excluídos entram na proposta. Informe nome opcional e telefone com DDD, ou utilize o contato de uma empresa cadastrada. A prévia reúne os nomes, preços por período, renovação e descrições atuais; não inclui credenciais, dados financeiros da empresa nem auditoria.

O botão abre o WhatsApp com a mensagem pronta. O Master revisa o destinatário e confirma o envio no WhatsApp; não há disparo automático nem registro de contratação por esse botão. Também é possível copiar a mensagem. A escolha e a contratação são concluídas na conversa com o cliente. Textos acima de 10.000 caracteres exigem selecionar menos planos ou copiar a mensagem.

No computador, os planos abrem diretamente em `web.whatsapp.com/send`, evitando a passagem do texto pelo redirecionamento para o aplicativo nativo. Celulares e iPads mantêm a abertura pelo aplicativo. A codificação da mensagem preserva o texto Unicode completo, incluindo emojis compostos. Se uma versão do WhatsApp ainda substituir caracteres, a seção “Emojis diferentes ao abrir o WhatsApp?” permite copiar a mensagem e abrir uma conversa sem texto no link para colar o conteúdo original. `scripts/verify-plan-sharing.mjs` verifica a igualdade dos bytes UTF-8, destinos por dispositivo e o caminho alternativo; não verifica a renderização dentro do WhatsApp.

## Master: edição completa da empresa

Aplique `database/master-company-editor.sql` e publique a função `supabase/functions/agenda-master-company`. Em Master → Empresas → Editar empresa, o editor oferece:

- Dados: nome, responsável, e-mail comercial, telefone, CPF/CNPJ e link exclusivo. Alterar o link pede confirmação, pois o endereço anterior deixa de funcionar.
- Licença: plano, início, vencimento, valor, pagamento e suspensão/reativação. Planos excluídos já contratados podem ser mantidos. O editor verifica a revisão dos dados para impedir que uma tela antiga sobrescreva alterações recentes.
- Configurações: dados públicos, razão social, endereço, redes sociais, logo, paletas e funcionamento, utilizando os mesmos validadores do painel da empresa.
- Acessos: autorizar usuários, mudar permissões e vínculo profissional, ativar/desativar, criar senha inicial e alterar e-mail de login ou senha. A desativação vale somente para a empresa selecionada e desativa os avisos desse usuário nessa empresa.

O e-mail comercial não altera o login. A edição de credenciais usa a API administrativa do Auth na Edge, com sessão e permissão Master verificadas; senhas não entram no PostgreSQL de negócio, auditoria ou respostas. Contas Master e contas vinculadas a outras empresas não podem ter suas credenciais globais alteradas nesse editor. Para essas contas, as permissões específicas da empresa continuam editáveis. Não há consulta de senha atual, apenas definição de nova senha. A atualização de credenciais também desativa as inscrições Push do usuário na empresa para reautorização. Não promete invalidação imediata de JWTs já emitidos; a desativação da permissão é a ação para bloquear o acesso à empresa.

Uma falha de rede após alterar Auth pode exigir reabrir o editor e repetir o mesmo e-mail para sincronizar o vínculo. Contas antigas autorizadas somente por e-mail são vinculadas ao identificador do Auth antes de uma troca de e-mail. Contas novas recebem metadados administrativos para retomar o vínculo sem tomar uma conta alheia.

`database/verify-master-company-editor.sql` verifica os fluxos no banco com rollback. `scripts/verify-master-company-credentials.mjs` verifica a orquestração de Auth com serviços simulados. As abas Dados, Licença e Acessos foram inspecionadas no navegador usando uma página local temporária com dados simulados, removida antes da publicação. Nenhuma credencial real de cliente foi alterada nos testes.

`database/verify-backup.sql` testa autorização, cobertura e reconstituição financeira em tabelas temporárias com rollback. `node scripts/verify-backup-crypto.mjs` testa a ferramenta de criptografia e sua integridade. `node scripts/verify-public-access.mjs` verifica o acesso público, bloqueios de APIs e ausência de dados privados no catálogo, sem criar contas nem enviar e-mails.

O roteiro de operação, incluindo o que ainda não foi ativado, está em `docs/backup-and-recovery.md`. O resultado da conferência e as pendências de lançamento estão em `docs/commercial-readiness.md`. Não há backup automático externo nem recuperação de desastre completa homologada nesta entrega.
