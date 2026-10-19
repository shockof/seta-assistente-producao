# Plano anual do Seta

O site está preparado para um plano Stripe com cobrança recorrente de **R$ 59,88 a cada ano** (equivalente a R$ 4,99 por mês). A interface, sozinha, não concede acesso: o estado do pagamento vem do webhook validado do Stripe e as políticas RLS usam esse estado no Supabase.

## Preparação no Stripe

1. Crie um produto “Seta Pro — Anual”.
2. Crie um preço recorrente de **R$ 59,88 BRL por ano** e copie o Price ID (`price_...`).
3. Cadastre o webhook apontando para `https://pdxamdlhuuhrwqtlnpnt.supabase.co/functions/v1/stripe-webhook`.
4. Selecione os eventos `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated` e `customer.subscription.deleted`.
5. Copie a chave secreta e o segredo de assinatura do webhook para os secrets das Edge Functions no Supabase. Nunca os coloque em `web/config.js` ou no app iOS.

## Secrets das Edge Functions

Configure no Supabase:

- `STRIPE_SECRET_KEY`
- `STRIPE_ANNUAL_PRICE_ID`
- `STRIPE_WEBHOOK_SECRET`
- `SETA_WEB_URL` — URL completa do site, incluindo caminho do repositório no GitHub Pages, por exemplo `https://USUARIO.github.io/REPOSITORIO/`.

O Supabase disponibiliza `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` no ambiente das funções. Não copie a service role key para o navegador.

Publique as funções `create-checkout-session`, `create-customer-portal` e `stripe-webhook`. A função do webhook não valida JWT do Supabase; valida a assinatura do Stripe no corpo bruto da requisição. O portal do Stripe oferece cancelamento e atualização dos dados de cobrança.

## Banco

Execute as migrações em ordem pelo SQL Editor do Supabase ou pela ferramenta de migrações:

1. `202610180001_repair_team_owner_insert_policy.sql`
2. `202610190001_annual_web_subscription.sql`

A primeira restaura o proprietário da equipe a partir da sessão. A segunda cria o registro de assinatura e passa a exigir plano anual ativo para criar, consultar, alterar ou excluir equipes e operar os dados relacionados. Usuários podem entrar e assinar antes de acessar as equipes.

Se o erro de RLS continuar antes de ativar o plano, execute primeiro a migração de reparo e instale/execute no iPhone a versão atual do código, que envia `owner_id` com a sessão autenticada. Depois da migração de cobrança, o bloqueio para uma conta sem assinatura é esperado; com plano ativo, o webhook deve registrar `status = active` e uma data futura em `billing_subscriptions`.

## GitHub Pages e autenticação

1. Envie a pasta `web/` e o workflow `.github/workflows/deploy-pages.yml` para o repositório privado `seta-assistente-producao`. O repositório pode conter também o projeto iOS.
2. Para publicar Pages a partir de repositório privado, a conta precisa de plano GitHub Pro, Team ou Enterprise. O endereço publicado é público, mesmo com o código-fonte privado. [Disponibilidade do GitHub Pages por plano](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).
3. Em **Settings → Pages**, escolha **GitHub Actions** como fonte. Cada envio para `main` que alterar `web/` publica o site.
4. Em Supabase **Authentication → URL Configuration**, inclua a URL publicada do site em **Redirect URLs**. Configure também Google OAuth com o callback do Supabase informado na tela do provedor.
5. Atualize `SETA_WEB_URL` com a URL publicada, incluindo o caminho do repositório.

## Importante para o app iOS

O entitlement no banco é compartilhado pela conta, então uma assinatura anual ativa libera a equipe também para sessões móveis usando a mesma conta. Antes de distribuir o app pela App Store, cadastre a assinatura equivalente no App Store Connect e implemente a compra/validação com StoreKit. As regras da Apple para serviços multiplataforma exigem que os itens compráveis fora do app também estejam disponíveis como compra dentro do app. A versão atual do site ainda não inclui uma opção de pagamento da App Store.

Enquanto Stripe e webhook não estiverem configurados, o botão de assinatura apresentará uma mensagem de configuração pendente; nenhuma assinatura será inventada ou liberada pelo navegador.
