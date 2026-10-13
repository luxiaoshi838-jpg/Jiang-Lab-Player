; Suibo/随播 Windows installer. Inno Setup 6.
; Immutable AppId allows an installer to upgrade the preceding installed version.
; This installer includes the entire Flutter release directory; suibo.exe alone
; is not a portable or installable app.
#ifndef MyAppVersion
  #error MyAppVersion must be supplied by build_windows_installer.ps1
#endif
#ifndef FlutterReleaseDir
  #error FlutterReleaseDir must be supplied by build_windows_installer.ps1
#endif
#ifndef InstallerOutputDir
  #error InstallerOutputDir must be supplied by build_windows_installer.ps1
#endif

[Setup]
AppId={{FE6015EC-9973-449D-9B64-662CF98C580B}
AppName=随播
AppVerName=随播 {#MyAppVersion}
AppVersion={#MyAppVersion}
AppPublisher=Jiang Lab
AppPublisherURL=https://github.com/luxiaoshi838-jpg/Jiang-Lab-Player
AppSupportURL=https://github.com/luxiaoshi838-jpg/Jiang-Lab-Player/issues
DefaultDirName={localappdata}\Programs\Suibo
DefaultGroupName=随播
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
PrivilegesRequired=lowest
OutputDir={#InstallerOutputDir}
OutputBaseFilename=Suibo-Setup-{#MyAppVersion}-Windows-x64
UninstallDisplayIcon={app}\Suibo-{#MyAppVersion}.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
CloseApplications=yes
RestartApplications=no
AppMutex=suibo.win.mutex
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "chinesesimp"; MessagesFile: ".\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务:"; Flags: unchecked

[Files]
Source: "{#FlutterReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\windows\runner\resources\app_icon.ico"; DestDir: "{app}"; DestName: "Suibo-{#MyAppVersion}.ico"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\随播"; Filename: "{app}\suibo.exe"; IconFilename: "{app}\Suibo-{#MyAppVersion}.ico"
Name: "{autodesktop}\随播"; Filename: "{app}\suibo.exe"; IconFilename: "{app}\Suibo-{#MyAppVersion}.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\suibo.exe"; Description: "启动随播"; Flags: nowait postinstall skipifsilent

; Deliberately no [UninstallDelete] of AppData, Hive, collections or settings.
; Flutter's per-user application-support data must survive upgrades.
