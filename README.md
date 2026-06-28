# OpenCB

OpenCB là MVP quản lý clipboard theo hướng **Windows trước, local-first**. Mục tiêu dài hạn là trở thành workspace clipboard/bookmark đa nền tảng cho Windows, Ubuntu và Android.

## Hiện Trạng

- `crates/opencb_core`: Rust core nền tảng với SQLite schema, CRUD, deduplication, FTS search, retention cleanup, blob image storage, trusted device primitives và C ABI cho Flutter.
- `apps/opencb_app`: Flutter app cho Windows và Android với giao diện tiếng Việt Material 3, light/system/dark mode, preset màu Material You, bắt clipboard text/image/file-reference native trên Windows, Android UI dọc, system tray/background lifecycle trên Windows, phím tắt `Ctrl+Alt+V`, quick picker, lưu SQLite qua Rust core, search, ghim, sửa thẻ, xóa, dọn lịch sử chưa ghim có xác nhận, chỉnh retention, loại trừ app nguồn, copy/auto paste và LAN sync.
- `docs/mvp.md`: Ghi chú sản phẩm/kỹ thuật cho phạm vi MVP hiện tại.

## Chạy Khi Phát Triển

```powershell
cargo test
cd apps\opencb_app
flutter test
flutter run -d windows
```

Android debug:

```powershell
cd apps\opencb_app
flutter run -d <device-id>
```

Khi chạy bằng `flutter run -d windows`, có thể dùng:

- `r`: hot reload.
- `R`: hot restart.
- `q`: thoát app.

## Bản Build

```powershell
cd apps\opencb_app
flutter build windows --release
```

Android debug APK:

```powershell
cd apps\opencb_app
flutter build apk --debug
```

File chạy nằm ở:

```text
apps\opencb_app\build\windows\x64\runner\Release\opencb_app.exe
```

## Dữ Liệu Local

OpenCB lưu dữ liệu người dùng trong `%APPDATA%\OpenCB`:

- `opencb.sqlite3`: lịch sử clipboard, FTS index, blob ảnh và metadata.
- `clipboard_history.json`: lịch sử cũ, được import/dedupe vào SQLite khi app mở.
- `sync_peers.json`: danh sách thiết bị LAN đã thêm.
- `clipboard_settings.json`: giới hạn lưu clipboard và danh sách app nguồn bị loại trừ.
- `theme.json`: chế độ giao diện và preset Material You.

## Sync LAN

Mỗi app đang chạy lắng nghe TCP port `47873` và broadcast discovery trong LAN. Trên máy khác cùng LAN/VPN, có thể thêm peer bằng một trong ba cách:

- Quét QR pairing ở tab `Thiết bị`.
- Copy payload pairing ở tab `Thiết bị`, dán vào dialog `Thêm thiết bị LAN`, rồi bấm `Áp dụng payload`.
- Nhập tay peer dạng `host:47873` kèm mã pairing hiển thị trên máy kia.

Sau khi thêm peer, OpenCB sync hai chiều các clipboard mới/chưa có, có sync ngay khi copy nếu peer online, và có cơ chế tombstone để clipboard đã xóa không bị hồi lại.

Sync LAN hiện tại tập trung vào clipboard text/code/url. File reference được lưu local nhưng chưa sync nội dung file thật.

## Giao Diện Material 3

App mặc định dùng Light mode và có thể đổi giữa:

- Sáng.
- Hệ thống.
- Tối.

Các preset màu Material You hiện có:

- Xanh OpenCB.
- Tím Material.
- Xanh Đại Dương.
- Mực Lam.
- Xanh Rừng.
- San Hô Hoàng Hôn.

## Phím Tắt

Nhấn `Ctrl+Alt+V` để mở quick picker, tìm nhanh clipboard và sao chép lại mục đã chọn. Có thể mở quick picker bằng nút tia sét ở top bar.

## System Tray

Khi bấm nút đóng cửa sổ, OpenCB sẽ ẩn xuống system tray và tiếp tục chạy nền để bắt clipboard/sync LAN.

- Double click tray icon để mở lại.
- Chuột phải tray icon để chọn `Mở OpenCB` hoặc `Thoát`.

## Version Và Release

- `CHANGELOG.md`: ghi thay đổi theo từng version.
- `docs/versioning-and-release.md`: quy ước version, branch, tag và release qua GitHub.
- `.github/workflows/ci.yml`: CI kiểm tra Rust core và Flutter app.
- `.github/workflows/release-windows.yml`: tạo Windows portable artifact khi push tag `v*`.

Lệnh tag release mẫu:

```powershell
git tag v0.1.0
git push origin main
git push origin v0.1.0
```

## Mốc Tiếp Theo

- Mã hóa payload sync LAN.
- Pause rules theo thời gian và điều kiện nâng cao.
- Tối ưu thumbnail/lazy loading cho thư viện ảnh lớn.
- Chuẩn bị adapter Ubuntu và Android.
- Installer Windows, ký app và kênh auto-update.

Chi tiết roadmap nâng cấp sâu nằm trong `docs/mvp.md`, `docs/sync-lan.md` và `docs/windows-production.md`.
