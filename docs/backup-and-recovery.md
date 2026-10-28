# Backup e recuperação do Agenda+

## Master → Backups

A exportação manual cria um arquivo `.agendabackup`, criptografado com AES-256-GCM e senha de pelo menos 12 caracteres (PBKDF2-SHA256, 310.000 iterações). Guardar a senha separada do arquivo. Sem ela não é possível recuperar a cópia.

Inclui todas as empresas, clientes, agendamentos de todos os períodos e status, bloqueios, profissionais, procedimentos, planos, licenças, acessos, configurações, modelos de WhatsApp, financeiro e auditoria. Inclui contas de e-mail/senha com hashes de senha protegidos pela criptografia, identidades de login e imagens PNG/JPEG do bucket branding. Não exporta tokens de recuperação nem sessões de login.

A exportação é consistente no banco. Mudanças nos arquivos durante a cópia interrompem a exportação. Até 8 MB de dados de banco, imagens de até 2 MB cada e 12 MB no pacote antes da criptografia; exceder o limite recusa a cópia inteira, sem truncar histórico. Novas tabelas públicas ou provedores de login/MFA não suportados também interrompem a exportação para evitar uma cópia incompleta.

## Restaurar pelo painel

1. Selecionar o arquivo completo e informar sua senha.
2. Clicar em **Validar e visualizar restauração**. A validação testa inserções e restrições do banco em subtransação revertida. A prévia mostra dados existentes, diferentes e ausentes, e vale 15 minutos.
3. Conferir a prévia, digitar **RESTAURAR** e confirmar.

A recuperação é aditiva: insere os identificadores ausentes, sem apagar nem substituir registros atuais. Preserva clientes, senhas atuais, alterações posteriores e novos agendamentos. Não reverte alterações de registros existentes. Conflitos de identificador entre empresas, e-mail, telefone, protocolo, horário ou vínculos interrompem a transação inteira. Não há remapeamento silencioso de identificadores. Cópias de outro projeto não são aceitas.

Arquivos são criados somente se ausentes e nunca substituídos. Como Storage e PostgreSQL não compartilham transação, falha posterior pode deixar arquivos sem vínculo; repetir a operação recupera o restante. A recuperação de agendamentos não dispara notificações antigas. Cada confirmação concluída é registrada na auditoria.

Somente o Master autenticado usa o recurso. A função de banco com dados de Auth só aceita o serviço interno, após validação independente da sessão e do papel Master. O arquivo e a senha nunca são gravados em logs nem no repositório.

Não inclui sessões, inscrições e filas de notificações, código, DNS/domínio ou segredos de infraestrutura. O dispositivo continua cadastrado se já existir; em uma infraestrutura nova deve ser ativado novamente. Código e migrações ficam versionados separadamente. Este recurso recupera dados da aplicação no projeto existente; reconstrução total da infraestrutura exige o procedimento operacional abaixo.

## Validação realizada

- `node scripts/verify-complete-backup.mjs`: autorização Master, criptografia com contas/arquivos/histórico sintéticos, senha incorreta, adulteração, prévia sem upload, confirmação, arquivos sem sobrescrita e rejeição de outro projeto.
- `database/verify-complete-backup.sql`: testes no banco em transação terminada em rollback. Recuperação de conta e identidade, hash de senha, cliente com Unicode, profissional/procedimento e seis status de agendamento; prévia sem gravação, repetição sem duplicidade, alteração posterior preservada, conflito rejeitado e ausência de novas entregas push. Não exclui dados reais nem mantém fixtures.

Backup externo automático e ensaio de desastre em outro projeto permanecem pendentes de destino e credenciais privados.

# Backup e recuperação do Agenda+

Estado: ferramentas e testes parciais preparados. Backup automático externo e restauração completa ainda não configurados nem homologados.

## Cópia de dados de negócio pelo Master

O botão Backups exporta uma fotografia consistente das tabelas de negócio, incluindo Financeiro, lançamentos anulados, auditoria, modelos de WhatsApp, planos, licenças, vínculos e cadastros. A função é exclusiva do Master e limita a exportação pelo navegador a 8 MB. O arquivo é privado e contém dados pessoais.

Essa exportação não contém contas/senhas do Supabase Auth, arquivos binários do Storage, segredos nem inscrições/filas Push. Portanto não substitui um plano de recuperação do projeto. Não existe importação pública ou restauração diretamente pelo navegador.

`database/verify-backup.sql` confirma que os valores financeiros, datas, identificadores, textos e registros anulados sobrevivem à serialização JSON e à reconstituição em tabelas temporárias. O teste é transacional e termina em rollback. Isso não equivale a restaurar uma instância Supabase completa.

## Cópia PostgreSQL criptografada

Requisitos no executor privado da rotina: Node 22 ou posterior, ferramentas PostgreSQL 18, acesso de leitura suficiente ao banco e um diretório privado fora do repositório. O banco consultado usa PostgreSQL 17.11; o cliente precisa ser compatível com essa versão.

Configurar somente no ambiente de segredos do executor:

- `BACKUP_DATABASE_URL`: conexão PostgreSQL direta ou pooler em modo de sessão, obtida no painel Supabase. Não usar o pooler em modo de transação para esse procedimento.
- `BACKUP_KEY_BASE64`: 32 bytes criptograficamente aleatórios em Base64. Gerar e guardar em um gerenciador de segredos; não publicar em chats, commits ou no mesmo local da cópia de segurança.
- `BACKUP_CA_FILE`: opcional, caminho do certificado CA obtido oficialmente. Na ausência desse campo, utiliza o repositório de certificados do sistema. TLS usa `verify-full`, sem desabilitar validação.

Com esses valores já configurados de forma privada:

```sh
node scripts/ops/backup-database.mjs create /diretorio-privado/agenda
node scripts/ops/backup-database.mjs verify /diretorio-privado/agenda/arquivo.dump.enc
```

O primeiro comando produz um arquivo `pg_dump` no formato custom, criptografa com AES-256-GCM e grava checksum SHA-256 do arquivo cifrado. O dump temporário é removido ao encerrar, inclusive em falhas. Credenciais não são colocadas nos argumentos dos processos. O segundo valida checksum, autenticidade e catálogo `pg_restore`; não altera nenhum banco e não exporta um dump decifrado persistente. Arquivos existentes não são sobrescritos nem apagados.

`node scripts/verify-backup-crypto.mjs` testa recuperação byte a byte com dados sintéticos, permissões privadas dos arquivos, chave incorreta, adulteração e preservação de arquivos existentes. Nenhum dump real foi gerado nesta conferência: não há conexão PostgreSQL privada nem ferramentas `pg_dump`/`pg_restore` disponíveis no executor desta sessão.

O banco não inclui os binários de logotipos/fotos do Storage. Copiar esses objetos separadamente com ferramentas oficiais Supabase/S3, preservando seus caminhos e metadados. No momento da conferência, o bucket de branding estava sem objetos.

## Ativação da periodicidade

Definir com o responsável um executor e um armazenamento externo privado. Proposta operacional inicial: uma cópia diária, retenção de 7 diárias e 4 semanais, com aviso quando a execução ou a verificação falhar. A periodicidade não foi ativada: faltam conexão privada, chave de recuperação, destino externo e confirmação da retenção. Nenhuma cópia é enviada automaticamente para GitHub, e-mail ou outro serviço.

A rotina futura deve criar, verificar e transferir o arquivo cifrado e seu checksum; registrar apenas horário, sucesso/falha e tamanho; testar a possibilidade de baixar a cópia; e aplicar retenção somente aos arquivos daquele projeto. A chave precisa de cópia de recuperação separada. Código versionado, arquivos JSON e checksums sozinhos não asseguram recuperação.

## Ensaio de restauração completa

1. Preparar um projeto Supabase separado e descartável, com região, versão e extensões compatíveis. Não usar o projeto comercial como destino de teste.
2. Validar a chave e o checksum e decifrar o dump em ambiente privado com arquivo temporário de permissão 0600.
3. Seguir o procedimento de migração/restauração do Supabase para schemas gerenciados, papéis e privilégios. Não executar uma restauração cega sobre a instância padrão nem aceitar erros indiscriminadamente.
4. Impedir que jobs, URLs, segredos ou integrações restaurados disparem ações no projeto de origem; ajustar as credenciais no destino e manter tarefas de envio suspensas durante o ensaio. Reavaliar sessões e inscrições de dispositivos antes de reativá-las.
5. Restaurar também os arquivos do Storage. Validar RLS, contagens, vínculos de usuários, login, recuperação de senha, agenda, Financeiro e permissões entre empresas.
6. Comparar contagens e amostras privadas com a origem; medir tempo de recuperação e registrar o resultado. Descartar dados temporários por um processo controlado.

O ensaio completo e a restauração de arquivos permanecem pendentes. Não apresentar o teste de criptografia ou o round-trip JSON como recuperação de desastre validada.

Referências: [backups Supabase](https://supabase.com/docs/guides/platform/backups), [pg_dump](https://www.postgresql.org/docs/18/app-pgdump.html), [SSL PostgreSQL](https://www.postgresql.org/docs/18/libpq-ssl.html).
