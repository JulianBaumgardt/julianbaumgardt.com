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
echo   RECOMMENDED
echo     X  SAFE OPTIMISE ^(NO TEMP/CACHE CLEANUP^)
echo.
echo   REPORTS
echo     1  PREVIEW
echo     2  AUDIT
echo     3  POST-CHECK
echo     4  OPEN LAST REPORT
echo.
echo   MAINTENANCE
echo     5  SAFE OPTIMISE + TEMP/CACHE CLEANUP
echo     6  UNDO LATEST RUN
echo.
echo   OTHER
echo     0  EXIT
echo.
set /p "choice=CHOOSE AN OPTION: "

if /I "%choice%"=="X" goto safe
if "%choice%"=="1" goto preview
if "%choice%"=="2" goto audit
if "%choice%"=="3" goto check
if "%choice%"=="4" goto lastreport
if "%choice%"=="5" goto safeclean
if "%choice%"=="6" goto undo
if "%choice%"=="0" exit /b 0

echo.
echo PLEASE CHOOSE X OR 0-6.
pause
goto menu

:audit
call :banner "AUDIT"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode Audit
goto done

:preview
call :banner "PREVIEW"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode Preview
goto done

:safe
call :confirm_safe "NO TEMP/CACHE CLEANUP"
if errorlevel 1 goto menu
call :banner "SAFE OPTIMISE - NO TEMP/CACHE CLEANUP"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode SafeOptimize -SkipTempCleanup -Force
goto done

:safeclean
call :confirm_safe "TEMP/CACHE CLEANUP INCLUDED"
if errorlevel 1 goto menu
call :banner "SAFE OPTIMISE - TEMP/CACHE CLEANUP INCLUDED"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode SafeOptimize -Force
goto done

:check
call :banner "POST-CHECK"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode PostCheck
goto done

:lastreport
call :banner "OPEN LAST REPORT"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode OpenLastReport
goto done

:undo
call :confirm_undo
if errorlevel 1 goto menu
call :banner "UNDO LATEST RUN"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode UndoLatest -Force
goto done

:help
cls
echo.
echo W11 OPTIMISER LAUNCHER
echo ============================
echo.
echo DOUBLE-CLICK THIS FILE FOR THE MENU, OR RUN ONE OF THESE:
echo.
echo   w11-optimiser-launcher.cmd audit
echo   w11-optimiser-launcher.cmd preview
echo   w11-optimiser-launcher.cmd x
echo   w11-optimiser-launcher.cmd safe
echo   w11-optimiser-launcher.cmd check
echo   w11-optimiser-launcher.cmd report
echo   w11-optimiser-launcher.cmd undo
echo.
echo GENERATED FILES GO HERE:
echo.
echo   Desktop\W11 Optimiser
echo.
echo AUDIT, PREVIEW, SAFE, AND CHECK MODES OPEN A CLEAN HTML REPORT IN YOUR BROWSER.
echo.
echo SAFE MODE DOES NOT DISABLE DEFENDER, FIREWALL, WINDOWS UPDATE,
echo MEMORY INTEGRITY, HAGS, SERVICES, DRIVERS, VENDOR GPU SOFTWARE,
echo BIOS SETTINGS, OVERCLOCKING, UNDERVOLTING, OR STARTUP APPS.
echo.
goto done

:confirm_safe
cls
echo.
echo   ============================================================
echo      CONFIRM SAFE OPTIMISE
echo   ============================================================
echo.
echo   YES WILL:
echo     + APPLY ONLY THE SAFE ITEMS LISTED HERE
echo     + CREATE OR VERIFY A RESTORE POINT
echo     + SAVE LOCAL BACKUPS BEFORE CHANGES
echo     + TUNE SAFE AC POWER AND GAMING RESPONSIVENESS SETTINGS
echo     + OPTIMISE ACTIVE PHYSICAL NETWORK ADAPTER POWER SAVING
echo     + GENERATE A LOCAL BROWSER REPORT
echo.
echo   NO WILL:
echo     + CANCEL BEFORE ANY CHANGES ARE MADE
echo.
echo   SAFE BOUNDARY:
echo     + DEFENDER, FIREWALL, WINDOWS UPDATE, DRIVERS, SERVICES,
echo       BIOS, OVERCLOCKING, UNDERVOLTING, HAGS, MEMORY INTEGRITY,
echo       AND STARTUP APPS ARE NOT CHANGED
echo.
echo   CLEANUP: %~1
echo   OUTPUT: DESKTOP\W11 OPTIMISER
echo.
set /p "confirm=CONTINUE? (Y/N): "
if /I "%confirm%"=="Y" exit /b 0
if /I "%confirm%"=="YES" exit /b 0
echo.
echo CANCELLED. NO CHANGES WERE MADE.
pause
exit /b 1

:confirm_undo
cls
echo.
echo   ============================================================
echo      CONFIRM UNDO
echo   ============================================================
echo.
echo   YES WILL RESTORE SETTINGS FROM THE LATEST SAVED W11 OPTIMISER RUN.
echo   NO WILL CANCEL BEFORE ANY CHANGES ARE MADE.
echo   IT USES LOCAL BACKUP FILES FROM DESKTOP\W11 OPTIMISER.
echo.
set /p "confirm=CONTINUE? (Y/N): "
if /I "%confirm%"=="Y" exit /b 0
if /I "%confirm%"=="YES" exit /b 0
echo.
echo CANCELLED. NO CHANGES WERE MADE.
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
    echo DONE. IF A REPORT WAS GENERATED, IT SHOULD OPEN IN YOUR BROWSER.
    echo FILES ARE SAVED IN DESKTOP\W11 OPTIMISER.
) else (
    echo STOPPED OR FAILED. NO FURTHER LAUNCHER ACTION WAS TAKEN.
    echo IF A REPORT WAS CREATED, IT WILL BE SAVED IN DESKTOP\W11 OPTIMISER.
)
echo.
pause
if defined MENU_MODE goto menu
exit /b %LAST_STATUS%
