@echo off

:: --- CONFIGURACIÓN DE ACTUALIZACIÓN ---
set "CURRENT_VERSION=1.0"
set "URL_VERSION=https://tu-servidor.com/version.txt"
set "URL_SCRIPT=https://tu-servidor.com/script.bat"
set "TEMP_SCRIPT=%temp%\update_v!random!.bat"

echo [0/4] Checking for updates (Current: %CURRENT_VERSION%)...

:: Descargar versión remota a una variable
for /f "delims=" %%v in ('curl -s %URL_VERSION%') do set "REMOTE_VERSION=%%v"

:: Comparar versiones
if "%REMOTE_VERSION%" neq "%CURRENT_VERSION%" (
    if defined REMOTE_VERSION (
        echo [!] New version detected: %REMOTE_VERSION%. Downloading...
        
        :: Descargar el nuevo script
        curl -s -o "%~dp0%~n0_new%~x0" "%URL_SCRIPT%"
        
        :: Crear un script temporal para reemplazar el actual y reiniciarlo
        (
            echo @echo off
            echo timeout /t 1 /nobreak ^>nul
            echo del "%~f0"
            echo ren "%~dp0%~n0_new%~x0" "%~nx0"
            echo start "" "%~f0"
            echo del "%%~f0"
        ) > "%TEMP_SCRIPT%"
        
        start /b "" "%TEMP_SCRIPT%"
        exit /b
    )
)
echo [+] Script is up to date.
:: --- FIN DEL BLOQUE DE ACTUALIZACIÓN ---

setlocal enabledelayedexpansion

:: --- CONFIGURATION ---
set "APP_NAME=xiaowei.exe"
set "DEFAULT_PATH=C:\Program Files (x86)\Xiaowei\xiaowei\xiaowei.exe"
set "AUTO_SVC=ch.gridvision.ppam.androidautomagic/ch.gridvision.ppam.androidautomagic.AccessibilityService"
set "CACHE_FILE=%~dp0xiaowei_last_path.txt"

echo [1/4] Detecting application path...

:: 1. Try to detect the path from a running process
set "EXE_PATH="
for /f "delims=" %%a in ('powershell -command "(Get-Process xiaowei -ErrorAction SilentlyContinue).Path" 2^>nul') do (
    set "EXE_PATH=%%a"
)

:: 2. If not running, try to read from the cache file
if not defined EXE_PATH (
    if exist "%CACHE_FILE%" (
        set /p CACHED_VAL=<"%CACHE_FILE%"
        if exist "!CACHED_VAL!" (
            set "EXE_PATH=!CACHED_VAL!"
            echo [+] Using last known path from cache: "!EXE_PATH!"
        )
    )
)

:: 3. If still not found, use the default fallback path
if not defined EXE_PATH (
    if exist "%DEFAULT_PATH%" (
        set "EXE_PATH=%DEFAULT_PATH%"
        echo [i] Process not running. Using default system path.
    ) else (
        echo [!] Warning: Application not found in memory or default folder.
    )
) else (
    if not defined CACHED_VAL echo [+] Detected running process path: "!EXE_PATH!"
)

:: SAVE THE PATH: If we have a valid path, update the cache file
if defined EXE_PATH (
    if exist "!EXE_PATH!" echo !EXE_PATH! > "%CACHE_FILE%"
)

echo.
echo [2/4] Closing processes (End Task)...
taskkill /f /t /im "%APP_NAME%" >nul 2>&1
taskkill /f /im adb.exe >nul 2>&1
timeout /t 2 /nobreak >nul

echo [3/4] Starting ADB configuration...
adb start-server >nul 2>&1

:: Device Loop using subroutine to prevent syntax errors
for /f "tokens=1,2" %%i in ('adb devices ^| findstr /v "List" ^| findstr "device"') do (
    if "%%j"=="device" (
        call :PROCESS_DEVICE %%i
    )
)

goto :FINISH_ADB

:PROCESS_DEVICE
set "ID=%1"
echo.
echo ---------------------------------------
echo Processing device: %ID%

:: 1. MUTE ALL VOLUMES
echo [+] Muting all volumes (Media, Ring, System, Alarm)...
adb -s %ID% shell settings put system volume_music 0 >nul 2>&1
adb -s %ID% shell settings put system volume_ring 0 >nul 2>&1
adb -s %ID% shell settings put system volume_system 0 >nul 2>&1
adb -s %ID% shell settings put system volume_alarm 0 >nul 2>&1
adb -s %ID% shell settings put system mode_ringer 0 >nul 2>&1

:: 2. Accessibility (Append Mode - Preserves App Cloner)
set "CURRENT_SVCS="
for /f "tokens=*" %%a in ('adb -s %ID% shell settings get secure enabled_accessibility_services') do (
    set "CURRENT_SVCS=%%a"
)
echo "!CURRENT_SVCS!" | findstr /C:"%AUTO_SVC%" >nul
if errorlevel 1 (
    if "!CURRENT_SVCS!"=="null" (
        set "NEW_SVCS=%AUTO_SVC%"
    ) else (
        set "TEMP_SVCS=!CURRENT_SVCS:null=!"
        if "!TEMP_SVCS!"=="" ( set "NEW_SVCS=%AUTO_SVC%" ) else ( set "NEW_SVCS=!TEMP_SVCS!:%AUTO_SVC%" )
    )
    adb -s %ID% shell settings put secure accessibility_enabled 1 >nul 2>&1
    adb -s %ID% shell settings put secure enabled_accessibility_services !NEW_SVCS! >nul 2>&1
    echo [+] Automagic Accessibility: ENABLED
) else (
    echo [i] Automagic Accessibility: ALREADY ON
)

:: 3. Keyboard Configuration
set "KEY_ID="
for /f "tokens=1" %%k in ('adb -s %ID% shell "ime list -a | grep mId | cut -d'=' -f2"') do (
    echo %%k | findstr /i "Automagic" >nul
    if !errorlevel! equ 0 ( set "KEY_ID=%%k" )
)
if defined KEY_ID (
    adb -s %ID% shell ime enable !KEY_ID! >nul 2>&1
    adb -s %ID% shell ime set !KEY_ID! >nul 2>&1
    echo [+] Keyboard: !KEY_ID!
)

:: 4. Roaming and AppOps Fixes
adb -s %ID% shell settings put global roaming_reminder_mode_setting 0 >nul 2>&1
adb -s %ID% shell settings put global data_roaming 0 >nul 2>&1
adb -s %ID% shell appops set ch.gridvision.ppam.androidautomagic PROJECT_MEDIA allow >nul 2>&1
adb -s %ID% shell appops set ch.gridvision.ppam.androidautomagic SYSTEM_ALERT_WINDOW allow >nul 2>&1
adb -s %ID% shell dumpsys deviceidle whitelist +ch.gridvision.ppam.androidautomagic >nul 2>&1
echo [+] System fixes applied.
exit /b

:FINISH_ADB
echo.
echo Cleaning up ADB...
taskkill /f /im adb.exe >nul 2>&1

echo.
echo [4/4] Restarting Xiaowei...
if exist "!EXE_PATH!" (
    for %%A in ("!EXE_PATH!") do set "DIR=%%~dpA"
    pushd "!DIR!"
    start "" "%APP_NAME%"
    popd
    echo [OK] Xiaowei started from: "!EXE_PATH!"
) else (
    echo [!] ERROR: Could not find executable to restart.
)

echo.
echo Process finished