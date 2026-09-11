#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // Default client area 1024x768 to align with tool/screenshots/sfvideo/
  // 1024x768_tablet_land_* baselines (browser viewport size). CreateWindow
  // takes the OUTER size (frame + title bar), so convert the desired client
  // rect via AdjustWindowRect to keep the Flutter viewport exactly 1024x768.
  RECT target_client = {0, 0, 1024, 768};
  AdjustWindowRect(&target_client, WS_OVERLAPPEDWINDOW, FALSE);
  const int outer_w = target_client.right - target_client.left;
  const int outer_h = target_client.bottom - target_client.top;
  Win32Window::Size size(outer_w, outer_h);
  if (!window.Create(L"zishu_flutter", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
