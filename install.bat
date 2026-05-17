@echo off
chcp 65001 >nul 2>&1
title Smart Maniac - Installer
color 0A

echo ============================================================
echo   Smart Maniac NPC - Автоматическая установка
echo ============================================================
echo.

:: Try common Steam paths
set "FOUND_PATH="

:: Check standard Steam paths
if exist "C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\garrysmod\addons" (
    set "FOUND_PATH=C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\garrysmod\addons"
)
if exist "C:\Program Files\Steam\steamapps\common\GarrysMod\garrysmod\addons" (
    set "FOUND_PATH=C:\Program Files\Steam\steamapps\common\GarrysMod\garrysmod\addons"
)
if exist "D:\Steam\steamapps\common\GarrysMod\garrysmod\addons" (
    set "FOUND_PATH=D:\Steam\steamapps\common\GarrysMod\garrysmod\addons"
)
if exist "D:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons" (
    set "FOUND_PATH=D:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons"
)
if exist "E:\Steam\steamapps\common\GarrysMod\garrysmod\addons" (
    set "FOUND_PATH=E:\Steam\steamapps\common\GarrysMod\garrysmod\addons"
)
if exist "E:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons" (
    set "FOUND_PATH=E:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons"
)
if exist "F:\Steam\steamapps\common\GarrysMod\garrysmod\addons" (
    set "FOUND_PATH=F:\Steam\steamapps\common\GarrysMod\garrysmod\addons"
)
if exist "F:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons" (
    set "FOUND_PATH=F:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\addons"
)

if defined FOUND_PATH (
    echo [OK] Garry's Mod найден: %FOUND_PATH%
    echo.
    goto :install
)

:: Not found automatically, ask user
echo [!] Garry's Mod не найден автоматически.
echo.
echo Введите путь к папке addons вашего Garry's Mod:
echo Пример: D:\Steam\steamapps\common\GarrysMod\garrysmod\addons
echo.
set /p "FOUND_PATH=Путь: "

if not exist "%FOUND_PATH%" (
    echo.
    echo [ОШИБКА] Папка не найдена: %FOUND_PATH%
    echo Проверьте путь и попробуйте снова.
    echo.
    pause
    exit /b 1
)

:install
echo Установка Smart Maniac в: %FOUND_PATH%\gmod-smart-maniac
echo.

:: Get the directory where this bat file is located
set "SOURCE_DIR=%~dp0"

:: Remove trailing backslash
if "%SOURCE_DIR:~-1%"=="\" set "SOURCE_DIR=%SOURCE_DIR:~0,-1%"

:: Target directory
set "TARGET_DIR=%FOUND_PATH%\gmod-smart-maniac"

:: Remove old installation if exists
if exist "%TARGET_DIR%" (
    echo [*] Удаляю старую версию...
    rmdir /s /q "%TARGET_DIR%" 2>nul
)

:: Create target directory
mkdir "%TARGET_DIR%" 2>nul

:: Copy addon files
echo [*] Копирую файлы аддона...
xcopy "%SOURCE_DIR%\lua" "%TARGET_DIR%\lua" /s /e /i /q >nul 2>&1
if exist "%SOURCE_DIR%\materials" xcopy "%SOURCE_DIR%\materials" "%TARGET_DIR%\materials" /s /e /i /q >nul 2>&1
if exist "%SOURCE_DIR%\models" xcopy "%SOURCE_DIR%\models" "%TARGET_DIR%\models" /s /e /i /q >nul 2>&1
if exist "%SOURCE_DIR%\sound" xcopy "%SOURCE_DIR%\sound" "%TARGET_DIR%\sound" /s /e /i /q >nul 2>&1
if exist "%SOURCE_DIR%\resource" xcopy "%SOURCE_DIR%\resource" "%TARGET_DIR%\resource" /s /e /i /q >nul 2>&1

:: Verify installation
if exist "%TARGET_DIR%\lua\autorun\server\sv_smart_maniac_init.lua" (
    echo.
    echo ============================================================
    echo   [OK] Smart Maniac успешно установлен!
    echo ============================================================
    echo.
    echo   Путь: %TARGET_DIR%
    echo.
    echo   --- НАСТРОЙКА В GARRY'S MOD ---
    echo.
    echo   1. Запусти Garry's Mod
    echo   2. Открой консоль (~)
    echo   3. Введи команду быстрой настройки:
    echo.
    echo      sm_maniac_setup ТВОЙ_OPENROUTER_КЛЮЧ
    echo.
    echo   4. Получи ключ тут: https://openrouter.ai/workspaces/default/keys
    echo   5. Заспавни маньяка: sm_maniac_spawn
    echo   6. Подойди к маньяку и нажми V чтобы говорить!
    echo.
    echo   --- ДОПОЛНИТЕЛЬНЫЕ КОМАНДЫ ---
    echo.
    echo   sm_maniac_spawn          - заспавнить маньяка
    echo   sm_maniac_test_openai    - тест подключения к ИИ
    echo   sm_maniac_say "текст"    - заставить маньяка сказать фразу
    echo   sm_maniac_voice_debug    - информация о голосовой системе
    echo   sm_maniac_force_relay 1  - включить SSL-фикс (если ИИ не отвечает)
    echo.
) else (
    echo.
    echo [ОШИБКА] Установка не удалась! Файлы не скопировались.
    echo Попробуйте запустить от имени администратора.
    echo.
)

pause
