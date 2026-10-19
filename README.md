# Seta — Assistente de Produção

App iOS nativo em SwiftUI. O projeto Supabase está configurado em `SupabaseService.swift`; a URL e a publishable key são dados públicos próprios para apps cliente. A sessão de acesso é guardada no Keychain. As permissões das tabelas e arquivos são aplicadas pelas políticas RLS da migração SQL.

## Abrir no Xcode

1. Abra `AssistenteProducao.xcodeproj`.
2. Selecione um simulador iOS 17 ou posterior e execute o scheme `AssistenteProducao`.
3. Para instalar em aparelho, selecione sua equipe em **Signing & Capabilities**.

## Supabase

O app usa o projeto `https://pdxamdlhuuhrwqtlnpnt.supabase.co`. A migração `supabase/migrations/202610070001_initial_backend.sql` precisa estar aplicada no projeto e as tabelas/bucket precisam existir.

- E-mail e senha: use **Authentication → Sign In / Providers** para escolher se o cadastro exige confirmação de e-mail. Se exigir, a pessoa deve confirmar antes de entrar.
- Google: habilite Google em **Authentication → Sign In / Providers** e cadastre as credenciais OAuth esperadas pelo Supabase. O Client ID iOS do Google Sign-In permanece em Build Settings.
- Apple: a capacidade **Sign in with Apple** e a configuração do provedor no Supabase exigem uma equipe Apple Developer. O botão segue desabilitado para a Personal Team usada atualmente.

Não coloque `service_role` ou secret keys no app. A chave `sb_publishable_...` usada pelo cliente não substitui políticas RLS.

## Sincronização

Cadastro/login, perfil, equipes, integrantes, chat, verbas, despesas e imagens de comprovantes usam os endpoints Supabase. Ao abrir o painel, os dados visíveis para a conta autenticada são carregados para o SwiftData local; alterações sincronizadas ficam no servidor. Exclusão de equipe permanece local nesta versão, pois a migração atual não concede exclusão remota.

## Site e plano anual

Uma versão web está em `web/`, pronta para GitHub Pages e ligada ao mesmo projeto Supabase. O site oferece acesso por e-mail/senha e Google, equipes e inclusão de integrantes. O plano configurado é R$ 4,99/mês com compromisso e cobrança anual de R$ 59,88. A publicação e a integração de pagamento exigem um repositório GitHub próprio e as credenciais Stripe no servidor Supabase.

Consulte [`supabase/SETUP_PAGAMENTOS.md`](supabase/SETUP_PAGAMENTOS.md) para as configurações de RLS, Stripe, Edge Functions, GitHub Pages e a assinatura equivalente exigida para a distribuição pela App Store.
