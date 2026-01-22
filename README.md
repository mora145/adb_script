## Description
Batch script to automate Android device setup via adb: mutes volume, enables the Automagic accessibility service, applies `appops` permissions, and restarts the Xiaowei app. Includes self-update from GitHub (uses `version.txt` and replaces the `.bat` when a new version is published).

## Requirements
- Windows with PowerShell and `curl` available (included since Windows 10).
- `adb` installed and available in `PATH` (install Android Platform Tools).
- Xiaowei app installed on target devices.

## Files
- `set_appops.bat`: main script with self-update and adb configuration.
- `version.txt`: version number on GitHub to compare and update the script.

## Quick start
1) Connect one or more Android devices with USB debugging enabled.
2) Run `set_appops.bat` (double-click or from a console). The script:
   - Checks for a new version and self-replaces if needed.
   - Detects the path to `xiaowei.exe` (running process, local cache, or default path).
   - Kills `xiaowei.exe` and `adb.exe`, then restarts the adb server.
   - Iterates each device in `device` state and applies:
     - Music and ring volumes to 0.
     - Enables accessibility service `ch.gridvision.ppam.androidautomagic`.
     - Common tweaks and `appops` permissions for Automagic.
   - Stops adb and relaunches Xiaowei.
3) Check `execution_log.txt` in the same folder if you need to review the run.

## Options and customization
- Update `CURRENT_VERSION` in `set_appops.bat` when publishing a new release (and bump `version.txt` on GitHub).
- Adjust `APP_NAME`, `DEFAULT_PATH`, or `AUTO_SVC` if the app or service changes.
- The script caches the last detected path in `xiaowei_last_path.txt` to avoid asking each time.

## Troubleshooting
- **No devices show up**: run `adb devices` and confirm they are in `device` state; check drivers and cable.
- **Self-update fails**: verify connectivity to GitHub and write permissions in the script folder.
- **`xiaowei.exe` not found**: update `DEFAULT_PATH` or delete `xiaowei_last_path.txt` to force re-detection.
- **Permissions/service not applied**: confirm package `ch.gridvision.ppam.androidautomagic` is installed and debugging is enabled.
