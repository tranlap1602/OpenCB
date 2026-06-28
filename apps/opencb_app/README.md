# OpenCB App

Đây là Flutter Windows app cho MVP OpenCB.

## Hiện Có

- Giao diện tiếng Việt Material 3.
- Light/system/dark mode và preset màu Material You.
- Bắt clipboard text native trên Windows.
- Bắt clipboard image native trên Windows và preview ảnh đã lưu.
- Bắt file reference khi copy file trong Explorer.
- Lưu lịch sử local bằng SQLite qua Rust core, có fallback JSON cho test/dev khi DLL chưa có.
- Search, preview, ghim, sửa thẻ, xóa, bulk actions, dọn mục chưa ghim có xác nhận và copy lại vào clipboard.
- Cài đặt retention, bắt/tạm dừng clipboard, phím tắt, tự mở cùng Windows, loại clipboard được bắt và danh sách app nguồn không bắt clipboard.
- Sync text clipboard qua LAN với discovery tự thấy thiết bị, manual pairing code, QR/payload copy-dán nhanh, auto sync nền và trạng thái online/offline.
- Android có thể scan QR pairing để test sync LAN cơ bản.
- Phím tắt toàn cục `Ctrl+Alt+V` để mở quick picker, tìm nhanh, chọn bằng phím và tự paste vào ô nhập liệu trước đó.
- System tray: đóng cửa sổ để ẩn xuống tray, click một lần mở quick picker, double click hoặc menu mở app chính.
- Mục Dữ liệu trong Cài đặt hỗ trợ mở thư mục dữ liệu, tạo backup JSON và xóa toàn bộ lịch sử có xác nhận.

## Chạy Dev

```powershell
flutter run -d windows
```

Trong terminal dev:

- `r`: hot reload.
- `R`: hot restart.
- `q`: thoát.

## Build

```powershell
flutter build windows --release
```

Exe nằm tại:

```text
build\windows\x64\runner\Release\opencb_app.exe
```

## Ghi Chú Kỹ Thuật

App dùng MethodChannel `opencb/windows_clipboard` để nhận clipboard event từ Windows runner và dùng Dart FFI để gọi `opencb_core.dll` cho storage/search/dedupe/retention. Bản Windows release copy `opencb_core.dll` cạnh `opencb_app.exe`. LAN sync lưu identity trong `sync_identity.json`, peer đã pair trong `sync_peers.json` và hỗ trợ QR/payload dạng `opencb://pair?...` để scan hoặc copy/dán nhanh khi thêm thiết bị. Cài đặt retention/excluded sources nằm trong `clipboard_settings.json`.
