-- Lab Record — quyền ghi danh mục (lab_settings) theo file "Quản lý người dùng.xlsx" (2026-10-06).
-- Chạy SAU auth.sql. Chạy lại nhiều lần được. CHƯA áp dụng lên project Supabase thật — tự chạy trong SQL Editor khi sẵn sàng.
--
-- Ma trận (khớp giao diện index.html — applyRolePermissions):
--   * itemCodes (tab Item Code): MỌI vai trò đã đăng nhập có hồ sơ (Inspector/Supervisor/Admin) được thêm/sửa/xoá — gồm nhập từ Excel.
--   * thresholds (Spec), repeatability (Độ lặp lại), fieldMapping (Parameter), staff: CHỈ Admin ghi. Supervisor chỉ xem.
--   * Đọc: mọi vai trò (như auth.sql).
-- Khác auth.sql: itemCodes hạ từ Supervisor xuống Inspector; thresholds/repeatability nâng từ Supervisor lên Admin.

drop policy if exists lab_settings_write on public.lab_settings;
drop policy if exists lab_settings_upd   on public.lab_settings;
drop policy if exists lab_settings_del   on public.lab_settings;
create policy lab_settings_write on public.lab_settings for insert to authenticated with check (
  (key = 'itemCodes' and public.lab_level() >= 1) or
  (key in ('thresholds', 'repeatability', 'fieldMapping', 'staff') and public.lab_level() >= 3));
create policy lab_settings_upd on public.lab_settings for update to authenticated using (
  (key = 'itemCodes' and public.lab_level() >= 1) or
  (key in ('thresholds', 'repeatability', 'fieldMapping', 'staff') and public.lab_level() >= 3)) with check (
  (key = 'itemCodes' and public.lab_level() >= 1) or
  (key in ('thresholds', 'repeatability', 'fieldMapping', 'staff') and public.lab_level() >= 3));
create policy lab_settings_del on public.lab_settings for delete to authenticated using (public.lab_level() = 3);

-- Giới hạn: RLS phân quyền theo KHOÁ (cả mảng JSON), không phân biệt từng dòng. Quy tắc "chỉ sửa dòng Parameter do người dùng tự
-- nhập (origin = 'user')" chỉ ở giao diện. Phiếu (lab_records) do trigger trong approval_flow.sql.
