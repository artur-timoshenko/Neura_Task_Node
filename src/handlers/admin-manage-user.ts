import { createClient } from "@supabase/supabase-js";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

export default async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Not authenticated" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      process.env.SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!
    );

    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: userError } = await supabase.auth.getUser(token);
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check admin role
    const { data: roleData } = await supabase
      .from("user_roles")
      .select("role")
      .eq("user_id", user.id)
      .eq("role", "admin")
      .maybeSingle();

    if (!roleData) {
      return new Response(JSON.stringify({ error: "Not an admin" }), {
        status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { action, targetUserId, newPassword, newEmail, newName, newRole, banned, memberId, memberIds, nickname, tags } = await req.json();

    if (action === "create_buyer") {
      const nick = String(nickname || "").trim();
      if (!/^[a-zA-Z0-9_.-]{2,40}$/.test(nick)) {
        return new Response(JSON.stringify({ error: "Ник: 2-40 символов, латиница/цифры/_.-" }), {
          status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      const email = `buyer_${nick.toLowerCase()}@buyers.neuratasks.local`;
      // Auto-generate password (16 chars, letters+digits)
      const bytes = new Uint8Array(16);
      crypto.getRandomValues(bytes);
      const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
      let password = "";
      for (const b of bytes) password += alphabet[b % alphabet.length];

      // Check duplicates: by nick in profiles
      const { data: existingProfile } = await supabase
        .from("profiles").select("id").eq("name", nick).maybeSingle();
      if (existingProfile) {
        return new Response(JSON.stringify({ error: `Баер с ником "${nick}" уже существует` }), {
          status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      const { data: created, error: createErr } = await supabase.auth.admin.createUser({
        email, password, email_confirm: true, user_metadata: { name: nick },
      });
      if (createErr) {
        const msg = String(createErr.message || "");
        if (/already|exist|registered|duplicate/i.test(msg)) {
          return new Response(JSON.stringify({ error: `Баер с ником "${nick}" уже существует` }), {
            status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
          });
        }
        throw createErr;
      }
      const newId = created.user!.id;
      // Ensure profile row (trigger usually creates it, but upsert to guarantee name)
      await supabase.from("profiles").upsert({
        id: newId, name: nick, email,
        tags: Array.isArray(tags) ? tags : [],
      } as any, { onConflict: "id" });
      const { error: roleErr } = await supabase.from("user_roles").upsert({ user_id: newId, role: "buyer" } as any, { onConflict: "user_id" });
      if (roleErr) throw roleErr;
      return new Response(JSON.stringify({ success: true, email, password, userId: newId }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }


    if (action === "change_password") {
      const { error } = await supabase.auth.admin.updateUserById(targetUserId, { password: newPassword });
      if (error) throw error;
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "change_name") {
      const { error } = await supabase.from("profiles").update({ name: newName }).eq("id", targetUserId);
      if (error) throw error;
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "toggle_role") {
      // newRole can be 'admin' | 'teamlead' | 'buyer' | 'user'
      const target = newRole === "admin" || newRole === "teamlead" || newRole === "buyer" ? newRole : "user";
      const { data: existing } = await supabase.from("user_roles").select("id").eq("user_id", targetUserId).maybeSingle();
      if (existing) {
        await supabase.from("user_roles").update({ role: target }).eq("user_id", targetUserId);
      } else {
        await supabase.from("user_roles").insert({ user_id: targetUserId, role: target });
      }
      // If demoted from teamlead, clean up their memberships
      if (target !== "teamlead") {
        await supabase.from("team_memberships").delete().eq("teamlead_id", targetUserId);
      }
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "set_team_members") {
      // targetUserId = teamlead, memberIds = array of subordinate user ids
      await supabase.from("team_memberships").delete().eq("teamlead_id", targetUserId);
      const ids: string[] = Array.isArray(memberIds) ? memberIds.filter((x: any) => typeof x === "string" && x !== targetUserId) : [];
      if (ids.length > 0) {
        const rows = ids.map((mid) => ({ teamlead_id: targetUserId, member_id: mid }));
        const { error } = await supabase.from("team_memberships").insert(rows);
        if (error) throw error;
      }
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "change_email") {
      const { error } = await supabase.auth.admin.updateUserById(targetUserId, { email: newEmail });
      if (error) throw error;
      // Update profile email too
      await supabase.from("profiles").update({ email: newEmail }).eq("id", targetUserId);
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "verify_email") {
      const { data: target, error: targetError } = await supabase.auth.admin.getUserById(targetUserId);
      if (targetError || !target.user) throw targetError || new Error("Пользователь не найден");
      if (!target.user.email) throw new Error("У пользователя не указана почта");
      if (!target.user.email_confirmed_at) {
        const { error } = await supabase.auth.admin.updateUserById(targetUserId, { email_confirm: true });
        if (error) throw error;
      }
      return new Response(JSON.stringify({ success: true, alreadyVerified: Boolean(target.user.email_confirmed_at) }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "ban") {
      await supabase.from("profiles").update({ banned }).eq("id", targetUserId);
      if (banned) {
        await supabase.auth.admin.updateUserById(targetUserId, { ban_duration: "876600h" });
      } else {
        await supabase.auth.admin.updateUserById(targetUserId, { ban_duration: "none" });
      }
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "delete") {
      // Let database foreign keys handle a single auth-user deletion atomically.
      // A referenced project may block deletion; do not partially erase user data.
      const { error } = await supabase.auth.admin.deleteUser(targetUserId);
      if (error) throw error;
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), {
      status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : "Operation failed" }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
}
