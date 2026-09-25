-- Lab Record — đăng nhập thật (Supabase Auth) + phân quyền bằng RLS.
-- Chạy SAU schema.sql: Supabase Dashboard → SQL Editor → New query → Run. Chạy lại nhiều lần được.
--
-- Sau khi chạy: (1) TẮT "Allow anonymous sign-ins" (Authentication → Sign In / Providers) — nếu để bật,
-- ai cũng tự lấy được phiên đăng nhập ẩn danh; các policy dưới đây vẫn chặn (ẩn danh không có hồ sơ
-- nên không có quyền), nhưng không có lý do gì để bật. (2) Tạo thêm user ở Authentication → Users
-- (tick "Auto Confirm User"); mỗi user mới tự có hồ sơ vai trò 'inspector', Admin đổi vai trò trong app
-- (Cài đặt → Quản lý người dùng).

-- 1) Hồ sơ vai trò của từng tài khoản
create table if not exists public.profiles (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  email        text,
  display_name text,
  role         text not null default 'inspector' check (role in ('inspector', 'supervisor', 'admin')),
  created_at   timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- 2) Mức quyền của người đang đăng nhập: 0 = không có hồ sơ, 1 = inspector, 2 = supervisor, 3 = admin
create or replace function public.lab_level() returns int
language sql stable security definer set search_path = public as $$
  select coalesce((select case role when 'inspector' then 1 when 'supervisor' then 2 when 'admin' then 3 end
                   from public.profiles where user_id = auth.uid()), 0)
$$;
revoke all on function public.lab_level() from public, anon;
grant execute on function public.lab_level() to authenticated;

-- 3) Tài khoản (có email) mới tạo tự có hồ sơ 'inspector'. Phiên ẩn danh (không có email) bị bỏ qua.
create or replace function public.lab_handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.email is not null then
    insert into public.profiles (user_id, email, display_name, role)
    values (new.id, new.email, split_part(new.email, '@', 1), 'inspector')
    on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists lab_on_auth_user_created on auth.users;
create trigger lab_on_auth_user_created after insert on auth.users
  for each row execute function public.lab_handle_new_user();

-- Hồ sơ cho các tài khoản đã tạo sẵn; binh.dang là Admin
insert into public.profiles (user_id, email, display_name, role)
select id, email, split_part(email, '@', 1), 'inspector' from auth.users where email is not null
on conflict (user_id) do nothing;
update public.profiles set role = 'admin', display_name = 'Bình Đặng' where email = 'binh.dang@ild-coffee.com';

-- 4) Policy: bỏ các policy mở cho mọi người, thay bằng policy theo vai trò
drop policy if exists lab_records_all  on public.lab_records;
drop policy if exists lab_settings_all on public.lab_settings;
drop policy if exists lab_audit_all    on public.lab_audit;

-- profiles: mọi người đã đăng nhập có hồ sơ được xem danh sách (để chọn Reviewed by); chỉ Admin sửa vai trò
drop policy if exists profiles_read  on public.profiles;
drop policy if exists profiles_admin on public.profiles;
create policy profiles_read  on public.profiles for select to authenticated using (public.lab_level() >= 1 or user_id = auth.uid());
create policy profiles_admin on public.profiles for update to authenticated using (public.lab_level() = 3) with check (public.lab_level() = 3);

-- lab_records: mọi vai trò đọc/ghi phiếu; chỉ Admin xoá cứng
drop policy if exists lab_records_read   on public.lab_records;
drop policy if exists lab_records_insert on public.lab_records;
drop policy if exists lab_records_update on public.lab_records;
drop policy if exists lab_records_delete on public.lab_records;
create policy lab_records_read   on public.lab_records for select to authenticated using (public.lab_level() >= 1);
create policy lab_records_insert on public.lab_records for insert to authenticated with check (public.lab_level() >= 1);
create policy lab_records_update on public.lab_records for update to authenticated using (public.lab_level() >= 1) with check (public.lab_level() >= 1);
create policy lab_records_delete on public.lab_records for delete to authenticated using (public.lab_level() = 3);

-- Inspector không được đổi trạng thái phê duyệt và không được xoá (tombstone) phiếu.
-- Nội dung phiếu là JSON nên policy không tách cột được — dùng trigger để chặn.
create or replace function public.lab_records_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.lab_level() < 2 then
    if new.deleted then
      raise exception 'Chỉ Supervisor trở lên được xoá phiếu';
    end if;
    if tg_op = 'UPDATE' then
      if (new.data -> 'approval') is distinct from (old.data -> 'approval') then
        raise exception 'Chỉ Supervisor trở lên được phê duyệt phiếu';
      end if;
    elsif new.data ? 'approval' then
      -- upsert của app đi qua INSERT ... ON CONFLICT: chỉ cho phép khi giữ nguyên phê duyệt đang có
      if not exists (select 1 from public.lab_records r
                     where r.id = new.id and (r.data -> 'approval') is not distinct from (new.data -> 'approval')) then
        raise exception 'Chỉ Supervisor trở lên được phê duyệt phiếu';
      end if;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_lab_records_guard on public.lab_records;
create trigger trg_lab_records_guard before insert or update on public.lab_records
  for each row execute function public.lab_records_guard();

-- lab_settings: đọc: mọi vai trò. Ghi: thresholds/itemCodes/repeatability từ Supervisor; staff/fieldMapping chỉ Admin
drop policy if exists lab_settings_read  on public.lab_settings;
drop policy if exists lab_settings_write on public.lab_settings;
drop policy if exists lab_settings_upd   on public.lab_settings;
drop policy if exists lab_settings_del   on public.lab_settings;
create policy lab_settings_read on public.lab_settings for select to authenticated using (public.lab_level() >= 1);
create policy lab_settings_write on public.lab_settings for insert to authenticated with check (
  (key in ('thresholds', 'itemCodes', 'repeatability') and public.lab_level() >= 2) or
  (key in ('staff', 'fieldMapping') and public.lab_level() >= 3));
create policy lab_settings_upd on public.lab_settings for update to authenticated using (
  (key in ('thresholds', 'itemCodes', 'repeatability') and public.lab_level() >= 2) or
  (key in ('staff', 'fieldMapping') and public.lab_level() >= 3)) with check (
  (key in ('thresholds', 'itemCodes', 'repeatability') and public.lab_level() >= 2) or
  (key in ('staff', 'fieldMapping') and public.lab_level() >= 3));
create policy lab_settings_del on public.lab_settings for delete to authenticated using (public.lab_level() = 3);

-- lab_audit: mọi vai trò ghi nhật ký của mình; Supervisor trở lên xem
drop policy if exists lab_audit_insert on public.lab_audit;
drop policy if exists lab_audit_read   on public.lab_audit;
create policy lab_audit_insert on public.lab_audit for insert to authenticated with check (public.lab_level() >= 1);
create policy lab_audit_read   on public.lab_audit for select to authenticated using (public.lab_level() >= 2);

-- Ảnh đính kèm: chỉ người đã đăng nhập có hồ sơ
drop policy if exists lab_attachments_all on storage.objects;
create policy lab_attachments_all on storage.objects for all to authenticated
  using (bucket_id = 'lab-attachments' and public.lab_level() >= 1)
  with check (bucket_id = 'lab-attachments' and public.lab_level() >= 1);
