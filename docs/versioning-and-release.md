# OpenCB Versioning And Release

Tài liệu này là quy ước quản lý version, tag, changelog và phát hành OpenCB qua GitHub.

## Quy Ước Version

OpenCB dùng SemVer:

```text
MAJOR.MINOR.PATCH+BUILD
```

- `MAJOR`: thay đổi lớn, có thể phá tương thích dữ liệu hoặc workflow.
- `MINOR`: thêm chức năng mới tương thích ngược.
- `PATCH`: sửa lỗi, tối ưu nhỏ.
- `BUILD`: số build cho Android/Windows metadata.

Hiện tại:

- Flutter app: `apps/opencb_app/pubspec.yaml` đang là `1.0.0+1`.
- Rust core: `crates/opencb_core/Cargo.toml` đang là `0.1.0`.

Trước bản public đầu tiên nên chọn một hướng:

- Giữ `1.0.0+1` nếu xem MVP hiện tại là bản 1.0 nội bộ.
- Hoặc đưa app về `0.1.0+1` nếu muốn đi theo hướng pre-release rõ ràng hơn.

Khuyến nghị cho giai đoạn hiện tại: dùng tag `v0.1.0` hoặc `v1.0.0-internal.1` cho bản nội bộ.

## Branch

Khuyến nghị đơn giản:

- `main`: nhánh ổn định, luôn build được.
- `dev`: nhánh phát triển hằng ngày nếu cần.
- `feature/<ten-ngan>`: chức năng lớn.
- `fix/<ten-loi>`: sửa lỗi.

Nếu làm một mình, có thể chỉ dùng `main` và commit nhỏ, rõ nghĩa.

## Commit

Dùng Conventional Commits:

```text
feat: thêm quick picker Android
fix: không sync lại clipboard đã xóa
ui: chỉnh filter tag trên mobile
docs: thêm hướng dẫn release
build: thêm GitHub Actions CI
```

Nhóm phổ biến:

- `feat`: chức năng mới.
- `fix`: sửa lỗi.
- `ui`: thay đổi giao diện/UX.
- `docs`: tài liệu.
- `build`: CI, build script, dependency.
- `refactor`: đổi cấu trúc không đổi hành vi.
- `test`: test.

## Checklist Trước Khi Tag

```powershell
cargo test
cd apps\opencb_app
flutter analyze
flutter test
flutter build windows
flutter build apk --debug
```

QA thủ công:

- Windows: copy text/image/path, quick picker, tray, hotkey, auto paste.
- Android: UI dọc, pairing, discovery LAN, nhận sync, copy URL/path/text.
- LAN: pair hai thiết bị, sync hai chiều, delete/pin/tag không bị hồi lại.

## Tạo Release Trên GitHub

1. Cập nhật `CHANGELOG.md`.
2. Cập nhật version trong:
   - `apps/opencb_app/pubspec.yaml`
   - `crates/opencb_core/Cargo.toml` nếu Rust core đổi API/hành vi đáng kể.
3. Commit:

```powershell
git add .
git commit -m "chore: prepare v0.1.0 release"
```

4. Tag:

```powershell
git tag v0.1.0
git push origin main
git push origin v0.1.0
```

5. GitHub Actions sẽ chạy CI. Nếu dùng workflow release, tag `v*` có thể tạo artifact Windows portable.

## Update App Sau Này

Giai đoạn MVP nên dùng GitHub Releases:

- Mỗi release có file `.zip` Windows portable hoặc installer.
- App có thể kiểm tra JSON manifest trong GitHub Release hoặc một file public:

```json
{
  "version": "0.1.0",
  "windows_x64_url": "https://github.com/<owner>/<repo>/releases/download/v0.1.0/OpenCB-Windows-x64.zip",
  "android_apk_url": "https://github.com/<owner>/<repo>/releases/download/v0.1.0/OpenCB-Android-debug.apk",
  "notes_url": "https://github.com/<owner>/<repo>/releases/tag/v0.1.0"
}
```

Khi app ổn định hơn:

- Windows: Inno Setup/MSIX + signed installer.
- Android: APK signed hoặc Play Store/internal app sharing.
- Auto-update: manifest JSON + kiểm tra version trong app.
