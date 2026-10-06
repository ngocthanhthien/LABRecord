-- Lab Record — quyền ghi danh mục (lab_settings) sau khi tab Parameters mở cho Supervisor (2026-10-06).
-- Chạy SAU auth.sql. Chạy lại nhiều lần được. CHƯA áp dụng lên project Supabase thật — tự chạy trong SQL Editor khi sẵn sàng.
--
-- Thay đổi so với auth.sql: khoá `fieldMapping` (bảng Parameters) cho phép Supervisor trở lên GHI (trước đây chỉ Admin), vì
-- tab Parameters nay hiện cho Supervisor sửa "Chỉ tiêu"/"Trường" của dòng người dùng tự nhập. Khoá `staff` vẫn chỉ Admin.
-- Item Code / Spec / Độ lặp lại (itemCodes / thresholds / repeatability) vẫn từ Supervisor — dùng cho nhập Item Code bằng Excel.

drop policy if exists lab_settings_write on public.lab_settings;
drop policy if exists lab_settings_upd   on public.lab_settings;
create policy lab_settings_write on public.lab_settings for insert to authenticated with check (
  (key in ('thresholds', 'itemCodes', 'repeatability', 'fieldMapping') and public.lab_level() >= 2) or
  (key in ('staff') and public.lab_level() >= 3));
create policy lab_settings_upd on public.lab_settings for update to authenticated using (
  (key in ('thresholds', 'itemCodes', 'repeatability', 'fieldMapping') and public.lab_level() >= 2) or
  (key in ('staff') and public.lab_level() >= 3)) with check (
  (key in ('thresholds', 'itemCodes', 'repeatability', 'fieldMapping') and public.lab_level() >= 2) or
  (key in ('staff') and public.lab_level() >= 3));

-- Giới hạn: RLS chỉ phân quyền theo KHOÁ (cả mảng fieldMapping). Việc "chỉ sửa dòng do người dùng tự nhập (origin = 'user')" được
-- kiểm ở giao diện (index.html) — máy chủ không phân biệt từng dòng trong mảng JSON.
