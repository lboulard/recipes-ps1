CALL "%~dp0msys2-silent-install.bat" uninstall
@IF ERRORLEVEL 1 GOTO :NagUser
@GOTO :EOF
@:NagUser
@:: Pause if not interactive
@ECHO %cmdcmdline% | FIND /i "%~0" >NUL
@IF NOT ERRORLEVEL 1 PAUSE