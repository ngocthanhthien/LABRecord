# Lab Record – ILD Coffee — Handoff Document

**Cập nhật:** 2026-10-05 (đợt "On going" Excel dòng 10/12/13/20 — mục 10; trước đó: mục 8 sửa theo Excel, mục 9 rebrand ILD Crafted + Theme)
**Vị trí dự án:** `C:\Users\BinhDang\Documents\GitHub\LABRecord` (git repo; trước đây ở `C:\Apps\Q - LAB RECORD`, đã chuyển)
**Trạng thái:** Đã hỗ trợ nhiều LOẠI SẢN PHẨM (Powder / Coffee Oil / Liquid) theo kiến trúc cấu hình (mục 3.6). Powder chạy đầy đủ và cho kết quả trùng bản cũ; Coffee Oil và Liquid mới có khung, chưa có trường/chỉ tiêu. Ứng dụng chạy được đầy đủ (Phần 1-5 kế hoạch gốc + 13 mục hiệu chỉnh vòng 2 + tab Độ lặp lại cho thêm/xoá chỉ tiêu). Còn vài giả định nghiệp vụ cần QA xác nhận (mục 5).

Tài liệu này viết cho AI/dev khác tiếp nhận dự án mà không có lịch sử hội thoại. Đọc trước khi sửa code.

---

## 1. Ứng dụng là gì

Web app nội bộ (offline-first) cho phòng QA/Lab của ILD Coffee Vietnam:
- Nhập kết quả phân tích hóa lý cà phê hòa tan (9 chỉ tiêu: Độ ẩm, Tỷ trọng, Độ màu, Độ cặn, pH, Acidity, Độ hòa tan, Kích thước hạt, Ngoại vật)
- Tự động so ngưỡng, kết luận Đạt/Không đạt
- Lưu bền, tra cứu lịch sử, xuất CSV/PDF, backup/restore JSON
- Phân quyền 3 cấp: Inspector / Supervisor / Admin

**Toàn bộ ứng dụng là 1 file `index.html`** (~198KB, ~3560 dòng): HTML + CSS + JavaScript + dữ liệu danh mục đều nhúng trong file. Mở trực tiếp bằng trình duyệt là chạy — không server, không internet, không Node/npm, không build step. Lý do: người dùng cần gửi file cho đồng nghiệp xem/dùng offline.

---

## 2. Nội dung thư mục hiện tại

```
LABRecord/
├── index.html    ← TOÀN BỘ ỨNG DỤNG (sửa file này)
├── HANDOFF.md    ← file này
└── .git/
```

**Đã KHÔNG còn trong thư mục mới (chỉ có ở thư mục cũ `C:\Apps\Q - LAB RECORD`, nếu còn):**
- 4 file Excel nguồn (Result Form, Field Mapping, ITEM CODE, Thông tin kết luận) — dữ liệu đã trích xuất và nhúng cứng vào `index.html` từ đầu; không cần để chạy app. Chỉ dùng khi cần đối chiếu nghiệp vụ gốc.
- `sample-record.json` — ví dụ 1 bản ghi JSON đầy đủ (không được app đọc). Schema thực tế xem hàm `buildFullRecord()` trong `index.html`.
- `html-app-architect.skill` — skill Claude Code dùng định hướng quy trình xây dựng (khảo sát → kiến trúc → code theo phần), không ảnh hưởng runtime.
- `.claude/launch.json` — cấu hình chạy preview `python -m http.server 8765`; nếu dùng Claude Code Browser tool ở thư mục mới cần tạo lại (xem mục 6).

Sửa danh mục (mã hàng/ngưỡng/field mapping) nên làm **qua giao diện app** (tab Item Code / Spec. / Parameters — tự lưu vào IndexedDB), không cần sửa Excel rồi trích xuất lại.

---

## 3. Kiến trúc kỹ thuật

### 3.1. Vị trí các khối trong `index.html`
- `<style>` … `</style>`: dòng ~7–693. CSS dùng biến (`:root { --bg; --surface; --text; ... }`), Dark mode qua `:root[data-theme="dark"]`.
- Thân HTML: dòng ~694–1558 — Header, thanh tab ngang (Sidebar), 9 khối chỉ tiêu trong form Nhập liệu, các panel quản trị, Modal dùng chung, màn đăng nhập (`#login-overlay`), khu vực in (`#print-area`).
- `<script>` … `</script>`: dòng ~1559–3557. Toàn bộ JS, global scope, không module/import; chia theo comment `/* ---------------- TÊN MODULE ---------------- */`.

Số dòng sẽ lệch khi sửa code — dùng search theo tên hàm/comment.

### 3.2. Không dùng framework/thư viện ngoài
Vanilla HTML/CSS/JS. Thêm thư viện ngoài sẽ phá tính "1 file mở là chạy" trừ khi nhúng thẳng code thư viện vào file.

### 3.3. Lưu trữ dữ liệu (quan trọng nhất)
Module `Storage` (IIFE, search `const Storage = (function ()`):
- Ưu tiên **IndexedDB** (db `lab_record_db`, store: `records`, `attachments`, `settings`, `auditLog`).
- Tự **fallback sang `localStorage`** nếu IndexedDB không mở được (dễ xảy ra khi mở bằng `file://`). Fallback không lưu được ảnh (Blob).
- `Storage.mode()` cho biết chế độ đang dùng; hiển thị ở tab Cài đặt.
- **Chưa từng được test bằng double-click mở `file://` thật** (công cụ trình duyệt của Claude Code không chạy JS trên `file://` ngoài thư mục project). Việc đầu tiên nên làm: mở thật bằng file://, F12 xem Console, xác nhận `Storage.mode()`.

Master data là biến JS top-level, seed cứng trong code, rồi bị **nạp đè bởi bản đã lưu trong Storage** khi khởi động (`loadMasterDataFromDb()`):

| Biến | Ý nghĩa | Key trong Storage `settings` |
|---|---|---|
| `ITEM_CODES` | 239 mã hàng {item, name, recipe} | `itemCodes` |
| `THRESHOLDS` | 23 dòng ngưỡng {customer, parameter, unit, requirement, recipe} (từ Sheet1 file "Thông tin kết luận") | `thresholds` |
| `FIELD_MAPPING` | 76 dòng field dictionary {parameter, field, format, type, remark} | `fieldMapping` |
| `STAFF` | 6 tên nhân viên thực hiện phép đo | `staff` |
| `USERS` | tài khoản đăng nhập {name, password, role} | `users` |
| `REPEATABILITY` | dung sai tối đa giữa 2 lần đo {parameter, unit, maxDiff} | `repeatability` |

**Bẫy hay gặp:** nếu sửa seed trong code mà máy đó từng mở app, Storage sẽ nạp đè lại bản cũ → không thấy thay đổi. Cần xoá IndexedDB/localStorage của origin (DevTools → Application → Storage → Clear site data).

Phiếu đã lưu (`records`) theo schema lồng nhau: `sampleInfo`, `parameters.{doAm,tyTrong,doMau,doCan,ph,acidity,hoaTan,kichThuoc,ngoaiVat}` (mỗi khối có reps/average/difference/range/status/enteredAt; Độ cặn & Ngoại vật có `attachments[]`), `notes`, `conclusion`, `reviewedBy`, `reviewedDate`, `meta`, `forcedClose`. Xem `buildFullRecord()`.

### 3.4. Đăng nhập / phân quyền
- **Hiện đang TẮT rào cản đăng nhập** (theo yêu cầu người dùng, để hoàn thiện tính năng trước): `CONFIG.loginRequired = false` trong `index.html` → app tự vào bằng tài khoản `CONFIG.autoLoginUser` (`Admin`) nên thấy đủ tab, không hiện nút Đăng xuất. Toàn bộ code đăng nhập/phân quyền vẫn nguyên; muốn bật lại chỉ cần đặt `loginRequired: true`. **Trước khi giao dùng thật phải bật lại và đổi mật khẩu mặc định.**
- `#login-overlay` tách riêng khỏi `Modal` (không tắt được bằng X/click ngoài).
- Phiên lưu ở `sessionStorage` key `labrecord_session` → mất khi đóng tab, giữ khi F5.
- **KHÔNG phải bảo mật thật**: mật khẩu là chuỗi thường, không hash, không backend. Chỉ để phân biệt người dùng trên máy dùng chung. Ẩn/hiện tab theo quyền chỉ là `element.hidden` — bypass được bằng DevTools. Đừng "vá bảo mật" như thể đây là yêu cầu bảo mật thật; muốn bảo mật thật cần backend.
- `ROLES`: `inspector`(1) < `supervisor`(2) < `admin`(3); hàm `hasRole(minRole)`.
- Ma trận quyền: Inspector → Tổng quan / Nhập liệu / Lịch sử / Hướng dẫn. Supervisor thêm → Item Code / Spec. / Độ lặp lại + nút Xoá phiếu. Admin thêm → Parameters / Cài đặt (gồm Quản lý người dùng). Nút Force đóng Report: ai cũng dùng được. `reviewedBy` chỉ chọn được Supervisor/Admin.
- Tài khoản mặc định (**đổi trước khi dùng thật**, ở Cài đặt → Quản lý người dùng):

  | Tên | Mật khẩu | Vai trò |
  |---|---|---|
  | Trân, Huy, Hiền, Định, Trang, Triều | `1234` | inspector |
  | Supervisor | `sup1234` | supervisor |
  | Admin | `admin1234` | admin |

### 3.5. Luồng nhập liệu chính
(Các bước dưới mô tả form Powder; hàm và tên trường vẫn đúng nhưng form nay được dựng bởi Form Engine — mục 3.6.)
1. `itemCode` đổi → `onItemCodeChange()` → tra `ITEM_CODES` → điền Recipe/Product Name → `updateThresholdsForCustomer()`.
2. `batch` đổi → `onBatchChange()` → `productionDateFromBatch()` (ký tự vị trí 2-3-4 của Batch = ngày Julian, năm = năm hiện tại) → Ngày sản xuất.
3. `po` đổi → `onPoChange()` → gợi ý SSCC = PO + "000" (người dùng gõ tiếp 3 số cuối).
4. `customer` đổi → `updateThresholdsForCustomer()` → `getThreshold()` (ưu tiên theo dải Recipe khi có nhiều dòng) → `state.currentThresholds` → `recomputeAll()`.
5. Mọi input/select trong `#analysis-form` → `recomputeAll()` → 9 hàm `computeDoAm/TyTrong/DoMau/DoCan/Ph/Acidity/HoaTan/KichThuoc/NgoaiVat()` (tính TB, sai khác, so ngưỡng, badge `pass/fail/accept/pending`, cảnh báo Độ lặp lại qua `applyRepeatabilityWarn()`) → `recomputeConclusion()` → `calcCompletion()` (% hoàn thành).
6. Cùng listener stamp `state.blockEnteredAt[1-9]` lần đầu có input trong mỗi khối.
7. Lưu nháp / Lưu phiếu (`submitRecord(false)`) / Force đóng Report (`submitRecord(true)`) → `buildFullRecord()` → `Storage.put('records', …)`.
8. Auto Save mỗi 20s (khi ở tab Nhập liệu) ghi vào bản ghi cố định `draft_current` — khác "Lưu nháp" (tạo bản ghi nháp id riêng, hiện trong Lịch sử). Mở lại app → `checkAutoRecovery()` hỏi khôi phục. Chỉ chạy SAU khi đăng nhập.

### 3.6. Loại sản phẩm + Form Engine (quan trọng — đọc trước khi sửa form)

Form Nhập liệu KHÔNG còn là HTML viết cứng. Ở tab Nhập liệu người dùng chọn **Loại sản phẩm** (`#form-product-type`), form được dựng động từ cấu hình `TYPE_CONFIG[type]` (search `const TYPE_CONFIG`):
- `sampleFields`: các trường "Thông tin mẫu" của loại đó (mỗi loại KHÁC nhau). Trường có thể mang hành vi tự động: `behavior:'itemLookup'` (tra Item Code → Recipe/Product Name), `'julianBatch'` (ngày SX từ Batch), `'ssccFromPo'` (gợi ý SSCC từ PO); `thresholdKey:true` = trường dùng để tra ngưỡng (Customer); `required:true` = bắt buộc khi lưu.
- `blocks`: danh sách khối chỉ tiêu. Mỗi khối có `kind` trỏ tới `BLOCK_KINDS`: `pair` (2 lần đo số → TB/sai khác/so ngưỡng/cảnh báo độ lặp lại; cột kết quả có thể `input:'computed'` với `formula`), `single` (1 nhóm trường + kết quả số hoặc lựa chọn, tuỳ chọn ảnh; `evaluate:'numericRange'|'absentPresent'`), `hotCold` (nhiều dòng như Nóng/Lạnh, tất cả phải V), `sieve` (bảng rây). Mỗi kiểu khối có 4 hàm: `html`, `compute`, `collect`, `apply`.
- **Thêm chỉ tiêu/loại mới = thêm cấu hình**, chỉ cần viết kiểu khối mới khi có cách đo hoàn toàn khác. Tên input trong DOM = `prefix_rep_key` (VD `do_am_1_ket_qua`); khoá bản ghi giữ nguyên schema cũ (`doAm`, `reps`, `average`... xem `buildFullRecord`).
- `renderFormForType(type)` dựng lại form (dùng cho đổi loại, Phiếu mới, reset, nạp bản nháp/phục hồi). Đổi loại khi đang có dữ liệu sẽ hỏi xác nhận rồi xoá form.
- **Coffee Oil và Liquid hiện có `sampleFields: []`, `blocks: []`** → form hiện thông báo "chưa được cấu hình", nút lưu bị chặn. Giai đoạn 3 (chưa làm, đang chờ người dùng cung cấp danh sách trường thông tin mẫu, chỉ tiêu, công thức, ngưỡng, dung sai của 2 loại này): điền cấu hình vào `TYPE_CONFIG.coffeeOil / liquid`.
- **Dữ liệu theo loại:** mọi dòng của `ITEM_CODES`, `THRESHOLDS`, `FIELD_MAPPING`, `REPEATABILITY` và mỗi phiếu có trường `productType`. Dữ liệu cũ thiếu trường này được gán `powder` khi nạp (`migrateProductTypes()`, `loadRecordsCache()`, khi import backup). Các tab Item Code / Spec. / Parameters / Độ lặp lại có ô "Loại sản phẩm" (`state.adminType`) chỉ hiện và sửa dòng của loại đang chọn; Spec. và Parameters cho phép thêm/xoá dòng (Customer, Chỉ tiêu nhập tự do có gợi ý). `getThreshold(type, customer, label, recipe)`, `findItemByCodeIn(type, code)`, `getMaxDiff()` đều lọc theo loại. Lịch sử và Dashboard có bộ lọc loại; CSV/Full Report/chi tiết phiếu có thông tin loại và dựng theo `orderedParams(record)`.
- Quy tắc riêng của Powder (Item Code lấy Recipe, ngày Julian từ Batch, SSCC từ PO) chỉ áp dụng khi cấu hình loại đó bật hành vi tương ứng; Oil/Liquid không bị áp dụng mặc định.

---

## 4. Tính năng đã hoàn thành

- **Phần 1–5 gốc:** khung HTML; logic tính toán/điều hướng; IndexedDB + fallback, Auto Save/Recovery, Backup/Restore JSON, xuất CSV; Dark mode, responsive, animation; validation (Item Code tồn tại, định dạng Batch, trùng Batch, ảnh ≤5MB, try/catch quanh Storage).
- **13 mục vòng 2:** (1) thanh tab ngang; (2) Item Code & PO dạng số; (3) tab Item Code (CRUD); (4) SSCC gợi ý từ PO; (5) tab Độ lặp lại, lệch quá → cảnh báo đỏ (không đổi Kết luận); (6) bỏ ảnh "Vị trí dán mẫu cặn" trùng ở Độ màu; (8) Full Report PDF riêng; (9) đa ảnh cộng dồn + thư viện xem trước; (10) timestamp nhập theo khối; (11) thanh % hoàn thành; (12) Force đóng Report (đánh dấu "⚠ Force"); (13) đăng nhập + phân quyền. *(Người dùng không đánh số 7 — không phải thiếu sót.)*
- **Sau vòng 2:** tab Độ lặp lại cho **thêm/xoá chỉ tiêu** (`btn-add-repeat`, `renderRepeatabilityTable()`). Lưu ý: cảnh báo đỏ tự động chỉ hoạt động với 5 chỉ tiêu có 2 lần đo trong form (Độ ẩm, Tỷ trọng, Độ màu, pH, Acidity); chỉ tiêu gõ tự do chỉ được lưu trong bảng, chưa có ô nhập tương ứng trong form.
- **Đồng bộ Supabase (offline-first):** `CONFIG.supabase` {url, key(publishable), enabled}; module `Sync` (search `const Sync = (function`) dùng `fetch` tới PostgREST, không SDK. Ghi/xoá cục bộ vào hàng đợi (localStorage `labrecord_syncq`) rồi đẩy lên bảng `lab_records` / `lab_settings` / `lab_audit` và bucket `lab-attachments` (schema + RLS trong `supabase/schema.sql`, **phải chạy 1 lần trong SQL Editor — key publishable không tạo được bảng**). Kéo về khi khởi động, mỗi 60s, khi có mạng lại, khi tab hiện lại, hoặc bấm "Đồng bộ ngay" (Cài đặt). Phiếu: bản `meta.updatedAt` mới hơn thắng, xoá = tombstone `deleted=true`; danh mục: ghi đè cả tài liệu, mới hơn thắng (2 máy cùng sửa 1 danh mục → mất một bên). `Storage.put/delete` được bọc để tự vào hàng đợi; `Storage.raw.*` ghi cục bộ không đồng bộ (dùng khi kéo). KHÔNG đồng bộ `users` (mật khẩu chữ thường), `theme`, `draft_current`. **Bảo mật:** `schema.sql` tạo policy mở cho mọi người có publishable key — `auth.sql` thay bằng policy theo vai trò (xem mục Đăng nhập thật). Đã test logic bằng server giả lập (đẩy lần đầu, kéo phiếu/ngưỡng từ máy khác, tombstone hai chiều) và xác nhận app vẫn chạy khi chưa có bảng; đã chạy `schema.sql` và test trên Supabase thật (2026-09-25): bảng, trigger `synced_at`, upload ảnh; app đẩy phiếu Force lên, một "máy thứ hai" (origin khác, IndexedDB trống) kéo về đúng, duyệt Approve ở máy 2 sang máy 1, xoá phiếu lan qua tombstone; dữ liệu thử đã được xoá sạch khỏi project. Chưa test: kéo/hiển thị ảnh đính kèm về máy khác (hiện chỉ đẩy lên bucket, app chưa hiển thị ảnh), 2 máy sửa cùng danh mục đồng thời.
- **Đăng nhập thật (Supabase Auth):** `CONFIG.supabase.auth = true` → overlay đăng nhập dùng email + mật khẩu (`Auth` module, `/auth/v1/token`), token dùng cho mọi request Supabase (tự refresh), phiên lưu `localStorage['labrecord_auth']`; vai trò lấy từ bảng `profiles` (`role` inspector/supervisor/admin), `Auth.validate()` kiểm tra lại phiên khi mở app (thu hồi/hết hạn → bắt đăng nhập lại; offline → giữ phiên). Quyền THẬT do RLS + trigger trong `supabase/auth.sql` quyết định (chạy SAU `schema.sql`): mọi vai trò đọc/ghi phiếu; Inspector không được đổi phê duyệt hoặc xoá phiếu (trigger `lab_records_guard`); ghi `thresholds/itemCodes/repeatability` từ Supervisor, `staff/fieldMapping` chỉ Admin; `lab_audit` xem từ Supervisor; ảnh chỉ người có hồ sơ. `binh.dang@ild-coffee.com` = Admin; user mới tạo ở Dashboard tự có hồ sơ inspector, Admin đổi vai trò ở Cài đặt → Quản lý người dùng. Đặt `auth:false` để quay về đăng nhập cục bộ. Hàng đợi đồng bộ bỏ qua (không chặn) mục bị server từ chối 4xx và báo lỗi ở header. **Phải TẮT "Allow anonymous sign-ins"** trong Supabase. Đã test: sai mật khẩu bị từ chối bởi Supabase thật; đăng nhập thành công/phân quyền UI/Bearer token/xử lý từ chối bằng server giả lập. **Chưa test với tài khoản thật và với RLS thật (cần chạy `auth.sql` và có mật khẩu).**
- **Tab Người dùng (Admin, mô phỏng app CloseCAPGMP):** danh sách / thêm người dùng / đổi vai trò / vô hiệu hoá–kích hoạt (`renderUsersTab`, `openUserAddModal`). Chế độ Supabase gọi Edge Function `admin-users` (`supabase/functions/admin-users/index.ts`, dùng service_role trên server, kiểm tra người gọi là Admin; upsert `profiles`, ghi `lab_audit`; chặn tự hạ quyền Admin duy nhất/tự khoá mình). Đăng nhập nhận email HOẶC tên đăng nhập (tên → email nội bộ `<tên>@<projectref>.users.internal`, `Auth.toEmail` phải khớp function). `supabase/users.sql` thêm cột `profiles.disabled/username` và cho `lab_level()` trả 0 với tài khoản bị khoá. Chế độ cục bộ (`auth:false`) thao tác trên `USERS`. Card "Quản lý người dùng" cũ ở Cài đặt đã bỏ. Hướng dẫn deploy: `supabase/README.md`. **Function chưa được deploy/test trên Supabase thật** (mới test giao diện với server giả lập).
- **Tab Data Log (Supervisor+):** bảng ai / máy nào / lúc nào / hành động / chi tiết cho mọi thao tác ghi bởi `AuditLog.log` (lưu phiếu, Force, xoá, phê duyệt, đăng nhập, sửa Spec/Parameters/độ lặp lại/mã hàng, người dùng...). Mỗi dòng có `device` (tên máy tự đặt trong tab, mã máy `labrecord_device_id` trong localStorage — `Device`). Khi đã đăng nhập Supabase, nút Tải lại gộp thêm log của các máy khác từ `lab_audit` (RLS chỉ cho Supervisor trở lên đọc; log tạo/khoá user từ Edge Function được chuẩn hoá tên hành động). Có lọc (tìm chữ, hành động, người, khoảng ngày), tối đa 500 dòng hiển thị, xuất CSV. Log cũ trước khi có tính năng không có cột Máy.
- **Phê duyệt phiếu:** cột "Phê duyệt" ở Lịch sử với 3 trạng thái Approve / Not Approve / Reject (`record.approval = {status:'approved'|'not_approved'|'rejected', by, at}`; thiếu trường = Not Approve; phiếu nháp không duyệt được). Chỉ `hasRole('supervisor')` (Supervisor và Admin) mới đổi được — nút nằm trong modal chi tiết phiếu (`setApproval()`); Inspector chỉ xem. Có bộ lọc theo trạng thái, xuất CSV/Full Report/chi tiết phiếu, ghi Audit Log. Chưa có ô nhập lý do khi Reject.
- **Loại sản phẩm (Giai đoạn 1+2 xong):** chọn loại ở đầu phiếu; cấu hình Spec./Độ lặp lại/Parameters/Item Code theo loại; Powder được chuyển sang cấu hình và kiểm chứng trùng số liệu bản cũ (Độ ẩm 2.25/0.04, Tỷ trọng 234.10, Acidity 4.14, sàng <0.5mm 0.12%, sau sàng 100.42g, lưu → nạp lại cho bản ghi giống hệt). **Giai đoạn 3 (Oil/Liquid) đang chờ dữ liệu từ người dùng.**
- **Đang dở (cũ):** người dùng vừa nhắn "Tại tab độ lặp lại. Cho phép chèn thêm chỉ tiêu mới &" — tin nhắn bị cắt ở dấu "&". Phần "thêm chỉ tiêu" đã làm; phần sau dấu "&" (có thể là sửa đơn vị/đổi tên chỉ tiêu trực tiếp trong bảng) chưa rõ — hỏi lại người dùng.

---

## 5. Giả định nghiệp vụ CHƯA được QA xác nhận

1. **Khớp ngưỡng theo dải Recipe** (`getThreshold()`): khi một chỉ tiêu (Độ màu, Tỷ trọng-LDC) có nhiều dòng ngưỡng theo dải Recipe ("30/35/40" vs "45/50" vs "55"), code so 2 ký tự số đầu của Recipe. Khớp ví dụ đã biết (Recipe 452 → Max 88) nhưng chưa chắc đúng mọi trường hợp; nhánh "Low Density" của Tỷ trọng-LDC không khớp được theo cách này, rơi về dòng đầu tiên.
2. **Ngoại vật:** đơn giản hoá Absent = Đạt / Present = Không đạt. Quy tắc gốc (tối đa 10 hạt <1mm, tối đa 1 hạt >1mm) chưa implement.
3. **`REPEATABILITY`:** 5 giá trị mặc định (0.1 / 5 / 1 / 0.05 / 0.05) là ước lượng, không phải số liệu chính thức — Supervisor cần sửa ở tab Độ lặp lại.
4. **Quyền Xoá phiếu = Supervisor+:** lựa chọn mặc định tự đặt, người dùng chỉ xác nhận riêng cho quyền Force.
5. **PO không tự sinh** (chỉ SSCC gợi ý từ PO); PO nhập tay.
6. Nếu một chỉ tiêu có `Kết luận` còn `pending` (chưa đủ 9 chỉ tiêu) thì "Lưu phiếu" bị chặn, phải dùng Force.

---

## 6. Chạy / test

Không cần cài đặt.

**A. Mở trực tiếp:** double-click `index.html` (Chrome/Edge).

**B. Qua local server (khuyên dùng khi dev để chắc IndexedDB chạy đúng chế độ chính):**
```bash
cd C:\Users\BinhDang\Documents\GitHub\LABRecord
python -m http.server 8765
# mở http://localhost:8765
```
Nếu dùng Claude Code Browser tool, tạo `.claude/launch.json`:
```json
{ "version": "0.0.1", "configurations": [
  { "name": "lab-record-static", "runtimeExecutable": "python",
    "runtimeArgs": ["-m", "http.server", "8765"], "port": 8765 } ] }
```
Lưu ý: Browser tool không chạy được JS trên `file://` ngoài thư mục project — phải test qua server. Sau khi đổi thư mục, preview của Claude Code vẫn có thể phục vụ thư mục CŨ (từng gặp: trang không có thay đổi mới) — kiểm tra bằng `fetch('/index.html')` xem có nội dung mới không; nếu sai, tự chạy `python -m http.server 8766` trong thư mục dự án (hiện đang dùng cách này) rồi mở `http://localhost:8766`.

**Kiểm tra nhanh sau khi sửa:**
1. Console không có lỗi đỏ khi tải trang. Kiểm cú pháp script: tách nội dung giữa `<script>`…`</script>` ra file `.js` rồi `node --check`.
2. Đăng nhập `Admin / admin1234` → thấy đủ tab.
3. Nhập liệu: Item Code `11000028`, Batch `62550110F1` → tự điền Recipe `405A` và Ngày SX (ngày Julian 255 của năm hiện tại).
4. Điền vài chỉ tiêu → Kết luận + % hoàn thành cập nhật real-time.
5. Lưu phiếu → Lịch sử → F5 → phiếu còn (Storage hoạt động).

Không có test tự động; mọi kiểm tra đều thủ công.

---

## 7. Việc tiếp theo gợi ý

- **Giai đoạn 3:** khi người dùng gửi thông tin Coffee Oil/Liquid, điền `TYPE_CONFIG` (xem 3.6), thêm seed `THRESHOLDS`/`REPEATABILITY`/`FIELD_MAPPING`/`ITEM_CODES` với `productType` tương ứng (hoặc để người dùng nhập ở các tab quản trị), rồi test như Powder (đối chiếu tay số liệu mẫu).
- Hỏi người dùng nốt yêu cầu bị cắt ở tab Độ lặp lại (mục 4).
- Xác nhận 6 giả định ở mục 5 với QA/Supervisor.
- Test thật mở bằng `file://` trên máy người dùng cuối.
- Dữ liệu không đồng bộ giữa các máy (mỗi máy một Storage riêng) — nếu nhiều Inspector dùng nhiều thiết bị, hiện chỉ gộp thủ công qua Backup/Restore JSON; đồng bộ thật cần server (định hướng ban đầu: "build offline trước, đẩy lên web sau").
- Cân nhắc commit vào git ở thư mục mới (hiện repo mới có 1 commit "Add files via upload").

## Tối ưu Egress Supabase (2026-09-26)
- `Sync.pull`: `lab_settings` lấy `key,updated_at` trước, chỉ tải `value` của key mới hơn máy này.
- Đồng bộ định kỳ 3 phút (trước 60 giây), bỏ qua khi tab ẩn; quay lại tab chỉ sync nếu lần trước cách ≥30 giây.
- Data Log: `fetchAudit(since)` chỉ tải dòng `created_at` mới hơn, cache trong bộ nhớ (`dataLogRemote`), xoá khi đăng xuất.
- Ảnh: `compressImage` (cạnh dài ≤1600px, JPEG 0.8, chỉ khi >300KB), giới hạn gốc nâng lên 15MB; `attachmentRefCache` (WeakMap) để tự lưu nháp/Lưu phiếu dùng lại cùng tham chiếu, không tạo & đẩy ảnh mới mỗi 20 giây.
- Chưa làm: bỏ việc máy tải lại phiếu do chính nó vừa đẩy (cần cột device_id), Realtime.

## 8. Đợt sửa theo phản hồi người dùng — `Comment-Lab Record.xlsx` (2026-09-29)

Đối chiếu trực tiếp file Excel (7 dòng phản hồi, 1 ảnh minh hoạ cấu trúc Batch) với code hiện có. Không sửa dữ liệu lịch sử — mọi thay đổi bên dưới chỉ ảnh hưởng NHẬP LIỆU MỚI / SỬA phiếu; đọc phiếu cũ vẫn hiển thị nguyên như đã lưu.

**1. Batch** — `parseBatchStructure()`, `resolveBatchYear()`, `recomputeProductionDate()` ([index.html](index.html) khu vực `BATCH_RE`):
- Viết hoa tự động khi gõ/dán (`input` listener), trim trước khi tính/lưu.
- Cấu trúc bắt buộc đúng 10 ký tự: 1 số năm + 3 số Julian + 4 số cuối PO + 1 chữ loại sản phẩm + 1 số line (regex `BATCH_RE`), kiểm tra ngày Julian 1–366 và năm nhuận (`isLeapYear`) trước khi chấp nhận ngày 366.
- **Năm SX**: Batch chỉ có 1 chữ số năm → thêm field mới `productionYear` ("Năm SX (xác nhận)") cạnh Batch. Trống → tự đoán năm gần năm hiện tại nhất (`resolveBatchYear`, cửa sổ ±6 năm, hoà thì để trống bắt xác nhận) và LUÔN hiển thị ghi chú "tự động…" để không đoán ngầm; người dùng sửa tay thì giữ nguyên, chỉ kiểm tra khớp chữ số cuối với Batch. Ngày SX = năm đã xác nhận + ngày Julian, lưu vào `sampleInfo.productionYear` + `sampleInfo.productionDate` như các field khác — mở lại phiếu cũ chỉ đọc lại giá trị đã lưu (`setFieldValue`, không dispatch event) nên KHÔNG tự tính lại/đổi năm.
- `validateBeforeSubmit()` chặn lưu chính thức/Force nếu Batch sai cấu trúc, thiếu năm xác nhận, hoặc năm không khớp Batch.
- Riêng của Powder (field `batch` có `behavior:'julianBatch'` chỉ khai báo ở `TYPE_CONFIG.powder`) — Oil/Liquid chưa có field này nên không bị áp quy tắc.

**2. SSCC — CHƯA SỬA, đang chờ xác nhận.** Ghi chú Excel mô tả 11 chữ số (1+5+5) nhưng ví dụ mẫu `61260008300221` có 14 chữ số — mâu thuẫn, không tự suy đoán bỏ bớt số 0 để khớp ví dụ. Đã hỏi người dùng câu hỏi ngắn (cấu trúc chính xác + 2-3 cặp PO–SSCC mẫu đã xác nhận đúng) trong hội thoại. Thuật toán gợi ý hiện tại (`onPoChange()`: SSCC = PO + "000" + 3 số tự nhập) giữ nguyên, không đổi.

**3. Người thực hiện** — kiến trúc Form Engine (`TYPE_CONFIG`/`BLOCK_KINDS`) đổi từ "1 cột lặp theo dòng" (`STAFF_COL` nằm trong `cols`/`fields`, mỗi lần đo 1 ô riêng) sang **1 ô chọn CHUNG ở đầu mỗi khối** (`sharedStaffHtml`, `staffFieldName`, `hasStaffCol`, `withoutStaffCol`): dùng chung cho 2 lần đo (`pair`) và cho cả Nóng+Lạnh (`hotCold`); `single`/`sieve` vốn đã 1 giá trị/khối nên chỉ đổi vị trí hiển thị lên đầu. Khối **Ngoại vật** trước đây THIẾU hẳn field này — đã bổ sung `STAFF_COL` vào `fields`. Khi thu thập (`collect`), cả 2 lần đo/2 dòng đều ghi CÙNG giá trị ô chung (giữ đúng schema cũ `rep.nguoiThucHien`/`hot.nguoiThucHien`/`cold.nguoiThucHien` nên chi tiết phiếu/in/CSV/Full Report không cần sửa). Khi mở lại 1 phiếu CŨ mà các lần đo có người khác nhau, ô chung `applySharedStaff()` để TRỐNG + viền cảnh báo + tooltip liệt kê các tên cũ — không tự chọn 1 người rồi bỏ người kia, bắt người dùng chọn lại.

**4. Thời gian sấy** — cột `thoi_gian_say` đổi `input:'text'` → `input:'mmss'`: 2 ô số (phút, giây) do `inputCellHtml()` render, dấu `:` do app tự chèn (không phải nhân viên gõ). `readMmSs()`/`setMmSs()` phân biệt Ô TRỐNG (chưa nhập) khỏi "00:00" (đã nhập, bằng 0) và validate phút nguyên ≥0, giây nguyên 0–59; chặn Lưu chính thức/Force qua `BLOCK_KINDS.pair.validate()` (xem mục 7). Đọc phiếu cũ: `setMmSs()` nhận diện `mm:ss` hoặc `mm/ss` (theo đúng ghi chú Excel về dấu "/"); định dạng tự do khác của dữ liệu cũ để 2 ô trống (không đoán) — giá trị gốc vẫn nguyên trong bản ghi, vẫn hiển thị đúng khi xem/in/Full Report (các hàm đó chỉ dump chuỗi đã lưu).

**5. Nhiệt độ hòa tan** — khối `hoaTan` (`hotCold`) đã có sẵn ngưỡng `warn:{min,max}` (Nóng 96–98°C, Lạnh 18–20°C) nhưng trước đây chỉ tô viền đỏ khi SAI, không tô xanh khi ĐÚNG và không có chữ mô tả. Bổ sung: ô nhập thêm class `field__input--ok` (xanh, CSS mới `--ok`) khi trong khoảng, `--warn` (đỏ, đã có) khi ngoài khoảng, không class khi trống; `<div class="field__hint">` ngay dưới ô hiện "Ngưỡng: X–Y°C — ✓/✗ …". Đây là cảnh báo ĐIỀU KIỆN ĐO, tách biệt hoàn toàn khỏi kết luận Đạt/Không đạt của Độ hòa tan (vẫn chỉ dựa kết quả V/X như cũ, không đổi).

**6. Khối lượng sàng** — khối `kichThuoc` (`sieve`): bỏ `Math.max(0, wt - w)` (từng che số âm/không hợp lệ). `compute()` giờ chỉ tính %/Range khi ĐỦ cả 8 cỡ sàng và TẤT CẢ hợp lệ (KL mẫu+sàng ≥ KL sàng, không âm, không thiếu 1 trong 2 ô/dòng) — thiếu/sai bất kỳ dòng nào thì cả bảng hiện "--", Range vẫn "pending" (không suy luận kết luận từ dữ liệu 1 phần/sai). `BLOCK_KINDS.sieve.validate()` (mới, xem mục 7) báo lỗi đúng ô và chặn Lưu chính thức/Force (không chặn Lưu nháp) khi: 1 dòng chỉ có 1 trong 2 ô, giá trị âm, KL mẫu+sàng < KL sàng, hoặc (đủ dữ liệu nhưng) tổng khối lượng giữ lại = 0.

**7. Kiểm tra trước khi lưu & Alarm** — tách 3 khái niệm:
- *Hợp lệ dữ liệu*: `validateBeforeSubmit()` (Item Code/Batch/Customer/Năm SX như cũ) + **`blockValidationErrors()`** (mới) gọi `BLOCK_KINDS[kind].validate(b)` của từng khối (hiện có ở `pair` cho mm:ss, `sieve` cho khối lượng). Lỗi này chặn CẢ Lưu chính thức LẪN Force — Force chỉ bỏ qua "chưa đủ chỉ tiêu", không bỏ qua lỗi hợp lệ.
- *Đầy đủ chỉ tiêu*: kết luận còn `pending` → chặn Lưu chính thức, Force mới bỏ qua được (không đổi so với trước).
- *Kết luận chất lượng*: nếu ≥1 chỉ tiêu `fail`, `submitRecord()` mở modal `confirmSaveAlarm()` (nút riêng "Quay lại kiểm tra"/"Xác nhận lưu", KHÔNG dùng `confirmModal()` nhãn Huỷ/Đồng ý) liệt kê tên chỉ tiêu + `paramSummaryLine()` (TB/sai khác/Range). Xác nhận thì vẫn lưu bình thường (không cấm Không đạt hợp lệ), lưu `record.qcAlarm = {confirmedBy, confirmedAt, failedParams[]}` + `AuditLog.log(...,{khongDat:...})`; hiện trong chi tiết phiếu và Full Report. Lưu nháp (`btn-save-draft`) không qua alarm này.

**8. Lịch sử & Tra cứu** (`renderHistoryTable`, `panel-history`):
- Bộ lọc kết hợp: Loại sản phẩm (đã có), tìm theo Item Code/PO/Batch/Product Name (`history-search`, không phân biệt hoa/thường, an toàn field thiếu), Customer, Kết luận, Phê duyệt, **Nháp/chính thức** (mới), Ngày lưu (đã có, đổi nhãn cho rõ), **MFG từ–đến** (mới, `parseVNDate()` đọc `sampleInfo.productionDate` dạng `dd/mm/yyyy`; thiếu MFG thì không khớp bộ lọc theo khoảng ngày).
- Bảng thêm cột **PO** và **Ngày SX (MFG)**.
- Sắp xếp: **Nháp lên đầu**, trong từng nhóm theo `meta.updatedAt` (fallback `savedAt`) mới nhất trước; `state.filteredHistory` lưu ĐÚNG thứ tự đang hiển thị nên **Xuất CSV** (`exportHistoryCsv`, thêm cột PO/Ngày SX/cờ Nháp) khớp tuyệt đối tập + thứ tự trên bảng.
- Nút **"Tiếp tục nhập"** ngay trên dòng Nháp trong bảng (không cần mở modal chi tiết mới thấy).

**9. Flow phê duyệt** — mở rộng, không tạo luồng song song:
- Trạng thái mới: `pending` (Chờ duyệt) → `approved` (Đã duyệt) hoặc `returned` (Trả lại sửa, bắt buộc lý do) → sửa → tự động về `pending` khi lưu lại ("Gửi duyệt lại"). Ánh xạ trạng thái CŨ khi ĐỌC (`LEGACY_APPROVAL_MAP`, không ghi đè dữ liệu đã lưu): `approved→approved`, `not_approved`/thiếu`→pending`, `rejected→returned` (không có lý do cũ).
- `approveRecord()`/`returnRecordForEdit()` (thay `setApproval()` cũ): chỉ Supervisor/Admin, chỉ tác động phiếu đang `pending`, Trả lại bắt buộc lý do (modal `promptModal()`), mỗi lần chuyển trạng thái nối vào `record.approval.history[]` (status/by/at/reason).
- **Khoá nội dung bản đã duyệt**: sửa 1 phiếu `approved` (nút "Sửa phiếu (tạo phiên bản mới)" → `resumeRecordForEdit()` đặt `state.editingWasApproved`) — khi Lưu (`submitRecord`), bản ĐANG approved được lưu nguyên vẹn thành 1 bản ghi `archived:true` id riêng (`<id>_approved_<ts>`, `versionOf` trỏ về id gốc) để truy vết; "id sống" (id gốc) nhận nội dung mới, `version+1`, trạng thái reset về `pending`. Chi tiết phiếu có link "xem các phiên bản trước đã duyệt" liệt kê các bản `archived`. Lịch sử/Dashboard/CSV lọc bỏ `archived` theo mặc định.
- Bảo toàn `meta.createdBy`/`meta.createdAt` (mới) qua mọi lần sửa (kể cả sửa nháp) — trước đây `createdBy` bị ghi đè bằng người vừa lưu.
- Sync: LWW hiện có theo `meta.updatedAt` (không đổi cơ chế); mọi thao tác duyệt/trả lại/tạo phiên bản đều bump `updatedAt` nên vẫn qua được hàng đợi đồng bộ sẵn có. Toast không khẳng định "đã duyệt trên hệ thống" — chỉ nói lưu trên máy này (+ "đang đồng bộ" nếu Supabase bật).
- **Supabase**: viết migration mới `supabase/approval_flow.sql` (thay `lab_records_guard` cũ) khoá nội dung phiếu `approved` ở DB (không chỉ ẩn nút UI) + bắt buộc lý do khi `returned` + chỉ Supervisor+ đổi trạng thái. **CHƯA chạy trên project thật** — đọc phần "Đã biết/giới hạn" cuối file đó trước khi chạy, đặc biệt về xung đột đồng bộ 2 máy (chưa có cơ chế báo xung đột chủ động, chỉ dựa vào lỗi 4xx bị Sync bỏ qua).

**10. Item Code — tìm Recipe**: sửa lỗi có thật khi `it.item`/`it.name`/`it.recipe` là số hoặc thiếu (dữ liệu cũ) sẽ làm `.toLowerCase()` ném lỗi — bọc `String(...||'')`. Đổi placeholder ô tìm thành "Tìm Item Code, tên sản phẩm hoặc Recipe...". `findItemByCodeIn()` (dùng cho tra cứu ở form Nhập liệu) cũng bọc `String()` tương tự.

**11. Spec — lọc Customer**: thêm dropdown Customer (theo Loại sản phẩm đang chọn, có "Tất cả") + dòng đếm "Hiển thị X / Y dòng". `idx` dùng để sửa/xoá vẫn lấy từ mảng `THRESHOLDS` GỐC (lấy trước khi lọc Customer), nên sửa/xoá sau khi lọc luôn đúng bản ghi gốc.

### Bảng ánh xạ 12 dòng yêu cầu Excel

| # | Yêu cầu (Excel) | Trạng thái |
|---|---|---|
| 1 | Batch viết hoa | ✅ Đã làm |
| 2 | Batch: cấu trúc năm+Julian+PO+loại+line, kiểm tra ngày/năm nhuận, không mặc định năm hiện tại | ✅ Đã làm (field "Năm SX (xác nhận)" mới) |
| 3 | SSCC dư 1 số 0 | ⛔ Còn chờ — ghi chú Excel (11 số) mâu thuẫn ví dụ mẫu (14 số), đã hỏi người dùng, thuật toán giữ nguyên |
| 4 | Người thực hiện — 1 người/phương pháp | ✅ Đã làm (ô chung đầu khối, bổ sung cho khối Ngoại vật vốn thiếu) |
| 5 | Thời gian sấy — 2 ô phút/giây, dấu tự động | ✅ Đã làm |
| 6 | Độ hòa tan — range nhiệt độ tô xanh/đỏ | ✅ Đã làm (+ chữ mô tả ngưỡng, giữ nguyên quy tắc kết luận V/X) |
| 7 | Kích thước hạt — KL mẫu+sàng ≥ KL sàng | ✅ Đã làm (bỏ Math.max che số âm, chặn lưu khi sai) |
| 8 | Lưu phiếu — Alarm khi có Không đạt | ✅ Đã làm (tách hợp lệ/đầy đủ/kết luận, modal riêng, lưu người xác nhận) |
| 9 | Lịch sử & Tra cứu — tìm theo Loại/Item/PO/Batch/MFG | ✅ Đã làm (+ Nháp lên đầu, CSV khớp, cột PO/MFG) |
| 10 | Bổ sung Flow Phê duyệt | ✅ Đã làm (Nháp→Chờ duyệt→Đã duyệt/Trả lại sửa, khoá bản đã duyệt, versioning; migration Supabase CHƯA chạy) |
| 11 | Item Code — tìm theo Recipe | ✅ Đã có sẵn, đã kiểm tra + vá lỗi null/kiểu dữ liệu cũ, đổi placeholder |
| 12 | Spec — tìm theo Customer | ✅ Đã làm (dropdown lọc, sửa/xoá vẫn đúng bản ghi gốc) |

### Kiểm tra đã chạy (cục bộ, qua Console/JS trực tiếp trên `http://localhost:8766` — CHƯA kiểm thử tích hợp với Supabase thật)
Batch: chữ thường→hoa, cấu trúc sai, ngày 366 năm thường (chặn)/năm nhuận 2016 (qua), năm không khớp chữ số cuối, năm để trống tự đoán gần nhất + hiển thị ghi chú ổn định qua nhiều lần fire change/blur. Người thực hiện: khối `pair` thu thập 1 giá trị chung cho 2 lần đo; nạp lại bản ghi cũ có 2 tên khác nhau → để trống + cảnh báo + tooltip. Thời gian sấy: hợp lệ `05:07`, giây `60` bị chặn với thông báo đúng khối/lần đo, sửa lại qua được; đọc `12/30` (cũ) và `abc` (không đoán được) không crash. Khối lượng sàng: `wt<w` bị chặn đúng cỡ lưới, thiếu 1 ô bị chặn, âm bị chặn, đủ dữ liệu hợp lệ thì qua. Nhiệt độ hòa tan: 97°C (trong khoảng, xanh) và 25°C (ngoài khoảng 18–20, đỏ) ra đúng class + chữ mô tả. Phê duyệt: approve → sửa phiếu đã duyệt (Force) → version 2 + bản `archived` version 1 giữ nguyên + `createdBy` không đổi; trả lại thiếu lý do bị chặn, có lý do thành công; sửa phiếu `returned` rồi lưu → tự về `pending`. Đọc 1 bản ghi "kiểu cũ" (approval `rejected`, thời gian sấy `12/30`, người thực hiện khác nhau) qua `applyRecordToForm`/`viewRecord` không lỗi console, hiển thị đúng nhãn mới ("Trả lại sửa"). Item Code/Spec: filter Customer + đếm dòng đúng; tìm kiếm không crash với dữ liệu số/thiếu field. Toàn bộ `<script>` qua `node --check` sau mỗi bước. KHÔNG kiểm thử: Supabase RLS/trigger mới (`approval_flow.sql` chưa chạy), đồng bộ 2 máy với dữ liệu approval mới, in PDF/Full Report thật (chỉ kiểm tra hàm dựng HTML không lỗi), mở bằng `file://` thật.

### Hạn chế còn lại
- SSCC: thuật toán CŨ vẫn dùng tạm (PO + "000" + 3 số) — chờ xác nhận cấu trúc thật.
- `supabase/approval_flow.sql` mới viết, CHƯA chạy trên Supabase thật; RLS/trigger CŨ (`auth.sql`) vẫn đang là bản 3 trạng thái approved/not_approved/rejected — app vẫn ghi được (trigger cũ chỉ chặn Inspector đổi `approval`, không biết khái niệm `returned`/khoá nội dung) cho tới khi chạy `approval_flow.sql`.
- Đồng bộ 2 máy cùng sửa 1 phiếu quanh thời điểm phê duyệt: vẫn dựa Last-Write-Wins theo `meta.updatedAt`, chưa có cảnh báo xung đột chủ động cho người dùng (xem ghi chú cuối `approval_flow.sql`).
- "Đã biết/giả định" ở mục 5 (Recipe-band threshold, Ngoại vật Absent/Present, REPEATABILITY mặc định...) vẫn còn nguyên, chưa đổi trong đợt này.
- Coffee Oil / Liquid vẫn chưa có cấu hình (Giai đoạn 3, đang chờ dữ liệu).

## 9. Rebrand ILD Crafted + mô-đun Theme (2026-09-29)

Áp nhận diện ILD Crafted (nền kem #F7F0E6, espresso, logo thật) + thêm DUY NHẤT 1 tính năng mới: bảng tùy chỉnh Theme. Không sửa JS nghiệp vụ, không đổi ID/class/name/data-*/value đang có, không thêm dependency/CDN.

- **Logo:** nhúng trực tiếp file logo người dùng cung cấp dạng `data:image/webp;base64,...` (không vẽ lại, không đổi màu/tỷ lệ), thay `<span class="app-header__logo">☕</span>` bằng `<img>` cùng class, luôn đặt trên nền trắng riêng (kể cả Theme tối) qua CSS `.app-header__logo`.
- **Token màu:** đổi GIÁ TRỊ (không đổi TÊN) của các biến `:root`/`:root[data-theme="dark"]` đã có sẵn (`--bg,--surface,--border,--text,--primary,--accent-bg,...`) sang bảng ILD Crafted sáng/tối; toàn bộ CSS nghiệp vụ đang dùng `var(--...)` tự động lên màu mới, không phải sửa từng rule. Thêm biến mới: `--input-border` (viền ô nhập rõ hơn viền phân cách), `--focus-ring` (tách khỏi màu nút chính), `--primary-hover`, `--accent-brown`, `--accent-red`.
- **Lưu ý quan trọng:** `:root[data-theme="dark"]` trước đây tồn tại trong CSS nhưng KHÔNG có JS nào từng gán `data-theme` — dark mode cũ là code chết. Mô-đun Theme mới là nơi DUY NHẤT gán thuộc tính này (dùng làm cầu nối tái sử dụng khối CSS đó), nên không có xung đột với tính năng cũ nào.
- **Cấu hình mẫu / Sáng-Tối-Hệ thống / Tương phản / Độ đậm:** đúng theo yêu cầu — 4 preset (`crafted-standard/soft/dark/sharp`), tự nhận diện "Tuỳ chỉnh" khi tổ hợp không khớp preset nào; "Theo hệ thống" theo `prefers-color-scheme`, chỉ lắng nghe khi đang chọn chế độ này; Tương phản cao chỉ tăng rõ chữ/ô nhập/focus/vùng chọn (không tô viền đậm mọi khối); Độ đậm chỉ đổi `font-weight` (2 biến mới `--ild-fw-body/--ild-fw-strong`, áp cho `body`, `.field__label`, `.card__title`, `.panel__title`, `legend`, `th`, `.sidebar__item` — các vị trí RỘNG, không rà từng rule `font-weight:600` đang có rải rác trong file để tránh sửa hàng loạt ngoài phạm vi).
- **Vị trí:** nút "🎨 Giao diện" trong `.app-header__actions` (cạnh "+ Phiếu mới"); panel là overlay RIÊNG (`#ild-theme-overlay`, prefix `ild-theme-`), KHÔNG dùng chung `#modal-overlay`/`Modal` nghiệp vụ — tránh mọi rủi ro đụng vào modal chi tiết phiếu/phê duyệt.
- **Lưu cấu hình:** `localStorage['ild-crafted-appearance-v1']` = `{appearance, contrast, emphasis}`; đọc có kiểm tra từng field hợp lệ (sai/hỏng → về mặc định); lỗi localStorage (chặn/quota) bọc try/catch, Theme vẫn hoạt động trong phiên. Không đụng tới bất kỳ khoá localStorage nào khác của app (`labrecord_*`).
- **Chống chớp màu:** thêm 1 `<script>` nhỏ ngay sau `</style>` trong `<head>` (trước `<body>`), CHỈ đọc localStorage + set `data-theme`/`data-ild-*` trên `<html>` — chạy trước khi phần còn lại của trang vẽ. Mô-đun Theme đầy đủ (panel, sự kiện, đồng bộ hệ thống) vẫn nằm ở cuối `<script>` nghiệp vụ như 1 IIFE riêng (`ildCraftedTheme`), không có biến toàn cục mới ngoài closure của chính nó.
- **Khả năng truy cập:** dùng `role="dialog"` + `aria-modal` + `aria-labelledby`; các lựa chọn là `<input type="radio">` thật (không phải div giả); Escape đóng panel và trả focus về đúng nút đã mở; click ra ngoài overlay cũng đóng; "Khôi phục mặc định" CHỈ gọi lại Theme mặc định, không gọi bất kỳ hàm reset dữ liệu nào của app.
- **In ấn:** không cần sửa gì thêm — cơ chế in sẵn có (`body.is-printing > *:not(#print-area){display:none}`) đã ẩn toàn bộ header/nút Theme khi in qua `printRecord()`/`printFullReport()`; có thêm 1 rule `@media print` ẩn nút/panel Theme phòng trường hợp người dùng tự Ctrl+P ngoài luồng đó.
- **Không đổi:** biểu đồ/canvas (app hiện không dùng canvas/chart JS nào), ảnh đính kèm/ảnh bằng chứng (không áp filter Theme lên `<img>` ảnh nghiệp vụ), ý nghĩa màu trạng thái Đạt/Không đạt/Chấp nhận/Pending (giữ nguyên `--pass/--fail/--accept/--pending`, chỉ đổi `--pending-bg` sang tông ấm hơn cho khớp nền mới, không đổi ý nghĩa).

**Kiểm tra đã chạy** (qua `localhost:8766`, Console/JS + click thật qua Browser tool): 4 cấu hình mẫu áp đúng tổ hợp và hiển thị đúng tên; chọn tay 1 tổ hợp không khớp preset nào → hiện "Tuỳ chỉnh"; Sáng/Tối áp ngay không cần tải lại; lưu & đọc lại đúng sau khi điều hướng lại trang (bootstrap sớm không chớp màu — kiểm tra `data-theme` đã đúng ngay khi trang vừa vào, trước khi chạy script cuối); "Khôi phục mặc định" đưa về đúng Crafted tiêu chuẩn và ghi đúng localStorage; Escape đóng panel + trả focus đúng về nút mở; đổi tab/nhập dữ liệu Batch rồi mở/đóng panel không mất dữ liệu form, không đổi tab đang xem; sau khi đổi Theme, các hàm nghiệp vụ đã sửa ở mục 8 (tra Item Code, validate sàng) vẫn chạy đúng; giao diện mobile 375px không vỡ layout (dùng đúng CSS responsive có sẵn, không sửa). Không có lỗi Console trong toàn bộ quá trình. **Chưa kiểm tra:** mở thật bằng `file://` (chỉ test qua local server), trình duyệt không hỗ trợ `:has()` (chỉ ảnh hưởng hiệu ứng highlight lựa chọn đang chọn trong panel, không ảnh hưởng chức năng), độ tương phản đo bằng công cụ chuyên dụng (chỉ ước lượng theo bảng màu spec).

**Giới hạn còn lại:** "Độ đậm" chỉ áp cho 1 tập chọn lọc các phần tử tiêu đề/nhãn rộng (không rà toàn bộ ~10 vị trí có `font-weight:600/700` rải rác trong file) — đủ tạo khác biệt rõ giữa 3 mức nhưng không phải 100% mọi chữ đậm trong app đều đổi theo; nếu cần phủ kín hơn, làm ở đợt sau (rà từng rule, rủi ro thấp nhưng tốn thời gian). File gốc trước khi rebrand có thể xem lại qua lịch sử git (không tạo file `-ILD-Crafted.html` riêng vì đây là dự án git có lịch sử, không phải 1 file HTML rời).


## 10. Đợt "On going" theo `Comment-Lab Record.xlsx` (2026-10-05)

Chỉ làm 4 dòng Excel được yêu cầu (10, 12, 13, 20). Không đổi Status trong Excel.

**Dòng 10 — Thanh tiến độ cố định (nhập liệu).** `.completion-row--sticky` (`position:sticky; top:var(--sticky-offset)`, z-index 40 < thanh tab 50 < modal 900); `updateStickyOffset()` đo chiều cao `#sidebar` (gọi lúc khởi động + `resize`). Vì `.main-content{overflow-y:auto}` biến nó thành khung cuộn làm sticky vô hiệu, CSS bỏ overflow đó CHỈ khi tab Nhập liệu đang mở (`.main-content:has(> #panel-form.is-active)`) và chuyển cuộn ngang sang `#analysis-form` (bảng sàng trên mobile vẫn cuộn ngang được như trước, trang không bị tràn ngang). Các tab khác giữ nguyên. Công thức % KHÔNG đổi (đã đối chiếu 85/85 trường = cách đếm DOM cũ).

**Dòng 20 — Tiến độ trong chi tiết phiếu.** Logic thuần tách khỏi DOM: `completionFieldsFor(type)` (danh sách trường tự nhập theo `TYPE_CONFIG`), `summarizeCompletion()` (chỗ thay công thức theo "số chỉ tiêu/tổng" ở đợt sau), `completionOfForm()` (đọc DOM) và `completionOfRecord(r)` (chỉ đọc bản ghi `r`, không đụng form/phiếu khác/không ghi lại). Hiển thị "Tiến độ nhập liệu" giữa dòng Customer/Ngày SX/PO/SSCC và danh sách chỉ tiêu (đúng vị trí ảnh Excel), cả nháp lẫn chính thức; không in kèm trong "In tóm tắt". Dữ liệu cũ không đủ khối/khoá (thiếu khối chỉ tiêu, thiếu `reps`/`sieve`/hàng nóng-lạnh, khoá cũ không có) -> `completionOfRecord` trả `null` -> "Chưa xác định" (không gán 0%/100%). Ngoại lệ có chủ đích: khoá thêm SAU các bản ghi cũ (`productionYear`, Người thực hiện) thiếu thì bỏ khỏi tổng thay vì coi là chưa nhập. Không dùng tỷ lệ Đạt.

**Dòng 12 — Alarm thiếu kết quả khi Lưu chính thức.** `BLOCK_KINDS[kind].missing(b)` (pair/single/hotCold/sieve) + `collectMissingResults()`; modal "Chưa nhập đủ kết quả" (`showMissingResultsModal`) liệt kê từng mục, bấm mục -> cuộn+focus đúng ô (`focusFormField`); ghi chú đỏ ngay tại khối + viền ô thiếu (`refreshMissingNotes`, tự cập nhật khi nhập tiếp). Căn cứ: đầu vào cần để RA kết quả — pair: ô kết quả từng lần đo (kết quả tự tính: các đầu vào khai báo ở `needs` của cột, VD Tỷ trọng cần KL mẫu + thể tích bình, Acidity cần nồng độ NaOH + thể tích tiêu tốn); single: ô kết quả; hotCold: kết quả V/X từng dòng nóng/lạnh; sieve: đủ KL sàng và KL mẫu+sàng ở MỌI cỡ. Số 0 là đã nhập. Không dựa vào kết luận `pending` nên phiếu có 1 chỉ tiêu Không đạt vẫn bị báo các chỉ tiêu khác chưa nhập. Tách biệt hoàn toàn với alarm Không đạt (`confirmSaveAlarm`, vẫn chạy sau khi hết thiếu). Force vẫn bỏ qua alarm thiếu; lưu nháp không đổi. **Hai thay đổi kéo theo cần biết:** (1) nút Force trước đây chỉ hiện khi kết luận `pending`; nay còn hiện khi `collectMissingResults()` khác rỗng (nếu không, phiếu có chỉ tiêu Không đạt + còn thiếu sẽ không còn lối đóng nào) — không thêm/bỏ quyền. (2) `sieve.validate()` không còn coi dòng sàng chỉ nhập 1 trong 2 ô là lỗi chặn cả Force — nay là "thiếu" (alarm, Force bỏ qua được); vẫn chặn cả Force: số âm, KL mẫu+sàng < KL sàng, tổng khối lượng = 0.

**Dòng 13 — Báo lỗi định dạng tại trường (CHỈ kiểm tra định dạng đã biết, KHÔNG kiểm tra chéo Item Code/Batch/PO/SSCC/Customer).** 1 validator dùng chung UI + lưu: `validateSampleField(f, v)` / `collectFieldErrors(cfg)` / `setFieldError(name, msg)` (lỗi dưới ô bằng `textContent`, viền đỏ, `aria-invalid`). Cấu hình theo trường qua `format` trong `TYPE_CONFIG.powder.sampleFields`: Item Code `itemCode` (chuỗi chữ số + có trong danh mục loại đang chọn, không áp độ dài), PO `digits` (chuỗi chữ số, vẫn tuỳ chọn), Batch `batch` (dùng lại `parseBatchStructure`/Năm SX/năm nhuận, chỉ đổi cách hiển thị lỗi), SSCC `sscc14` (đúng 14 chữ số; chuỗi bằng tiền tố gợi ý `PO+"000"` KHÔNG hợp lệ; trống vẫn được). Item Code và PO đổi từ `<input type=number>` sang text `inputmode=numeric` (`input:'digits'`) để giữ số 0 đầu và bắt được ký tự không phải số. Hành vi: kiểm khi blur/change, đã báo lỗi thì cập nhật/xoá khi sửa, không báo lúc đang gõ dở; lưu chính thức (kể cả Force) chạy lại cùng validator (`validateBeforeSubmit`), hiện lỗi mọi trường sai và focus trường sai đầu tiên; lưu nháp không kiểm tra. Bỏ toast "không tìm thấy Item Code" (thay bằng lỗi tại trường). Chi tiết phiếu và bảng Lịch sử nay escape (`escapeAttr`) mã người dùng (batch/item/PO/SSCC/Customer/MFG/tên SP).

**SSCC — ghi nhận, CHƯA triển khai sinh số.** Theo Excel mới (Powder): 14 chữ số = Customer (1: 6-LDC, 7-Instanta) + Line (1) + Năm (2) + 5 số cuối PO + số thứ tự (5). Người dùng xác nhận **số thứ tự bắt đầu lại theo từng PO (bộ đếm theo PO)**. Chưa xác nhận: tăng cả 5 chữ số hay chỉ 3 cuối; 2 chữ số trước xác định ra sao nếu chỉ tăng 3 số; giá trị bắt đầu/giới hạn/xử lý khi hết dải. => `onPoChange()` (gợi ý PO+"000") giữ nguyên. Hệ quả cần người dùng lưu ý: với PO 9 chữ số, tiền tố gợi ý + 3 số tự nhập ra 15 chữ số nên SẼ bị báo sai định dạng 14 số — người dùng phải gõ đủ 14 số hoặc xoá trống. Ngoài ra `onPoChange()` còn ghi đè SSCC đã nhập nếu PO đổi sau đó và SSCC không bắt đầu bằng tiền tố PO mới (hành vi có từ trước, chưa sửa vì thuộc thuật toán SSCC chờ xác nhận).

**Vẫn chưa làm (chờ xác nhận):** tự tăng SSCC; công thức % mẫu trên sàng; tiến độ theo số chỉ tiêu; tô xanh tên chỉ tiêu; kiểm tra chéo các mã/Customer; bỏ "Năm SX (xác nhận)"; quyền sửa kết quả Admin/Supervisor/Inspector; import Excel Item Code; sửa tên Chỉ tiêu/Trường; ngưỡng độ lặp lại theo Customer.

**Kiểm thử đã chạy** (local `http://localhost:8766`, Console/JS + Browser pane; chưa chạy Supabase/RLS): tiến độ form = đếm DOM cũ (85 trường, 25 mặc định) và = tiến độ bản ghi vừa dựng (kể cả sau JSON round-trip, số 0 tính là đã nhập); mở chi tiết phiếu A khi form chứa dữ liệu khác (34% của A, không phải 39% của form); thanh nằm đúng giữa dòng Customer… và danh sách chỉ tiêu; bản ghi cũ thiếu `productionYear`/staff Ngoại vật vẫn tính (83 trường), thiếu khối `hoaTan` / thiếu khoá rep -> "Chưa xác định"; alarm thiếu: Độ ẩm lần 2, Độ hòa tan lạnh, Kích thước hạt thiếu KL mẫu+sàng tại 1.00 mm, Tỷ trọng/Acidity thiếu đầu vào; 0 không bị coi là thiếu; phiếu có Ngoại vật Không đạt + chỉ tiêu khác trống vẫn bị báo thiếu và Force vẫn hiện; Force chuyển sang alarm Không đạt riêng (không lưu khi chọn Quay lại); bấm mục thiếu focus đúng ô và ghi chú cập nhật khi nhập; PO có ký tự, Item Code không tồn tại/có chữ/số 0 đầu giữ nguyên, Batch sai/hợp lệ (chữ thường -> hoa), SSCC 13/14/15 số + ký tự lạ + tiền tố gợi ý + số 0 đầu; lỗi xuất hiện khi blur (không khi đang gõ), xoá sau khi sửa đúng; lưu chính thức/Force bị chặn khi SSCC là tiền tố gợi ý, lưu nháp vẫn giữ nguyên dữ liệu; mã chứa thẻ HTML hiển thị escape; sticky desktop 1100px và mobile 375px (thanh dính ngay dưới thanh tab, không tràn ngang trang); lưu thường 1 phiếu đủ dữ liệu (qua alarm Không đạt) + Duyệt vẫn chạy; không lỗi Console. **Hạn chế:** Browser pane đang ẩn nên một số kiểm tra chỉ qua DOM/JS (screenshot chập chờn); animation `fadeIn` của panel bị đóng băng khi pane ẩn gây lệch 4px giả khi đo sticky; ảnh đính kèm chỉ được xét ở mức `completionFieldsFor` bỏ qua input file, chưa chụp/đính ảnh thật trong lượt này; chưa thử mở bằng `file://`.

## 11. Công thức sàng, hoàn thành chỉ tiêu, Customer theo PO (2026-10-05, đợt 2)

**1. % mẫu trên sàng — đã đúng, giữ nguyên logic** (`BLOCK_KINDS.sieve.compute`): % = (KL mẫu+sàng − KL sàng) / tổng KL thu hồi × 100; chỉ tính khi đủ 8 cỡ hợp lệ và tổng > 0, ngược lại hiện `--` (không thành 0); `validate()` vẫn chặn mẫu+sàng < sàng, số âm, tổng = 0. Chỉ thêm comment. Đã thử: số mẫu (9.90%/…/0.99%, tổng 10.10), mẫu số 0, thiếu 1 ô, mẫu+sàng < sàng.

**2. Hoàn thành chỉ tiêu (thay công thức tiến độ theo số trường của đợt trước).** Một quy tắc dùng chung: `blockSpecs(b)` (mọi trường của phương pháp) + `blockCompletion(b, get)` -> `{complete, missing[], invalid[]}`; `get` là `fval` (form) hoặc getter đọc bản ghi (`recordBlockGetter` + `blockReaders`). Hoàn thành = đủ MỌI trường (người thực hiện, mọi ô đo/điều kiện từng lần/nóng-lạnh, mọi ô sàng, kết quả tự tính tính ra được) và hợp lệ (số, mm:ss phút nguyên ≥0 giây 0–59, sàng mẫu+sàng ≥ sàng và tổng thu hồi > 0). Số 0 hợp lệ = đã nhập. Độc lập Đạt/Không đạt (đủ dữ liệu nhưng Không đạt vẫn hoàn thành, nhãn chất lượng giữ riêng). Dùng cho: thanh tiến độ form (`calcCompletion`: x/9 chỉ tiêu), tiến độ khi xem phiếu (`completionOfRecord`, vẫn "Chưa xác định" nếu bản ghi cũ thiếu khối/khoá), màu xanh tên chỉ tiêu (class `card__title--done`, kèm dấu ✓), và cảnh báo khi Lưu chính thức (`collectMissingResults` nay liệt kê MỌI trường thiếu theo từng chỉ tiêu, không chỉ ô kết quả). Các lưu ý: (a) ô có giá trị mặc định của form (VD KL mẫu 100 g, nhiệt độ sấy 114) được tính là đã có giá trị — app không tự điền gì thêm; (b) ảnh đính kèm không tính là trường bắt buộc; (c) trường thêm SAU các bản ghi cũ (Người thực hiện của Ngoại vật) bị bỏ qua khi bản ghi không có khoá đó, nên phiếu cũ vẫn tính được; (d) giá trị không hợp lệ vẫn do `blockValidationErrors` chặn lưu (kể cả Force) — alarm thiếu chỉ liệt kê trường chưa nhập; Force bỏ qua alarm thiếu, lưu nháp không đổi; (e) nút Force hiện khi còn trường thiếu (như đợt trước). Tiến độ không còn tính trường "Thông tin mẫu"/Reviewed by.

**3. Customer theo PO** (cấu hình ở field `po` của `TYPE_CONFIG.powder`: `format:'po'`, `customerByPrefix:{6:'INS',7:'LDC'}` — quy tắc mới nhất, ngược với mapping 6-LDC/7-Instanta ở ghi chú SSCC cũ; Oil/Liquid không bị áp). `poCustomerFor`, `validateCustomerAgainstPo`, `applyCustomerFromPo`: nhập PO có tiền tố 6/7 -> tự điền Customer khi Customer trống hoặc do app điền trước (`state.customerAutoFilled`, đổi PO thì cập nhật theo); Customer người dùng đã chọn KHÔNG bị ghi đè, nếu lệch thì báo lỗi ngay dưới ô Customer; PO tiền tố khác (hoặc có ký tự không phải số) báo lỗi dưới ô PO và KHÔNG đoán Customer. Lệch Customer–PO chặn Lưu chính thức và Force (nằm trong `collectFieldErrors`/`validateBeforeSubmit`); lưu nháp không chặn. Chỉ chạy khi nhập PO/Customer hoặc lưu — mở xem/nạp phiếu lịch sử không đổi Customer (đã kiểm). PO vẫn là chuỗi (giữ số 0 đầu), vẫn tuỳ chọn. SSCC (thuật toán, mâu thuẫn mapping chữ số đầu 6-LDC/7-Instanta) và "Năm SX (xác nhận)" chưa đụng tới. **Cần xác nhận:** chữ số đầu SSCC theo Excel ghi 6-LDC/7-Instanta, ngược với quy tắc PO mới — chưa đổi gì ở SSCC.

**Kiểm thử đã chạy** (local, Console/JS qua Browser pane; chưa Supabase): công thức sàng (hợp lệ, mẫu số 0, thiếu ô, wt<w); hoàn thành: thiếu kết quả lần 2, thiếu nhiệt độ sấy (trường phụ trợ), giây 60 (không hợp lệ), kết quả 0, đủ dữ liệu nhưng Không đạt (xanh + vẫn tính hoàn thành), Hòa tan thiếu lạnh, sàng thiếu 1 ô; tiến độ form = tiến độ bản ghi (kể cả JSON round-trip) ở 100%/11%; bản ghi cũ thiếu staff Ngoại vật, thiếu hàng lạnh (-> Chưa xác định), thiếu kết quả, mm:ss hỏng; 9/9 tên chỉ tiêu xanh khi đủ; modal alarm 48 mục + Force vẫn hiện + lưu nháp vẫn lưu + chi tiết phiếu hiện 11% (1/9 chỉ tiêu); Customer: PO 6 -> INS, đổi PO 7 -> LDC, chọn tay lệch -> lỗi, đổi PO không đè lựa chọn tay, PO đầu 8 / đầu 0 / có chữ -> lỗi PO không đoán Customer, Force bị chặn khi lệch, nạp phiếu cũ không đổi Customer. Không lỗi Console. Chưa kiểm thử: Supabase/đồng bộ, đính ảnh thật, giao diện mobile/sticky sau thay đổi (không đụng CSS sticky).
