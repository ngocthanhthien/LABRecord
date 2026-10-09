# Lab Record – ILD Coffee Vietnam — Handoff

**Cập nhật:** 2026-10-06 (viết lại toàn bộ, hợp nhất các bản ghi chú theo đợt trước đó — không còn mục "đợt 1/2/3": mọi thứ dưới đây là TRẠNG THÁI HIỆN TẠI)
**Vị trí:** `C:\Users\BinhDang\Documents\GitHub\LABRecord` (git repo, nhánh `main`; người dùng tự commit — AI không commit/push trừ khi được yêu cầu)

Tài liệu cho AI/dev khác tiếp nhận dự án mà không có lịch sử hội thoại. Đọc §0 và §1 trước khi sửa code.

---

## 0. Quy tắc làm việc với chủ dự án (bắt buộc)

- **"Không đoán":** thiếu thông tin nghiệp vụ → hỏi hoặc ghi rõ "chưa xác nhận" và để hành vi an toàn (chỉ tiêu ở trạng thái chờ, "Chưa xác định"), không tự bịa quy tắc/số liệu. Danh sách việc đang chờ xác nhận ở §10.
- **Không deploy production, không chạy migration trên Supabase thật, không sửa dữ liệu thật.** Các file SQL trong `supabase/` mới chỉ được viết, chưa áp dụng (trạng thái từng file ở §7).
- Không đổi cột Status trong các file Excel phản hồi của người dùng.
- Giao diện toàn bộ bằng **tiếng Việt**; trả lời người dùng bằng tiếng Việt, ngắn gọn; báo cáo chỉ những kiểm thử **thực sự đã chạy** và nêu rõ phần chưa kiểm thử.
- Không đổi tên/ID/`name`/`data-*` hiện có trừ khi thật cần (dữ liệu đã lưu và code tham chiếu theo các tên đó).
- Sửa **dữ liệu lịch sử**: không tự quy đổi/ghi đè phiếu cũ; đọc phiếu cũ phải hiển thị đúng như đã lưu (xem §6 "tương thích ngược").

---

## 1. Ứng dụng là gì

Web app nội bộ **offline-first** cho phòng QA/Lab của ILD Coffee Vietnam: nhập kết quả phân tích hoá lý, tự so ngưỡng → Đạt/Không đạt, lưu bền, tra cứu lịch sử, phê duyệt, xuất CSV/PDF/Excel, backup/restore, đồng bộ Supabase, đăng nhập + phân quyền theo vai trò.

- **3 loại sản phẩm** (`productType`): `powder` (Powder, 9 chỉ tiêu), `coffeeOil` (Coffee Oil, 3 chỉ tiêu), `liquid` (Liquid, 7 chỉ tiêu). Mỗi loại có form, Item Code, Spec, Parameters, Độ lặp lại riêng.
- **Toàn bộ app là 1 file `index.html`** (~6160 dòng, ~450 KB): HTML + CSS + JS + seed dữ liệu + logo (base64) nhúng cả trong file. **Không build, không npm, không CDN, không thư viện ngoài** (có module tự viết đọc/ghi `.xlsx` — `XlsxLite`). Lý do: gửi 1 file cho đồng nghiệp là chạy. Đừng thêm dependency.
- Mở trực tiếp bằng trình duyệt được; nên dev qua local server (§9).

### Nội dung thư mục

```
LABRecord/
├── index.html                  ← TOÀN BỘ ỨNG DỤNG (sửa file này)
├── HANDOFF.md                  ← file này
├── .claude/launch.json         ← cấu hình preview của Claude Code (python http.server, cổng 8765)
└── supabase/
    ├── README.md               ← thứ tự chạy SQL + hướng dẫn deploy Edge Function
    ├── schema.sql              ← bảng lab_records/lab_settings/lab_audit + bucket lab-attachments
    ├── auth.sql                ← profiles, lab_level(), RLS theo vai trò
    ├── users.sql               ← profiles.disabled/username
    ├── approval_flow.sql       ← trigger phê duyệt (khoá nội dung bản đã duyệt…) — CHƯA chạy
    ├── permissions_matrix.sql  ← lab_can() đọc ma trận quyền; thay approval_flow.sql — CHƯA chạy
    └── functions/admin-users/index.ts ← Edge Function tạo/khoá người dùng (Admin)
```

File Excel nguồn của người dùng (Result Form, Field Mapping, ITEM CODE, Comment-Lab Record, Quản lý người dùng…) **không nằm trong repo**; dữ liệu cần thiết đã nhúng vào code. Sửa danh mục (Item Code/Spec/Parameters/Độ lặp lại) nên làm **qua giao diện app**, không sửa seed trong code.

---

## 2. Kiến trúc `index.html`

Số dòng lệch khi sửa — luôn tìm theo comment `/* ---------------- TÊN ---------------- */` hoặc tên hàm.

| Khối | Vị trí xấp xỉ | Ghi chú |
|---|---|---|
| `<style>` | dòng 7–892 | Biến CSS ở `:root` (token ILD Crafted) + `:root[data-theme="dark"]`. `[hidden]{display:none!important}` toàn cục. |
| `<script>` nhỏ trong `<head>` | ~895 | Bootstrap theme đọc `localStorage['ild-crafted-appearance-v1']` trước khi vẽ (chống chớp màu). |
| HTML thân | ~920–1520 | Thanh tab ngang `#sidebar` (`.sidebar__item[data-tab]`), các `section.panel#panel-<tab>`, `#login-overlay`, `#modal-overlay`, `#ild-theme-overlay`, `#print-area`. |
| `<script>` chính | ~1524–6158 | Toàn JS, global scope, không module. Các khối chính bên dưới. |

Các khối JS (theo thứ tự trong file): `CONFIG` → `ROLES/hasRole` → `REPEATABILITY`, master data (`ITEM_CODES`, `THRESHOLDS`, `FIELD_MAPPING`, `STAFF`, `USERS`) → `SEED_BY_TYPE` (+ `ensureTypeSeeds`) → `UTILS` → `Storage` → `Auth` → `Sync` → `AuditLog`/`Device` → `state` → **`TYPE_CONFIG`** → **`BLOCK_KINDS`** → hoàn thành chỉ tiêu (`blockSpecs`/`blockCompletion`) → alarm thiếu dữ liệu → dựng form → báo lỗi định dạng (Item Code/Batch/PO/SSCC) → navigation/dashboard → `Modal` → đăng nhập + **`PERMISSION_DEFS`/ma trận quyền** → tab Người dùng → Data Log → Lịch sử + phê duyệt → CSV/in/Full Report → Cài đặt (nhân viên, ma trận quyền) → tab quản trị theo loại → **`XlsxLite`** + Item Code Excel → Item Code / Độ lặp lại / Spec / Parameters → nạp/lưu master data → ảnh đính kèm → `buildFullRecord` → validation + `submitRecord` → backup/restore → auto save/recovery → **BOOTSTRAP** (gắn sự kiện, quyết định đăng nhập).

Không có test tự động. Không có framework.

### 2.1. Lưu trữ (`Storage`)

IndexedDB `lab_record_db`, stores `records`, `attachments`, `settings`, `auditLog`; tự **fallback localStorage** nếu IndexedDB không mở được (fallback không lưu được ảnh). API: `Storage.put/get/getAll/delete` (có bọc để tự đẩy vào hàng đợi đồng bộ) và `Storage.raw.*` (ghi cục bộ, KHÔNG đồng bộ — dùng khi kéo dữ liệu về). `Storage.mode()` hiển thị ở Cài đặt.

Master data là biến JS top-level, seed cứng trong code rồi **bị nạp đè bởi bản đã lưu** (`loadMasterDataFromDb()`):

| Biến | Key `settings` | Đồng bộ Supabase |
|---|---|---|
| `ITEM_CODES` {item,name,recipe,productType} | `itemCodes` | ✔ |
| `THRESHOLDS` {customer,parameter,unit,requirement,recipe,productType,unitBasis?} | `thresholds` | ✔ |
| `FIELD_MAPPING` {id,parameter,field,format,type,remark,origin,productType} | `fieldMapping` | ✔ |
| `REPEATABILITY` {parameter,unit,maxDiff,customer,productType} | `repeatability` | ✔ |
| `STAFF` (tên nhân viên đo) | `staff` | ✔ |
| `PERMISSIONS` (ghi đè ma trận quyền) | `permissions` | ✔ |
| `USERS` (chỉ dùng khi `auth:false`) | `users` | ✘ (mật khẩu chữ thường) |
| theme cũ | `theme` | ✘ |

**Bẫy:** sửa seed trong code mà máy từng mở app → Storage nạp đè bản cũ → không thấy đổi (xoá site data của origin để thử). Riêng `SEED_BY_TYPE` (Oil/Liquid) chỉ nạp vào bộ nhớ khi loại đó **chưa có dòng nào** (không đè dữ liệu người dùng, không tự ghi lại Storage/Supabase). **Cẩn thận TDZ:** `ensureTypeSeeds()` chạy sau khi `TYPE_CONFIG` tồn tại; `migrateDensityThresholds()` chỉ gọi trong `loadMasterDataFromDb`.

### 2.2. Form Engine (đọc trước khi sửa form)

Form Nhập liệu dựng động từ `TYPE_CONFIG[type]` = `{ sampleFields, blocks }`:
- `sampleFields`: trường "Thông tin mẫu" (mỗi loại khác nhau). Thuộc tính hay dùng: `behavior` (`itemLookup`, `julianBatch`, `ssccFromPo`, `sampleType`), `thresholdKey` (Customer dùng tra ngưỡng), `required`, `format` (`itemCode|digits|batch|po|sscc14`), `batchRule`, `customerByPrefix`, `autoGen`, `suggestZeros`, `codeCheck`.
- `blocks`: danh sách chỉ tiêu; `kind` trỏ `BLOCK_KINDS`: `pair` (2 lần đo; `shared` = điều kiện chung lưu ở `dieuKien`; cột tính nối tiếp `formula`/`needs`; `digits`; `thresholdUnit`), `single` (1 nhóm trường, kết quả số hoặc chọn; `evaluate:'numericRange'|'absentPresent'`; ảnh tuỳ chọn), `hotCold` (nhiều dòng Nóng/Lạnh), `sieve` (bảng rây 8 cỡ). Mỗi kind có `html/compute/collect/apply/validate/missing`.
- Kiểu ô: number, select, text, computed, staff, `mmss` (phút:giây, Powder thời gian sấy), `hhmm` (giờ:phút, giờ vào/ra lò Oil/Liquid), `digits` (text chỉ số, giữ số 0 đầu), `time` (cũ).
- Tên input DOM = `prefix_rep_key`; khoá bản ghi giữ schema cũ (`doAm`, `reps`, `average`…). Xem `buildFullRecord()`.
- `renderFormForType(type)` dựng lại form (đổi loại, phiếu mới, nạp nháp, sửa phiếu).
- Thêm chỉ tiêu/loại mới = thêm cấu hình; chỉ viết kind mới khi cách đo hoàn toàn khác.
- **Người thực hiện:** 1 ô chọn CHUNG ở đầu mỗi khối (`sharedStaffHtml`); `collect` ghi cùng giá trị vào mọi lần đo (giữ schema `nguoiThucHien` cũ). Phiếu cũ có 2 người khác nhau → ô chung để trống + cảnh báo (không tự chọn).

**Chỉ tiêu theo loại**
- Powder: Độ ẩm, Tỷ trọng, Độ màu, Độ cặn (ảnh), pH, Acidity, Độ hòa tan (Nóng/Lạnh V/X + cảnh báo nhiệt độ 96–98 / 18–20 °C), Kích thước hạt (sàng), Ngoại vật (Absent/Present + ảnh).
- Coffee Oil: Moisture (Oven), Sediment, Density (g/L). Trường Type (FGs/Semi-FGs) → Customer tự điền (FGs→LDC, Semi-FGs→NA).
- Liquid: Brix, Dry Matter, Sediment (Grade + ảnh), pH, Acidity, Density (g/L), Foreign Matter.
- Công thức Oil/Liquid đã đối chiếu số mẫu trong Excel: Moisture = ((đĩa+nắp)+mẫu−sau sấy)/mẫu×100; Sediment (Oil) = (ống+cặn−ống)/(KL mẫu)×100; Dry Matter = (sau sấy−đĩa)/mẫu×100; Acidity = V×NaOH/0.1; **Density (g/L) = (bình+mẫu−bình)/dung tích×1000**, không mặc định dung tích (nhân viên nhập), hiển thị 1 chữ số thập phân. Nhiệt độ lò: Oil 102–104 °C, Liquid 94–96 °C, chỉ cảnh báo màu (xanh/đỏ), không đổi kết luận.
- **Công thức % mẫu trên sàng:** % = (KL mẫu+sàng − KL sàng) / tổng KL thu hồi × 100; chỉ tính khi đủ 8 cỡ hợp lệ và tổng > 0 (ngược lại hiện `--`); validate chặn mẫu+sàng < sàng, số âm, tổng = 0.

### 2.3. Hoàn thành chỉ tiêu & cảnh báo thiếu

- Một quy tắc dùng chung: `blockSpecs(b)` + `blockCompletion(b, get)` → `{complete, missing[], invalid[]}`; `get` đọc form (`fval`) hoặc bản ghi (`recordBlockGetter` + `blockReaders`). Hoàn thành = đủ MỌI trường của phương pháp và hợp lệ; số 0 = đã nhập; độc lập Đạt/Không đạt; ảnh không bắt buộc; ô có giá trị mặc định tính là đã có.
- Dùng cho: thanh tiến độ cố định ở form (x/N chỉ tiêu, `calcCompletion`), tiến độ trong chi tiết phiếu (`completionOfRecord(r)` → `null` ⇒ "Chưa xác định" nếu bản ghi cũ thiếu khối/khoá), màu xanh tên chỉ tiêu (`card__title--done`, dấu ✓), và alarm khi Lưu chính thức (`collectMissingResults` → modal `showMissingResultsModal`, bấm mục để focus ô; `refreshMissingNotes` cập nhật khi nhập tiếp). Trường thêm SAU các bản ghi cũ (Người thực hiện của Ngoại vật, `productionYear`) thiếu khoá thì bỏ khỏi tổng.
- Tách 3 khái niệm khi lưu: *hợp lệ dữ liệu* (`validateBeforeSubmit` + `blockValidationErrors` — chặn cả Force), *đầy đủ* (thiếu → chặn Lưu chính thức, Force bỏ qua; nút Force hiện khi còn thiếu), *chất lượng* (có chỉ tiêu Không đạt → `confirmSaveAlarm`, lưu `record.qcAlarm`). Lưu nháp không qua các bước này.

### 2.4. Quy tắc mã (Item Code / Batch / PO / SSCC / Customer)

Validator dùng chung UI + lưu: `validateSampleField`, `collectFieldErrors`, `setFieldError` (lỗi dưới ô, `aria-invalid`), `revalidateCodeFields`. Kiểm khi blur/change, không kiểm lúc đang gõ dở; lưu chính thức (kể cả Force) chạy lại; lưu nháp không kiểm.

- **Item Code, PO:** `<input inputmode=numeric>` (giữ số 0 đầu). Item Code phải tồn tại trong danh mục loại đang chọn.
- **Batch** (`parseBatchStructure`, `BATCH_RULE_*`): tự viết hoa, đúng cấu trúc theo loại — Powder 10 ký tự: 1 số năm + 3 số Julian + 4 số cuối PO + 1 chữ loại + 1 số line; Oil FGs `…OF<line>` (11 ký tự), Oil Semi-FGs `…O<line>` (10), Liquid `…L<line>`; kiểm Julian 1–366 + năm nhuận. Batch chỉ có 1 chữ số năm → field **"Năm SX (xác nhận)"** (`productionYear`): trống thì tự đoán năm gần nhất (±6 năm, hoà → để trống) và LUÔN hiện ghi chú "tự động…"; người dùng sửa thì chỉ kiểm khớp chữ số cuối. Ngày SX = năm xác nhận + Julian. Mở phiếu cũ chỉ đọc lại giá trị đã lưu.
- **PO Powder** tự sinh (`generatedPo/maybeGeneratePo`): Customer (6=INS, 7=LDC) + Line (Batch[10]) + 2 số cuối Năm SX xác nhận + "0" + 4 số cuối PO (Batch ký tự 5–8); chỉ điền khi PO trống hoặc đúng là PO app sinh trước đó (`state.poAutoValue`). Customer tự điền theo chữ số đầu PO (`applyCustomerFromPo`, không đè lựa chọn tay; lệch → lỗi tại ô, chặn lưu chính thức/Force). **6=INS, 7=LDC áp cho Powder và Liquid.**
- **SSCC:** 14 chữ số = PO(9) + "00" + **3 số nhân viên tự nhập** (VD 612600083 → 61260008300 → +221 → 61260008300221). Tiền tố tự điền `ssccSuggestPrefix` (`suggestZeros:2`); **KHÔNG tự tăng số**. Khi PO đổi, `syncSsccPrefix(old,new)` đổi tiền tố tự sinh, giữ phần người dùng gõ. 9 số đầu SSCC phải trùng PO (`ssccPoMessage`). Tiền tố chưa đủ 14 số bị chặn lưu chính thức; trống thì được.
- `poStructureMessage`: PO 9 số phải khớp Batch (4 số cuối, line), năm, chữ số thứ 5 = 0 (Powder), Customer theo chữ số đầu. Dữ liệu thiếu không bị coi là mâu thuẫn.
- **Coffee Oil Semi-FGs:** Customer NA, PO không có tiền tố Customer, không tự điền SSCC, **không kiểm cấu trúc/độ dài PO và SSCC** (chỉ chuỗi chữ số) — cấu trúc thật chưa xác nhận.

### 2.5. Ngưỡng (Spec) & độ lặp lại

- `getThreshold(type, customer, label, recipe)` lọc theo loại; nhiều dòng theo dải Recipe thì so 2 số đầu (giả định chưa QA xác nhận §10).
- **Density g/L:** block khai báo `thresholdUnit:'g/L'`; dòng Spec chỉ dùng khi có `unitBasis:'g/L'`. `migrateDensityThresholds()` chỉ ×1000 các dòng còn đúng giá trị seed cũ (`0.92-1.2`, `1.184-1.223`); dòng khác bị tô nền ở tab Spec, phiếu hiện "Cần xác nhận đơn vị ngưỡng", chỉ tiêu ở trạng thái chờ tới khi Supervisor/Admin nhập lại theo g/L (sửa ô Yêu cầu = xác nhận). Phiếu cũ (không `unitBasis`) không bị tính lại; chi tiết ghi "Lưu theo đơn vị cũ (g/ml), không tự quy đổi".
- **Độ lặp lại theo Customer:** `getRepeatConfig()` ưu tiên đúng Customer → "Mặc định chung" (customer rỗng) → `null` ("chưa cấu hình ngưỡng", không coi là 0). Chặn trùng (loại+chỉ tiêu+Customer). Chỉ cảnh báo đỏ, không đổi Kết luận. Dung tích Oil/Liquid chưa có dòng nào (Excel không nêu).

### 2.6. Phê duyệt phiếu & sửa phiếu đã lưu

- Trạng thái `record.approval = {status, by, at, reason?, history[]}`: `pending` (chờ duyệt) → `approved` | `returned` (trả lại, **bắt buộc lý do**) → sửa → tự về `pending` ("gửi duyệt lại"). Ánh xạ cũ khi ĐỌC (`LEGACY_APPROVAL_MAP`): `approved→approved`, `not_approved`/thiếu→`pending`, `rejected→returned`.
- `approveRecord()`, `returnRecordForEdit()`, `resumeRecordForEdit()`; Lịch sử/Dashboard/CSV lọc bỏ bản `archived`.
- **Khoá bản đã duyệt:** sửa phiếu `approved` → khi Lưu (`submitRecord`) bản đang duyệt được lưu thành bản `archived:true` id riêng (`<id>_approved_<ts>`, `versionOf` trỏ về id gốc), id gốc nhận nội dung mới, `version+1`, về `pending`. Bản archive chỉ lưu SAU khi người dùng xác nhận cảnh báo Không đạt. Chi tiết phiếu liệt kê các phiên bản trước.
- `canEditSavedRecord(r)`: chờ duyệt → quyền `history.editSaved`; đã duyệt → `history.editApproved`; bị trả lại → người có quyền nhập liệu. Mỗi lần sửa ghi `record.edits[] = {at,by,role,version,count,changes[{field,from,to}]}` (`recordChanges`) + Audit Log `edit-saved-record`.
- "Lưu nháp" không đè phiếu đã lưu chính thức thành nháp. `meta.createdBy/createdAt` được bảo toàn qua mọi lần sửa.
- Lịch sử: bộ lọc loại, tìm Item/PO/Batch/Product Name, Customer, Kết luận, Phê duyệt, Nháp/chính thức, ngày lưu, MFG từ–đến (`parseVNDate`); cột PO + MFG; Nháp lên đầu; `state.filteredHistory` = đúng thứ tự bảng nên CSV khớp bảng; nút "Tiếp tục nhập" ngay trên dòng nháp.

### 2.7. Excel Item Code (`XlsxLite`)

Module tự viết: ghi zip STORE + chuỗi nội tuyến định dạng Text (giữ số 0 đầu); đọc zip + `DecompressionStream('deflate-raw')` (cần trình duyệt mới). Tab Item Code: "Tải Template", "Xuất dữ liệu", "Nhập từ .xlsx…". Cột: Loại sản phẩm | Item Code | Product Name | Recipe (+ sheet "Huong dan"). Nhập: xem trước (thêm mới / cập nhật before→after / không đổi / lỗi / cảnh báo), chỉ ghi khi "Xác nhận nhập"; khoá = loại + Item Code; mã vắng trong file giữ nguyên; **có dòng lỗi → không ghi gì**; trùng hoàn toàn chỉ cảnh báo (powder 11000018 trùng sẵn trong dữ liệu gốc); Item Code dạng số trong file bị cảnh báo (có thể mất số 0 đầu). Ghi qua `persistItemCodes()`; Audit Log `import-itemcode`/`export-itemcode`. Nhập Excel cần cả quyền thêm và sửa Item Code.

### 2.8. Parameters

Mỗi dòng có `id` ổn định; dòng người dùng thêm có `origin:'user'` → sửa được "Chỉ tiêu"/"Trường" nếu có quyền `param.edit` (chặn trống/trùng; Audit `rename-param`; chỉ đổi dòng tham chiếu, không đụng Spec/Độ lặp lại/cấu hình form). Dòng `system` (seed) hoặc không có `origin` (dữ liệu cũ, không phân biệt được) bị khoá tên.

### 2.9. Theme "ILD Crafted"

- Nền kem `#F7F0E6`, espresso, logo thật nhúng base64 trên nền trắng. Token màu: đổi GIÁ TRỊ (không đổi tên) các biến `:root` + thêm `--input-border`, `--focus-ring`, `--primary-hover`, `--accent-brown`, `--accent-red`. Ý nghĩa màu Đạt/Không đạt/Chấp nhận/Pending giữ nguyên.
- Nút "🎨 Giao diện" → overlay RIÊNG `#ild-theme-overlay` (IIFE `ildCraftedTheme`, cuối script, không dùng chung `Modal`). 4 cấu hình mẫu (`crafted-standard/soft/dark/sharp`), Sáng/Tối/Hệ thống, Tương phản (`data-ild-contrast`), Độ đậm (`data-ild-emphasis`, chỉ đổi `font-weight` ở tập tiêu đề/nhãn rộng, không phủ mọi chữ đậm). Lưu `localStorage['ild-crafted-appearance-v1']`. Radio thật, Escape đóng, trả focus.
- **Xung đột đã biết (CHƯA xử lý):** tab Cài đặt còn thẻ "Giao diện" cũ `#theme-select` (Light/Dark) + `persistTheme` + khối trong `loadMasterDataFromDb` cũng gán `document.documentElement.dataset.theme` (key `settings.theme`). Hai nơi có thể ghi đè nhau (chọn Dark ở thẻ cũ khi Theme ILD đang Sáng, hoặc `settings.theme` đã lưu đè lúc nạp). Cần chủ dự án quyết định: nên bỏ thẻ cũ và dùng Theme ILD làm nơi duy nhất.

### 2.10. Đồng bộ Supabase & đăng nhập

- `CONFIG.supabase = {enabled:true, auth:true, url, key(publishable)}`; `CONFIG.loginRequired=false` chỉ áp khi `auth:false`.
- **`Sync`** (fetch tới PostgREST, không SDK): ghi/xoá cục bộ vào hàng đợi `localStorage['labrecord_syncq']` rồi đẩy `lab_records`/`lab_settings`/`lab_audit` + bucket `lab-attachments`. Phiếu: last-write-wins theo `meta.updatedAt`, xoá = tombstone `deleted=true`; danh mục: ghi đè cả tài liệu, mới hơn thắng (2 máy cùng sửa 1 danh mục → mất một bên). `SYNC_SETTINGS = [staff, thresholds, fieldMapping, itemCodes, repeatability, permissions]`. Hàng đợi bỏ qua mục bị server từ chối 4xx và báo lỗi ở header. Mục bị 4xx do RLS (nếu RLS máy chủ chặt hơn giao diện) sẽ không đồng bộ — xem §7.
- Tối ưu egress: `lab_settings` kéo `key,updated_at` trước rồi chỉ tải `value` mới hơn; đồng bộ định kỳ 3 phút, bỏ khi tab ẩn; Data Log tải gia tăng (`fetchAudit(since)`, cache `dataLogRemote`); ảnh nén (`compressImage` cạnh dài ≤1600px, JPEG 0.8 khi >300 KB, giới hạn gốc 15 MB) + `attachmentRefCache`. Chưa làm: bỏ việc máy tải lại phiếu do chính nó đẩy (cần `device_id`), Realtime.
- **`Auth`** (`auth:true`): đăng nhập email hoặc **tên đăng nhập** (tên → email nội bộ `<tên>@<projectref>.users.internal`; `Auth.toEmail` phải khớp `usernameToEmail` của Edge Function), token Bearer tự refresh, phiên `localStorage['labrecord_auth']`, vai trò từ bảng `profiles`; `Auth.validate()` kiểm lại phiên khi mở (thu hồi → đăng nhập lại; offline giữ phiên). `auth:false` → đăng nhập cục bộ bằng `USERS` (mặc định: Trân/Huy/Hiền/Định/Trang/Triều `1234` inspector, `Supervisor`/`sup1234`, `Admin`/`admin1234`; **chỉ để phát triển — không bảo mật thật**, mật khẩu chữ thường).
- Tab **Người dùng** (Admin): danh sách/thêm/đổi vai trò/vô hiệu hoá qua Edge Function `admin-users` (service_role chỉ ở server). Người dùng tự có hồ sơ inspector khi tạo ở Dashboard; Admin đổi vai trò ở tab này. Nên TẮT "Allow anonymous sign-ins".
- Tab **Data Log** (Supervisor+ theo mặc định): mọi thao tác ghi bởi `AuditLog.log` (ai/máy/lúc nào/hành động/chi tiết), mã máy `labrecord_device_id` + tên máy tự đặt (`Device`), gộp log máy khác từ `lab_audit` khi đã đăng nhập, lọc + xuất CSV, tối đa 500 dòng hiển thị.

### 2.11. Khác

- Auto Save mỗi 20 s khi ở tab Nhập liệu → bản ghi cố định `draft_current` (khác "Lưu nháp" tạo bản ghi nháp riêng); `checkAutoRecovery()` hỏi khôi phục khi mở lại; chỉ chạy sau đăng nhập.
- Ảnh đính kèm (Độ cặn, Ngoại vật, Sediment Liquid…): Blob trong IndexedDB, đa ảnh cộng dồn + thư viện xem trước; ảnh đã đẩy lên bucket nhưng **app chưa hiển thị ảnh kéo về từ máy khác**.
- Xuất: CSV (Lịch sử/Data Log), PDF qua `window.print` (`printRecord`, `printFullReport`; in dùng `body.is-printing`), Backup/Restore JSON (gồm ma trận quyền).
- Thanh tiến độ ở form dính (`.completion-row--sticky`, `--sticky-offset` do `updateStickyOffset()`); `.main-content:has(> #panel-form.is-active){overflow:visible}` để sticky hoạt động (vì `.main-content{overflow-y:auto}` sẽ vô hiệu nó) và `#analysis-form{overflow-x:auto}` cho bảng sàng trên mobile.

---

## 3. Phân quyền

Vai trò: `inspector`(1) < `supervisor`(2) (nhãn "Manager") < `admin`(3). **Admin luôn đủ quyền** (checkbox khoá). Ma trận có **21 quyền** trong `PERMISSION_DEFS`; Admin chỉnh ở **Cài đặt → "Phân quyền theo vai trò"** (lưu `settings.permissions`, đồng bộ, vào backup). Bảng dưới là **mặc định** (theo file "Quản lý người dùng.xlsx"):

| Quyền | Inspector | Supervisor |
|---|---|---|
| Nhập liệu (`form.entry`) | ✔ | ✔ |
| Lịch sử: xem / tiếp tục nháp | ✔ | ✔ |
| Lịch sử: phê duyệt, sửa phiếu đã lưu, sửa phiếu đã duyệt, xoá | ✘ | ✔ |
| Item Code: hiển thị / thêm / sửa-xoá (gồm Excel) | ✔ | ✔ |
| Spec, Parameter, Độ lặp lại: hiển thị (tab) | ✘ (ẩn) | ✔ |
| Spec, Parameter, Độ lặp lại: thêm / sửa-xoá | ✘ | ✘ (chỉ xem; chỉ Admin) |
| Data Log | ✘ | ✔ |
| Người dùng (`users.manage`) | ✘ | ✘ (khoá Admin-only) |

Tab **Cài đặt** và **Người dùng** là Admin cố định. Inspector vẫn sửa được phiếu bị TRẢ LẠI (để gửi duyệt lại). Supervisor không thấy tab Người dùng vì Edge Function chỉ cho Admin (muốn Supervisor xem chỉ-đọc phải sửa function — chưa làm).

- API: `userCan(key)`, `requirePerm(key)`, `permAllowed`, `TAB_PERMS`, `applyRolePermissions()`, `applyEditPermissions()` (alias `applyAdminOnlyEditing`; ẩn dòng thêm khi thiếu quyền thêm, khoá ô/nút khi thiếu quyền sửa-xoá, ghi chú "chỉ XEM"), `requireAdminEdit()`/`requirePerm` chặn ở từng handler. Phụ thuộc tự động: bật thêm/sửa/duyệt/xoá → tự bật hiển thị tab; tắt hiển thị → tắt quyền phụ thuộc; thu quyền tab đang mở → về Tổng quan. Mỗi thay đổi ghi Audit `edit-permissions`.
- **Đây là kiểm soát ở GIAO DIỆN** (ẩn/hiện bằng `hidden`, bypass được bằng DevTools). Quyền thật phụ thuộc RLS/trigger ở Supabase — hiện RLS trong `auth.sql` còn cũ (§7).

---

## 4. Schema bản ghi (rút gọn)

`record = { id, productType, sampleInfo:{itemCode, recipe, productName, customer, type?, batch, productionYear, productionDate(dd/mm/yyyy), po, sscc,…}, parameters:{<khoá chỉ tiêu>:{reps/rows, average, difference, range, status, enteredAt, dieuKien?, attachments[], …}}, notes, conclusion, reviewedBy, reviewedDate, approval, version, archived?, versionOf?, edits[], qcAlarm?, forcedClose, draft?, meta:{createdBy, createdAt, updatedBy, updatedAt} }`. Chi tiết thật: `buildFullRecord()`. Khoá chỉ tiêu Powder: `doAm, tyTrong, doMau, doCan, ph, acidity, hoaTan, kichThuoc, ngoaiVat`; Oil/Liquid theo `TYPE_CONFIG`. Dữ liệu thiếu `productType` được gán `powder` khi nạp (`migrateProductTypes`).

---

## 5. Tính năng đã hoàn thành (tóm tắt)

Form động 3 loại; kết luận tự động; tiến độ + alarm thiếu; alarm Không đạt; validate mã (Item/Batch/PO/SSCC/Customer); phê duyệt có phiên bản; sửa phiếu đã lưu có lịch sử thay đổi; Lịch sử/Tra cứu nhiều bộ lọc; CSV/PDF/Full Report; Item Code CRUD + Excel; Spec/Parameters/Độ lặp lại theo loại (+ theo Customer cho độ lặp lại); ma trận quyền Admin chỉnh được; Data Log; Supabase Sync + Auth + quản lý người dùng; Theme ILD Crafted; Backup/Restore; Auto Save/Recovery; Dashboard.

---

## 6. Tương thích ngược (đừng phá)

- Đọc phiếu cũ không được tự tính lại/đổi dữ liệu: Năm SX không tự đoán lại, Density cũ không quy đổi, Customer không bị đổi khi mở xem, thời gian sấy cũ không đúng `mm:ss` để 2 ô trống (giá trị gốc vẫn nằm trong bản ghi và hiển thị ở xem/in/CSV), giờ lò cũ `HH:mm` / `HH:mm:ss` đều đọc được, approval cũ qua `LEGACY_APPROVAL_MAP`.
- Mã người dùng nhập (batch/item/PO/SSCC/Customer…) luôn escape khi dựng HTML (`escapeAttr`/`escapeHtml`). Tìm kiếm Item Code phải bọc `String(x||'')` (dữ liệu cũ có thể là số/thiếu).
- Không đổi khoá bản ghi hiện có; thêm khoá mới phải chịu được bản ghi cũ thiếu khoá đó.

---

## 7. Supabase — trạng thái các file SQL

| File | Việc | Trạng thái |
|---|---|---|
| `schema.sql` | Bảng + bucket + policy mở | **Đã chạy** trên project thật (2026-09-25), đã test đẩy/kéo/tombstone/ảnh; dữ liệu thử đã xoá |
| `auth.sql`, `users.sql` | `profiles`, `lab_level()`, RLS theo vai trò | Viết xong; **chưa test với tài khoản thật + RLS thật** (xác nhận lại với chủ dự án trạng thái đã chạy hay chưa trước khi giả định) |
| `approval_flow.sql` | Trigger phê duyệt/khoá bản đã duyệt | **CHƯA chạy** |
| `permissions_matrix.sql` | `lab_can(perm)`; policy `lab_settings`; trigger phiếu theo ma trận. **Thay thế** `approval_flow.sql` (tự tạo lại trigger `lab_records_guard`) | **CHƯA chạy** |
| Edge Function `admin-users` | Tạo/khoá user (Admin) | **Chưa deploy/test trên Supabase thật** (mới test UI với server giả lập). File đã dọn khối "Hello world" thừa |

Hệ quả cần biết: cho tới khi chạy `permissions_matrix.sql`, RLS cũ của `auth.sql` còn là: Item Code cần Supervisor (Inspector sẽ bị server từ chối → mục bị bỏ khỏi hàng đợi + báo lỗi header), Spec/Độ lặp lại cho Supervisor ghi. Giới hạn của `permissions_matrix.sql`: server không kiểm `form.entry`/`history.view`/Data Log theo ma trận; mảng danh mục là 1 hàng JSON nên cho ghi nếu có MỘT trong quyền thêm/sửa; quy tắc "chỉ sửa dòng Parameter tự nhập" chỉ ở giao diện; người dùng đang đăng nhập nhận ma trận mới sau lần đồng bộ kế (≤ ~3 phút) hoặc khi tải lại. Xung đột 2 máy sửa cùng phiếu quanh lúc duyệt vẫn dựa last-write-wins, chưa có cảnh báo xung đột chủ động.

Thứ tự chạy + hướng dẫn deploy Edge Function: `supabase/README.md`. **Người phụ trách tự chạy trong SQL Editor; AI không chạy migration trên project thật.**

---

## 8. Giả định nghiệp vụ CHƯA được QA xác nhận

1. Khớp ngưỡng theo dải Recipe (so 2 số đầu) — nhánh "Low Density" của Tỷ trọng-LDC rơi về dòng đầu.
2. Ngoại vật Powder: đơn giản hoá Absent = Đạt / Present = Không đạt (quy tắc gốc "tối đa 10 hạt <1mm, tối đa 1 hạt >1mm" chưa implement).
3. `REPEATABILITY` mặc định Powder (0.1 / 5 / 1 / 0.05 / 0.05) là ước lượng; cảnh báo tự động chỉ chạy với chỉ tiêu 2 lần đo có dòng cấu hình.
4. Quyền xoá phiếu = Supervisor+ do AI tự chọn; chủ dự án chỉ xác nhận riêng quyền Force.
5. Quyền Force đóng Report: ai có quyền nhập liệu cũng dùng được (gắn nhãn "⚠ Force").

---

## 9. Chạy / test

Không cần cài đặt. **A.** Double-click `index.html` (Chrome/Edge) — **chưa từng được kiểm thử bằng `file://` thật**; `Storage.mode()` có thể rơi về localStorage. **B.** Local server (khuyên dùng):

```bash
cd C:\Users\BinhDang\Documents\GitHub\LABRecord
python -m http.server 8765
# mở http://localhost:8765
```

`.claude/launch.json` (cổng 8765, `--directory` tuyệt đối) dùng cho Browser pane của Claude Code. Trong các phiên trước, preview đôi khi phục vụ bản/thư mục cũ → kiểm tra `fetch('/index.html')` có nội dung mới, hoặc chạy `python -m http.server 8766` và mở `http://localhost:8766?v=<timestamp>` để tránh cache. Browser pane **không chạy JS trên `file://`** ngoài thư mục project. Khi pane ẩn, animation/screenshot chập chờn → kiểm bằng DOM/JS (`read_page`, `javascript_tool`).

**Kiểm cú pháp:** có 2 thẻ `<script>` (bootstrap theme nhỏ ở head và script nghiệp vụ lớn ở cuối; kiểm cả hai): tách nội dung giữa `<script>`…`</script>` ra file `.js` rồi `node --check`. **Không có test tự động**; mọi kiểm tra là thủ công qua Console/JS.

**Kiểm nhanh sau khi sửa:** (1) Console không lỗi đỏ khi tải; (2) đăng nhập (Supabase hoặc `Admin / admin1234` khi `auth:false`); (3) Nhập liệu Powder: Item Code `11000028`, Batch `62550110F1` → Recipe `405A`, Ngày SX theo Julian + Năm SX xác nhận; (4) điền chỉ tiêu → kết luận + tiến độ cập nhật; (5) Lưu phiếu → Lịch sử → F5 → còn phiếu; (6) đổi loại Oil/Liquid dựng được form, lưu + nạp lại bản ghi giống hệt (so JSON).

Ghi chú công cụ (Windows): shell là Git Bash/PowerShell; script Python/JS lớn nên ghi ra file rồi chạy (heredoc dài dễ hỏng quoting); `pkill` không có — dừng server bằng PowerShell `Get-CimInstance Win32_Process`.

---

## 10. Việc còn chờ xác nhận / chưa làm

**Chờ chủ dự án xác nhận (không đoán):**
1. Cách suy ra năm đầy đủ nếu bỏ ô "Năm SX (xác nhận)" (hiện bắt buộc xác nhận vì Batch chỉ có 1 chữ số năm).
2. Cấu trúc đầy đủ PO/SSCC của **Coffee Oil Semi-FGs** và 2 chữ số "mã sản phẩm" đầu PO/SSCC của Oil/Liquid (chỉ kiểm chuỗi số).
3. Thuật toán sinh/tăng 3 số cuối SSCC (hiện nhân viên tự nhập; đã bỏ đề xuất "bộ đếm theo PO").
4. **Spec cho Customer khác:** Oil Semi-FGs = NA; Liquid LDC. File Mapping trỏ tới "bảng Thông tin Kết luận" của Oil/Liquid nhưng chưa được cung cấp → hiện chỉ có seed LDC (Oil) và INS (Liquid); Customer khác ở trạng thái chờ tới khi Admin thêm dòng ở tab Spec.
5. Dung sai Độ lặp lại cho Oil/Liquid (chưa có dòng nào).
6. Ngưỡng Density Coffee Oil: Mapping ghi 1.184–1.223, Form ghi 0.92–1.2 → đã dùng giá trị Form (920–1200 g/L); xác nhận.
7. Danh mục Item Code đầy đủ của Oil/Liquid (mới 1 mã ví dụ/loại).
8. Quyết định về thẻ Theme cũ ở Cài đặt (§2.9).
9. Quyền Supervisor xem tab Người dùng (cần sửa Edge Function).
10. Seed Parameters của Liquid trong `SEED_BY_TYPE` vẫn có ghi chú Excel cũ "6-LDC, 7-Instanta" (chỉ là tài liệu; quy tắc áp dụng trong code là 6=INS, 7=LDC) — sửa ở tab Parameters nếu cần.

**Chưa làm / ý tưởng:** kiểm thử thật Supabase (RLS, Edge Function, đồng bộ 2 máy, ảnh kéo về máy khác); mở bằng `file://` thật; đo độ tương phản bằng công cụ; "Độ đậm" Theme chưa phủ mọi `font-weight`; kiểm tra bằng Excel thật (mới thử openpyxl) cho import/export Item Code; giao diện mobile của các mục mới (chỉ kiểm sticky/overflow cơ bản ở 375px); Ngoại vật theo quy tắc hạt; bỏ việc tự tải lại phiếu do chính máy đẩy; Realtime; cảnh báo xung đột 2 máy sửa cùng phiếu; thay đổi mật khẩu mặc định/`CONFIG.supabase` trước khi giao dùng thật.

---

## 11. Lịch sử thay đổi (rút gọn, để biết vì sao code như vậy)

- Vòng 1–2 (Phần 1–5 + 13 mục): form Powder, lưu IndexedDB, Backup, thanh tab ngang, Item Code CRUD, SSCC gợi ý, tab Độ lặp lại, Full Report, đa ảnh, timestamp theo khối, tiến độ, Force đóng Report, đăng nhập + phân quyền.
- Supabase Sync + Auth + Edge Function người dùng + Data Log; tối ưu Egress (2026-09-26).
- Loại sản phẩm + Form Engine cấu hình (Powder chuyển sang cấu hình, đối chiếu số liệu trùng bản cũ).
- Đợt theo `Comment-Lab Record.xlsx` (2026-09-29 → 10-05): Batch/Năm SX, Người thực hiện chung, mm:ss, cảnh báo nhiệt độ hoà tan, validate sàng, alarm Không đạt, Lịch sử nhiều bộ lọc, flow phê duyệt, lọc Spec theo Customer, sticky progress, tiến độ trong chi tiết phiếu, alarm thiếu, báo lỗi định dạng tại trường, hoàn thành theo chỉ tiêu, Customer theo PO.
- ILD Crafted rebrand + Theme (2026-09-29).
- Coffee Oil + Liquid (2026-10-05): form, công thức, Batch theo loại, seed, engine `pair.shared`/`hhmm`.
- Đợt 2026-10-06: SSCC/PO tự điền + đối chiếu mã, giờ lò hh:mm, Density g/L, Supervisor sửa phiếu đã lưu + lịch sử chỉnh sửa, Excel Item Code, sửa tên Parameter, độ lặp lại theo Customer, ma trận quyền theo "Quản lý người dùng.xlsx" rồi cho Admin chỉnh trong Cài đặt.
- 2026-10-06 (dọn dẹp): viết lại HANDOFF; xoá `supabase/settings_permissions.sql` (bị `permissions_matrix.sql` thay thế); bỏ khối "Hello world" thừa trong `admin-users/index.ts`; cập nhật `supabase/README.md`.

**Phương pháp kiểm thử đã dùng (cục bộ, chưa Supabase thật):** Console/JS trên `http://localhost:8766` qua Browser pane — Powder/Oil/Liquid đủ luồng nhập→lưu→nạp lại giống hệt, công thức theo số mẫu Excel, mọi validator mã, sticky/mobile 375px, 3 vai trò × ma trận quyền, flow duyệt/trả lại/phiên bản, Excel round-trip (240 dòng, 0 lỗi), `node --check` sau mỗi bước. Không có lỗi Console ở các lượt kiểm.
