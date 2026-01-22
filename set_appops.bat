@echo off
setlocal enabledelayedexpansion

:: --- CONFIGURACIÓN DE ACTUALIZACIÓN ---
set "CURRENT_VERSION=1.5"
set "URL_VERSION=https://raw.githubusercontent.com/mora145/adb_script/refs/heads/main/version.txt"
set "URL_SCRIPT=https://raw.githubusercontent.com/mora145/adb_script/refs/heads/main/set_appops.bat"

echo [0/4] Checking for updates (Current: %CURRENT_VERSION%)...
echo [DEBUG] Current version: "%CURRENT_VERSION%"

:: Obtener versión remota
set "REMOTE_VERSION="
for /f "usebackq delims=" %%v in (`curl -L -k -s "%URL_VERSION%"`) do set "REMOTE_VERSION=%%v"
if defined REMOTE_VERSION set "REMOTE_VERSION=%REMOTE_VERSION: =%"

echo [DEBUG] Remote version: "%REMOTE_VERSION%"

if "%REMOTE_VERSION%" neq "" if "%REMOTE_VERSION%" neq "%CURRENT_VERSION%" (
    echo [!] New version %REMOTE_VERSION% found. Updating...
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
        start /b "" "!TEMP_UPDATER!"
        exit /b
    )
)

:START_SCRIPT
:: --- CONFIGURACIÓN DE APLICACIÓN ---
set "APP_NAME=xiaowei.exe"
set "DEFAULT_PATH=C:\Program Files (x86)\Xiaowei\xiaowei\xiaowei.exe"
set "AUTO_SVC=ch.gridvision.ppam.androidautomagic/ch.gridvision.ppam.androidautomagic.AccessibilityService"
set "CACHE_FILE=%~dp0xiaowei_last_path.txt"

echo [1/4] Detecting application path...

:: 1. Detectar desde proceso activo
set "EXE_PATH="
for /f "delims=" %%a in ('powershell -command "(Get-Process xiaowei -ErrorAction SilentlyContinue).Path" 2^>nul') do (
    set "EXE_PATH=%%a"
)

:: 2. Detectar desde Caché o Ruta por defecto
if not defined EXE_PATH (
    if exist "%CACHE_FILE%" (
        set /p EXE_PATH=<"%CACHE_FILE%"
    ) else if exist "%DEFAULT_PATH%" (
        set "EXE_PATH=%DEFAULT_PATH%"
    )
)

:: Guardar la ruta válida encontrada
if defined EXE_PATH (
    if exist "!EXE_PATH!" (
        echo !EXE_PATH! > "%CACHE_FILE%"
    )
)

echo [2/4] Closing previous processes (End Task)...
taskkill /f /t /im "%APP_NAME%" >nul 2>&1
taskkill /f /im adb.exe >nul 2>&1
timeout /t 2 /nobreak >nul

echo [3/4] Starting ADB configuration...
adb start-server >nul 2>&1

:: Bucle de dispositivos
for /f "tokens=1,2" %%i in ('adb devices ^| findstr /v "List" ^| findstr "device"') do (
    if "%%j"=="device" (
        call :PROCESS_DEVICE %%i
    )
)

goto :FINISH_ADB

:PROCESS_DEVICE
set "ID=%1"
echo ---------------------------------------
echo Processing device: %ID%

:: 1. MUTE ALL VOLUMES
echo [+] Muting all volumes (Media, Ring, System, Alarm)...
adb -s %ID% shell settings put system volume_music 0 >nul 2>&1
adb -s %ID% shell settings put system volume_ring 0 >nul 2>&1
adb -s %ID% shell settings put system volume_system 0 >nul 2>&1
adb -s %ID% shell settings put system volume_alarm 0 >nul 2>&1
adb -s %ID% shell settings put system mode_ringer 0 >nul 2>&1

:: 2. Accesibilidad (Append Mode - Preserva otros servicios)
set "CURR_SVCS="
for /f "tokens=*" %%a in ('adb -s %ID% shell settings get secure enabled_accessibility_services') do (
    set "CURR_SVCS=%%a"
)
echo "!CURR_SVCS!" | findstr /C:"%AUTO_SVC%" >nul
if errorlevel 1 (
    if "!CURR_SVCS!"=="null" (
        set "NEW_SVCS=%AUTO_SVC%"
    ) else (
        set "TEMP_SVCS=!CURR_SVCS:null=!"
        if "!TEMP_SVCS!"=="" (set "NEW_SVCS=%AUTO_SVC%") else (set "NEW_SVCS=!TEMP_SVCS!:%AUTO_SVC%")
    )
    adb -s %ID% shell settings put secure accessibility_enabled 1 >nul 2>&1
    adb -s %ID% shell settings put secure enabled_accessibility_services !NEW_SVCS! >nul 2>&1
    echo [+] Automagic Accessibility: ENABLED
) else (
    echo [i] Automagic Accessibility: ALREADY ON
)

:: 3. Configuración de Teclado
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

:: 4. Roaming y AppOps
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

echo [4/4] Restarting %APP_NAME% and verifying startup...
if exist "!EXE_PATH!" (
    for %%A in ("!EXE_PATH!") do set "DIR=%%~dpA"
    pushd "!DIR!"
    start "" "%APP_NAME%"
    popd

    :: Verificación de inicio
    set "RETRIES=0"
    :CHECK_LOOP
    tasklist /FI "IMAGENAME eq %APP_NAME%" 2>nul | find /I "%APP_NAME%" >nul
    if !errorlevel! equ 0 (
        echo [OK] %APP_NAME% started from: "!EXE_PATH!"
        goto :END
    )
    set /a RETRIES+=1
    if !RETRIES! lss 10 (
        timeout /t 1 /nobreak >nul
        goto :CHECK_LOOP
    )
    echo [!] ERROR: %APP_NAME% failed to start.
) else (
    echo [!] ERROR: Could not find executable to restart.
)

:END
echo.
echo Process finished.
pause