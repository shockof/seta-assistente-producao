import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const webURL = Deno.env.get("SETA_WEB_URL") ?? "https://shockof.github.io/seta-assistente-producao/";
const corsOrigin = new URL(webURL).origin;
const corsHeaders = {
  "Access-Control-Allow-Origin": corsOrigin,
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Método não permitido" }, 405);
  if (request.headers.get("origin") !== corsOrigin) return json({ error: "Origem não autorizada" }, 403);

  const authorization = request.headers.get("Authorization");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY");
  const stripeSecret = Deno.env.get("STRIPE_SECRET_KEY");
  if (!authorization?.startsWith("Bearer ")) return json({ error: "Entre na sua conta para continuar." }, 401);
  if (!supabaseUrl || !publishableKey || !stripeSecret) return json({ error: "A gestão de cobrança ainda não foi configurada." }, 503);

  try {
    const supabase = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) return json({ error: "Sua sessão expirou. Entre novamente." }, 401);
    const { data: subscription, error: subscriptionError } = await supabase
      .from("billing_subscriptions").select("stripe_customer_id").eq("user_id", user.id).maybeSingle();
    if (subscriptionError || !subscription?.stripe_customer_id) return json({ error: "Não encontramos uma assinatura ativa para esta conta." }, 404);

    const form = new URLSearchParams({ customer: subscription.stripe_customer_id, return_url: webURL });
    const stripeResponse = await fetch("https://api.stripe.com/v1/billing_portal/sessions", {
      method: "POST",
      headers: { Authorization: `Bearer ${stripeSecret}`, "Content-Type": "application/x-www-form-urlencoded" },
      body: form,
    });
    const portal = await stripeResponse.json();
    if (!stripeResponse.ok || !portal.url) {
      console.error("Stripe customer portal creation failed", portal);
      return json({ error: "Não foi possível abrir a gestão do plano." }, 502);
    }
    return json({ url: portal.url }, 200);
  } catch (error) {
    console.error("Customer portal error", error);
    return json({ error: "Não foi possível abrir a gestão do plano." }, 500);
  }

  function json(body: unknown, status: number) {
    return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
