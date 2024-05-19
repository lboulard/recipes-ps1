@SETLOCAL EnableExtensions EnableDelayedExpansion
@CHCP 65001 >NUL:
@CD /D "%~dp0"
@IF ERRORLEVEL 1 GOTO :exit

:: check if not admin
@fsutil dirty query %SYSTEMDRIVE% >nul 2>&1
@IF %ERRORLEVEL% EQU 0 (
  @ECHO This script shall run as current user.
  @GOTO :exit
)

::::

:: CMD.EXE /C EXIT 13
:: SET "CR=!=ExitCodeAscii!"

:: Clear end of line and move to first column
@IF NOT DEFINED ANSI_SUPPORT @(
  @SET ANSI_SUPPORT=0
  @FOR /F "usebackq skip=2 tokens=3*" %%a IN (`REG QUERY "HKCU\Console" /v VirtualTerminalLevel 2^>nul`) DO @(
      @SET /A "ANSI_SUPPORT=%%a"
  )
)
@IF "%ANSI_SUPPORT%"=="1" @SET "EOL=[0K[G"
@TYPE NUL>NUL
@SET N=0

::::

:: {{ template }}

::::

:: Last progress line to conclude operations
@CALL :prefix ""
@CALL :log " *DONE* all files processed"

@:: Pause if not interactive
@:exit
@SET ERR=%ERRORLEVEL%
@TYPE NUL>NUL
@ECHO %cmdcmdline% | FIND /i "%~0" >NUL
@IF NOT ERRORLEVEL 1 PAUSE
@ENDLOCAL&EXIT /B %ERR%

@:do
@IF ERRORLEVEL 1 @GOTO :EOF
@CALL :progress " %~3\%~nx2"
@IF EXIST "%~2" @(
  @CALL %~1 "%~2" "%REPO%\%~3\%~nx2" "%~3\%~nx2"
) ELSE @(
  @CALL :log " NOT FOUND %~2"
  @TYPE NUL>NUL
)
@SET /A N=N+1
@GOTO :EOF

@:bcomp
@REM %1:pathname %2:repo absolute path %3:repo relative path
@CALL :modified "%~1" "%~2"
@IF "%MODIFIED%"=="1" @(
  @CALL :log " COMPARE %~1 %~3"
  START BComp.exe "/fv=Text Compare" "%~1" "%~2"
)
@IF ERRORLEVEL 1 @ECHO.ERRORLEVEL=%ERRORLEVEL%
@GOTO :EOF

@:copy
@REM %1:pathname %2:repo absolute path %3:repo relative path
@CALL :modified "%~1" "%~2"
@IF "%MODIFIED%"=="1" @(
  @CALL :log " COPY %~1 %~2"
  @IF "%MODIFIED%"=="1" @(
    @COPY /Y "%~1" "%~32"
  ) ELSE @(
    @ECHO.** ERROR Destination is more recent that source
    @CALL :errorlevel "%MODIFIED%"
  )
)
@GOTO :EOF

@:prefix
@SETLOCAL EnableExtensions EnableDelayedExpansion
@SET ERR=%ERRORLEVEL%
@SET "_n=        %N%"
@SET "_n=%_n:~-4%"
@SET "_a=[ %_n%/%NFILES% ]"
@::IF NOT "%~1"=="" @CALL :padright _a 33
@ENDLOCAL & SET "_prefix=%_a%" & CALL :errorlevel %ERR%
@GOTO :EOF

@:progress
@CALL :prefix "%~1"
@IF "%ANSI_SUPPORT%"=="1" @<NUL SET /P=.%_prefix%%~1%EOL%
@IF "%ANSI_SUPPORT%"=="1" SET "CR=1"
@IF NOT "%ANSI_SUPPORT%"=="1" @ECHO. %_prefix%%~1%EOL%
@GOTO :EOF

@:log
@ECHO. %_prefix%%~1%EOL%
@SET CR=0
@GOTO :EOF

@:modified
@SET MODIFIED=0
@SETLOCAL EnableExtensions EnableDelayedExpansion
@:: When destination file is more recent than source file, shall not copy
@IF EXIST "%~1" @(
  @IF EXIST "%~2" @(
    @FOR /F %%z IN ('DIR /B /O:D "%~1" "%~2"') DO @SET "NEWEST=%%z"
    @IF "%NEWEST%"=="%~2" @(
      @ENDLOCAL&SET MODIFIED=2
      @GOTO :EOF
    )
  )
)
@:: compare files size
@IF NOT "%~z1"=="%~z2" @(
  @ENDLOCAL&SET MODIFIED=1
  @GOTO :EOF
)
@:: compare content
@IF %MODIFIED%==0 @(
  @FC /B "%~1" "%~2" >NUL 2>&1
  @IF ERRORLEVEL 1 @(
    @TYPE NUL>NUL
    @ENDLOCAL&SET MODIFIED=1
    @GOTO :EOF
  )
)
@GOTO :EOF

@:padright
@CALL SET "_pad_orig=%%%~1%%"
@:: 50 space after
@CALL SET "_pad_extend=%%%1%%                                                  "
@CALL SET "%1=%%_pad_extend:~0,%~2%%"
:: restore on truncation
@SET "_pad_dummy=!%1:%_pad_orig%=!"
@IF "%_pad_dummy%"=="!%1!" @CALL SET "%1=%%_pad_orig%%"
@GOTO :EOF

:errorlevel
@EXIT /B %~1
