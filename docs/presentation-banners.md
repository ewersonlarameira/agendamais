# Banners da apresentação

Imagens ilustrativas geradas com a ferramenta integrada de geração de imagens, otimizadas em WebP em `public/images/presentation/`. Não são capturas reais da plataforma.

Direção comum dos prompts: fotografia cinematográfica para banner de marketing Agenda+, fundo azul carvão #090c13 e dourado #f4cb6b, objetos à direita, espaço escuro à esquerda, bordas esmaecidas, sem textos ou marcas. Formato paisagem 1536 × 1024.

- overview.webp: responsável de salão organizando agendamentos no notebook.
- resources.webp: celular com horários e notebook com calendário, cliente e gráfico financeiro abstratos.
- setup.webp: mãos configurando serviços, perfis de profissionais e horários em tablet.
- plans.webp: comparação de duas assinaturas abstratas em notebook, sem preços.
- access.webp: acesso por e-mail e senha em notebook com símbolo de cadeado.
- routine.webp: duas profissionais acompanhando a agenda em um tablet.

`components/section-banner.tsx` contém o banner reutilizável. Imagens decorativas usam texto alternativo vazio, legendas em HTML, dimensões explícitas e carregamento tardio abaixo do primeiro banner. Gradientes CSS preservam contraste. Nenhum dado de clientes foi usado na geração.
