@SETLOCAL
@CHCP 65001 >NUL
@REM file name shall be RubyXY-silent-install{-default}

@SET "MYSELF=%~n0"
@SET "MAJOR=%MYSELF:~4,1%"
@SET "MINOR=%MYSELF:~5,1%"
@SET "BRANCH=%MAJOR%.%MINOR%"

@SET "TASKS=nomodpath,noassocfiles"
@IF NOT "%MYSELF:-default=%" == "%MYSELF%" (
  @SET "TASKS=modpath,assocfiles"
)
@SET "TASKS=%TASKS%,noridkinstall,defaultutf8"

@CD /D "%~dp0%BRANCH%"
@IF ERRORLEVEL 1 GOTO :exit

:: check if not admin
@fsutil dirty query %SYSTEMDRIVE% >nul 2>&1
@IF %ERRORLEVEL% EQU 0 (
  @ECHO This script shall run as current user.
  @CALL :errorlevel 128
  @GOTO :exit
)


@SET RBINST=
@FOR %%f IN ("rubyinstaller-%BRANCH%.*-x64.exe") DO @SET "RBINST=%%~f"
@ECHO SET RBINST=%RBINST%
@IF NOT DEFINED RBINST (
  @ECHO ** ERROR: No Ruby installation program found
  @CALL :errorlevel 64
  @GOTO :exit
)

@IF NOT EXIST "%LOCALAPPDATA%\lboulard\logs\."^
 MD "%LOCALAPPDATA%\lboulard\logs"
@::IF ERRORLEVEL 1 GOTO :exit

@SET "RBVER=Ruby%MAJOR%%MINOR%"
@SET "DEST=%LBHOME%\%RBVER%-x64"
@CALL :expand "%DEST%"
@SET "DEST=%RETVAL%"

".\%RBINST%" /SILENT /CURRENTUSER ^
 /TASKS="%TASKS%"^
 /LOG="%LOCALAPPDATA%\lboulard\logs\%RBVER%-Install.log"^
 /COMPONENTS=ruby,rdoc^
 /DIR="%DEST%"


@:: Pause if not interactive
@:exit
@SET ERR=%ERRORLEVEL%
@IF ERRORLEVEL 1 @ECHO Failure ERRORLEVEL=%ERRORLEVEL%
@TYPE NUL>NUL
@ECHO %cmdcmdline% | FIND /i "%~0" >NUL
@IF NOT ERRORLEVEL 1 PAUSE
@ENDLOCAL&EXIT /B %ERR%

@:expand
@SET "RETVAL=%~dpf1"
@GOTO :EOF

:errorlevel
@EXIT /B %~1
