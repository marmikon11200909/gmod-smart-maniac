@echo off
echo.
echo ====================================
echo   SMART MANIAC NPC - INSTALLER
echo ====================================
echo.

:: Try to run Python installer (more reliable)
where python >nul 2>&1
if %errorlevel% equ 0 (
    echo Found Python, running installer...
    python "%~dp0install.py"
    exit /b
)
where python3 >nul 2>&1
if %errorlevel% equ 0 (
    echo Found Python3, running installer...
    python3 "%~dp0install.py"
    exit /b
)
where py >nul 2>&1
if %errorlevel% equ 0 (
    echo Found Python launcher, running installer...
    py "%~dp0install.py"
    exit /b
)

echo Python not found. Using simple copy mode.
echo.
echo Type your GMod addons path.
echo Example: C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\garrysmod\addons
echo.
set /p ADDONS_PATH=Path: 
echo.
echo Copying files...
robocopy "%~dp0lua" "%ADDONS_PATH%\gmod-smart-maniac\lua" /e /is /it >nul
if exist "%~dp0addon.json" copy /y "%~dp0addon.json" "%ADDONS_PATH%\gmod-smart-maniac\addon.json" >nul

if exist "%ADDONS_PATH%\gmod-smart-maniac\lua\autorun\server\sv_smart_maniac_init.lua" (
    echo.
    echo [OK] INSTALLED! 
    echo Path: %ADDONS_PATH%\gmod-smart-maniac
    echo.
    echo In GMod console type:
    echo   sm_maniac_setup YOUR_OPENROUTER_KEY
    echo   sm_maniac_spawn
    echo Then press V near the maniac to talk!
) else (
    echo [ERROR] Copy failed. Try manual install.
)
echo.
pause
