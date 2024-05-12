@SETLOCAL
@ECHO OFF
CD /D "%~dp0"

SET VERSION=notfound
SET ARCHIVE=
FOR %%f IN ("clink.*.zip") DO (
  FOR /F "tokens=2-4 delims=." %%i IN ("%%f") DO CALL :version "%%i" "%%j" "%%k" "%%f"
)
ECHO/VERSION=%VERSION%
IF %VERSION%==notfound GOTO :NagUser
ECHO/ARCHIVE=%ARCHIVE%

where /q pwsh.exe
IF %ERRORLEVEL% equ 0 (
ECHO ON
pwsh.exe -NoProfile -Ex Unrestricted -Command "Expand-Archive -LiteralPath $env:ARCHIVE -DestinationPath $env:LBPROGRAMS\clink.$env:VERSION -Verbose -Force"
) ELSE (
ECHO ON
powershell.exe -NoProfile -Ex Unrestricted -Command "Expand-Archive -LiteralPath $env:ARCHIVE -DestinationPath $env:LBPROGRAMS\clink.$env:VERSION -Verbose -Force"
)
IF EXIST "%LBPROGRAMS%\clink" RD "%LBPROGRAMS%\clink"
MKLINK /J "%LBPROGRAMS%\clink" "%LBPROGRAMS%\clink.%VERSION%"
@ECHO OFF
@GOTO :NagUser

:version
SET "X=000000000%~1"
SET "Y=000000000%~2"
SET "Z=000000000%~3"
SET "__VERSION=%X:~-8%.%Y:~-8%.%Z:~-8%"
IF %VERSION%==notfound GOTO :update
IF %__VERSION% GTR %_VERSION% GOTO :update
GOTO :EOF

:update
SET "_VERSION=%__VERSION%"
SET "VERSION=%~1.%~2.%~3"
SET "ARCHIVE=%~4"
GOTO :EOF

:NagUser
:: Pause if not interactive
ECHO %cmdcmdline% | FIND /i "%~0" >NUL
IF NOT ERRORLEVEL 1 PAUSE
