#define AppName "OpenCB"
#ifndef AppVersion
#define AppVersion "1.0.0"
#endif
#ifndef RepoRoot
#define RepoRoot "..\.."
#endif

#define BuildDir RepoRoot + "\apps\opencb_app\build\windows\x64\runner\Release"

[Setup]
AppId={{7F4C8D69-26AD-4E80-A4A9-31E3F7F0A8CB}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=OpenCB
AppPublisherURL=https://github.com/tranlap1602/OpenCB
AppSupportURL=https://github.com/tranlap1602/OpenCB/issues
AppUpdatesURL=https://github.com/tranlap1602/OpenCB/releases
DefaultDirName={autopf}\OpenCB
DefaultGroupName=OpenCB
DisableProgramGroupPage=yes
OutputDir={#RepoRoot}\dist
OutputBaseFilename=OpenCB-Setup-{#AppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\opencb_app.exe
SetupIconFile={#RepoRoot}\apps\opencb_app\windows\runner\resources\app_icon.ico
CloseApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\OpenCB"; Filename: "{app}\opencb_app.exe"
Name: "{autodesktop}\OpenCB"; Filename: "{app}\opencb_app.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\opencb_app.exe"; Description: "{cm:LaunchProgram,OpenCB}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
const
  OpenCBTrayQuitCommand = 40002;
  WM_COMMAND = $0111;

procedure RequestOpenCBQuit();
var
  Wnd: HWND;
  Attempt: Integer;
begin
  for Attempt := 1 to 4 do
  begin
    Wnd := FindWindowByWindowName('OpenCB');
    if Wnd = 0 then
      Exit;

    PostMessage(Wnd, WM_COMMAND, OpenCBTrayQuitCommand, 0);
    Sleep(500);
  end;
end;

function StopOpenCBProcess(): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  Exec(
    ExpandConstant('{sys}\taskkill.exe'),
    '/IM opencb_app.exe /T /F',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  );

  // taskkill returns 128 when there is no matching process, which is fine here.
  if (ResultCode <> 0) and (ResultCode <> 128) then
    Result := False;
end;

function CloseRunningOpenCB(): Boolean;
begin
  RequestOpenCBQuit();
  Sleep(300);
  Result := StopOpenCBProcess();
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not CloseRunningOpenCB() then
    Result := 'Không thể đóng OpenCB đang chạy nền. Hãy thoát OpenCB ở system tray rồi chạy lại bộ cài.';
end;

function InitializeUninstall(): Boolean;
begin
  Result := CloseRunningOpenCB();
  if not Result then
    MsgBox(
      'Không thể đóng OpenCB đang chạy nền. Hãy thoát OpenCB ở system tray rồi gỡ cài đặt lại.',
      mbError,
      MB_OK
    );
end;
