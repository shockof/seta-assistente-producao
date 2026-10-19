import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedOrigins = new Set([
  Deno.env.get("SETA_WEB_URL") ? new URL(Deno.env.get("SETA_WEB_URL")!).origin : "https://shockof.github.io",
  "http://localhost:3000",
]);
const corsHeaders = {
  "Access-Control-Allow-Origin": "https://shockof.github.io",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const collections = new Set([
  "profiles", "teams", "team_members", "expenses", "expense_receipts",
  "team_messages", "billing_subscriptions",
]);

Deno.serve(async (request) => {
  const origin = request.headers.get("origin") ?? "";
  const cors = { ...corsHeaders, "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : "null" };
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "Método não permitido" }, 405, cors);
  if (!allowedOrigins.has(origin)) return json({ error: "Origem não autorizada" }, 403, cors);

  const authorization = request.headers.get("Authorization");
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!authorization?.startsWith("Bearer ")) return json({ error: "Entre na sua conta para continuar." }, 401, cors);
  if (!url || !anonKey || !serviceKey) return json({ error: "Painel administrativo indisponível." }, 503, cors);

  try {
    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return json({ error: "Sua sessão expirou. Entre novamente." }, 401, cors);

    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: grant } = await admin.from("app_admins").select("user_id").eq("user_id", user.id).maybeSingle();
    if (!grant) return json({ error: "Acesso administrativo não autorizado." }, 403, cors);

    const body = await request.json().catch(() => ({}));
    if (body.action === "check") return json({ is_admin: true }, 200, cors);
    if (body.action === "accounts") return json(await listAccounts(admin, Number(body.page) || 1), 200, cors);
    if (body.action === "summary") return json(await getSummary(admin), 200, cors);
    if (body.action === "records") {
      const table = String(body.collection ?? "");
      if (!collections.has(table)) return json({ error: "Categoria inválida." }, 400, cors);
      return json(await listRecords(admin, table, Math.max(1, Number(body.page) || 1)), 200, cors);
    }
    if (body.action === "set-status") {
      const targetId = String(body.user_id ?? "");
      if (!targetId || targetId === user.id) return json({ error: "Não é possível alterar o status desta conta." }, 400, cors);
      const { data: protectedAdmin } = await admin.from("app_admins").select("user_id").eq("user_id", targetId).maybeSingle();
      if (protectedAdmin) return json({ error: "Uma conta administrativa não pode ser suspensa por este painel." }, 403, cors);
      const active = body.active === true;
      const { data, error } = await admin.auth.admin.updateUserById(targetId, { ban_duration: active ? "none" : "876000h" });
      if (error) throw error;
      return json({ user_id: data.user.id, active: !data.user.banned_until || new Date(data.user.banned_until) <= new Date() }, 200, cors);
    }
    return json({ error: "Ação inválida." }, 400, cors);
  } catch (error) {
    console.error("Admin console request failed", error);
    return json({ error: "Não foi possível carregar o painel administrativo." }, 500, cors);
  }
});

async function listAccounts(client: ReturnType<typeof createClient>, page: number) {
  const { data, error } = await client.auth.admin.listUsers({ page, perPage: 50 });
  if (error) throw error;
  const users = data.users ?? [];
  const ids = users.map((item) => item.id);
  const { data: profiles, error: profilesError } = ids.length
    ? await client.from("profiles").select("id,full_name,phone_number,profession").in("id", ids)
    : { data: [], error: null };
  if (profilesError) throw profilesError;
  const profileById = new Map((profiles ?? []).map((profile) => [profile.id, profile]));
  return {
    page,
    has_more: users.length === 50,
    accounts: users.map((item) => {
      const until = item.banned_until ? new Date(item.banned_until) : null;
      const active = !until || until <= new Date();
      const profile = profileById.get(item.id);
      return {
        id: item.id,
        email: item.email ?? "",
        full_name: profile?.full_name || item.user_metadata?.full_name || item.user_metadata?.name || "",
        phone_number: profile?.phone_number ?? item.phone ?? "",
        profession: profile?.profession ?? item.user_metadata?.profession ?? "",
        active,
        email_confirmed: Boolean(item.email_confirmed_at),
        created_at: item.created_at,
        last_sign_in_at: item.last_sign_in_at,
        provider: item.app_metadata?.provider ?? "email",
      };
    }),
  };
}

async function getSummary(client: ReturnType<typeof createClient>) {
  const result: Record<string, number> = {};
  for (const table of collections) {
    const { count, error } = await client.from(table).select("*", { count: "exact", head: true });
    if (error) throw error;
    result[table] = count ?? 0;
  }
  let page = 1;
  let active = 0;
  let inactive = 0;
  while (page <= 100) {
    const { data, error } = await client.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    const users = data.users ?? [];
    for (const item of users) {
      const until = item.banned_until ? new Date(item.banned_until) : null;
      if (!until || until <= new Date()) active++;
      else inactive++;
    }
    if (users.length < 1000) break;
    page++;
  }
  result.active_accounts = active;
  result.inactive_accounts = inactive;
  return { counts: result };
}

async function listRecords(client: ReturnType<typeof createClient>, table: string, page: number) {
  const from = (page - 1) * 50;
  const orderColumn = table === "billing_subscriptions" ? "updated_at" : "created_at";
  const { data, count, error } = await client.from(table).select("*", { count: "exact" })
    .order(orderColumn, { ascending: false }).range(from, from + 49);
  if (error) throw error;
  let records = data ?? [];
  if (table === "expense_receipts" && records.length) {
    const paths = records.map((row) => row.storage_path).filter(Boolean);
    const { data: links } = await client.storage.from("expense-receipts").createSignedUrls(paths, 3600);
    const urls = new Map((links ?? []).map((link) => [link.path, link.signedUrl]));
    records = records.map((row) => ({ ...row, signed_url: urls.get(row.storage_path) ?? null }));
  }
  return { records, count: count ?? 0, page, per_page: 50, has_more: from + records.length < (count ?? 0) };
}

function json(body: unknown, status: number, headers: Record<string, string>) {
  return new Response(JSON.stringify(body), { status, headers: { ...headers, "Content-Type": "application/json" } });
}
