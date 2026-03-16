#define MyAppName "KiCk"

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#ifndef SourceDir
  #error SourceDir define is required.
#endif

#ifndef OutputDir
  #define OutputDir "build\dist"
#endif

#ifndef RepoRoot
  #error RepoRoot define is required.
#endif

[Setup]
AppId={{1D568E3B-29E9-4C4D-9438-308E83DCC73E}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppVerName={#MyAppName} {#AppVersion}
AppPublisher=nikzmx
DefaultDirName={localappdata}\Programs\KiCk
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=kick-windows-{#AppVersion}-setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile={#RepoRoot}\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\KiCk.exe
LicenseFile={#RepoRoot}\LICENSE.md

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\KiCk"; Filename: "{app}\KiCk.exe"
Name: "{autodesktop}\KiCk"; Filename: "{app}\KiCk.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\KiCk.exe"; Description: "{cm:LaunchProgram,KiCk}"; Flags: nowait postinstall skipifsilent
