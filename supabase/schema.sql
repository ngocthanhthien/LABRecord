-- Lab Record — schema Supabase. Chạy 1 lần trong: Supabase Dashboard → SQL Editor → New query → Run.
-- An toàn khi chạy lại (idempotent).

-- 1) Phiếu kết quả (mỗi phiếu là 1 dòng, toàn bộ nội dung nằm trong cột JSON `data`)
create table if not exists public.lab_records (
  id           text primary key,
  product_type text,
  data         jsonb       not null default '{}'::jsonb,
  deleted      boolean     not null default false,   -- xoá mềm (tombstone) để các máy khác biết phiếu đã bị xoá
  updated_at   timestamptz not null default now(),   -- thời điểm sửa do app ghi (dùng so sánh bản mới hơn)
  synced_at    timestamptz not null default now()    -- do server đặt (trigger), dùng để kéo dữ liệu thay đổi
);

-- 2) Danh mục/cài đặt dùng chung (nhân viên, ngưỡng, field mapping, mã hàng, độ lặp lại)
create table if not exists public.lab_settings (
  key        text primary key,
  value      jsonb       not null,
  updated_at timestamptz not null default now(),
  synced_at  timestamptz not null default now()
);

-- 3) Nhật ký thao tác
create table if not exists public.lab_audit (
  id         text primary key,
  data       jsonb       not null,
  created_at timestamptz not null default now()
);

-- synced_at luôn do server đặt
create or replace function public.lab_set_synced_at() returns trigger as $$
begin
  new.synced_at := now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_lab_records_synced on public.lab_records;
create trigger trg_lab_records_synced before insert or update on public.lab_records
  for each row execute function public.lab_set_synced_at();

drop trigger if exists trg_lab_settings_synced on public.lab_settings;
create trigger trg_lab_settings_synced before insert or update on public.lab_settings
  for each row execute function public.lab_set_synced_at();

create index if not exists lab_records_synced_idx on public.lab_records (synced_at);

-- 4) Row Level Security.
-- LƯU Ý BẢO MẬT: app hiện chưa dùng Supabase Auth (đăng nhập trong app chỉ là giao diện), nên
-- policy dưới đây cho phép MỌI người có publishable key đọc/ghi các bảng này. Chấp nhận được
-- khi thử nghiệm nội bộ; trước khi dùng thật cần chuyển sang Supabase Auth và siết policy
-- (VD: chỉ role authenticated, Inspector chỉ ghi phiếu, chỉ Admin ghi lab_settings).
alter table public.lab_records  enable row level security;
alter table public.lab_settings enable row level security;
alter table public.lab_audit    enable row level security;

drop policy if exists lab_records_all  on public.lab_records;
drop policy if exists lab_settings_all on public.lab_settings;
drop policy if exists lab_audit_all    on public.lab_audit;
create policy lab_records_all  on public.lab_records  for all to anon, authenticated using (true) with check (true);
create policy lab_settings_all on public.lab_settings for all to anon, authenticated using (true) with check (true);
create policy lab_audit_all    on public.lab_audit    for all to anon, authenticated using (true) with check (true);

-- 5) Kho ảnh đính kèm (bucket riêng tư)
insert into storage.buckets (id, name, public)
values ('lab-attachments', 'lab-attachments', false)
on conflict (id) do nothing;

drop policy if exists lab_attachments_all on storage.objects;
create policy lab_attachments_all on storage.objects for all to anon, authenticated
  using (bucket_id = 'lab-attachments') with check (bucket_id = 'lab-attachments');
