; Quick Mail — Windows installer (NSIS).
;
; v1 POLICY: this REPACKAGES the official Thunderbird ESR win64 binaries (see
; windows-pin.txt) with QuickOpen branding around them — our distribution dir
; (policies.json + distribution.ini mirroring the Linux build's branding
; prefs), Quick Mail shortcuts + icon, a "Quick Mail" mailto handler, and our
; licences. The Linux deb is a full from-source rebrand; the Windows source
; build is a later phase. Upstream binaries ship byte-identical — Mozilla's
; Authenticode signatures on them are untouched; only this OUTER installer is
; ours.
;
;   makensis -DPAYLOAD=<dir> -DVERSION=<x.y.z.w> -DDISPLAYVERSION=<ver-rev> \
;            -DESTSIZE_KB=<du -sk> -DOUTFILE=<path> installer.nsi
;
; Supports silent install/uninstall with /S. Installs machine-wide (admin).

Unicode true
!include "MUI2.nsh"

!define APPNAME "Quick Mail"
!define APPKEY  "QuickMail"
!define PUBLISHER "QuickOpen"
!define APPURL "https://quickopen.ai/projects/quick-mail"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPKEY}"

Name "${APPNAME}"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\QuickOpen\${APPNAME}"
RequestExecutionLevel admin
; the outer installer gets Authenticode-signed after the build; the appended
; signature would invalidate the NSIS CRC, so integrity rides on the signature
CRCCheck off
SetCompressor /SOLID lzma
SetCompressorDictSize 64

VIProductVersion "${VERSION}"
VIAddVersionKey "ProductName" "${APPNAME}"
VIAddVersionKey "CompanyName" "${PUBLISHER}"
VIAddVersionKey "ProductVersion" "${DISPLAYVERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "${APPNAME} installer"
VIAddVersionKey "LegalCopyright" "Engine: MPL-2.0 (a derivative of Thunderbird). QuickOpen layer: Apache-2.0."

!define MUI_ICON "${ICOFILE}"
!define MUI_UNICON "${ICOFILE}"
!insertmacro MUI_PAGE_LICENSE "${LICENSEFILE}"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Quick Mail"
  SetRegView 64
  SetShellVarContext all
  SetOutPath "$INSTDIR"

  ; upstream payload, byte-identical (Mozilla signatures intact)
  File /r "${PAYLOAD}/*"

  ; our branding + licences
  File "${ICOFILE}"

  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ; shortcuts — Quick name + Quick icon
  CreateShortCut "$SMPROGRAMS\${APPNAME}.lnk" "$INSTDIR\thunderbird.exe" "" "$INSTDIR\quick-mail.ico" 0 SW_SHOWNORMAL "" "Send and receive mail, with calendar and contacts — on your machine, not in a cloud"
  CreateShortCut "$DESKTOP\${APPNAME}.lnk" "$INSTDIR\thunderbird.exe" "" "$INSTDIR\quick-mail.ico" 0

  ; uninstall entry
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayVersion" "${DISPLAYVERSION}"
  WriteRegStr HKLM "${UNINSTKEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayIcon" "$INSTDIR\quick-mail.ico"
  WriteRegStr HKLM "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTKEY}" "URLInfoAbout" "${APPURL}"
  WriteRegStr HKLM "${UNINSTKEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${UNINSTKEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoRepair" 1
  WriteRegDWORD HKLM "${UNINSTKEY}" "EstimatedSize" ${ESTSIZE_KB}

  ; mail-client capability + mailto handler, named Quick Mail
  ; (mirrors the Linux .desktop's x-scheme-handler/mailto)
  WriteRegStr HKLM "Software\Clients\Mail\${APPNAME}" "" "${APPNAME}"
  WriteRegStr HKLM "Software\Clients\Mail\${APPNAME}\DefaultIcon" "" "$INSTDIR\quick-mail.ico,0"
  WriteRegStr HKLM "Software\Clients\Mail\${APPNAME}\shell\open\command" "" '"$INSTDIR\thunderbird.exe" -mail'
  WriteRegStr HKLM "Software\Clients\Mail\${APPNAME}\Capabilities" "ApplicationName" "${APPNAME}"
  WriteRegStr HKLM "Software\Clients\Mail\${APPNAME}\Capabilities" "ApplicationDescription" "Send and receive mail, with calendar and contacts — on your machine, not in a cloud."
  WriteRegStr HKLM "Software\Clients\Mail\${APPNAME}\Capabilities" "ApplicationIcon" "$INSTDIR\quick-mail.ico,0"
  WriteRegStr HKLM "Software\Clients\Mail\${APPNAME}\Capabilities\StartMenu" "Mail" "${APPNAME}"
  WriteRegStr HKLM "Software\Clients\Mail\${APPNAME}\Capabilities\URLAssociations" "mailto" "${APPKEY}.Url.mailto"
  WriteRegStr HKLM "Software\Classes\${APPKEY}.Url.mailto" "" "${APPNAME} (URL:MailTo Protocol)"
  WriteRegStr HKLM "Software\Classes\${APPKEY}.Url.mailto" "URL Protocol" ""
  WriteRegStr HKLM "Software\Classes\${APPKEY}.Url.mailto\DefaultIcon" "" "$INSTDIR\quick-mail.ico,0"
  WriteRegStr HKLM "Software\Classes\${APPKEY}.Url.mailto\shell\open\command" "" '"$INSTDIR\thunderbird.exe" -osint -compose "%1"'
  WriteRegStr HKLM "Software\RegisteredApplications" "${APPNAME}" "Software\Clients\Mail\${APPNAME}\Capabilities"
SectionEnd

Section "Uninstall"
  SetRegView 64
  SetShellVarContext all
  Delete "$SMPROGRAMS\${APPNAME}.lnk"
  Delete "$DESKTOP\${APPNAME}.lnk"
  DeleteRegValue HKLM "Software\RegisteredApplications" "${APPNAME}"
  DeleteRegKey HKLM "Software\Classes\${APPKEY}.Url.mailto"
  DeleteRegKey HKLM "Software\Clients\Mail\${APPNAME}"
  DeleteRegKey HKLM "${UNINSTKEY}"
  ; mail profiles (%APPDATA%\Thunderbird) are the user's and are left alone
  RMDir /r "$INSTDIR"
SectionEnd
