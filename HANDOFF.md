# Lab Record – ILD Coffee — Handoff Document

**Cập nhật:** 2026-09-26
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
