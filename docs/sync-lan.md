# OpenCB LAN Sync

## Mục Tiêu

Sync LAN của OpenCB dùng để đồng bộ clipboard text giữa các thiết bị đã tin cậy trong cùng LAN/VPN. Thiết bị phải online và OpenCB phải đang chạy nền; không cần mở cửa sổ app chính.

## Discovery

- OpenCB gửi beacon UDP định kỳ trên port `47873`.
- Beacon chỉ chứa thông tin nhận diện cơ bản: protocol, device id, device name, host và port.
- Beacon không chứa mã pairing.
- Khi thấy thiết bị đã pair, app cập nhật endpoint mới nếu IP thay đổi do DHCP.
- Nếu thiết bị đã pair vừa online lại, app tự thử sync lại có giới hạn tần suất.

## Pairing

Có ba cách thêm thiết bị:

- Thiết bị tự xuất hiện trong LAN: chọn **Kết nối**, nhập mã đang hiển thị trên thiết bị kia.
- Copy/dán payload dạng `opencb://pair?...`.
- Quét QR pairing trên Android.

Khi một bên thêm thiết bị thành công, OpenCB gửi `pairRequest` sang thiết bị kia để cả hai cùng lưu nhau vào danh sách tin cậy. Nếu thiết bị kia đang offline, lần thêm tự động hai chiều sẽ cần thử lại khi thiết bị online.

## Trusted Devices

Thiết bị tin cậy được lưu trong `sync_peers.json` với:

- Device id.
- Tên thiết bị.
- Host và port hiện tại.
- Pair code của thiết bị kia.
- Thời điểm sync cuối.
- Lỗi sync gần nhất nếu có.

Tab Thiết bị hiển thị trạng thái online/offline dựa trên beacon LAN gần nhất, không chỉ dựa vào lần sync cuối.

## Sync

- MVP hiện sync text clipboard trước.
- Image và file reference metadata vẫn lưu local nhưng chưa sync payload.
- Khi sync, mỗi bên gửi danh sách text item local và merge vào database bên kia.
- Deduplication của Rust core tránh tạo quá nhiều item trùng nội dung.
- Nếu thiết bị offline, dữ liệu giữ local và sync bù khi thiết bị online lại.

## Unpair

Khi xóa thiết bị:

- OpenCB hỏi xác nhận.
- Nếu thiết bị kia online, app gửi `unpairRequest` để bên kia cũng xóa liên kết.
- Nếu thiết bị kia offline, chỉ xóa local; có thể cần xóa thủ công ở thiết bị còn lại.

## Giới Hạn Hiện Tại

- Payload sync LAN chưa mã hóa end-to-end.
- Pair code đang là lớp xác nhận MVP, chưa phải key exchange.
- Chưa sync image/file payload.
- Android UI mới dùng để test pairing/sync cơ bản, chưa phải layout mobile hoàn chỉnh.

## Hướng Nâng Cấp

- Keypair thật cho từng device.
- QR pairing chứa public key và nonce.
- Ký request sync, chống giả mạo device id.
- Mã hóa payload khi truyền qua LAN/VPN.
- Sync delta theo cursor thay vì gửi toàn bộ text item.
- Thumbnail/lazy payload cho image clipboard.
