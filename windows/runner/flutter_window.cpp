#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

std::optional<std::wstring> FlutterWindow::TakeScheduledInstallerPath() {
  return std::move(scheduled_installer_path_);
}

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
  app_update_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "kick/app_update",
          &flutter::StandardMethodCodec::GetInstance());
  app_update_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<
                 flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "scheduleInstallerOnExit") {
          result->NotImplemented();
          return;
        }

        const auto* arguments = call.arguments();
        const auto* arguments_map =
            arguments == nullptr
                ? nullptr
                : std::get_if<flutter::EncodableMap>(arguments);
        if (arguments_map == nullptr) {
          result->Error("invalid_args", "Expected a filePath argument.");
          return;
        }

        const auto iterator =
            arguments_map->find(flutter::EncodableValue("filePath"));
        if (iterator == arguments_map->end()) {
          result->Error("invalid_args", "Expected a filePath argument.");
          return;
        }

        const auto* file_path = std::get_if<std::string>(&iterator->second);
        if (file_path == nullptr || file_path->empty()) {
          result->Error("invalid_args", "Expected a non-empty filePath.");
          return;
        }

        const std::wstring wide_path = Utf16FromUtf8(file_path->c_str());
        if (wide_path.empty()) {
          result->Error("invalid_args", "The installer path could not be parsed.");
          return;
        }

        scheduled_installer_path_ = wide_path;
        result->Success(flutter::EncodableValue(true));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // The Dart side (window_manager + WindowBootstrap.reveal) controls when
  // the window becomes visible. Showing the window here, the moment the
  // engine reports its first frame, used to flash a default 430x860
  // WS_OVERLAPPEDWINDOW with a white background in the top-left corner
  // before WindowBootstrap.configure() had a chance to apply the saved
  // bounds, frameless chrome and dark theme. By keeping the window hidden
  // we let Dart restore geometry first and call windowManager.show() once
  // the loading shell is ready, eliminating the flash.
  //
  // ForceRedraw is intentionally left out for the same reason - we don't
  // want to repaint a window the user is not supposed to see yet.
  return true;
}

void FlutterWindow::OnDestroy() {
  if (app_update_channel_) {
    app_update_channel_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == GetKickActivateWindowMessage()) {
    ActivateKickWindow(hwnd);
    return 0;
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
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
