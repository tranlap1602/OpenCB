# OpenCB

OpenCB là ứng dụng quản lý clipboard và gửi file trong mạng LAN cho Windows và Android.

## Tính Năng Chính

- Lưu lịch sử clipboard: văn bản, URL, code, ảnh và đường dẫn file/folder.
- Tìm kiếm nhanh, ghim, gắn thẻ và xóa clipboard.
- Quick picker trên Windows bằng phím tắt.
- Sync clipboard qua LAN giữa các thiết bị đã ghép nối.
- Gửi file/folder qua LAN giữa Windows và Android.
- Android có foreground service và nút gửi clipboard từ thông báo chạy nền.
- Giao diện tiếng Việt, Material 3, light/dark/system mode và nhiều theme màu.

## Nền Tảng

- Windows: app chính, quick picker, system tray, clipboard background.
- Android: giao diện mobile, sync LAN, gửi/nhận file, share file từ app khác.
- Ubuntu: chưa hỗ trợ trong MVP hiện tại.

## Chạy Khi Phát Triển

```powershell
cd apps\opencb_app
flutter pub get
flutter run -d windows
```

Android:

```powershell
cd apps\opencb_app
flutter run -d <device-id>
```

Rust core:

```powershell
cargo test --workspace
```

## Build Local

Windows:

```powershell
cargo build --release --package opencb_core
cd apps\opencb_app
flutter build windows --release
```

Android debug:

```powershell
cd apps\opencb_app
flutter build apk --debug
```

## Release

Release được tạo bằng GitHub Actions khi push tag dạng `v*`.

Ví dụ:

```powershell
git tag v1.5.0
git push origin main
git push origin v1.5.0
```

Workflow sẽ build:

- Windows installer.
- Windows portable zip.
- Android release APK.

## Dữ Liệu Local

OpenCB lưu dữ liệu cục bộ trong thư mục `OpenCB` của hệ điều hành, gồm SQLite database, settings, theme, danh sách thiết bị đã ghép và lịch sử gửi file.

## Ghi Chú

OpenCB hiện vẫn là app đang phát triển. LAN sync hoạt động tốt nhất khi các thiết bị cùng Wi-Fi/VPN và OpenCB đang chạy nền.
