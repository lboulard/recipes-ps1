:: https://community.perforce.com/s/article/17304
@SETLOCAL

@SET DIR=p4-2024.3

@IF NOT EXIST %DIR% CD /D %~dp0
@IF "%1"=="uninstall" GOTO :Uninstall

START /WAIT %DIR%\p4vinst64.exe /passive /l p4v.log /norestart^
 REMOVEAPPS=P4V,P4ADMIN,P4 NOINTERNETSHORCUTS

@ENDLOCAL
@GOTO :EOF

@:Uninstall
START /WAIT %DIR%\p4vinst64.exe /uninstall /passive^
 DELETESETTINGS
@ENDLOCAL
