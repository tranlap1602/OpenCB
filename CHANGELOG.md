# Changelog

Tất cả thay đổi đáng chú ý của OpenCB sẽ được ghi ở đây.

Định dạng dựa trên Keep a Changelog và version theo SemVer.

## [Unreleased]

## [1.6.1] - 2026-07-11

### Added

- Chẩn đoán LAN và xuất log để kiểm tra discovery, server, beacon và trạng thái thiết bị.
- Ghi nhận lỗi Flutter/Dart cục bộ và xuất báo cáo sự cố từ trang Cập nhật ứng dụng.

### Changed

- Điều chỉnh discovery theo trạng thái màn hình Android, giảm sync lặp và làm rõ trạng thái online/offline.
- Chuẩn hóa căn nội dung button, badge và menu theo từng nền tảng.
- Mặc định cài mới trên Windows sử dụng tiếng Việt.
- Đồng bộ giao diện Cập nhật ứng dụng giữa Windows và Android.

### Fixed

- Sửa chiều cao vô hạn ở phần cuối trang Thiết bị trên Android.
- Ổn định trạng thái thiết bị khi beacon hết hạn hoặc điện thoại thay đổi trạng thái màn hình.

## [1.6.0] - 2026-07-09

### Added

- Android UI tối ưu màn hình dọc, floating toolbar, tìm kiếm nổi và tab thiết bị trong Cài đặt.
- LAN sync local-first với discovery trong LAN, QR/payload pairing, đổi tên thiết bị và auto set clipboard khi nhận sync.
- Windows quick picker native, system tray, global hotkey, pin window, auto paste và context menu.
- Material 3 theme presets, light/system/dark mode, logo/icon OpenCB cho Windows và Android.

### Changed

- Cải thiện layout desktop/compact/mobile, filter dạng connected button group, chip/tag UI và badge thời gian.
- Tối ưu hiển thị clipboard text, URL, ảnh, path/file reference và source app icon.

### Fixed

- Tránh lỗi Windows debug build khi instance cũ còn chạy dưới system tray.
- Đồng bộ trạng thái pin/tag/delete tốt hơn giữa thiết bị LAN.

## [1.0.0+1] - 2026-06-28

### Added

- Mốc MVP nội bộ đầu tiên được chuẩn bị để đưa lên GitHub.
