-- Lab Record — hỗ trợ quản lý người dùng (tạo user, vô hiệu hoá, tên đăng nhập).
-- Chạy SAU auth.sql: SQL Editor → New query → Run. Chạy lại nhiều lần được.
-- Cùng với đó cần triển khai Edge Function `admin-users` (xem supabase/README.md).

alter table public.profiles add column if not exists disabled boolean not null default false;
alter table public.profiles add column if not exists username text;
create unique index if not exists profiles_username_uidx on public.profiles (username) where username is not null;

-- Tài khoản bị vô hiệu hoá coi như không có quyền (RLS chặn ngay, kể cả khi token cũ chưa hết hạn)
create or replace function public.lab_level() returns int
language sql stable security definer set search_path = public as $$
  select coalesce((select case role when 'inspector' then 1 when 'supervisor' then 2 when 'admin' then 3 end
                   from public.profiles where user_id = auth.uid() and not disabled), 0)
$$;
revoke all on function public.lab_level() from public, anon;
grant execute on function public.lab_level() to authenticated;

-- Chỉ Admin (qua Edge Function hoặc trực tiếp) được sửa hồ sơ; người dùng chỉ đọc được hồ sơ của mình và
-- danh sách hồ sơ đang hoạt động (để chọn "Reviewed by"). Policy profiles_read/profiles_admin từ auth.sql giữ nguyên.
