#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdint>
#include <cstdio>
#include <cwchar>
#include <cwctype>
#include <string>
#include <vector>
#include "flutter_window.h"
#include "utils.h"

namespace
{
constexpr int kTrayMenuOpen = 40001;
constexpr const wchar_t kWindowTitle[] = L"OpenCB";

std::wstring CurrentExecutablePath()
{
  std::wstring path(MAX_PATH, L'\0');
  DWORD size = GetModuleFileNameW(nullptr, path.data(),
                                  static_cast<DWORD>(path.size()));
  while (size == path.size() && GetLastError() == ERROR_INSUFFICIENT_BUFFER)
  {
    path.resize(path.size() * 2, L'\0');
    size = GetModuleFileNameW(nullptr, path.data(),
                              static_cast<DWORD>(path.size()));
  }
  path.resize(size);
  return path;
}

std::wstring LowerPath(std::wstring value)
{
  for (auto &ch : value)
  {
    ch = static_cast<wchar_t>(std::towlower(ch));
  }
  return value;
}

uint64_t StablePathHash(const std::wstring &path)
{
  uint64_t hash = 1469598103934665603ULL;
  for (wchar_t ch : LowerPath(path))
  {
    hash ^= static_cast<uint64_t>(ch);
    hash *= 1099511628211ULL;
  }
  return hash;
}

std::wstring SingleInstanceMutexName(const std::wstring &path)
{
  wchar_t suffix[17]{};
  swprintf_s(suffix, L"%016llx",
             static_cast<unsigned long long>(StablePathHash(path)));
  return std::wstring(L"Local\\OpenCB_") + suffix;
}

std::wstring ProcessPath(DWORD process_id)
{
  HANDLE process =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (process == nullptr)
  {
    return L"";
  }

  std::wstring path(32768, L'\0');
  DWORD size = static_cast<DWORD>(path.size());
  if (!QueryFullProcessImageNameW(process, 0, path.data(), &size))
  {
    CloseHandle(process);
    return L"";
  }

  CloseHandle(process);
  path.resize(size);
  return path;
}

struct ExistingInstanceSearch
{
  std::wstring executable_path;
  HWND window = nullptr;
};

BOOL CALLBACK FindExistingInstanceWindow(HWND hwnd, LPARAM param)
{
  wchar_t title[64]{};
  GetWindowTextW(hwnd, title, static_cast<int>(sizeof(title) / sizeof(title[0])));
  if (wcscmp(title, kWindowTitle) != 0)
  {
    return TRUE;
  }

  DWORD process_id = 0;
  GetWindowThreadProcessId(hwnd, &process_id);
  if (process_id == 0)
  {
    return TRUE;
  }

  auto *search = reinterpret_cast<ExistingInstanceSearch *>(param);
  const std::wstring path = ProcessPath(process_id);
  if (!path.empty() &&
      LowerPath(path) == LowerPath(search->executable_path))
  {
    search->window = hwnd;
    return FALSE;
  }

  return TRUE;
}

void ShowExistingInstance(const std::wstring &executable_path)
{
  ExistingInstanceSearch search{executable_path, nullptr};
  EnumWindows(FindExistingInstanceWindow,
              reinterpret_cast<LPARAM>(&search));
  if (search.window == nullptr)
  {
    return;
  }

  PostMessageW(search.window, WM_COMMAND, kTrayMenuOpen, 0);
}

bool ShouldStartHidden(const std::vector<std::string> &arguments)
{
  for (const auto &argument : arguments)
  {
    if (argument == "--background" || argument == "--tray")
    {
      return true;
    }
  }
  return false;
}
} // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const bool start_hidden = ShouldStartHidden(command_line_arguments);

  const std::wstring executable_path = CurrentExecutablePath();
  HANDLE single_instance_mutex = CreateMutexW(
      nullptr, TRUE, SingleInstanceMutexName(executable_path).c_str());
  if (single_instance_mutex != nullptr &&
      GetLastError() == ERROR_ALREADY_EXISTS)
  {
    if (!start_hidden)
    {
      ShowExistingInstance(executable_path);
    }
    CloseHandle(single_instance_mutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, start_hidden);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1040, 660);
  window.SetMinimumSize(Win32Window::Size(390, 560));
  if (!window.Create(L"OpenCB", origin, size))
  {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance_mutex != nullptr)
  {
    CloseHandle(single_instance_mutex);
  }
  return EXIT_SUCCESS;
}
