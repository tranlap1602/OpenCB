# OpenCB Windows Production Checklist

Tài liệu này ghi lại các bước đưa OpenCB Windows từ bản dev sang bản phát hành nội bộ hoặc public.

## Trạng Thái Hiện Có

- App đã có tùy chọn **Tự mở cùng Windows** trong tab Cài đặt.
- App đã có quick picker native, system tray, global hotkey, close-to-tray và restore main window.
- Release build Windows tự build Rust core và copy `opencb_core.dll` cạnh `opencb_app.exe`.
- Dữ liệu runtime nằm trong `%APPDATA%\OpenCB`.
- Tab Cài đặt có mục Dữ liệu để mở thư mục dữ liệu, tạo backup JSON và xóa lịch sử có xác nhận.

## Auto Start

- Tùy chọn **Tự mở cùng Windows** ghi vào registry của user hiện tại:
  `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
- Không cần quyền admin.
- Khi tắt tùy chọn, app xóa value `OpenCB` khỏi Run key.
- Bước QA: bật tùy chọn, sign out/sign in lại Windows, kiểm tra OpenCB chạy trong tray.

## Release Build

```powershell
cd apps/opencb_app
flutter build windows --release
```

Thư mục cần đóng gói:

```text
apps/opencb_app/build/windows/x64/runner/Release
```

Trước khi đóng gói, kiểm tra trong thư mục release có:

- `opencb_app.exe`
- `opencb_core.dll`
- `data\flutter_assets`
- DLL runtime đi kèm Flutter/Windows runner.

## Installer

Khuyến nghị cho MVP nội bộ: dùng Inno Setup để tạo `.exe` installer nhanh.

Installer hiện được tạo bằng Inno Setup khi push tag `v*` lên GitHub. File phát hành nằm trong GitHub Releases với tên dạng:

```text
OpenCB-Setup-<version>.exe
```

Installer cần có:

- Shortcut Start Menu.
- Shortcut Desktop tùy chọn.
- Tùy chọn chạy OpenCB sau khi cài.
- Tùy chọn gỡ cài đặt sạch, nhưng không tự xóa `%APPDATA%\OpenCB` nếu user chưa xác nhận.

Khi phát hành qua Microsoft Store hoặc môi trường enterprise, cân nhắc MSIX để tận dụng app identity, update và policy của Windows.

## App Update

Chưa nên hard-code updater khi chưa chọn kênh phát hành. Có ba hướng chính:

- GitHub Releases: app kiểm tra manifest JSON trên HTTPS, so sánh version, mở trang tải installer.
- Server riêng: manifest và installer đặt trên domain riêng, có thể kiểm soát rollout.
- MSIX/App Installer: dùng cơ chế update của Windows App Installer.

Manifest gợi ý:

```json
{
  "version": "0.1.0",
  "windows_x64_url": "https://example.com/OpenCBSetup-0.1.0.exe",
  "sha256": "...",
  "notes": "Cải thiện sync LAN, quick picker và quản lý dữ liệu."
}
```

## Code Signing

Cần có code signing certificate thật trước khi ký bản phát hành public. Installer hiện tại chưa ký nên Windows SmartScreen có thể cảnh báo.

Quy trình:

1. Build release.
2. Ký `opencb_app.exe`, `opencb_core.dll` và installer.
3. Dùng timestamp server để chữ ký còn hợp lệ sau khi certificate hết hạn.
4. Verify chữ ký trước khi publish.

Lệnh mẫu:

```powershell
signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /a OpenCBSetup.exe
signtool verify /pa OpenCBSetup.exe
```

## QA Trước Khi Phát Hành

- Cài app bằng installer trên máy sạch.
- Copy text, image và file từ Explorer.
- Dùng quick picker bằng `Ctrl+Alt+V`, chọn item và kiểm tra auto paste.
- Đóng app xuống tray, click tray để mở quick picker, double click/menu để mở app chính.
- Bật auto start rồi đăng nhập lại Windows.
- Pair hai thiết bị trong LAN bằng QR/payload/code, kiểm tra trạng thái online/offline và sync bù.
- Tạo backup JSON, mở thư mục dữ liệu và reset lịch sử với xác nhận.

## Cần Quyết Định Trước Khi Làm Bản Public

- Chọn Inno Setup, MSIX hay cả hai.
- Versioning theo `pubspec.yaml` hay file release riêng.
- Kênh update là GitHub Releases, server riêng hay Microsoft Store.
- Đã có code signing certificate chưa.
