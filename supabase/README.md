# Backend do Seta

O projeto Supabase do Seta está em `https://pdxamdlhuuhrwqtlnpnt.supabase.co`.

## Criar as tabelas e regras

1. Abra o painel do projeto Supabase e entre em **SQL Editor**.
2. Abra `migrations/202610070001_initial_backend.sql` neste projeto.
3. Copie o arquivo inteiro para uma consulta nova e execute uma única vez.
4. Confirme que as tabelas `profiles`, `teams`, `team_members`, `expenses`, `expense_receipts` e `team_messages` foram criadas. O script cria também o bucket privado `expense-receipts`.

A migração cria políticas de Row Level Security. O produtor geral dono da equipe pode ver integrantes, liberar verba e consultar relatórios. O integrante associado a uma conta autenticada pode enviar despesas da própria equipe. O convite por e-mail só é vinculado à conta depois da confirmação do e-mail. Despesas são registros de auditoria e não podem ser alteradas ou removidas pela API do app.

## Credenciais do app

O app usa o Project URL e a **Publishable key** (`sb_publishable_...`). Essa chave pode estar no app iOS, mas só é segura junto das políticas RLS da migração. Nunca adicione uma **Secret key** ou a antiga `service_role` ao app.

## Provedores de login

O fluxo de e-mail e senha usa Supabase Auth. Para ativar Google no Supabase, habilite o provedor Google em **Authentication → Sign In / Providers** e configure as credenciais OAuth requeridas pelo painel. Use o callback URL apresentado pelo Supabase nas URIs de redirecionamento do OAuth no Google Cloud. Não compartilhe o Client Secret; ele fica apenas na configuração do Supabase. O Client ID iOS atual pode continuar no app, mas não substitui as credenciais do provedor no Supabase.

Sign in with Apple depende de uma equipe Apple que ofereça a capacidade. A Personal Team atual do Xcode não consegue gerar o perfil necessário para esse recurso.

## Limite desta etapa

O arquivo SQL prepara o backend. As telas existentes ainda precisam ser conectadas às tabelas remotas para que equipes, chat, despesas e saldo sincronizem entre dispositivos. A integração do app deve acontecer depois de executar e conferir a migração no projeto Supabase.
