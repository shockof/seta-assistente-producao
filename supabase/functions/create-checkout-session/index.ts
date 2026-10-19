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
  if (!authorization?.startsWith("Bearer ")) return json({ error: "Entre na sua conta para continuar." }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY");
  const stripeSecret = Deno.env.get("STRIPE_SECRET_KEY");
  const annualPrice = Deno.env.get("STRIPE_ANNUAL_PRICE_ID");
  if (!supabaseUrl || !publishableKey || !stripeSecret || !annualPrice) {
    return json({ error: "A cobrança anual ainda não foi configurada no servidor." }, 503);
  }

  try {
    const supabase = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) return json({ error: "Sua sessão expirou. Entre novamente." }, 401);

    const form = new URLSearchParams();
    form.set("mode", "subscription");
    form.set("line_items[0][price]", annualPrice);
    form.set("line_items[0][quantity]", "1");
    form.set("client_reference_id", user.id);
    form.set("customer_email", user.email ?? "");
    form.set("subscription_data[metadata][user_id]", user.id);
    form.set("success_url", `${webURL}?payment=success`);
    form.set("cancel_url", `${webURL}?payment=cancelled`);
    form.set("allow_promotion_codes", "true");

    const stripeResponse = await fetch("https://api.stripe.com/v1/checkout/sessions", {
      method: "POST",
      headers: { Authorization: `Bearer ${stripeSecret}`, "Content-Type": "application/x-www-form-urlencoded" },
      body: form,
    });
    const session = await stripeResponse.json();
    if (!stripeResponse.ok || !session.url) {
      console.error("Stripe checkout creation failed", session);
      return json({ error: "Não foi possível abrir o pagamento. Tente novamente em instantes." }, 502);
    }
    return json({ url: session.url }, 200);
  } catch (error) {
    console.error("Checkout error", error);
    return json({ error: "Não foi possível abrir o pagamento." }, 500);
  }

  function json(body: unknown, status: number) {
    return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
