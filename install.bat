@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Smart Maniac - Installer
color 0A

echo.
echo ============================================================
echo   SMART MANIAC NPC - INSTALLER
echo ============================================================
echo.

:: Get the directory where this bat file is located (contains lua/ folder)
set "SOURCE_DIR=%~dp0"
if "!SOURCE_DIR:~-1!"=="\" set "SOURCE_DIR=!SOURCE_DIR:~0,-1!"

:: Verify lua folder exists in source
if not exist "!SOURCE_DIR!\lua" (
    echo [ERROR] Folder "lua" not found next to install.bat!
    echo.
    echo Make sure install.bat is inside the addon folder
    echo that contains the "lua" folder.
    echo.
    echo Current location: !SOURCE_DIR!
    echo.
    pause
    exit /b 1
)

echo [OK] Addon files found: !SOURCE_DIR!\lua
echo.

:: ============================================================
:: Try to find GMod automatically
:: ============================================================
set "ADDONS_PATH="

:: Method 1: Check Windows registry for Steam install path
for /f "tokens=2*" %%a in ('reg query "HKLM\SOFTWARE\WOW6432Node\Valve\Steam" /v InstallPath 2^>nul') do set "STEAM_REG=%%b"
if defined STEAM_REG (
    if exist "!STEAM_REG!\steamapps\common\GarrysMod\garrysmod\addons" (
        set "ADDONS_PATH=!STEAM_REG!\steamapps\common\GarrysMod\garrysmod\addons"
        echo [OK] GMod found via registry: !ADDONS_PATH!
        goto :do_install
    )
)
for /f "tokens=2*" %%a in ('reg query "HKLM\SOFTWARE\Valve\Steam" /v InstallPath 2^>nul') do set "STEAM_REG=%%b"
if defined STEAM_REG (
    if exist "!STEAM_REG!\steamapps\common\GarrysMod\garrysmod\addons" (
        set "ADDONS_PATH=!STEAM_REG!\steamapps\common\GarrysMod\garrysmod\addons"
        echo [OK] GMod found via registry: !ADDONS_PATH!
        goto :do_install
    )
)

:: Method 2: Check common paths on all drives
for %%D in (C D E F G H) do (
    if exist "%%D:\Program Files (x86)\Steam\steamapps\common\GarrysMod\garrysmod\addons" (
        set "ADDONS_PATH=%%D:\Program Files (x86)\Steam\steamapps\common\GarrysMod\garrysmod\addons"
        echo [OK] GMod found: !ADDONS_PATH!
        goto :do_install
    )
    if exist "%%D:\Program Files\Steam\steamapps\common\GarrysMod\garrysmod\addons" (
        set "ADDONS_PATH=%%D:\Program Files\Steam\steamapps\common\GarrysMod\garrysmod\addons"
        echo [OK] GMod found: !ADDONS_PATH!
        goto :do_install
    )
    if exist "%%D:\Steam\steamapps\common\GarrysMod\garrysmod\addons" (
        set "ADDONS_PATH=%%D:\Steam\steamapps\common\GarrysMod\garrysmod\addons"
        echo [OK] GMod found: !ADDONS_PATH!
        goto :do_install
    )
    if exist "%%D:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons" (
        set "ADDONS_PATH=%%D:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons"
        echo [OK] GMod found: !ADDONS_PATH!
        goto :do_install
    )
    if exist "%%D:\Games\Steam\steamapps\common\GarrysMod\garrysmod\addons" (
        set "ADDONS_PATH=%%D:\Games\Steam\steamapps\common\GarrysMod\garrysmod\addons"
        echo [OK] GMod found: !ADDONS_PATH!
        goto :do_install
    )
    if exist "%%D:\Games\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons" (
        set "ADDONS_PATH=%%D:\Games\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons"
        echo [OK] GMod found: !ADDONS_PATH!
        goto :do_install
    )
)

:: ============================================================
:: GMod not found - ask user
:: ============================================================
echo [!] GMod not found automatically.
echo.
echo HOW TO FIND YOUR ADDONS FOLDER:
echo   1. Open Steam
echo   2. Right-click "Garry's Mod" in library
echo   3. Click "Properties" then "Local Files" then "Browse"
echo   4. Open folder: garrysmod\addons
echo   5. Copy the path from the address bar
echo.
echo Type the FULL path to your addons folder:
echo.
set /p "ADDONS_PATH=Path: "

:: Remove quotes if user added them
set "ADDONS_PATH=!ADDONS_PATH:"=!"

if not exist "!ADDONS_PATH!" (
    echo.
    echo [ERROR] Folder not found: !ADDONS_PATH!
    echo.
    echo === MANUAL INSTALL ===
    echo   1. Copy this entire folder to your addons:
    echo      !SOURCE_DIR!
    echo   2. Paste into: ...\GarrysMod\garrysmod\addons\
    echo   3. Rename the pasted folder to: gmod-smart-maniac
    echo.
    pause
    exit /b 1
)

:: ============================================================
:: Install
:: ============================================================
:do_install
echo.
set "TARGET=!ADDONS_PATH!\gmod-smart-maniac"

:: Remove old version
if exist "!TARGET!" (
    echo [*] Removing old version...
    rmdir /s /q "!TARGET!" 2>nul
    timeout /t 1 /nobreak >nul
)

:: Create target
mkdir "!TARGET!" 2>nul
if not exist "!TARGET!" (
    echo [ERROR] Cannot create folder: !TARGET!
    echo Try: right-click install.bat - Run as Administrator
    echo.
    pause
    exit /b 1
)

:: Copy files (show output so user sees progress)
echo [*] Copying addon files...
echo.

xcopy "!SOURCE_DIR!\lua" "!TARGET!\lua" /s /e /i /y
if errorlevel 1 (
    echo.
    echo [ERROR] Failed to copy files!
    echo Try: right-click install.bat - Run as Administrator
    echo.
    pause
    exit /b 1
)

:: Copy optional folders
if exist "!SOURCE_DIR!\materials" xcopy "!SOURCE_DIR!\materials" "!TARGET!\materials" /s /e /i /y >nul 2>&1
if exist "!SOURCE_DIR!\models" xcopy "!SOURCE_DIR!\models" "!TARGET!\models" /s /e /i /y >nul 2>&1
if exist "!SOURCE_DIR!\sound" xcopy "!SOURCE_DIR!\sound" "!TARGET!\sound" /s /e /i /y >nul 2>&1
if exist "!SOURCE_DIR!\resource" xcopy "!SOURCE_DIR!\resource" "!TARGET!\resource" /s /e /i /y >nul 2>&1

:: Verify
echo.
if exist "!TARGET!\lua\autorun\server\sv_smart_maniac_init.lua" (
    echo ============================================================
    echo   [OK] SMART MANIAC INSTALLED!
    echo ============================================================
    echo.
    echo   Installed to: !TARGET!
    echo.
    echo   === SETUP IN GARRY'S MOD ===
    echo.
    echo   1. Launch Garry's Mod
    echo   2. Start a game (Create Multiplayer or Singleplayer)
    echo   3. Open console (press ~ key)
    echo   4. Type:
    echo.
    echo      sm_maniac_setup YOUR_OPENROUTER_KEY
    echo.
    echo   5. Get key here: https://openrouter.ai/workspaces/default/keys
    echo   6. Spawn maniac: sm_maniac_spawn
    echo   7. Walk up to maniac and press V to talk!
    echo.
    echo   === COMMANDS ===
    echo.
    echo   sm_maniac_spawn          - spawn maniac
    echo   sm_maniac_test_openai    - test AI connection
    echo   sm_maniac_voice_debug    - voice debug info
    echo   sm_maniac_force_relay 1  - force SSL fix
    echo.
) else (
    echo [ERROR] Installation failed - files not copied.
    echo.
    echo === MANUAL INSTALL ===
    echo   1. Copy this folder: !SOURCE_DIR!
    echo   2. Paste into: !ADDONS_PATH!\
    echo   3. Rename to: gmod-smart-maniac
    echo.
)

echo Press any key to close...
pause >nul
