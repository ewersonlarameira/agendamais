# Fase 1 — Autenticação e proteção dos dados

Esta fase substitui o login por nickname/senha armazenado na tabela `usuarios`
por Supabase Auth e protege os dados com privilégios mínimos e Row Level
Security (RLS).

## Mudanças principais

- Login interno com e-mail e senha pelo Supabase Auth.
- Conversão das senhas legadas para bcrypt e remoção imediata do texto simples.
- Ativação dos perfis antigos com nickname e senha antigos, em uso único.
- Ativação de novos profissionais com código aleatório, de uso único e válido
  por sete dias.
- RLS nas tabelas `usuarios`, `pacientes`, `procedimentos`, `agendamentos` e
  `anamneses`.
- Agendamento público por RPC transacional: o navegador público não lê
  pacientes nem detalhes da agenda.
- Índice único por data/horário e locks transacionais contra reservas
  simultâneas.
- Renderização sem HTML vindo do banco e Content Security Policy nas páginas.

## Primeiro acesso de um perfil existente

1. Na tela interna, clique em **Ativar meu primeiro acesso**.
2. Cadastre um e-mail e uma senha nova de pelo menos oito caracteres.
3. Confirme o e-mail, se solicitado, e faça login.
4. Em **Vincular perfil profissional**, informe o nickname e a senha antigos.
5. A credencial antiga é descartada após o vínculo.

## Novo profissional

1. Uma pessoa com a permissão `profissionais` cria o perfil.
2. O sistema exibe um código de ativação uma única vez.
3. O profissional cria seu acesso com e-mail e senha e informa esse código.

## Corte de produção

A publicação do front-end e a aplicação da migração devem ocorrer na mesma
janela. A migração bloqueia o acesso direto usado pela versão antiga do site;
por isso, aplicar apenas um dos lados interrompe o sistema.

Migração:

`supabase/migrations/20260921032138_secure_auth_rls_phase1.sql`

Teste de regressão:

`supabase/tests/phase1_security.sql`

Antes do corte, faça backup do banco. Depois da migração, execute o teste e os
advisors de segurança e desempenho do Supabase.

## Limite conhecido

Os horários de abertura, fechamento e almoço ainda ficam no navegador da área
interna. Centralizar essa configuração no banco faz parte da próxima etapa.
