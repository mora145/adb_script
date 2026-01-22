@echo off
setlocal enabledelayedexpansion

:: --- UPDATE CONFIGURATION ---
:: When you want to update all PCs, change this number here AND in version.txt on GitHub.
set "CURRENT_VERSION=1.3"
set "URL_VERSION=https://raw.githubusercontent.com/mora145/adb_script/refs/heads/main/version.txt"
set "URL_SCRIPT=https://raw.githubusercontent.com/mora145/adb_script/refs/heads/main/set_appops.bat"
set "LOG_FILE=%~dp0execution_log.txt"

echo [%date% %time%] --- STARTING EXECUTION v%CURRENT_VERSION% --- >> "%LOG_FILE%"

echo [0/4] Checking for updates...
set "REMOTE_VERSION="
for /f "usebackq delims=" %%v in (`curl -L -k -s "%URL_VERSION%"`) do set "REMOTE_VERSION=%%v"
if defined REMOTE_VERSION set "REMOTE_VERSION=%REMOTE_VERSION: =%"

if "%REMOTE_VERSION%" neq "" if "%REMOTE_VERSION%" neq "%CURRENT_VERSION%" (
    echo [!] New version %REMOTE_VERSION% found. Updating... >> "%LOG_FILE%"
    curl -L -k -s -o "%~dp0%~n0_new%~x0" "%URL_SCRIPT%"
    
    if exist "%~dp0%~n0_new%~x0" (
        set "TEMP_UPDATER=%temp%\updater_!random!.bat"
        (
            echo @echo off
            echo timeout /t 1 /nobreak ^>nul
            echo del /f /q "%~f0"
            echo ren "%~dp0%~n0_new%~x0" "%~nx0"
            echo start "" "%~f0"
            echo del "%%~f0"
        ) > "!TEMP_UPDATER!"
        echo [+] Update downloaded. Restarting script... >> "%LOG_FILE%"
        start /b "" "!TEMP_UPDATER!"
        exit /b
    )
)

:START_SCRIPT
:: --- APP CONFIGURATION ---
set "APP_NAME=xiaowei.exe"
set "DEFAULT_PATH=C:\Program Files (x86)\Xiaowei\xiaowei\xiaowei.exe"
set "AUTO_SVC=ch.gridvision.ppam.androidautomagic/ch.gridvision.ppam.androidautomagic.AccessibilityService"
set "CACHE_FILE=%~dp0xiaowei_last_path.txt"

echo [1/4] Detecting path...
set "EXE_PATH="
for /f "delims=" %%a in ('powershell -command "(Get-Process xiaowei -ErrorAction SilentlyContinue).Path" 2^>nul') do set "EXE_PATH=%%a"

if not defined EXE_PATH (
    if exist "%CACHE_FILE%" (
        set /p EXE_PATH=<"%CACHE_FILE%"
    ) else if exist "%DEFAULT_PATH%" (
        set "EXE_PATH=%DEFAULT_PATH%"
    )
)

if defined EXE_PATH (
    echo !EXE_PATH! > "%CACHE_FILE%"
)

echo [2/4] Killing processes...
taskkill /f /t /im "%APP_NAME%" >nul 2>&1
taskkill /f /im adb.exe >nul 2>&1
timeout /t 2 /nobreak >nul

echo [3/4] Configuring devices...
adb start-server >nul 2>&1

for /f "tokens=1,2" %%i in ('adb devices ^| findstr /v "List" ^| findstr "device"') do (
    if "%%j"=="device" (
        call :PROCESS_DEVICE %%i
    )
)

goto :FINISH_ADB

:PROCESS_DEVICE
set "ID=%1"
echo Processing: %ID%
echo [%date% %time%] Configuring device %ID% >> "%LOG_FILE%"

:: Mute
adb -s %ID% shell settings put system volume_music 0 >nul 2>&1
adb -s %ID% shell settings put system volume_ring 0 >nul 2>&1

:: Accessibility
set "CURR="
for /f "tokens=*" %%a in ('adb -s %ID% shell settings get secure enabled_accessibility_services') do set "CURR=%%a"
echo "!CURR!" | findstr /C:"%AUTO_SVC%" >nul
if errorlevel 1 (
    set "NEW=%CURR:null=%"
    if "!NEW!"=="" (set "NEW=%AUTO_SVC%") else (set "NEW=!NEW!:%AUTO_SVC%")
    adb -s %ID% shell settings put secure accessibility_enabled 1 >nul 2>&1
    adb -s %ID% shell settings put secure enabled_accessibility_services !NEW! >nul 2>&1
)

:: Common Fixes
adb -s %ID% shell settings put global roaming_reminder_mode_setting 0 >nul 2>&1
adb -s %ID% shell appops set ch.gridvision.ppam.androidautomagic PROJECT_MEDIA allow >nul 2>&1
adb -s %ID% shell appops set ch.gridvision.ppam.androidautomagic SYSTEM_ALERT_WINDOW allow >nul 2>&1
exit /b

:FINISH_ADB
taskkill /f /im adb.exe >nul 2>&1
echo [4/4] Restarting app...
if exist "!EXE_PATH!" (
    for %%A in ("!EXE_PATH!") do set "DIR=%%~dpA"
    pushd "!DIR!"
    start "" "%APP_NAME%"
    popd
)
echo [%date% %time%] Execution finished. >> "%LOG_FILE%"
echo.
echo Done.