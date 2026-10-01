#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

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

  nav_syskey_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "zishu/windows/nav_syskey",
          &flutter::StandardMethodCodec::GetInstance());

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  nav_syskey_channel_ = nullptr;

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Drive a redraw + present after any resize. Without this, launching in a
  // no-interaction environment (scheduled task, no mouse/keyboard event stream)
  // can end up with a blank client area: restoring the saved window geometry
  // triggers WM_SIZE, the surface is recreated at the new size and the frame
  // already presented is discarded, but the message loop never delivers a
  // WM_PAINT afterwards, so the first frame at the new size never hits the
  // screen until the user resizes the window manually. ForceRedraw is a no-op
  // until the first frame completes (see the comment in OnCreate), so this is
  // free on the regular startup path; minimized windows need no painting.
  if (message == WM_SIZE && wparam != SIZE_MINIMIZED && flutter_controller_) {
    flutter_controller_->ForceRedraw();
  }

  // Alt+arrow / Alt+Home navigation forwarded to Dart at the message level.
  //
  // External mouse-gesture tools replay these combos as synthetic key events,
  // and synthetic Alt never survives to the framework: the engine synthesizes
  // an Alt key-up right after the injected Alt key-down (the physical key is
  // not held), so the framework sees ArrowLeft without the Alt modifier and
  // the CallbackShortcuts binding (SingleActivator alt: true) never fires.
  // WM_SYSKEYDOWN posted directly to this top-level window is not surfaced to
  // the framework at all. Every form (real presses, SendInput/keybd_event,
  // posted messages) carries the KF_ALTDOWN context bit in lParam, so match
  // it here before Flutter handles the message. Consuming the message also
  // keeps real key presses single-pathed (the framework shortcut never sees
  // them, so navigation cannot fire twice).
  if (flutter_controller_ && nav_syskey_channel_ &&
      (message == WM_SYSKEYDOWN || message == WM_SYSKEYUP) &&
      (HIWORD(lparam) & KF_ALTDOWN) != 0) {
    const char* method = nullptr;
    switch (wparam) {
      case VK_LEFT:
        method = "back";
        break;
      case VK_RIGHT:
        method = "forward";
        break;
      case VK_HOME:
        method = "home";
        break;
      default:
        break;
    }
    if (method != nullptr) {
      if (message == WM_SYSKEYDOWN) {
        nav_syskey_channel_->InvokeMethod(method, nullptr);
      }
      return 0;
    }
  }

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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
