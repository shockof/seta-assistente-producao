import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from "./config.js";

const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
});
const $ = (id) => document.getElementById(id);
const views = [$("auth-view"), $("billing-view"), $("dashboard-view")];
let authMode = "signin";
let signedInUser = null;
let teamMembers = new Map();

function showView(view) {
  views.forEach((item) => { item.hidden = item !== view; });
  $("account-actions").hidden = !signedInUser;
}

function message(id, text = "", success = false) {
  const node = $(id);
  node.textContent = text;
  node.classList.toggle("success", success);
}

function formatError(error) {
  const text = error?.message || "Não foi possível concluir. Tente novamente.";
  if (/row-level security|violates row-level security/i.test(text)) {
    return "O Supabase bloqueou esta operação pelas permissões da equipe. Atualize o app/site após aplicar a migração de permissões.";
  }
  if (/relation .* does not exist|schema cache/i.test(text)) {
    return "O banco ainda não recebeu a migração do Seta. Aplique os arquivos da pasta supabase/migrations no SQL Editor.";
  }
  return text;
}

document.querySelectorAll(".auth-tab").forEach((button) => button.addEventListener("click", () => {
  authMode = button.dataset.mode;
  document.querySelectorAll(".auth-tab").forEach((tab) => tab.classList.toggle("active", tab === button));
  $("name-label").hidden = authMode !== "signup";
  $("full-name").required = authMode === "signup";
  $("auth-submit").innerHTML = authMode === "signup" ? "Criar acesso <span>→</span>" : "Entrar <span>→</span>";
  message("auth-message");
}));

$("auth-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  message("auth-message", "Aguarde…", true);
  const email = $("email").value.trim().toLowerCase();
  const password = $("password").value;
  try {
    if (authMode === "signup") {
      const { data, error } = await supabase.auth.signUp({
        email, password,
        options: { data: { full_name: $("full-name").value.trim(), profession: "Produtor geral" }, emailRedirectTo: location.href.split("?")[0] },
      });
      if (error) throw error;
      if (!data.session) {
        message("auth-message", "Cadastro iniciado. Confirme o e-mail enviado e depois entre.", true);
        return;
      }
    } else {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) throw error;
    }
    await refreshApp();
  } catch (error) { message("auth-message", formatError(error)); }
});

$("google-sign-in").addEventListener("click", async () => {
  const { error } = await supabase.auth.signInWithOAuth({ provider: "google", options: { redirectTo: location.href.split("?")[0] } });
  if (error) message("auth-message", formatError(error));
});

$("sign-out").addEventListener("click", async () => {
  await supabase.auth.signOut();
  signedInUser = null;
  showView($("auth-view"));
});

async function refreshApp() {
  const { data: { session } } = await supabase.auth.getSession();
  signedInUser = session?.user ?? null;
  if (!signedInUser) { showView($("auth-view")); return; }
  $("user-email").textContent = signedInUser.email ?? "";
  const { data: subscription, error: subError } = await supabase.from("billing_subscriptions")
    .select("status,current_period_end,cancel_at_period_end").eq("user_id", signedInUser.id).maybeSingle();
  if (subError && !/does not exist|schema cache/i.test(subError.message)) {
    showView($("billing-view")); message("billing-message", formatError(subError)); return;
  }
  const endDate = subscription?.current_period_end ? new Date(subscription.current_period_end) : null;
  const paid = ["active", "trialing"].includes(subscription?.status) && (!endDate || endDate > new Date());
  if (!paid) {
    $("manage-plan").hidden = true;
    showView($("billing-view"));
    const paymentState = new URLSearchParams(location.search).get("payment");
    message("billing-message", paymentState === "success"
      ? "Pagamento recebido. Aguarde a confirmação do provedor e toque em “Já assinei? Atualizar acesso”."
      : paymentState === "cancelled" ? "Pagamento cancelado. Você pode retomar quando quiser." : "", paymentState === "success");
    return;
  }
  $("manage-plan").hidden = false;
  $("plan-status").textContent = subscription.cancel_at_period_end ? "Ativo até o fim do período" : "Anual ativo";
  showView($("dashboard-view"));
  await loadDashboard();
}

async function loadDashboard() {
  message("dashboard-message", "Carregando equipes…", true);
  try {
    const [{ data: profile }, { data: teams, error: teamError }] = await Promise.all([
      supabase.from("profiles").select("full_name").eq("id", signedInUser.id).maybeSingle(),
      supabase.from("teams").select("id,name,description,created_at").order("created_at", { ascending: false }),
    ]);
    if (teamError) throw teamError;
    $("welcome-title").textContent = profile?.full_name ? `Olá, ${profile.full_name.split(" ")[0]}` : "Suas equipes";
    const ids = (teams ?? []).map((team) => team.id);
    const { data: members, error: memberError } = ids.length
      ? await supabase.from("team_members").select("id,team_id,email,full_name,phone_number,role,is_active").in("team_id", ids).eq("is_active", true)
      : { data: [], error: null };
    if (memberError) throw memberError;
    teamMembers = new Map((teams ?? []).map((team) => [team.id, (members ?? []).filter((member) => member.team_id === team.id)]));
    renderTeams(teams ?? []);
    $("team-count").textContent = String(teams?.length ?? 0);
    $("member-count").textContent = String(members?.length ?? 0);
    message("dashboard-message");
  } catch (error) { message("dashboard-message", formatError(error)); }
}

function renderTeams(teams) {
  const root = $("teams-list");
  root.replaceChildren();
  if (!teams.length) {
    root.innerHTML = '<div class="empty-state"><strong>Sua primeira equipe começa aqui</strong>Crie uma equipe e convide as pessoas da produção.</div>';
    return;
  }
  for (const team of teams) {
    const members = teamMembers.get(team.id) ?? [];
    const card = document.createElement("article");
    card.className = "team-card";
    const header = document.createElement("div"); header.className = "team-card-head";
    const details = document.createElement("div");
    const title = document.createElement("h2"); title.textContent = team.name;
    const description = document.createElement("p"); description.className = "team-description"; description.textContent = team.description || "Equipe de produção";
    details.append(title, description); header.append(details); card.append(header);
    const meta = document.createElement("div"); meta.className = "team-meta"; meta.textContent = `${members.length} ${members.length === 1 ? "integrante" : "integrantes"}`; card.append(meta);
    const list = document.createElement("div"); list.className = "member-list";
    for (const member of members) {
      const row = document.createElement("div"); row.className = "member";
      const avatar = document.createElement("div"); avatar.className = "avatar"; avatar.textContent = (member.full_name || "?").slice(0, 1).toUpperCase();
      const info = document.createElement("div"); info.className = "member-info";
      const name = document.createElement("strong"); name.textContent = member.full_name;
      const role = document.createElement("span"); role.textContent = `${member.role} · ${member.email}`;
      info.append(name, role); row.append(avatar, info);
      const phone = (member.phone_number || "").replace(/\D/g, "");
      if (phone.length >= 8) { const link = document.createElement("a"); link.className = "member-whatsapp"; link.href = `https://wa.me/${phone}`; link.target = "_blank"; link.rel = "noreferrer"; link.textContent = "WhatsApp"; row.append(link); }
      const remove = document.createElement("button"); remove.type = "button"; remove.className = "member-remove"; remove.setAttribute("aria-label", `Remover ${member.full_name}`); remove.textContent = "×";
      remove.addEventListener("click", async () => {
        if (!confirm(`Remover ${member.full_name} desta equipe?`)) return;
        const { error } = await supabase.from("team_members").update({ is_active: false }).eq("id", member.id);
        if (error) message("dashboard-message", formatError(error)); else await loadDashboard();
      });
      row.append(remove);
      list.append(row);
    }
    card.append(list);
    const actions = document.createElement("div"); actions.className = "team-actions";
    const date = document.createElement("span"); date.className = "team-meta"; date.textContent = new Date(team.created_at).toLocaleDateString("pt-BR");
    const manage = document.createElement("span"); manage.className = "manage-actions";
    const edit = document.createElement("button"); edit.type = "button"; edit.textContent = "Editar"; edit.addEventListener("click", () => editTeam(team));
    const remove = document.createElement("button"); remove.type = "button"; remove.textContent = "Excluir"; remove.addEventListener("click", () => deleteTeam(team));
    const add = document.createElement("button"); add.type = "button"; add.textContent = "+ Adicionar integrante"; add.addEventListener("click", () => openMemberDialog(team));
    manage.append(edit, remove, add); actions.append(date, manage); card.append(actions); root.append(card);
  }
}

$("create-team-open").addEventListener("click", () => $("team-dialog").showModal());
$("team-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const button = $("team-save"); button.disabled = true; button.textContent = "Criando…";
  try {
    const { error } = await supabase.from("teams").insert({
      name: $("team-name").value.trim(), description: $("team-description").value.trim(), owner_id: signedInUser.id,
    });
    if (error) throw error;
    $("team-dialog").close(); $("team-form").reset(); await loadDashboard();
  } catch (error) { message("dashboard-message", formatError(error)); }
  finally { button.disabled = false; button.textContent = "Criar equipe"; }
});

let selectedTeam = null;
function openMemberDialog(team) { selectedTeam = team; $("member-dialog").showModal(); }
$("member-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const button = $("member-save"); button.disabled = true; button.textContent = "Adicionando…";
  try {
    const { error } = await supabase.from("team_members").insert({
      team_id: selectedTeam.id, email: $("member-email").value.trim().toLowerCase(),
      full_name: $("member-name").value.trim(), phone_number: $("member-phone").value.trim(),
      role: $("member-role").value, invited_by: signedInUser.id,
    });
    if (error) throw error;
    $("member-dialog").close(); $("member-form").reset(); await loadDashboard();
  } catch (error) { message("dashboard-message", formatError(error)); }
  finally { button.disabled = false; button.textContent = "Adicionar"; }
});

async function editTeam(team) {
  const name = prompt("Nome da equipe", team.name);
  if (name === null) return;
  const description = prompt("Descrição da equipe", team.description || "");
  if (description === null) return;
  try {
    const { error } = await supabase.from("teams").update({ name: name.trim(), description: description.trim() }).eq("id", team.id);
    if (error) throw error;
    await loadDashboard();
  } catch (error) { message("dashboard-message", formatError(error)); }
}

async function deleteTeam(team) {
  if (!confirm(`Excluir a equipe “${team.name}” e os dados ligados a ela?`)) return;
  try {
    const { error } = await supabase.from("teams").delete().eq("id", team.id);
    if (error) throw error;
    await loadDashboard();
  } catch (error) { message("dashboard-message", formatError(error)); }
}

$("subscribe").addEventListener("click", async () => {
  const button = $("subscribe"); button.disabled = true; button.textContent = "Abrindo pagamento…";
  try {
    const { data, error } = await supabase.functions.invoke("create-checkout-session", { body: {} });
    if (error) throw error;
    if (!data?.url) throw new Error("O checkout não retornou um endereço de pagamento.");
    location.assign(data.url);
  } catch (error) { message("billing-message", formatError(error)); button.disabled = false; button.innerHTML = 'Assinar plano anual <span>→</span>'; }
});
$("manage-plan").addEventListener("click", async () => {
  try {
    const { data, error } = await supabase.functions.invoke("create-customer-portal", { body: {} });
    if (error) throw error;
    if (!data?.url) throw new Error("O portal não retornou um endereço válido.");
    location.assign(data.url);
  } catch (error) { message("dashboard-message", formatError(error)); }
});
$("refresh-plan").addEventListener("click", () => refreshApp().catch((error) => message("billing-message", formatError(error))));

supabase.auth.onAuthStateChange((_event, _session) => { setTimeout(() => refreshApp().catch((error) => message("auth-message", formatError(error))), 0); });
refreshApp().catch((error) => message("auth-message", formatError(error)));
