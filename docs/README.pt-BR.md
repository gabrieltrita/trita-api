# trita-api

[Read in English](../README.md)

Todo produto precisa do mesmo backend antes de fazer qualquer coisa útil: contas, login seguro, permissões, área administrativa, LGPD e a infraestrutura de produção. A trita-api é esse backend, já construído, testado e documentado. Com ela, um projeto novo começa no primeiro dia pelas regras de negócio, sem gastar semanas refazendo autenticação.

É uma API em Rails 8.1 consumida por um front web ou mobile, feita para ser a base de novos projetos: renomeia com um comando e o domínio do produto entra por cima.

## O que já vem pronto

| Área | Incluído |
| --- | --- |
| Contas | Cadastro com confirmação de e-mail, login, perfil e troca de e-mail, recuperação de senha, exclusão de conta |
| Segurança | JWT com refresh token rotativo, sessões por dispositivo, autenticação em dois fatores (TOTP e códigos de backup), bloqueio após tentativas erradas, rate limiting, dados pessoais criptografados |
| Login social | Google e Apple, identidades vinculadas e contas sem senha |
| Permissões e admin | Autorização por papéis, área administrativa protegida por 2FA, gestão de usuários, log de auditoria imutável |
| Privacidade (LGPD) | Consentimentos versionados, exportação completa dos dados pessoais, anonimização ao excluir a conta |
| Operação | Docker para desenvolvimento e produção, jobs em segundo plano e agendados, health checks, logs em JSON, Sentry, checagem rígida da configuração de produção |
| Qualidade | 100% de cobertura de testes (linhas e branches), contrato da API validado contra o OpenAPI, Swagger UI, CI com RuboCop, Brakeman e bundler-audit |
| Velocidade | Um gerador que cria um recurso completo do usuário (model, policy, controller, rotas, testes e documentação) com um comando |

## Quanto tempo economiza

Esforço estimado para construir o mesmo escopo do zero, para um desenvolvedor experiente:

| Bloco | Tempo economizado (estimativa) |
| --- | --- |
| Autenticação, sessões e 2FA | 3 a 4 semanas |
| Login social e contas sem senha | 1 a 2 semanas |
| Permissões, área admin e auditoria | 1 a 2 semanas |
| LGPD: consentimentos, exportação e anonimização | 1 semana |
| Infraestrutura, observabilidade e CI | 1 semana |
| **Total** | **7 a 10 semanas** |

São estimativas, não medições. Na prática, um backend de MVP pode ser entregue em 2 a 4 semanas, com o tempo todo dedicado ao que diferencia o produto.

## Para quem é

- Startups e fundadores que precisam de um backend de MVP pronto para produção e para auditoria.
- Agências e desenvolvedores de front-end ou mobile que precisam de uma API confiável por trás dos apps.
- Empresas no Brasil que precisam cumprir a LGPD desde a primeira versão.

## Documentação técnica

A documentação completa, em inglês, está no [README principal](../README.md): como rodar, cada recurso com exemplos de chamadas, produção, logs e segurança ([SECURITY.md](SECURITY.md)).
