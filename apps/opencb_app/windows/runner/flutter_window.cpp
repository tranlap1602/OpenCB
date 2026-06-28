#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <objbase.h>
#include <shellapi.h>
#include <wincodec.h>
#include <windowsx.h>

#include <cstdint>
#include <cstring>
#include <cwctype>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr int kQuickOpenHotKeyId = 0x4F43;
constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kQuickOpenMessage = WM_APP + 2;
constexpr UINT kTrayMenuOpen = 40001;
constexpr UINT kTrayMenuQuit = 40002;
constexpr const wchar_t kQuickPickerWindowClassName[] =
    L"OPENCB_QUICK_PICKER_WINDOW";

#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif

#ifndef DWMWCP_DEFAULT
#define DWMWCP_DEFAULT 0
#endif

#ifndef DWMWCP_ROUND
#define DWMWCP_ROUND 2
#endif

#pragma pack(push, 2)
struct BmpFileHeader {
  uint16_t type;
  uint32_t size;
  uint16_t reserved1;
  uint16_t reserved2;
  uint32_t off_bits;
};
#pragma pack(pop)

std::string Utf8FromWide(const std::wstring& value) {
  if (value.empty()) {
    return "";
  }
  int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                 static_cast<int>(value.size()), nullptr, 0,
                                 nullptr, nullptr);
  std::string result(size, 0);
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

std::string Utf8FromAnsi(const std::string& value) {
  if (value.empty()) {
    return "";
  }
  int wide_size = MultiByteToWideChar(CP_ACP, 0, value.c_str(),
                                      static_cast<int>(value.size()), nullptr,
                                      0);
  if (wide_size <= 0) {
    return "";
  }
  std::wstring wide(wide_size, L'\0');
  MultiByteToWideChar(CP_ACP, 0, value.c_str(),
                      static_cast<int>(value.size()), wide.data(), wide_size);
  return Utf8FromWide(wide);
}

std::wstring LowerWide(std::wstring value) {
  for (auto& ch : value) {
    ch = static_cast<wchar_t>(std::towlower(ch));
  }
  return value;
}

std::wstring FileStemFromPath(const std::wstring& path) {
  const size_t slash = path.find_last_of(L"\\/");
  std::wstring name =
      slash == std::wstring::npos ? path : path.substr(slash + 1);
  const size_t dot = name.find_last_of(L'.');
  if (dot != std::wstring::npos) {
    name = name.substr(0, dot);
  }
  return name;
}

std::optional<std::string> ClipboardWideText(UINT format) {
  if (format == 0 || !IsClipboardFormatAvailable(format)) {
    return std::nullopt;
  }
  HANDLE data = GetClipboardData(format);
  if (data == nullptr) {
    return std::nullopt;
  }
  auto text = static_cast<const wchar_t*>(GlobalLock(data));
  if (text == nullptr) {
    return std::nullopt;
  }
  std::wstring value(text);
  GlobalUnlock(data);
  if (value.empty()) {
    return std::nullopt;
  }
  return Utf8FromWide(value);
}

std::optional<std::string> ClipboardAnsiText(UINT format) {
  if (format == 0 || !IsClipboardFormatAvailable(format)) {
    return std::nullopt;
  }
  HANDLE data = GetClipboardData(format);
  if (data == nullptr) {
    return std::nullopt;
  }
  auto text = static_cast<const char*>(GlobalLock(data));
  if (text == nullptr) {
    return std::nullopt;
  }
  std::string value(text);
  GlobalUnlock(data);
  if (value.empty()) {
    return std::nullopt;
  }
  return Utf8FromAnsi(value);
}

std::string FriendlyProcessName(const std::wstring& path) {
  const auto stem = FileStemFromPath(path);
  const auto lower = LowerWide(stem);

  if (lower == L"explorer") return "File Explorer";
  if (lower == L"chrome") return "Google Chrome";
  if (lower == L"msedge") return "Microsoft Edge";
  if (lower == L"firefox") return "Mozilla Firefox";
  if (lower == L"code") return "Visual Studio Code";
  if (lower == L"devenv") return "Visual Studio";
  if (lower == L"notepad") return "Notepad";
  if (lower == L"notepad++") return "Notepad++";
  if (lower == L"windowsterminal") return "Windows Terminal";
  if (lower == L"cmd") return "Command Prompt";
  if (lower == L"powershell" || lower == L"pwsh") return "PowerShell";
  if (lower == L"winword") return "Microsoft Word";
  if (lower == L"excel") return "Microsoft Excel";
  if (lower == L"powerpnt") return "Microsoft PowerPoint";
  if (lower == L"outlook") return "Microsoft Outlook";
  if (lower == L"onenote") return "Microsoft OneNote";
  if (lower == L"teams") return "Microsoft Teams";
  if (lower == L"telegram") return "Telegram";
  if (lower == L"discord") return "Discord";
  if (lower == L"zalo") return "Zalo";
  if (lower == L"obsidian") return "Obsidian";
  if (lower == L"figma") return "Figma";
  if (lower == L"slack") return "Slack";

  return Utf8FromWide(stem);
}

template <typename T>
void SafeRelease(T** value) {
  if (value != nullptr && *value != nullptr) {
    (*value)->Release();
    *value = nullptr;
  }
}

std::vector<uint8_t> BytesFromStream(IStream* stream) {
  std::vector<uint8_t> result;
  if (stream == nullptr) {
    return result;
  }

  HGLOBAL memory = nullptr;
  if (FAILED(GetHGlobalFromStream(stream, &memory)) || memory == nullptr) {
    return result;
  }

  const SIZE_T size = GlobalSize(memory);
  if (size == 0) {
    return result;
  }

  const auto* data = static_cast<const uint8_t*>(GlobalLock(memory));
  if (data == nullptr) {
    return result;
  }

  result.assign(data, data + size);
  GlobalUnlock(memory);
  return result;
}

std::vector<uint8_t> PngBytesFromIcon(HICON icon) {
  std::vector<uint8_t> result;
  if (icon == nullptr) {
    return result;
  }

  bool did_initialize_com = false;
  const HRESULT com_result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (SUCCEEDED(com_result)) {
    did_initialize_com = true;
  } else if (com_result != RPC_E_CHANGED_MODE) {
    return result;
  }

  IWICImagingFactory* factory = nullptr;
  IWICBitmap* bitmap = nullptr;
  IWICFormatConverter* converter = nullptr;
  IStream* stream = nullptr;
  IWICBitmapEncoder* encoder = nullptr;
  IWICBitmapFrameEncode* frame = nullptr;

  HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
  if (SUCCEEDED(hr)) {
    hr = factory->CreateBitmapFromHICON(icon, &bitmap);
  }
  if (SUCCEEDED(hr)) {
    hr = factory->CreateFormatConverter(&converter);
  }
  if (SUCCEEDED(hr)) {
    hr = converter->Initialize(
        bitmap, GUID_WICPixelFormat32bppPBGRA, WICBitmapDitherTypeNone,
        nullptr, 0.0, WICBitmapPaletteTypeCustom);
  }
  if (SUCCEEDED(hr)) {
    hr = CreateStreamOnHGlobal(nullptr, TRUE, &stream);
  }
  if (SUCCEEDED(hr)) {
    hr = factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder);
  }
  if (SUCCEEDED(hr)) {
    hr = encoder->Initialize(stream, WICBitmapEncoderNoCache);
  }
  if (SUCCEEDED(hr)) {
    hr = encoder->CreateNewFrame(&frame, nullptr);
  }
  if (SUCCEEDED(hr)) {
    hr = frame->Initialize(nullptr);
  }
  UINT width = 0;
  UINT height = 0;
  if (SUCCEEDED(hr)) {
    hr = converter->GetSize(&width, &height);
  }
  if (SUCCEEDED(hr)) {
    hr = frame->SetSize(width, height);
  }
  WICPixelFormatGUID pixel_format = GUID_WICPixelFormat32bppPBGRA;
  if (SUCCEEDED(hr)) {
    hr = frame->SetPixelFormat(&pixel_format);
  }
  if (SUCCEEDED(hr)) {
    hr = frame->WriteSource(converter, nullptr);
  }
  if (SUCCEEDED(hr)) {
    hr = frame->Commit();
  }
  if (SUCCEEDED(hr)) {
    hr = encoder->Commit();
  }
  if (SUCCEEDED(hr)) {
    LARGE_INTEGER offset{};
    stream->Seek(offset, STREAM_SEEK_SET, nullptr);
    result = BytesFromStream(stream);
  }

  SafeRelease(&frame);
  SafeRelease(&encoder);
  SafeRelease(&stream);
  SafeRelease(&converter);
  SafeRelease(&bitmap);
  SafeRelease(&factory);
  if (did_initialize_com) {
    CoUninitialize();
  }
  return result;
}

std::vector<uint8_t> SourceIconBytesFromPath(const std::wstring& path) {
  std::vector<uint8_t> result;
  if (path.empty()) {
    return result;
  }

  SHFILEINFOW file_info{};
  if (SHGetFileInfoW(path.c_str(), 0, &file_info, sizeof(file_info),
                     SHGFI_ICON | SHGFI_LARGEICON) == 0) {
    return result;
  }

  result = PngBytesFromIcon(file_info.hIcon);
  if (file_info.hIcon != nullptr) {
    DestroyIcon(file_info.hIcon);
  }
  return result;
}

struct SourceAppInfo {
  std::string name;
  std::vector<uint8_t> icon_bytes;
};

SourceAppInfo ForegroundSourceInfo(HWND own_window) {
  HWND foreground = GetForegroundWindow();
  if (foreground == nullptr || foreground == own_window) {
    return {};
  }

  DWORD process_id = 0;
  GetWindowThreadProcessId(foreground, &process_id);
  if (process_id == 0) {
    return {};
  }

  HANDLE process =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (process == nullptr) {
    return {};
  }

  std::wstring path(MAX_PATH, L'\0');
  DWORD size = static_cast<DWORD>(path.size());
  if (!QueryFullProcessImageNameW(process, 0, path.data(), &size)) {
    CloseHandle(process);
    return {};
  }
  CloseHandle(process);
  path.resize(size);
  return SourceAppInfo{FriendlyProcessName(path), SourceIconBytesFromPath(path)};
}

size_t DibPixelOffset(const BITMAPINFOHEADER* header) {
  if (header == nullptr) {
    return 0;
  }

  size_t offset = header->biSize;
  if (header->biClrUsed > 0) {
    offset += header->biClrUsed * sizeof(RGBQUAD);
  } else if (header->biBitCount <= 8) {
    offset += (static_cast<size_t>(1) << header->biBitCount) * sizeof(RGBQUAD);
  }

  if (header->biCompression == BI_BITFIELDS &&
      header->biSize == sizeof(BITMAPINFOHEADER)) {
    offset += 3 * sizeof(DWORD);
  }
  return offset;
}

std::vector<uint8_t> BmpBytesFromDib(HGLOBAL dib) {
  std::vector<uint8_t> result;
  if (dib == nullptr) {
    return result;
  }

  const SIZE_T dib_size = GlobalSize(dib);
  if (dib_size == 0) {
    return result;
  }

  const auto* dib_bytes = static_cast<const uint8_t*>(GlobalLock(dib));
  if (dib_bytes == nullptr) {
    return result;
  }

  const auto* header = reinterpret_cast<const BITMAPINFOHEADER*>(dib_bytes);
  const size_t pixel_offset = DibPixelOffset(header);
  if (pixel_offset > dib_size) {
    GlobalUnlock(dib);
    return result;
  }

  BmpFileHeader file_header{};
  file_header.type = 0x4D42;
  file_header.size =
      static_cast<uint32_t>(sizeof(BmpFileHeader) + dib_size);
  file_header.off_bits =
      static_cast<uint32_t>(sizeof(BmpFileHeader) + pixel_offset);

  result.resize(sizeof(BmpFileHeader) + dib_size);
  std::memcpy(result.data(), &file_header, sizeof(BmpFileHeader));
  std::memcpy(result.data() + sizeof(BmpFileHeader), dib_bytes, dib_size);
  GlobalUnlock(dib);
  return result;
}

std::vector<uint8_t> BytesFromGlobalMemory(HANDLE memory) {
  std::vector<uint8_t> result;
  if (memory == nullptr) {
    return result;
  }

  const SIZE_T size = GlobalSize(memory);
  if (size == 0) {
    return result;
  }

  const auto* bytes = static_cast<const uint8_t*>(GlobalLock(memory));
  if (bytes == nullptr) {
    return result;
  }

  result.assign(bytes, bytes + size);
  GlobalUnlock(memory);
  return result;
}

std::vector<uint8_t> BytesFromClipboardFormat(UINT format) {
  if (format == 0 || !IsClipboardFormatAvailable(format)) {
    return {};
  }
  return BytesFromGlobalMemory(GetClipboardData(format));
}

std::vector<uint8_t> PngBytesFromClipboard() {
  const UINT png_format = RegisterClipboardFormatW(L"PNG");
  auto bytes = BytesFromClipboardFormat(png_format);
  if (!bytes.empty()) {
    return bytes;
  }

  const UINT image_png_format = RegisterClipboardFormatW(L"image/png");
  bytes = BytesFromClipboardFormat(image_png_format);
  if (!bytes.empty()) {
    return bytes;
  }

  const UINT portable_png_format =
      RegisterClipboardFormatW(L"Portable Network Graphics");
  return BytesFromClipboardFormat(portable_png_format);
}

bool OpenClipboardWithRetry(HWND owner) {
  constexpr int kAttempts = 8;
  for (int attempt = 0; attempt < kAttempts; ++attempt) {
    if (OpenClipboard(owner)) {
      return true;
    }
    Sleep(20);
  }
  return false;
}

bool IsPngBytes(const std::vector<uint8_t>& bytes) {
  constexpr uint8_t kPngSignature[] = {0x89, 0x50, 0x4E, 0x47,
                                       0x0D, 0x0A, 0x1A, 0x0A};
  if (bytes.size() < sizeof(kPngSignature)) {
    return false;
  }
  return std::memcmp(bytes.data(), kPngSignature, sizeof(kPngSignature)) == 0;
}

HGLOBAL GlobalMemoryFromBytes(const std::vector<uint8_t>& bytes) {
  if (bytes.empty()) {
    return nullptr;
  }

  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
  if (memory == nullptr) {
    return nullptr;
  }

  void* target = GlobalLock(memory);
  if (target == nullptr) {
    GlobalFree(memory);
    return nullptr;
  }

  std::memcpy(target, bytes.data(), bytes.size());
  GlobalUnlock(memory);
  return memory;
}

const uint8_t* DibBytesFromBmpBytes(const std::vector<uint8_t>& bytes,
                                    size_t* dib_size) {
  if (bytes.size() > sizeof(BmpFileHeader)) {
    const auto* header = reinterpret_cast<const BmpFileHeader*>(bytes.data());
    if (header->type == 0x4D42) {
      *dib_size = bytes.size() - sizeof(BmpFileHeader);
      return bytes.data() + sizeof(BmpFileHeader);
    }
  }
  *dib_size = bytes.size();
  return bytes.data();
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetupClipboardChannel();
  AddClipboardFormatListener(GetHandle());
  AddTrayIcon();
  RegisterQuickOpenHotKey();
  flutter_view_hwnd_ = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(flutter_view_hwnd_);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  AttachFlutterViewToMainWindow();
  if (quick_picker_hwnd_) {
    DestroyWindow(quick_picker_hwnd_);
    quick_picker_hwnd_ = nullptr;
  }
  RemoveClipboardFormatListener(GetHandle());
  UnregisterQuickOpenHotKey();
  RemoveTrayIcon();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      ShowWindow(hwnd, SW_HIDE);
      return 0;

    case WM_ACTIVATE:
      if (quick_picker_window_style_ && LOWORD(wparam) == WA_INACTIVE &&
          !quick_picker_always_on_top_) {
        PublishQuickPickerDeactivated();
      }
      break;

    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case kTrayMenuOpen:
          ShowFromTray();
          return 0;
        case kTrayMenuQuit:
          RemoveTrayIcon();
          DestroyWindow(hwnd);
          return 0;
      }
      break;

    case kTrayMessage:
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          quick_paste_target_ = nullptr;
          PostMessage(hwnd, kQuickOpenMessage, 0, 0);
          return 0;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          ShowTrayMenu();
          return 0;
      }
      break;

    case WM_HOTKEY:
      if (static_cast<int>(wparam) == kQuickOpenHotKeyId) {
        CaptureQuickPasteTarget();
        PostMessage(hwnd, kQuickOpenMessage, 0, 0);
        return 0;
      }
      break;

    case kQuickOpenMessage:
      PublishQuickOpenRequest();
      return 0;

    case WM_NCHITTEST:
      if (quick_picker_window_style_) {
        const int y = GET_Y_LPARAM(lparam);
        RECT rect;
        GetWindowRect(hwnd, &rect);
        if (y >= rect.top && y < rect.top + 76) {
          return HTCAPTION;
        }
      }
      break;

    case WM_CLIPBOARDUPDATE:
      PublishClipboardSnapshot();
      return 0;

    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

LRESULT CALLBACK FlutterWindow::QuickPickerWndProc(HWND const window,
                                                   UINT const message,
                                                   WPARAM const wparam,
                                                   LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(create_struct->lpCreateParams));
  }

  auto that = reinterpret_cast<FlutterWindow*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
  if (that) {
    return that->QuickPickerMessageHandler(window, message, wparam, lparam);
  }
  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT FlutterWindow::QuickPickerMessageHandler(HWND window,
                                                 UINT const message,
                                                 WPARAM const wparam,
                                                 LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(window, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      PublishQuickPickerDeactivated();
      return 0;

    case WM_ACTIVATE:
      if (LOWORD(wparam) == WA_INACTIVE && !quick_picker_always_on_top_) {
        PublishQuickPickerDeactivated();
      } else if (flutter_view_hwnd_) {
        SetFocus(flutter_view_hwnd_);
      }
      return 0;

    case WM_SIZE: {
      if (flutter_view_hwnd_) {
        RECT rect;
        GetClientRect(window, &rect);
        MoveWindow(flutter_view_hwnd_, rect.left, rect.top,
                   rect.right - rect.left, rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_NCHITTEST: {
      const int y = GET_Y_LPARAM(lparam);
      RECT rect;
      GetWindowRect(window, &rect);
      if (y >= rect.top && y < rect.top + 76) {
        return HTCAPTION;
      }
      break;
    }

    case WM_NCDESTROY:
      if (window == quick_picker_hwnd_) {
        quick_picker_hwnd_ = nullptr;
        flutter_view_in_quick_picker_ = false;
      }
      break;
  }

  return DefWindowProc(window, message, wparam, lparam);
}

void FlutterWindow::SetupClipboardChannel() {
  clipboard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "opencb/windows_clipboard",
          &flutter::StandardMethodCodec::GetInstance());

  clipboard_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "getSnapshot") {
          result->Success(flutter::EncodableValue(ReadClipboardSnapshot()));
          return;
        }
        if (call.method_name() == "setImage") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (args == nullptr) {
            result->Error("invalid_args", "Missing image bytes");
            return;
          }
          auto bytes_it = args->find(flutter::EncodableValue("bytes"));
          if (bytes_it == args->end()) {
            result->Error("invalid_args", "Missing image bytes");
            return;
          }
          const auto* bytes =
              std::get_if<std::vector<uint8_t>>(&bytes_it->second);
          if (bytes == nullptr || bytes->empty()) {
            result->Error("invalid_args", "Invalid image bytes");
            return;
          }
          result->Success(flutter::EncodableValue(
              WriteBitmapToClipboard(*bytes)));
          return;
        }
        if (call.method_name() == "showQuickPickerWindow") {
          ShowQuickPickerWindow();
          result->Success();
          return;
        }
        if (call.method_name() == "hideWindow") {
          HideToTray();
          result->Success();
          return;
        }
        if (call.method_name() == "showMainWindow") {
          ShowFromTray();
          result->Success();
          return;
        }
        if (call.method_name() == "prepareMainWindowFromQuickPicker") {
          PrepareMainWindowFromQuickPicker();
          result->Success();
          return;
        }
        if (call.method_name() == "showPreparedMainWindow") {
          ShowPreparedMainWindow();
          result->Success();
          return;
        }
        if (call.method_name() == "setQuickPickerAlwaysOnTop") {
          bool enabled = false;
          if (const auto* args =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto it = args->find(flutter::EncodableValue("enabled"));
            if (it != args->end()) {
              if (const auto* value = std::get_if<bool>(&it->second)) {
                enabled = *value;
              }
            }
          }
          SetQuickPickerAlwaysOnTop(enabled);
          result->Success();
          return;
        }
        if (call.method_name() == "setQuickOpenHotKey") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (args == nullptr) {
            result->Error("invalid_args", "Missing hotkey arguments");
            return;
          }
          bool enabled = true;
          UINT modifiers = MOD_CONTROL | MOD_ALT;
          UINT key_code = 'V';
          auto enabled_it = args->find(flutter::EncodableValue("enabled"));
          if (enabled_it != args->end()) {
            if (const auto* value = std::get_if<bool>(&enabled_it->second)) {
              enabled = *value;
            }
          }
          auto modifiers_it = args->find(flutter::EncodableValue("modifiers"));
          if (modifiers_it != args->end()) {
            if (const auto* modifiers32 =
                    std::get_if<int32_t>(&modifiers_it->second)) {
              modifiers = static_cast<UINT>(*modifiers32);
            } else if (const auto* modifiers64 =
                           std::get_if<int64_t>(&modifiers_it->second)) {
              modifiers = static_cast<UINT>(*modifiers64);
            }
          }
          auto key_it = args->find(flutter::EncodableValue("keyCode"));
          if (key_it != args->end()) {
            if (const auto* key32 = std::get_if<int32_t>(&key_it->second)) {
              key_code = static_cast<UINT>(*key32);
            } else if (const auto* key64 =
                           std::get_if<int64_t>(&key_it->second)) {
              key_code = static_cast<UINT>(*key64);
            }
          }
          result->Success(flutter::EncodableValue(
              SetQuickOpenHotKey(enabled, modifiers, key_code)));
          return;
        }
        if (call.method_name() == "pasteToQuickTarget") {
          bool return_to_quick_picker = false;
          if (const auto* args =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto it = args->find(flutter::EncodableValue("returnToQuickPicker"));
            if (it != args->end()) {
              if (const auto* value = std::get_if<bool>(&it->second)) {
                return_to_quick_picker = *value;
              }
            }
          }
          result->Success(flutter::EncodableValue(
              PasteToQuickPasteTarget(return_to_quick_picker)));
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::AddTrayIcon() {
  if (tray_icon_added_) {
    return;
  }
  ZeroMemory(&tray_icon_data_, sizeof(tray_icon_data_));
  tray_icon_data_.cbSize = sizeof(tray_icon_data_);
  tray_icon_data_.hWnd = GetHandle();
  tray_icon_data_.uID = kTrayIconId;
  tray_icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayMessage;
  tray_icon_data_.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_icon_data_.szTip,
           L"OpenCB - \u0111ang ch\u1EA1y n\u1EC1n");
  tray_icon_added_ = Shell_NotifyIconW(NIM_ADD, &tray_icon_data_) == TRUE;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_added_) {
    return;
  }
  Shell_NotifyIconW(NIM_DELETE, &tray_icon_data_);
  tray_icon_added_ = false;
}

void FlutterWindow::ShowFromTray() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }
  if (quick_picker_hwnd_ && IsWindowVisible(quick_picker_hwnd_)) {
    ShowWindow(quick_picker_hwnd_, SW_HIDE);
  }
  PublishMainWindowRequest();
  SetQuickPickerAlwaysOnTop(false);
  AttachFlutterViewToMainWindow();
  if (has_main_window_rect_) {
    SetWindowPos(hwnd, nullptr, main_window_rect_.left, main_window_rect_.top,
                 main_window_rect_.right - main_window_rect_.left,
                 main_window_rect_.bottom - main_window_rect_.top,
                 SWP_NOZORDER | SWP_NOACTIVATE);
    has_main_window_rect_ = false;
  }
  ShowWindow(hwnd, SW_RESTORE);
  SetForegroundWindow(hwnd);
}

void FlutterWindow::PrepareMainWindowFromQuickPicker() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  if (quick_picker_hwnd_ && IsWindowVisible(quick_picker_hwnd_)) {
    SetWindowPos(quick_picker_hwnd_, HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_HIDEWINDOW);
  }

  quick_picker_always_on_top_ = false;
  AttachFlutterViewToMainWindow();

  if (has_main_window_rect_) {
    SetWindowPos(hwnd, nullptr, main_window_rect_.left, main_window_rect_.top,
                 main_window_rect_.right - main_window_rect_.left,
                 main_window_rect_.bottom - main_window_rect_.top,
                 SWP_NOZORDER | SWP_NOACTIVATE);
    has_main_window_rect_ = false;
  }
}

void FlutterWindow::ShowPreparedMainWindow() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }
  AttachFlutterViewToMainWindow();
  ShowWindow(hwnd, SW_RESTORE);
  SetForegroundWindow(hwnd);
}

bool FlutterWindow::EnsureQuickPickerWindow() {
  if (quick_picker_hwnd_) {
    return true;
  }

  static bool class_registered = false;
  HINSTANCE instance = GetModuleHandle(nullptr);
  if (!class_registered) {
    WNDCLASSW window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.hInstance = instance;
    window_class.hIcon = LoadIcon(instance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kQuickPickerWindowClassName;
    window_class.lpfnWndProc = FlutterWindow::QuickPickerWndProc;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    if (!RegisterClassW(&window_class)) {
      const DWORD error = GetLastError();
      if (error != ERROR_CLASS_ALREADY_EXISTS) {
        return false;
      }
    }
    class_registered = true;
  }

  quick_picker_hwnd_ = CreateWindowExW(
      WS_EX_TOOLWINDOW, kQuickPickerWindowClassName, L"OpenCB Quick Picker",
      WS_POPUP | WS_CLIPCHILDREN | WS_CLIPSIBLINGS, CW_USEDEFAULT,
      CW_USEDEFAULT, 630, 640, nullptr, nullptr, instance, this);
  if (!quick_picker_hwnd_) {
    return false;
  }

  const DWORD corner_preference = DWMWCP_ROUND;
  DwmSetWindowAttribute(quick_picker_hwnd_, DWMWA_WINDOW_CORNER_PREFERENCE,
                        &corner_preference, sizeof(corner_preference));
  return true;
}

void FlutterWindow::AttachFlutterViewToMainWindow() {
  HWND hwnd = GetHandle();
  if (!hwnd || !flutter_view_hwnd_ || !flutter_view_in_quick_picker_) {
    return;
  }
  SetChildContent(flutter_view_hwnd_);
  flutter_view_in_quick_picker_ = false;
}

bool FlutterWindow::AttachFlutterViewToQuickPicker() {
  if (!EnsureQuickPickerWindow() || !flutter_view_hwnd_) {
    return false;
  }
  if (!flutter_view_in_quick_picker_) {
    SetParent(flutter_view_hwnd_, quick_picker_hwnd_);
    flutter_view_in_quick_picker_ = true;
  }
  RECT frame;
  GetClientRect(quick_picker_hwnd_, &frame);
  MoveWindow(flutter_view_hwnd_, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, TRUE);
  SetFocus(flutter_view_hwnd_);
  return true;
}

void FlutterWindow::ApplyMainWindowStyle() {
  HWND hwnd = GetHandle();
  if (!hwnd || !quick_picker_window_style_) {
    return;
  }
  const DWORD corner_preference = DWMWCP_DEFAULT;
  DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE,
                        &corner_preference, sizeof(corner_preference));
  if (main_window_style_ != 0) {
    SetWindowLongPtr(hwnd, GWL_STYLE, main_window_style_);
  }
  if (main_window_ex_style_ != 0) {
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, main_window_ex_style_);
  }
  SetWindowRgn(hwnd, nullptr, TRUE);
  quick_picker_window_style_ = false;
  quick_picker_always_on_top_ = false;
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
}

void FlutterWindow::ApplyQuickPickerWindowStyle() {
  HWND hwnd = GetHandle();
  if (!hwnd || quick_picker_window_style_) {
    return;
  }
  main_window_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
  main_window_ex_style_ = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  SetWindowLongPtr(hwnd, GWL_STYLE, WS_POPUP | WS_CLIPCHILDREN | WS_CLIPSIBLINGS);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, main_window_ex_style_ | WS_EX_TOOLWINDOW);
  const DWORD corner_preference = DWMWCP_ROUND;
  DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE,
                        &corner_preference, sizeof(corner_preference));
  quick_picker_window_style_ = true;
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
}

void FlutterWindow::ShowQuickPickerWindow() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  if (!has_main_window_rect_ && IsWindowVisible(hwnd)) {
    GetWindowRect(hwnd, &main_window_rect_);
    has_main_window_rect_ = true;
  }

  const int width = 600;
  const int height = 640;
  POINT cursor;
  GetCursorPos(&cursor);
  HMONITOR monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFO);
  GetMonitorInfo(monitor, &monitor_info);
  const RECT work_area = monitor_info.rcWork;
  int x = cursor.x - width / 2;
  int y = cursor.y - height / 3;
  if (x < work_area.left) x = work_area.left;
  if (x > work_area.right - width) x = work_area.right - width;
  if (y < work_area.top) y = work_area.top;
  if (y > work_area.bottom - height) y = work_area.bottom - height;

  if (!AttachFlutterViewToQuickPicker()) {
    return;
  }
  ShowWindow(hwnd, SW_HIDE);
  SetWindowPos(quick_picker_hwnd_,
               quick_picker_always_on_top_ ? HWND_TOPMOST : HWND_TOP, x, y,
               width, height, SWP_SHOWWINDOW);
  SetForegroundWindow(quick_picker_hwnd_);
  SetFocus(flutter_view_hwnd_);
}

void FlutterWindow::SetQuickPickerAlwaysOnTop(bool enabled) {
  quick_picker_always_on_top_ = enabled;
  if (quick_picker_hwnd_) {
    SetWindowPos(quick_picker_hwnd_, enabled ? HWND_TOPMOST : HWND_NOTOPMOST, 0,
                 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }
}

void FlutterWindow::HideToTray() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }
  if (quick_picker_hwnd_ && IsWindowVisible(quick_picker_hwnd_)) {
    ShowWindow(quick_picker_hwnd_, SW_HIDE);
  }
  AttachFlutterViewToMainWindow();
  ShowWindow(hwnd, SW_HIDE);
}

void FlutterWindow::CaptureQuickPasteTarget() {
  HWND hwnd = GetHandle();
  HWND foreground = GetForegroundWindow();
  if (foreground == nullptr || foreground == hwnd ||
      foreground == quick_picker_hwnd_) {
    quick_paste_target_ = nullptr;
    return;
  }
  quick_paste_target_ = foreground;
}

bool FlutterWindow::PasteToQuickPasteTarget(bool return_to_quick_picker) {
  HWND target = quick_paste_target_;
  HWND picker = quick_picker_hwnd_;
  HWND main = GetHandle();
  if (target == nullptr || !IsWindow(target) || target == picker ||
      target == main) {
    return false;
  }

  if (IsIconic(target)) {
    ShowWindow(target, SW_RESTORE);
  }
  SetForegroundWindow(target);
  Sleep(80);
  SendCtrlV();

  if (return_to_quick_picker && picker != nullptr && IsWindow(picker)) {
    Sleep(90);
    SetForegroundWindow(picker);
  }
  return true;
}

void FlutterWindow::SendCtrlV() {
  INPUT inputs[4]{};
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_CONTROL;
  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = 'V';
  inputs[2].type = INPUT_KEYBOARD;
  inputs[2].ki.wVk = 'V';
  inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;
  inputs[3].type = INPUT_KEYBOARD;
  inputs[3].ki.wVk = VK_CONTROL;
  inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;
  SendInput(4, inputs, sizeof(INPUT));
}

void FlutterWindow::ShowTrayMenu() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, kTrayMenuOpen, L"M\u1EDF OpenCB");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayMenuQuit, L"Tho\u00E1t");

  POINT cursor;
  GetCursorPos(&cursor);
  SetForegroundWindow(hwnd);
  TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | TPM_LEFTALIGN,
                 cursor.x, cursor.y, 0, hwnd, nullptr);
  DestroyMenu(menu);
}

void FlutterWindow::RegisterQuickOpenHotKey() {
  if (!quick_open_hot_key_enabled_) {
    return;
  }
  RegisterHotKey(GetHandle(), kQuickOpenHotKeyId,
                 quick_open_hot_key_modifiers_,
                 quick_open_hot_key_key_code_);
}

void FlutterWindow::UnregisterQuickOpenHotKey() {
  UnregisterHotKey(GetHandle(), kQuickOpenHotKeyId);
}

bool FlutterWindow::SetQuickOpenHotKey(bool enabled, UINT modifiers,
                                       UINT key_code) {
  quick_open_hot_key_enabled_ = enabled;
  quick_open_hot_key_modifiers_ = modifiers;
  quick_open_hot_key_key_code_ = key_code;
  UnregisterQuickOpenHotKey();
  if (!enabled) {
    return true;
  }
  return RegisterHotKey(GetHandle(), kQuickOpenHotKeyId, modifiers, key_code) ==
         TRUE;
}

void FlutterWindow::PublishQuickOpenRequest() {
  if (!clipboard_channel_) {
    return;
  }
  clipboard_channel_->InvokeMethod("quickOpenRequested", nullptr);
}

void FlutterWindow::PublishMainWindowRequest() {
  if (!clipboard_channel_) {
    return;
  }
  clipboard_channel_->InvokeMethod("mainWindowRequested", nullptr);
}

void FlutterWindow::PublishQuickPickerDeactivated() {
  if (!clipboard_channel_) {
    return;
  }
  clipboard_channel_->InvokeMethod("quickPickerDeactivated", nullptr);
}

void FlutterWindow::PublishClipboardSnapshot() {
  if (!clipboard_channel_) {
    return;
  }
  auto snapshot = ReadClipboardSnapshot();
  auto type = snapshot.find(flutter::EncodableValue("type"));
  if (type == snapshot.end()) {
    return;
  }
  clipboard_channel_->InvokeMethod(
      "clipboardChanged",
      std::make_unique<flutter::EncodableValue>(std::move(snapshot)));
}

bool FlutterWindow::WriteBitmapToClipboard(const std::vector<uint8_t>& bytes) {
  if (IsPngBytes(bytes)) {
    if (!OpenClipboardWithRetry(GetHandle())) {
      return false;
    }

    EmptyClipboard();
    bool wrote_data = false;
    const UINT png_format = RegisterClipboardFormatW(L"PNG");
    HGLOBAL png_memory = GlobalMemoryFromBytes(bytes);
    if (png_format != 0 && png_memory != nullptr &&
        SetClipboardData(png_format, png_memory) != nullptr) {
      wrote_data = true;
    } else if (png_memory != nullptr) {
      GlobalFree(png_memory);
    }

    const UINT image_png_format = RegisterClipboardFormatW(L"image/png");
    HGLOBAL image_png_memory = GlobalMemoryFromBytes(bytes);
    if (image_png_format != 0 && image_png_memory != nullptr &&
        SetClipboardData(image_png_format, image_png_memory) != nullptr) {
      wrote_data = true;
    } else if (image_png_memory != nullptr) {
      GlobalFree(image_png_memory);
    }

    CloseClipboard();
    return wrote_data;
  }

  size_t dib_size = 0;
  const uint8_t* dib_bytes = DibBytesFromBmpBytes(bytes, &dib_size);
  if (dib_bytes == nullptr || dib_size == 0) {
    return false;
  }

  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, dib_size);
  if (memory == nullptr) {
    return false;
  }
  void* target = GlobalLock(memory);
  if (target == nullptr) {
    GlobalFree(memory);
    return false;
  }
  std::memcpy(target, dib_bytes, dib_size);
  GlobalUnlock(memory);

  if (!OpenClipboardWithRetry(GetHandle())) {
    GlobalFree(memory);
    return false;
  }
  EmptyClipboard();
  if (SetClipboardData(CF_DIB, memory) == nullptr) {
    CloseClipboard();
    GlobalFree(memory);
    return false;
  }
  CloseClipboard();
  return true;
}

flutter::EncodableMap FlutterWindow::ReadClipboardSnapshot() {
  flutter::EncodableMap snapshot;
  const auto source_info = ForegroundSourceInfo(GetHandle());
  if (!source_info.name.empty()) {
    snapshot[flutter::EncodableValue("sourceApp")] =
        flutter::EncodableValue(source_info.name);
  }
  if (!source_info.icon_bytes.empty()) {
    snapshot[flutter::EncodableValue("sourceIcon")] =
        flutter::EncodableValue(source_info.icon_bytes);
  }
  if (!OpenClipboardWithRetry(GetHandle())) {
    return snapshot;
  }

  if (IsClipboardFormatAvailable(CF_HDROP)) {
    auto drop = static_cast<HDROP>(GetClipboardData(CF_HDROP));
    if (drop != nullptr) {
      UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
      flutter::EncodableList files;
      for (UINT index = 0; index < count; ++index) {
        UINT length = DragQueryFileW(drop, index, nullptr, 0);
        std::wstring path(length + 1, L'\0');
        DragQueryFileW(drop, index, path.data(), length + 1);
        path.resize(length);
        files.emplace_back(Utf8FromWide(path));
      }
      if (!files.empty()) {
        snapshot[flutter::EncodableValue("type")] =
            flutter::EncodableValue("file_reference");
        snapshot[flutter::EncodableValue("files")] = flutter::EncodableValue(files);
        CloseClipboard();
        return snapshot;
      }
    }
  }

  const UINT file_name_w_format = RegisterClipboardFormatW(L"FileNameW");
  if (auto file_name = ClipboardWideText(file_name_w_format);
      file_name.has_value()) {
    flutter::EncodableList files;
    files.emplace_back(file_name.value());
    snapshot[flutter::EncodableValue("type")] =
        flutter::EncodableValue("file_reference");
    snapshot[flutter::EncodableValue("files")] =
        flutter::EncodableValue(files);
    snapshot[flutter::EncodableValue("format")] =
        flutter::EncodableValue("FileNameW");
    CloseClipboard();
    return snapshot;
  }

  const UINT file_name_format = RegisterClipboardFormatW(L"FileName");
  if (auto file_name = ClipboardAnsiText(file_name_format);
      file_name.has_value()) {
    flutter::EncodableList files;
    files.emplace_back(file_name.value());
    snapshot[flutter::EncodableValue("type")] =
        flutter::EncodableValue("file_reference");
    snapshot[flutter::EncodableValue("files")] =
        flutter::EncodableValue(files);
    snapshot[flutter::EncodableValue("format")] =
        flutter::EncodableValue("FileName");
    CloseClipboard();
    return snapshot;
  }

  auto png_bytes = PngBytesFromClipboard();
  if (!png_bytes.empty()) {
    snapshot[flutter::EncodableValue("type")] =
        flutter::EncodableValue("image");
    snapshot[flutter::EncodableValue("bytes")] =
        flutter::EncodableValue(std::move(png_bytes));
    snapshot[flutter::EncodableValue("format")] =
        flutter::EncodableValue("png");
    CloseClipboard();
    return snapshot;
  }

  if (IsClipboardFormatAvailable(CF_DIBV5)) {
    HANDLE data = GetClipboardData(CF_DIBV5);
    auto bytes = BmpBytesFromDib(data);
    if (!bytes.empty()) {
      snapshot[flutter::EncodableValue("type")] =
          flutter::EncodableValue("image");
      snapshot[flutter::EncodableValue("bytes")] =
          flutter::EncodableValue(std::move(bytes));
      snapshot[flutter::EncodableValue("format")] =
          flutter::EncodableValue("bmp_dibv5");
      CloseClipboard();
      return snapshot;
    }
  }

  if (IsClipboardFormatAvailable(CF_DIB)) {
    HANDLE data = GetClipboardData(CF_DIB);
    auto bytes = BmpBytesFromDib(data);
    if (!bytes.empty()) {
      snapshot[flutter::EncodableValue("type")] =
          flutter::EncodableValue("image");
      snapshot[flutter::EncodableValue("bytes")] =
          flutter::EncodableValue(std::move(bytes));
      snapshot[flutter::EncodableValue("format")] =
          flutter::EncodableValue("bmp_dib");
      CloseClipboard();
      return snapshot;
    }
  }

  if (IsClipboardFormatAvailable(CF_UNICODETEXT)) {
    HANDLE data = GetClipboardData(CF_UNICODETEXT);
    if (data != nullptr) {
      auto text = static_cast<const wchar_t*>(GlobalLock(data));
      if (text != nullptr) {
        std::wstring wide_text(text);
        GlobalUnlock(data);
        if (!wide_text.empty()) {
          snapshot[flutter::EncodableValue("type")] =
              flutter::EncodableValue("text");
          snapshot[flutter::EncodableValue("text")] =
              flutter::EncodableValue(Utf8FromWide(wide_text));
        }
      }
    }
  }

  CloseClipboard();
  return snapshot;
}
