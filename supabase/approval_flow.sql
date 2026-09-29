-- Lab Record — Flow phê duyệt mở rộng (item 9, 2026-09-29):
--   Nháp → Chờ duyệt (pending) → Đã duyệt (approved)
--                              ↘ Trả lại sửa (returned, bắt buộc lý do) → Chỉnh sửa → Gửi duyệt lại
--
-- Chạy SAU schema.sql + auth.sql (+ users.sql nếu đã dùng). Thay THẾ trigger lab_records_guard cũ
-- (3 trạng thái approved/not_approved/rejected) bằng bản mới khớp 3 trạng thái pending/approved/returned
-- mà index.html hiện dùng. Chạy lại nhiều lần được (create or replace / drop trigger if exists).
--
-- CHƯA áp dụng lên project Supabase thật — người phụ trách tự chạy trong SQL Editor khi đã sẵn sàng.
-- Trước khi chạy: đọc kỹ phần "Đã biết / giới hạn" ở cuối file.

create or replace function public.lab_records_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  old_status text;
  new_status text;
  new_reason text;
  content_changed boolean;
begin
  -- Xoá phiếu: vẫn chỉ Supervisor trở lên (không đổi so với bản cũ).
  if new.deleted and public.lab_level() < 2 then
    raise exception 'Chỉ Supervisor trở lên được xoá phiếu';
  end if;

  new_status := new.data #>> '{approval,status}';
  new_reason := new.data #>> '{approval,reason}';

  if tg_op = 'UPDATE' then
    old_status := old.data #>> '{approval,status}';
    content_changed := (new.data - 'approval') is distinct from (old.data - 'approval');

    -- Khoá nội dung phiếu ĐÃ DUYỆT: không được sửa data mà vẫn giữ nguyên status='approved'.
    -- App luôn tạo phiên bản mới (id khác lưu bản đã duyệt cũ, "id sống" chuyển status về 'pending')
    -- nên write hợp lệ của app không bao giờ chạm rule này; rule này chỉ chặn ai đó bỏ qua app.
    if old_status = 'approved' and new_status = 'approved' and content_changed then
      raise exception 'Phiếu đã duyệt bị khoá nội dung — sửa phải tạo phiên bản mới (chuyển trạng thái khỏi approved)';
    end if;

    if (new.data -> 'approval') is distinct from (old.data -> 'approval') then
      if public.lab_level() < 2 then
        raise exception 'Chỉ Supervisor trở lên được thay đổi trạng thái phê duyệt';
      end if;
      if new_status = 'returned' and coalesce(btrim(new_reason), '') = '' then
        raise exception 'Trả lại phiếu phải có lý do';
      end if;
    end if;
  elsif tg_op = 'INSERT' then
    -- PostgREST upsert (Prefer: resolution=merge-duplicates -> INSERT ... ON CONFLICT DO UPDATE) có
    -- thể chạy qua nhánh INSERT khi id đã tồn tại (tuỳ phiên bản Postgres/kế hoạch truy vấn) — kiểm
    -- tra tối thiểu ở đây phòng trường hợp nhánh UPDATE phía trên không được thực thi cho ca đó.
    if new_status = 'returned' and coalesce(btrim(new_reason), '') = '' then
      raise exception 'Trả lại phiếu phải có lý do';
    end if;
    if new_status in ('approved', 'returned') and public.lab_level() < 2 then
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
-- 1) Tương thích ngược: các phiếu cũ có approval.status = approved/not_approved/rejected (3 trạng thái
--    trước đây) KHÔNG bị sửa lại — trigger này chỉ diễn giải status theo đúng giá trị đang lưu; app
--    (LEGACY_APPROVAL_MAP trong index.html) mới là nơi ánh xạ not_approved->pending, rejected->returned
--    khi ĐỌC để hiển thị. Vì trigger so khớp chuỗi 'approved'/'returned' theo nghĩa MỚI, 1 phiếu cũ có
--    status='rejected' vẫn được xem là "không phải approved" ở DB (không bị khoá nội dung) — đúng ý vì
--    'rejected' cũ tương đương 'returned' mới (được sửa tiếp), không phải 'approved'.
-- 2) Trigger dùng security definer + lab_level() nên áp dụng cho MỌI request qua PostgREST bất kể UI ẩn
--    nút gì — đúng yêu cầu "kiểm soát ở phía Supabase, không chỉ ẩn nút trên UI".
-- 3) Đồng bộ 2 máy cùng lúc: LWW theo meta.updatedAt (xem Sync.pull trong index.html) — nếu máy A đang
--    offline sửa 1 phiếu TRƯỚC KHI biết nó vừa được duyệt ở máy B, khi A lên mạng và đẩy bản cũ lên,
--    trigger này CHẶN thẳng (vì server đã có status='approved' còn bản A gửi lên đổi content mà vẫn
--    ghi approved) — Sync.flush() hiện coi lỗi 4xx là "bị từ chối vĩnh viễn" và bỏ mục đó khỏi hàng đợi
--    (không tự động thử lại vô hạn), nhưng CŨNG không tự dựng lại UI cho máy A biết cần vào sửa lại từ
--    bản mới nhất — máy A cần vào lại tab Lịch sử để thấy bản đã duyệt & tự tạo phiên bản mới. Đây là
--    giới hạn đã biết của kiến trúc offline-first hiện tại, chưa có cơ chế thông báo xung đột chủ động.
