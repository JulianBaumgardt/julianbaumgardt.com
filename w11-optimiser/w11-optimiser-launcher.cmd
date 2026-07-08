@echo off
setlocal EnableExtensions
chcp 65001 >nul

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
echo   ==========================================================================
echo.
echo   █   █   █     █       ███  ████  █████ ███ █   █ ███  ████ █████ ████
echo   █   █  ██    ██      █   █ █   █   █    █  ██ ██  █  █     █     █   █
echo   █ █ █   █     █      █   █ ████    █    █  █ █ █  █   ███  ████  ████
echo   ██ ██   █     █      █   █ █       █    █  █   █  █      █ █     █  █
echo   █   █  ███   ███      ███  █       █   ███ █   █ ███ ████  █████ █   █
echo.
echo                                by Julian Baumgardt
echo.
echo   ==========================================================================
echo.
echo   Recommended
echo.
echo     X  Safe Optimise ^(No Temp/Cache Cleanup^)
echo.
echo   Reports
echo.
echo     1  Preview
echo     2  Audit
echo     3  Post-Check
echo     4  Open Last Report
echo.
echo   Maintenance
echo.
echo     5  Safe Optimise + Temp/Cache Cleanup
echo     6  Undo Latest Run
echo.
echo   Other
echo.
echo     0  Exit
echo.
set /p "choice=Choose An Option: "

if /I "%choice%"=="X" goto safe
if "%choice%"=="1" goto preview
if "%choice%"=="2" goto audit
if "%choice%"=="3" goto check
if "%choice%"=="4" goto lastreport
if "%choice%"=="5" goto safeclean
if "%choice%"=="6" goto undo
if "%choice%"=="0" exit /b 0

echo.
echo Please choose X or 0-6.
pause
goto menu

:audit
call :banner "Audit"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode Audit
goto done

:preview
call :banner "Preview"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode Preview
goto done

:safe
call :confirm_safe "No Temp/Cache Cleanup"
if errorlevel 1 goto menu
call :banner "Safe Optimise - No Temp/Cache Cleanup"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode SafeOptimize -SkipTempCleanup -Force
goto done

:safeclean
call :confirm_safe "Temp/Cache Cleanup Included"
if errorlevel 1 goto menu
call :banner "Safe Optimise - Temp/Cache Cleanup Included"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode SafeOptimize -Force
goto done

:check
call :banner "Post-Check"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode PostCheck
goto done

:lastreport
call :banner "Open Last Report"
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
echo      Confirm Safe Optimise
echo   ============================================================
echo.
echo   Yes Will:
echo.
echo     + Apply only the safe items listed here
echo     + Create or verify a restore point
echo     + Save local backups before changes
echo     + Tune safe AC power and gaming responsiveness settings
echo     + Optimise active physical network adapter power saving
echo     + Generate a local browser report
echo.
echo   No Will:
echo.
echo     + Cancel before any changes are made
echo.
echo   Safe Boundary:
echo.
echo     + Defender, Firewall, Windows Update, drivers, services,
echo       BIOS, overclocking, undervolting, HAGS, Memory Integrity,
echo       and startup apps are not changed
echo.
echo   Cleanup: %~1
echo   Output: Desktop\W11 Optimiser
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
echo   Yes will restore settings from the latest saved W11 Optimiser run.
echo   No will cancel before any changes are made.
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
    echo Done. If a report was generated, it should open in your browser.
    echo Files are saved in Desktop\W11 Optimiser.
) else (
    echo Stopped or failed. No further launcher action was taken.
    echo If a report was created, it will be saved in Desktop\W11 Optimiser.
)
echo.
pause
if defined MENU_MODE goto menu
exit /b %LAST_STATUS%
