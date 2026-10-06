-- Lab Record — máy chủ đọc MA TRẬN QUYỀN cấu hình ở Cài đặt → Phân quyền (2026-10-06).
-- Chạy SAU auth.sql (+ users.sql). THAY THẾ tác dụng của settings_permissions.sql và hàm lab_records_guard trong approval_flow.sql
-- (nếu đã chạy 2 file đó thì file này ghi đè các policy/hàm cùng tên). Chạy lại nhiều lần được.
-- CHƯA áp dụng lên project Supabase thật — người phụ trách tự chạy trong SQL Editor khi sẵn sàng.
--
-- Ma trận lưu ở lab_settings.key = 'permissions' (value = { "<quyền>": { "inspector": bool, "supervisor": bool } }), do Admin sửa trong app.
-- lab_can('<quyền>') trả true nếu: Admin; hoặc ma trận cho vai trò hiện tại; hoặc (không có ghi đè) theo MẶC ĐỊNH bên dưới
-- (= file "Quản lý người dùng.xlsx"). Tài khoản không có hồ sơ / bị khoá: luôn false.

create or replace function public.lab_can(perm text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  lvl int := public.lab_level();
  role_name text;
  ov jsonb;
  def jsonb := '{
    "form.entry":[1,1],"history.view":[1,1],"history.resumeDraft":[1,1],"history.approve":[0,1],"history.editSaved":[0,1],
    "history.editApproved":[0,1],"history.delete":[0,1],"itemcode.view":[1,1],"itemcode.add":[1,1],"itemcode.edit":[1,1],
    "spec.view":[0,1],"spec.add":[0,0],"spec.edit":[0,0],"param.view":[0,1],"param.add":[0,0],"param.edit":[0,0],
    "repeat.view":[0,1],"repeat.add":[0,0],"repeat.edit":[0,0],"datalog.view":[0,1],"users.manage":[0,0]}'::jsonb;
begin
  if lvl <= 0 then return false; end if;
  if lvl >= 3 then return true; end if;
  role_name := case lvl when 1 then 'inspector' else 'supervisor' end;
  if perm = 'users.manage' then return false; end if;
  select value into ov from public.lab_settings where key = 'permissions';
  if ov is not null and (ov -> perm -> role_name) is not null and jsonb_typeof(ov -> perm -> role_name) = 'boolean' then
    return (ov -> perm ->> role_name)::boolean;
  end if;
  return coalesce((def -> perm ->> (lvl - 1))::int, 0) = 1;
end;
$$;
revoke all on function public.lab_can(text) from public, anon;
grant execute on function public.lab_can(text) to authenticated;

-- ---- lab_settings: ghi theo quyền (RLS theo KHOÁ; không phân biệt thêm hay sửa trong cùng 1 mảng nên dùng "thêm HOẶC sửa") ----
drop policy if exists lab_settings_write on public.lab_settings;
drop policy if exists lab_settings_upd   on public.lab_settings;
drop policy if exists lab_settings_del   on public.lab_settings;
create policy lab_settings_write on public.lab_settings for insert to authenticated with check (
  (key = 'itemCodes'      and (public.lab_can('itemcode.add') or public.lab_can('itemcode.edit'))) or
  (key = 'thresholds'     and (public.lab_can('spec.add')     or public.lab_can('spec.edit'))) or
  (key = 'fieldMapping'   and (public.lab_can('param.add')    or public.lab_can('param.edit'))) or
  (key = 'repeatability'  and (public.lab_can('repeat.add')   or public.lab_can('repeat.edit'))) or
  (key in ('staff', 'permissions') and public.lab_level() >= 3));
create policy lab_settings_upd on public.lab_settings for update to authenticated using (
  (key = 'itemCodes'      and (public.lab_can('itemcode.add') or public.lab_can('itemcode.edit'))) or
  (key = 'thresholds'     and (public.lab_can('spec.add')     or public.lab_can('spec.edit'))) or
  (key = 'fieldMapping'   and (public.lab_can('param.add')    or public.lab_can('param.edit'))) or
  (key = 'repeatability'  and (public.lab_can('repeat.add')   or public.lab_can('repeat.edit'))) or
  (key in ('staff', 'permissions') and public.lab_level() >= 3)) with check (
  (key = 'itemCodes'      and (public.lab_can('itemcode.add') or public.lab_can('itemcode.edit'))) or
  (key = 'thresholds'     and (public.lab_can('spec.add')     or public.lab_can('spec.edit'))) or
  (key = 'fieldMapping'   and (public.lab_can('param.add')    or public.lab_can('param.edit'))) or
  (key = 'repeatability'  and (public.lab_can('repeat.add')   or public.lab_can('repeat.edit'))) or
  (key in ('staff', 'permissions') and public.lab_level() >= 3));
create policy lab_settings_del on public.lab_settings for delete to authenticated using (public.lab_level() = 3);

-- ---- lab_records: trigger theo ma trận (thay bản trong approval_flow.sql) ----
create or replace function public.lab_records_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  old_status text;
  new_status text;
  new_reason text;
  content_changed boolean;
begin
  if new.deleted and not public.lab_can('history.delete') then
    raise exception 'Bạn không có quyền xoá phiếu';
  end if;

  new_status := new.data #>> '{approval,status}';
  new_reason := new.data #>> '{approval,reason}';

  if tg_op = 'UPDATE' then
    old_status := old.data #>> '{approval,status}';
    content_changed := (new.data - 'approval' - 'edits') is distinct from (old.data - 'approval' - 'edits');

    -- Phiếu đã duyệt: không ai sửa nội dung mà vẫn giữ status = approved (phải tạo phiên bản mới).
    if old_status = 'approved' and new_status = 'approved' and content_changed then
      raise exception 'Phiếu đã duyệt bị khoá nội dung — sửa phải tạo phiên bản mới (chuyển trạng thái khỏi approved)';
    end if;
    -- Sửa nội dung phiếu đã lưu cần quyền tương ứng (phiếu bị trả lại: người nhập được sửa để gửi lại).
    if content_changed then
      if old_status = 'approved' and not public.lab_can('history.editApproved') then
        raise exception 'Bạn không có quyền điều chỉnh phiếu đã phê duyệt';
      elsif old_status in ('pending', 'not_approved') and not public.lab_can('history.editSaved') then
        raise exception 'Bạn không có quyền điều chỉnh phiếu đã lưu (chờ duyệt)';
      elsif old_status is not null and old_status not in ('approved', 'pending', 'not_approved') and not public.lab_can('form.entry') then
        raise exception 'Bạn không có quyền nhập liệu';
      end if;
    end if;

    if (new.data -> 'approval') is distinct from (old.data -> 'approval') then
      if old_status in ('returned', 'rejected') and new_status = 'pending' then
        if not public.lab_can('form.entry') then raise exception 'Bạn không có quyền gửi duyệt lại'; end if;
      elsif old_status = 'approved' and new_status = 'pending' then
        -- phiên bản mới sau khi sửa phiếu đã duyệt
        if not public.lab_can('history.editApproved') then raise exception 'Bạn không có quyền tạo phiên bản mới của phiếu đã duyệt'; end if;
      else
        if not public.lab_can('history.approve') then raise exception 'Bạn không có quyền phê duyệt / trả lại phiếu'; end if;
        if new_status = 'returned' and coalesce(btrim(new_reason), '') = '' then raise exception 'Trả lại phiếu phải có lý do'; end if;
      end if;
    end if;
  elsif tg_op = 'INSERT' then
    -- upsert PostgREST (INSERT ... ON CONFLICT DO UPDATE) chạy trigger INSERT rồi (nếu trùng id) trigger UPDATE ở trên.
    if new_status = 'returned' and coalesce(btrim(new_reason), '') = '' then
      raise exception 'Trả lại phiếu phải có lý do';
    end if;
    -- bản lưu trữ phiên bản đã duyệt (status approved) do người có quyền duyệt HOẶC điều chỉnh phiếu đã duyệt tạo
    if new_status in ('approved', 'returned') and not (public.lab_can('history.approve') or public.lab_can('history.editApproved')) then
      raise exception 'Bạn không có quyền thay đổi trạng thái phê duyệt';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_lab_records_guard on public.lab_records;
create trigger trg_lab_records_guard before insert or update on public.lab_records
  for each row execute function public.lab_records_guard();

-- Đã biết / giới hạn:
-- 1) Không kiểm 'form.entry' khi tạo phiếu MỚI hoặc 'history.view' khi đọc (lab_records chỉ yêu cầu có hồ sơ) — 2 quyền này chỉ ở giao diện.
-- 2) Phiếu cũ trạng thái 'not_approved' được coi như chờ duyệt (khớp LEGACY_APPROVAL_MAP trong index.html).
-- 3) Quyền Data Log (lab_audit đọc từ Supervisor trở lên) vẫn theo auth.sql, chưa đọc ma trận.
-- 4) users.manage luôn chỉ Admin (Edge Function admin-users kiểm vai trò Admin).
-- 5) Mảng danh mục (itemCodes/thresholds/...) là 1 hàng JSON: máy chủ không phân biệt "thêm" với "sửa/xoá" trong cùng khoá nên cho ghi nếu có MỘT trong hai quyền.
