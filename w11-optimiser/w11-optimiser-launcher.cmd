@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "SCRIPT=%SCRIPT_DIR%w11-optimiser.ps1"

if not exist "%SCRIPT%" (
    echo.
    echo ERROR: Could not find w11-optimiser.ps1
    echo Expected it here:
    echo %SCRIPT%
    echo.
    pause
    exit /b 1
)

if /I "%~1"=="audit" goto audit
if /I "%~1"=="preview" goto preview
if /I "%~1"=="safe" goto safe
if /I "%~1"=="x" goto safe
if /I "%~1"=="check" goto check
if /I "%~1"=="postcheck" goto check
if /I "%~1"=="report" goto lastreport
if /I "%~1"=="lastreport" goto lastreport
if /I "%~1"=="undo" goto undo
if /I "%~1"=="help" goto help
if /I "%~1"=="/?" goto help

:menu
set "MENU_MODE=1"
cls
echo.
echo   ================================================================================================================
echo.
echo   W     W  1   1      OOO  PPPP  TTTTT  III  M   M  III   SSS    AAA   TTTTT  III   OOO   N   N
echo   W     W 11  11     O   O P   P   T     I   MM MM   I   S      A   A    T     I   O   O  NN  N
echo   W  W  W  1   1     O   O PPPP    T     I   M M M   I    SSS   AAAAA    T     I   O   O  N N N
echo   W W W W  1   1     O   O P       T     I   M   M   I       S  A   A    T     I   O   O  N  NN
echo    W   W  111 111     OOO  P       T    III  M   M  III   SSS   A   A    T    III   OOO   N   N
echo.
echo                                               by Julian Baumgardt
echo.
echo   ================================================================================================================
echo.
echo   Recommended
echo     X  Apply all safe optimisations ^(recommended^)
echo.
echo   Reports
echo     1  Audit only
echo     4  Post-check report
echo     7  Preview planned changes
echo     8  View last report
echo.
echo   Maintenance
echo     2  Safe optimise ^(skip temp/cache cleanup^)
echo     3  Safe optimise ^(include old temp/cache cleanup^)
echo     5  Undo latest run
echo.
echo   Other
echo     6  Help
echo     0  Exit
echo.
set /p "choice=Choose an option: "

if /I "%choice%"=="X" goto safe
if "%choice%"=="1" goto audit
if "%choice%"=="2" goto safe
if "%choice%"=="3" goto safeclean
if "%choice%"=="4" goto check
if "%choice%"=="5" goto undo
if "%choice%"=="6" goto help
if "%choice%"=="7" goto preview
if "%choice%"=="8" goto lastreport
if "%choice%"=="0" exit /b 0

echo.
echo Please choose X or 0-8.
pause
goto menu

:audit
call :banner "Audit Only"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode Audit
goto done

:preview
call :banner "Preview Planned Changes"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode Preview
goto done

:safe
call :confirm_safe "skip temp/cache cleanup"
if errorlevel 1 goto menu
call :banner "Safe Optimise - Skip Temp Cleanup"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode SafeOptimize -SkipTempCleanup -Force
goto done

:safeclean
call :confirm_safe "include old temp/cache cleanup"
if errorlevel 1 goto menu
call :banner "Safe Optimise - Include Old Temp Cleanup"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode SafeOptimize -Force
goto done

:check
call :banner "Post-Check Report"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode PostCheck
goto done

:lastreport
call :banner "View Last Report"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode OpenLastReport
goto done

:undo
call :confirm_undo
if errorlevel 1 goto menu
call :banner "Undo Latest Run"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode UndoLatest -Force
goto done

:help
cls
echo.
echo W11 Optimiser Launcher
echo ============================
echo.
echo Double-click this file for the menu, or run one of these:
echo.
echo   w11-optimiser-launcher.cmd audit
echo   w11-optimiser-launcher.cmd preview
echo   w11-optimiser-launcher.cmd x
echo   w11-optimiser-launcher.cmd safe
echo   w11-optimiser-launcher.cmd check
echo   w11-optimiser-launcher.cmd report
echo   w11-optimiser-launcher.cmd undo
echo.
echo Generated files go here:
echo.
echo   Desktop\W11 Optimiser
echo.
echo Audit, preview, safe, and check modes open a clean HTML report in your browser.
echo.
echo Safe mode does not disable Defender, Firewall, Windows Update,
echo Memory Integrity, HAGS, services, drivers, vendor GPU software,
echo BIOS settings, overclocking, undervolting, or startup apps.
echo.
goto done

:confirm_safe
cls
echo.
echo   ============================================================
echo      Confirm Safe Optimisation
echo   ============================================================
echo.
echo   This will:
echo     + Create a restore point
echo     + Save local backups before changes
echo     + Tune safe AC power and gaming responsiveness settings
echo     + Keep Defender, Firewall, Windows Update, drivers, services,
echo       BIOS, overclocking, undervolting, and security settings untouched
echo     + Generate a local browser report
echo.
echo   Cleanup mode: %~1
echo   Output folder: Desktop\W11 Optimiser
echo.
set /p "confirm=Continue? (Y/N): "
if /I "%confirm%"=="Y" exit /b 0
if /I "%confirm%"=="YES" exit /b 0
echo.
echo Cancelled. No changes were made.
pause
exit /b 1

:confirm_undo
cls
echo.
echo   ============================================================
echo      Confirm Undo
echo   ============================================================
echo.
echo   This will restore settings from the latest saved W11 Optimiser run.
echo   It uses local backup files from Desktop\W11 Optimiser.
echo.
set /p "confirm=Continue? (Y/N): "
if /I "%confirm%"=="Y" exit /b 0
if /I "%confirm%"=="YES" exit /b 0
echo.
echo Cancelled. No changes were made.
pause
exit /b 1

:banner
cls
echo.
echo   ============================================================
echo      %~1
echo   ============================================================
echo.
exit /b 0

:done
set "LAST_STATUS=%ERRORLEVEL%"
echo.
if "%LAST_STATUS%"=="0" (
    echo Finished. If a report was generated, it should open in your browser.
    echo Files are saved in Desktop\W11 Optimiser.
) else (
    echo Stopped or failed. No further launcher action was taken.
    echo If a report was created, it will be saved in Desktop\W11 Optimiser.
)
echo.
pause
if defined MENU_MODE goto menu
exit /b %LAST_STATUS%
