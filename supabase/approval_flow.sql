-- Lab Record — Flow phê duyệt mở rộng + quyền sửa phiếu đã lưu (cập nhật 2026-10-06):
--   Nháp → Chờ duyệt (pending) → Đã duyệt (approved)
--                              ↘ Trả lại sửa (returned, bắt buộc lý do) → Chỉnh sửa → Gửi duyệt lại
--
-- Chạy SAU schema.sql + auth.sql (+ users.sql nếu đã dùng). Thay THẾ trigger lab_records_guard cũ
-- bằng bản khớp 3 trạng thái pending/approved/returned mà index.html hiện dùng. Chạy lại nhiều lần được.
--
-- Quyền (khớp UI trong index.html — canEditSavedRecord / approveRecord / returnRecordForEdit):
--   * Xoá phiếu, đổi trạng thái phê duyệt (duyệt / trả lại): Supervisor trở lên.
--   * Sửa NỘI DUNG phiếu đã lưu ở trạng thái chờ duyệt / đã duyệt: Supervisor trở lên.
--     (Phiếu đã duyệt: app tạo phiên bản mới — id "sống" chuyển về pending, bản đã duyệt lưu ở id khác.)
--   * Inspector: sửa phiếu nháp / chưa có trạng thái; sửa phiếu bị TRẢ LẠI và gửi duyệt lại (returned -> pending, chỉ chuyển này).
--   * Không ai được sửa nội dung 1 phiếu vẫn giữ status = approved.
--
-- CHƯA áp dụng lên project Supabase thật — người phụ trách tự chạy trong SQL Editor khi đã sẵn sàng.
-- Trước khi chạy: đọc kỹ phần "Đã biết / giới hạn" ở cuối file.

create or replace function public.lab_records_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  lvl int := public.lab_level();
  old_status text;
  new_status text;
  new_reason text;
  content_changed boolean;
begin
  -- Xoá phiếu: chỉ Supervisor trở lên.
  if new.deleted and lvl < 2 then
    raise exception 'Chỉ Supervisor trở lên được xoá phiếu';
  end if;

  new_status := new.data #>> '{approval,status}';
  new_reason := new.data #>> '{approval,reason}';

  if tg_op = 'UPDATE' then
    old_status := old.data #>> '{approval,status}';
    -- Nội dung = mọi thứ trừ trạng thái phê duyệt và nhật ký chỉnh sửa (edits).
    content_changed := (new.data - 'approval' - 'edits') is distinct from (old.data - 'approval' - 'edits');

    -- Khoá nội dung phiếu ĐÃ DUYỆT: không được sửa data mà vẫn giữ nguyên status='approved'.
    if old_status = 'approved' and new_status = 'approved' and content_changed then
      raise exception 'Phiếu đã duyệt bị khoá nội dung — sửa phải tạo phiên bản mới (chuyển trạng thái khỏi approved)';
    end if;

    -- Inspector không sửa nội dung phiếu đã lưu ở trạng thái chờ duyệt / đã duyệt.
    if lvl < 2 and old_status in ('pending', 'approved') and content_changed then
      raise exception 'Chỉ Supervisor trở lên được sửa phiếu đã lưu (chờ duyệt / đã duyệt)';
    end if;

    if (new.data -> 'approval') is distinct from (old.data -> 'approval') then
      if lvl >= 2 then
        if new_status = 'returned' and coalesce(btrim(new_reason), '') = '' then
          raise exception 'Trả lại phiếu phải có lý do';
        end if;
      else
        -- Inspector chỉ được gửi duyệt lại phiếu đã bị trả lại (returned/rejected cũ -> pending).
        if not (old_status in ('returned', 'rejected') and new_status = 'pending') then
          raise exception 'Chỉ Supervisor trở lên được thay đổi trạng thái phê duyệt (Inspector chỉ gửi duyệt lại phiếu bị trả)';
        end if;
      end if;
    end if;
  elsif tg_op = 'INSERT' then
    -- PostgREST upsert (Prefer: resolution=merge-duplicates -> INSERT ... ON CONFLICT DO UPDATE): Postgres chạy trigger INSERT
    -- cho dòng đề xuất rồi (nếu trùng id) chạy tiếp trigger UPDATE ở trên với OLD = dòng hiện có; kiểm tra tối thiểu ở đây
    -- cho phiếu mới và bản lưu trữ phiên bản đã duyệt.
    if new_status = 'returned' and coalesce(btrim(new_reason), '') = '' then
      raise exception 'Trả lại phiếu phải có lý do';
    end if;
    if new_status in ('approved', 'returned') and lvl < 2 then
      raise exception 'Chỉ Supervisor trở lên được thay đổi trạng thái phê duyệt';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_lab_records_guard on public.lab_records;
create trigger trg_lab_records_guard before insert or update on public.lab_records
  for each row execute function public.lab_records_guard();

-- Đã biết / giới hạn:
-- 1) Tương thích ngược: phiếu cũ có approval.status = approved/not_approved/rejected KHÔNG bị sửa lại; app (LEGACY_APPROVAL_MAP)
--    ánh xạ khi ĐỌC (not_approved->pending, rejected->returned). Trigger coi 'rejected' cũ như 'returned' khi Inspector gửi lại.
--    Phiếu cũ có status 'not_approved' được hiểu là "chờ duyệt" ở UI nhưng trigger KHÔNG coi là pending -> Inspector vẫn sửa được
--    phiếu 'not_approved' cũ ở máy chủ (UI đã chặn). Muốn chặt hơn, chạy 1 lần:
--      update public.lab_records set data = jsonb_set(data, '{approval,status}', '"pending"') where data #>> '{approval,status}' = 'not_approved';
--    (CHƯA chạy — đổi dữ liệu lịch sử cần bạn quyết định.)
-- 2) Trigger security definer + lab_level() áp dụng cho MỌI request qua PostgREST bất kể UI ẩn nút gì.
-- 3) Đồng bộ 2 máy: Last-Write-Wins theo meta.updatedAt. Nếu máy A offline sửa 1 phiếu rồi lên mạng khi server đã duyệt phiếu đó,
--    trigger từ chối (4xx) -> Sync.flush bỏ mục đó khỏi hàng đợi và báo lỗi ở header; chưa có thông báo xung đột chủ động.
-- 4) Quyền ghi danh mục Parameters (settings.fieldMapping) cho Supervisor nằm ở file permissions_matrix.sql.
