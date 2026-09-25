# Supabase — thiết lập cho Lab Record

Chạy theo thứ tự, trong **SQL Editor** (Dashboard → SQL Editor → New query → dán → Run). Chạy lại được.

| Thứ tự | File | Việc |
|---|---|---|
| 1 | `schema.sql` | Bảng phiếu / danh mục / nhật ký, kho ảnh |
| 2 | `auth.sql` | Bảng `profiles` (vai trò), RLS theo vai trò |
| 3 | `users.sql` | Cột `disabled` / `username`, vô hiệu hoá tài khoản |
| 4 | Edge Function `admin-users` | Cho tab **Người dùng** tạo/khoá tài khoản (bên dưới) |

## Triển khai Edge Function `admin-users`

Tạo user cần `service_role` key — key này **không được** đặt trong `index.html`, nên việc tạo/khoá tài khoản chạy trong Edge Function trên server (Supabase tự cấp key cho function).

**Cách 1 — Dashboard (không cần cài gì):**
1. Dashboard → **Edge Functions** → **Deploy a new function** → **Via Editor**.
2. Tên function: `admin-users` (đúng chính xác).
3. Xoá code mẫu, dán toàn bộ nội dung `supabase/functions/admin-users/index.ts` → **Deploy**.
4. Giữ bật **Verify JWT** (mặc định).

**Cách 2 — CLI:** `supabase functions deploy admin-users --project-ref stkxfpceffdtkxcrcrtw`

Kiểm tra: đăng nhập Admin → tab **Người dùng** → danh sách hiện ra. Nếu báo "Chưa triển khai Edge Function" là chưa deploy hoặc sai tên.

## Tên đăng nhập không cần email
Ô "Tên đăng nhập" khi tạo user (không có `@`) được đổi thành email nội bộ `<tên>@stkxfpceffdtkxcrcrtw.users.internal` (không gửi thư). Người dùng chỉ gõ tên. Nếu nhập địa chỉ có `@` thì họ đăng nhập bằng email đó. Phép biến đổi này nằm ở hai nơi phải luôn giống nhau: `Auth.toEmail` trong `index.html` và `usernameToEmail` trong Edge Function.

## Bảo mật
- Người gọi function phải là Admin đang hoạt động (kiểm tra bằng JWT của họ + bảng `profiles`); function không tin dữ liệu từ trình duyệt về vai trò.
- Không thể tự hạ quyền nếu là Admin duy nhất, không thể tự vô hiệu hoá chính mình.
- Nên TẮT "Allow anonymous sign-ins" trong Authentication.
