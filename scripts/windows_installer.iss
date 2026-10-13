; 随播 Windows 安装版：AppId 永久保持稳定，后续同安装目录覆盖升级。
#ifndef MyAppVersion
  #define MyAppVersion "2.3.8"
#endif

[Setup]
AppId=Suibo.Windows.Desktop
AppName=随播
AppVersion={#MyAppVersion}
AppVerName=随播 {#MyAppVersion}
DefaultDirName={autopf}\随播
DefaultGroupName=随播
OutputDir=..\build\windows\installer
OutputBaseFilename=Suibo-Windows-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\suibo.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\随播"; Filename: "{app}\suibo.exe"
Name: "{autodesktop}\随播"; Filename: "{app}\suibo.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\suibo.exe"; Description: "运行随播"; Flags: nowait postinstall skipifsilent
