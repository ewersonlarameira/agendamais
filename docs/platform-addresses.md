# Endereços da plataforma

A raiz `/` é a apresentação comercial pública do Agenda+, com recursos, demonstração, contato para planos e entrada para o painel do estabelecimento. Não carrega dados de empresas nem o painel Master.

| Caminho | Finalidade |
| --- | --- |
| `/` | Apresentação comercial |
| `/demo` | Demonstração com dados ilustrativos em memória |
| `/master` | Login e gerenciamento da plataforma pelo Master |
| `/<cliente>` | Agendamento público do estabelecimento |
| `/<cliente>/admin` | Login e gestão da empresa |
| `/<cliente>/agendaprofissional` | Login e consulta da própria agenda pelo profissional |

`cliente` é o link exclusivo (slug) definido no cadastro da empresa. As páginas usam o cadastro existente automaticamente, sem criar uma cópia do sistema por empresa. A autenticação e as permissões continuam aplicadas pelo servidor. O link `demo` é reservado e não pode ser usado no cadastro de empresas.

O endereço original `https://agenda-plus.ewersonlarameira.chatgpt.site` e os domínios próprios cadastrados servem a mesma publicação e a mesma estrutura de caminhos. Entrar por outro domínio pode exigir um novo login, pois cookies são separados por domínio.

A entrada “Área do cliente” na apresentação solicita somente o link curto e abre `/<cliente>/admin`; não lista estabelecimentos nem dados privados. Valores e condições dos planos são consultados pelo atendimento, sem criar ofertas diferentes das cadastradas no Master.
