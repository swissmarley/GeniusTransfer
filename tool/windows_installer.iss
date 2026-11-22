; Per-user installer for the Windows build. Built by the release workflow:
;   iscc /DAppVersion=1.0.0 /DSourceDir=<Release folder> /DOutputDir=<dir> tool\windows_installer.iss
#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

[Setup]
AppId={{6B0C2F0E-5A47-4B7D-9B38-2D9C1E8F7A11}
AppName=GeniusTransfer
AppVersion={#AppVersion}
AppPublisher=GeniusTransfer
DefaultDirName={localappdata}\GeniusTransfer
DefaultGroupName=GeniusTransfer
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=GeniusTransfer-{#AppVersion}-windows-x64
Compression=lzma2
SolidCompression=yes
UninstallDisplayIcon={app}\GeniusTransfer.exe
DisableProgramGroupPage=yes

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\GeniusTransfer"; Filename: "{app}\GeniusTransfer.exe"

[Run]
Filename: "{app}\GeniusTransfer.exe"; Description: "Launch GeniusTransfer"; Flags: nowait postinstall skipifsilent
