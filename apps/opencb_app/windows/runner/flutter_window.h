#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <shellapi.h>

#include <memory>
#include <vector>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project,
                         bool start_hidden = false);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;
  bool start_hidden_ = false;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      clipboard_channel_;

  NOTIFYICONDATAW tray_icon_data_{};
  bool tray_icon_added_ = false;
  RECT main_window_rect_{};
  bool has_main_window_rect_ = false;
  LONG_PTR main_window_style_ = 0;
  LONG_PTR main_window_ex_style_ = 0;
  bool quick_picker_window_style_ = false;
  bool quick_picker_always_on_top_ = false;
  HWND quick_picker_hwnd_ = nullptr;
  HWND flutter_view_hwnd_ = nullptr;
  bool flutter_view_in_quick_picker_ = false;
  HWND quick_paste_target_ = nullptr;
  bool quick_open_hot_key_enabled_ = true;
  UINT quick_open_hot_key_modifiers_ = MOD_CONTROL | MOD_ALT;
  UINT quick_open_hot_key_key_code_ = 'V';

  void SetupClipboardChannel();
  void AddTrayIcon();
  void RemoveTrayIcon();
  void ShowFromTray();
  void PrepareMainWindowFromQuickPicker();
  void ShowPreparedMainWindow();
  void ShowQuickPickerWindow();
  void HideToTray();
  void ShowTrayMenu();
  void ApplyMainWindowStyle();
  void ApplyQuickPickerWindowStyle();
  bool EnsureQuickPickerWindow();
  void AttachFlutterViewToMainWindow();
  bool AttachFlutterViewToQuickPicker();
  void SetQuickPickerAlwaysOnTop(bool enabled);
  void CaptureQuickPasteTarget();
  bool PasteToQuickPasteTarget(bool return_to_quick_picker);
  void SendCtrlV();
  void RegisterQuickOpenHotKey();
  void UnregisterQuickOpenHotKey();
  bool SetQuickOpenHotKey(bool enabled, UINT modifiers, UINT key_code);
  void PublishQuickOpenRequest();
  void PublishMainWindowRequest();
  void PublishQuickPickerDeactivated();
  void PublishClipboardSnapshot();
  bool WriteBitmapToClipboard(const std::vector<uint8_t>& bytes);
  flutter::EncodableMap ReadClipboardSnapshot();
  LRESULT QuickPickerMessageHandler(HWND window, UINT const message,
                                    WPARAM const wparam,
                                    LPARAM const lparam) noexcept;
  static LRESULT CALLBACK QuickPickerWndProc(HWND const window,
                                             UINT const message,
                                             WPARAM const wparam,
                                             LPARAM const lparam) noexcept;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
