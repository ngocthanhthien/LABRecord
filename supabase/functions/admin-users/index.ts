// Edge Function "admin-users" — quản lý người dùng cho Lab Record (chỉ Admin gọi được).
// Cần service_role key để tạo/khoá tài khoản nên PHẢI chạy trên server; key này tự có sẵn trong
// môi trường Edge Function (SUPABASE_SERVICE_ROLE_KEY) và KHÔNG bao giờ đưa vào index.html.
// Triển khai: xem supabase/README.md. Actions: list-users, create-user, change-role, disable-user, enable-user.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const ROLES = ["inspector", "supervisor", "admin"];

// Người dùng đăng nhập bằng "tên đăng nhập" (không cần email): Supabase Auth chỉ nhận email nên
// tạo email nội bộ không gửi thư. PHẢI giống hệt phép biến đổi trong index.html (Auth.toEmail).
const USERNAME_RE = /^[a-z0-9](?:[a-z0-9._-]{0,30}[a-z0-9])?$/;
const shadowDomain = (url: string) => new URL(url).hostname.split(".")[0] + ".users.internal";

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Chỉ hỗ trợ phương thức POST" }, 405);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Thiếu Authorization header" }, 401);

    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!url || !service) return json({ error: "Máy chủ chưa cấu hình SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY" }, 500);

    // 1. Xác thực người gọi bằng JWT của họ
    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: { user: caller }, error: authErr } = await userClient.auth.getUser();
    if (authErr || !caller) return json({ error: "Phiên đăng nhập không hợp lệ hoặc đã hết hạn." }, 401);

    // 2. Client quyền cao (chỉ tồn tại trong function này)
    const admin = createClient(url, service, { auth: { autoRefreshToken: false, persistSession: false } });

    // 3. Người gọi phải là Admin đang hoạt động
    const { data: me } = await admin.from("profiles")
      .select("user_id, display_name, role, disabled").eq("user_id", caller.id).maybeSingle();
    if (!me || me.role !== "admin" || me.disabled) return json({ error: "Từ chối truy cập: yêu cầu quyền Admin." }, 403);

    let body: any;
    try { body = await req.json(); } catch { return json({ error: "Dữ liệu JSON không hợp lệ" }, 400); }
    const { action } = body;

    const audit = (act: string, detail: string) =>
      admin.from("lab_audit").insert({
        id: "log_" + Date.now() + "_" + Math.random().toString(36).slice(2, 6),
        data: { time: new Date().toISOString(), action: act, detail: { text: detail }, user: me.display_name + " (admin-users)" },
      });

    // ---- list-users
    if (action === "list-users") {
      const { data: { users: authUsers }, error: e1 } = await admin.auth.admin.listUsers({ perPage: 1000 });
      if (e1) throw new Error("Không lấy được danh sách Auth: " + e1.message);
      const { data: profiles, error: e2 } = await admin.from("profiles")
        .select("user_id, display_name, role, disabled, username, email");
      if (e2) throw new Error("Không lấy được profiles: " + e2.message);

      const pMap = new Map((profiles || []).map((p: any) => [p.user_id, p]));
      const aMap = new Map((authUsers || []).map((u: any) => [u.id, u]));
      const list: any[] = [];
      for (const uid of new Set([...pMap.keys(), ...aMap.keys()])) {
        const a: any = aMap.get(uid), p: any = pMap.get(uid);
        if (!p && a && !a.email) continue; // bỏ phiên ẩn danh
        const banned = a?.banned_until ? new Date(a.banned_until) > new Date() : false;
        list.push({
          userId: uid,
          displayName: p?.display_name || a?.user_metadata?.display_name || a?.email?.split("@")[0] || "N/A",
          username: p?.username || null,
          email: p?.username ? null : (a?.email || "(không có email)"),
          role: p?.role || "inspector",
          status: (p?.disabled || banned) ? "Disabled" : "Active",
          hasProfile: !!p,
          createdAt: a?.created_at || null,
        });
      }
      list.sort((x, y) => (ROLES.indexOf(y.role) - ROLES.indexOf(x.role)) || x.displayName.localeCompare(y.displayName));
      return json({ users: list });
    }

    // ---- create-user
    if (action === "create-user") {
      const name = String(body.displayName || "").trim();
      const username = String(body.username || "").trim().toLowerCase();
      const email = String(body.email || "").trim().toLowerCase();
      const password = String(body.password || "");
      const role = ROLES.includes(body.role) ? body.role : "inspector";
      const useUsername = !email && !!username;

      if (!name) return json({ error: "Họ và tên không được để trống." }, 400);
      let authEmail = email;
      if (useUsername) {
        if (!USERNAME_RE.test(username)) {
          return json({ error: "Tên đăng nhập không hợp lệ: 2-32 ký tự, chữ thường/số, có thể chứa . _ -, không bắt đầu/kết thúc bằng ký tự đặc biệt." }, 400);
        }
        authEmail = username + "@" + shadowDomain(url);
      } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        return json({ error: "Địa chỉ email không đúng định dạng." }, 400);
      }
      if (password.length < 6) return json({ error: "Mật khẩu phải có tối thiểu 6 ký tự." }, 400);

      const { data: created, error: cErr } = await admin.auth.admin.createUser({
        email: authEmail, password, email_confirm: true, user_metadata: { display_name: name },
      });
      if (cErr || !created?.user) {
        const msg = cErr?.message || "Không xác định";
        return json({ error: /already.*(registered|exists)/i.test(msg)
          ? (useUsername ? "Tên đăng nhập đã được sử dụng." : "Email đã được sử dụng.") : "Lỗi tạo tài khoản Auth: " + msg }, 400);
      }
      const uid = created.user.id;

      // Trigger lab_handle_new_user có thể đã tạo hồ sơ 'inspector' → dùng upsert để đặt đúng giá trị
      const { error: pErr } = await admin.from("profiles").upsert({
        user_id: uid, email: authEmail, display_name: name, role, disabled: false, username: useUsername ? username : null,
      }, { onConflict: "user_id" });
      if (pErr) {
        await admin.auth.admin.deleteUser(uid); // không để lại tài khoản mồ côi
        return json({ error: (/duplicate|unique/i.test(pErr.message) ? "Tên đăng nhập đã được sử dụng."
          : "Lỗi tạo hồ sơ vai trò: " + pErr.message) + " Đã huỷ tạo tài khoản." }, 500);
      }
      await audit("USER_CREATED", `Tạo người dùng ${name} (${useUsername ? "@" + username : authEmail}), vai trò ${role}`);
      return json({ ok: true, user: { userId: uid, displayName: name, username: useUsername ? username : null,
        email: useUsername ? null : authEmail, role, status: "Active" } });
    }

    // ---- change-role
    if (action === "change-role") {
      const { targetUserId, newRole } = body;
      if (!targetUserId) return json({ error: "Thiếu targetUserId" }, 400);
      if (!ROLES.includes(newRole)) return json({ error: "Vai trò mới không hợp lệ." }, 400);

      if (targetUserId === caller.id && newRole !== "admin") {
        const { count } = await admin.from("profiles").select("user_id", { count: "exact", head: true })
          .eq("role", "admin").eq("disabled", false).neq("user_id", caller.id);
        if (!count) return json({ error: "Không thể hạ quyền: bạn là Admin đang hoạt động duy nhất." }, 400);
      }
      const { data: t } = await admin.from("profiles").select("display_name, role").eq("user_id", targetUserId).maybeSingle();
      if (!t) return json({ error: "Không tìm thấy hồ sơ của người dùng này." }, 404);
      const { error: uErr } = await admin.from("profiles").update({ role: newRole }).eq("user_id", targetUserId);
      if (uErr) return json({ error: "Lỗi cập nhật vai trò: " + uErr.message }, 500);
      await audit("ROLE_CHANGED", `Đổi vai trò ${t.display_name} từ ${t.role} thành ${newRole}`);
      return json({ ok: true, role: newRole });
    }

    // ---- disable-user / enable-user
    if (action === "disable-user" || action === "enable-user") {
      const { targetUserId } = body;
      const disable = action === "disable-user";
      if (!targetUserId) return json({ error: "Thiếu targetUserId" }, 400);
      if (disable && targetUserId === caller.id) return json({ error: "Không thể tự vô hiệu hoá tài khoản của chính bạn." }, 400);

      const { error: bErr } = await admin.auth.admin.updateUserById(targetUserId, { ban_duration: disable ? "876600h" : "none" });
      if (bErr) return json({ error: "Lỗi cập nhật trạng thái trong Auth: " + bErr.message }, 500);
      const { error: mErr } = await admin.from("profiles").update({ disabled: disable }).eq("user_id", targetUserId);
      if (mErr) return json({ error: "Lỗi cập nhật hồ sơ: " + mErr.message }, 500);
      const { data: t } = await admin.from("profiles").select("display_name").eq("user_id", targetUserId).maybeSingle();
      await audit(disable ? "USER_DISABLED" : "USER_ENABLED", `${disable ? "Vô hiệu hoá" : "Kích hoạt lại"} người dùng ${t?.display_name || targetUserId}`);
      return json({ ok: true, status: disable ? "Disabled" : "Active" });
    }

    return json({ error: `Action '${action}' không được hỗ trợ.` }, 400);
  } catch (err: any) {
    return json({ error: err.message || "Đã xảy ra lỗi nội bộ trên máy chủ." }, 500);
  }
});
