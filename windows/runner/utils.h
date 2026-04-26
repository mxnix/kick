#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>
#include <windows.h>

// Window title used by the Windows runner and activation lookup.
extern const wchar_t kKickWindowTitle[];

// Named mutex that prevents multiple KiCk processes from running at once.
extern const wchar_t kKickSingleInstanceMutexName[];

// Creates a console for the process, and redirects stdout and stderr to
// it for both the runner and the Flutter library.
void CreateAndAttachConsole();

// Takes a null-terminated wchar_t* encoded in UTF-16 and returns a std::string
// encoded in UTF-8. Returns an empty std::string on failure.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Takes a null-terminated UTF-8 string and returns a std::wstring encoded in
// UTF-16. Returns an empty std::wstring on failure.
std::wstring Utf16FromUtf8(const char* utf8_string);

// Gets the command line arguments passed in as a std::vector<std::string>,
// encoded in UTF-8. Returns an empty std::vector<std::string> on failure.
std::vector<std::string> GetCommandLineArguments();

// Returns the registered Windows message used to activate an existing KiCk
// window when a second process is launched.
UINT GetKickActivateWindowMessage();

// Shows, raises, and focuses an existing KiCk window as reliably as Windows
// foreground activation rules allow.
void ActivateKickWindow(HWND window);

// Tries to find an already-running KiCk window, ask it to show itself, and
// bring it to the foreground. Returns true when an existing window is found.
bool NotifyExistingKickInstance();

#endif  // RUNNER_UTILS_H_
