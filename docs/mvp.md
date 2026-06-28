# OpenCB Windows MVP

## Phạm Vi Sản Phẩm

MVP đầu tiên tập trung vào quản lý clipboard trên Windows. Bookmark, note và snippet là các module mở rộng sau khi vòng đời clipboard đã ổn định.

## Khả Năng Hiện Có

- Bắt clipboard text native trên Windows.
- Bắt clipboard image native trên Windows và preview trong UI.
- Bắt file reference khi copy file trong Explorer.
- Lưu tên ứng dụng nguồn theo foreground process khi Windows báo clipboard update.
- Lưu lịch sử clipboard local bằng SQLite thông qua Rust core.
- Search theo nội dung, preview, ghim, sửa thẻ, xóa và xóa các mục chưa ghim có xác nhận.
- Cài đặt retention trong UI, giữ pinned item và tự dọn mục chưa ghim theo giới hạn đã chọn.
- Cấu hình danh sách app nguồn không bắt clipboard.
- Sao chép lại item cũ vào clipboard.
- Phím tắt toàn cục `Ctrl+Alt+V` để mở quick picker, tìm nhanh và sao chép lại item cũ.
- Đóng cửa sổ sẽ ẩn app xuống system tray; app vẫn tiếp tục chạy nền.
- Giao diện tiếng Việt mặc định.
- Material 3 với `ColorScheme.fromSeed`, light/system/dark mode, preset màu Material You, `NavigationRail`, `SearchBar`, tonal surfaces, chips và MD3 button variants.
- Sync text clipboard qua LAN bằng TCP port `47873`, có manual pairing code, QR/payload pairing để scan hoặc copy/dán nhanh và auto sync nền.

## Trạng Thái Kỹ Thuật

- Rust core đã có storage SQLite, search, deduplication, retention, blob image storage, trusted device primitives và C ABI JSON-in/JSON-out cho Flutter.
- Flutter app hiện dùng `opencb_core.dll` qua Dart FFI; nếu DLL chưa có trong môi trường test/dev thì fallback JSON để UI vẫn mở được.
- Windows runner có Win32 MethodChannel bridge cho clipboard text/image/file-reference.
- Windows runner gửi thêm `sourceApp` lấy từ foreground process; UI đã hiển thị tên và icon app nguồn khi Windows lấy được.
- Windows runner có global hotkey `Ctrl+Alt+V`.
- Windows runner có tray icon, menu `Mở OpenCB`/`Thoát`, và close-to-tray behavior.
- Text clipboard có polling fallback nếu native MethodChannel không khả dụng.
- Windows release build tự chạy `cargo build --release --package opencb_core` và copy `opencb_core.dll` cạnh `opencb_app.exe`.

## File Dữ Liệu

- `%APPDATA%\OpenCB\opencb.sqlite3`: lịch sử clipboard, FTS index, blob ảnh và metadata.
- `%APPDATA%\OpenCB\clipboard_history.json`: lịch sử cũ, được import/dedupe vào SQLite khi app mở.
- `%APPDATA%\OpenCB\sync_identity.json`: device id, device name và mã pairing LAN của máy hiện tại.
- `%APPDATA%\OpenCB\sync_peers.json`: peer LAN đã pair.
- `%APPDATA%\OpenCB\clipboard_settings.json`: giới hạn retention và danh sách app nguồn bị loại trừ.
- `%APPDATA%\OpenCB\theme.json`: theme mode và preset màu.
- Backup thủ công được tạo trong `%APPDATA%\OpenCB` với tên dạng `opencb_backup_*.json`.

## Giới Hạn Hiện Tại

- Chưa sync nội dung file thật.
- LAN sync chưa mã hóa; pairing hiện dùng mã xác nhận/QR/payload trong cùng LAN.
- Image clipboard đã lưu/preview được, nhưng chưa có thumbnail cache/lazy loading tối ưu cho thư viện ảnh rất lớn.
- Android hiện mới dùng để test UI/sync LAN cơ bản; Ubuntu adapter chưa triển khai.

## Việc Cần Làm Tiếp

- Mã hóa payload sync LAN.
- Tối ưu thumbnail/lazy loading cho image clipboard.
- Thêm test integration cho native clipboard bridge và LAN sync.

## Roadmap Nâng Cấp Sâu

- Pairing LAN đa nền tảng: QR/payload pair đã có dạng `opencb://pair?...`; Android đã có scan QR cơ bản, bước tiếp theo là hoàn thiện mobile UI riêng.
- Mã hóa payload LAN: thay manual pair code hiện tại bằng key exchange, lưu trusted public key theo thiết bị, ký request sync và mã hóa nội dung clipboard khi truyền trong LAN/VPN.
- Quick picker nâng cao: đã paste trực tiếp vào app trước đó và hỗ trợ điều hướng bàn phím cơ bản; bước tiếp theo là tối ưu accessibility/focus state.
- Pause rules nâng cao: hỗ trợ rule theo process name/window title và trạng thái tạm dừng theo thời gian.
- Thumbnail/lazy loading cho image clipboard lớn: tạo thumbnail cache riêng, chỉ load blob ảnh đầy đủ khi mở preview, tránh kéo toàn bộ ảnh từ SQLite khi render list.
- Integration test native/sync: test bridge clipboard text/image/file-reference, test sync hai local app instances, test pairing sai mã bị từ chối và sync đúng mã thành công.
- Adapter Ubuntu và Android: tách platform clipboard adapter rõ hơn, tái dùng Rust core/SQLite/sync, triển khai tray/background/service theo từng nền tảng.

## Nguyên Tắc UI

- Các lần chỉnh giao diện tiếp theo mặc định theo **Material 3 mới nhất / M3 Expressive**.
- Ưu tiên Flutter `ThemeData(useMaterial3: true)`, `ColorScheme` semantic roles, tonal surfaces, shape token kiểu full/medium/large và typography roles thay vì hard-code màu/kích thước tùy tiện.
- Component nhỏ như badge, chip, button, icon button, search, navigation rail và list item cần bám MD3 tokens: container/on-container color pairing, pill/full shape cho badge/chip, state rõ cho selected/hover/focus.
- M3 Expressive được dùng có kiểm soát: tăng tính rõ ràng, hierarchy và cảm giác hiện đại cho desktop tool, nhưng không biến app thành landing page hoặc giao diện trang trí quá mức.
- Khi Flutter chưa có component Expressive tương đương, tự dựng component theo token MD3 thay vì dùng kiểu Material 2 hoặc custom visual lệch hệ thống.
