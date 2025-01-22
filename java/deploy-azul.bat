@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION ENABLEEXTENSIONS
CHCP 65001 >NUL

SET PWSH=PowerShell.exe
where /Q pwsh.exe
IF %ERRORLEVEL% EQU 0 (
  SET PWSH=pwsh.exe
)

IF "%INSTALL_PATH%"=="" SET "INSTALL_PATH=C:\lb\Apps"
IF NOT EXIST "%INSTALL_PATH%\." MD "%INSTALL_PATH%"

ECHO ON

"%PWSH%" -NoProfile -Command^
 "& '.\%~n0.ps1' -InstallPath "%INSTALL_PATH%" -FromPath jre8 -JRE -Arch x86 -OpenFX"
@IF ERRORLEVEL 1 GOTO :exit

"%PWSH%" -NoProfile -Command^
 "& '.\%~n0.ps1' -InstallPath "%INSTALL_PATH%" -FromPath jdk8,jdk11,jdk17 -JDK -Arch amd64 -OpenFX"
@IF ERRORLEVEL 1 GOTO :exit

:exit
@ECHO OFF

SET ERR=%ERRORLEVEL%
IF ERRORLEVEL 1 ECHO ** ERRORLEVEL=%ERRORLEVEL%
TYPE NUL>NUL
ECHO %cmdcmdline% | FIND /i "%~0" >NUL
IF NOT ERRORLEVEL 1 PAUSE
ENDLOCAL&EXIT /B %ERR%
