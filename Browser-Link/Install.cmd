@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem == Configur values below ==
set "APPNAME=My Web App"
set "APPURL=https://example.com"
set "ICONFILE=MyWebApp.ico"   rem must be .ico
rem ====

pushd "%~dp0" || (echo [ERROR] Unable to change to script directory & exit /b 1603)

set "LOGDIR=%ProgramData%\GenericApp"
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1
set "LOG=%LOGDIR%\Install_%DATE:~-4%%DATE:~3,2%%DATE:~0,2%_%TIME::=_%.log"
echo [%DATE% %TIME%] Starting install > "%LOG%"
echo Working dir: %CD% >> "%LOG%"

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\InstallApp.ps1" ^
  -Name "%APPNAME%" -Url "%APPURL%" -IconLocation "%CD%\%ICONFILE%" -UseAppWindow -Verbose ^
  1>>"%LOG%" 2>&1

set "ERR=%ERRORLEVEL%"
echo [%DATE% %TIME%] Finished with exit code %ERR% >> "%LOG%"
popd
exit /b %ERR%