#!/usr/bin/env python3
"""
Smart Maniac NPC - Installer
Automatically installs the addon to Garry's Mod addons folder.
Works on Windows, Linux, Mac.
"""
import os
import sys
import shutil
import platform

def find_gmod_addons():
    """Try to find GMod addons folder automatically."""
    system = platform.system()
    paths = []

    if system == "Windows":
        # Try Windows registry first
        try:
            import winreg
            for key_path in [
                r"SOFTWARE\WOW6432Node\Valve\Steam",
                r"SOFTWARE\Valve\Steam",
            ]:
                try:
                    key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, key_path)
                    steam_path = winreg.QueryValueEx(key, "InstallPath")[0]
                    winreg.CloseKey(key)
                    p = os.path.join(steam_path, "steamapps", "common", "GarrysMod", "garrysmod", "addons")
                    if os.path.isdir(p):
                        return p
                    # Check libraryfolders.vdf for other Steam libraries
                    vdf_path = os.path.join(steam_path, "steamapps", "libraryfolders.vdf")
                    if os.path.isfile(vdf_path):
                        try:
                            with open(vdf_path, "r", encoding="utf-8") as f:
                                for line in f:
                                    line = line.strip()
                                    if '"path"' in line:
                                        parts = line.split('"')
                                        if len(parts) >= 4:
                                            lib_path = parts[3].replace("\\\\", "\\")
                                            gmod = os.path.join(lib_path, "steamapps", "common", "GarrysMod", "garrysmod", "addons")
                                            if os.path.isdir(gmod):
                                                return gmod
                        except Exception:
                            pass
                except (FileNotFoundError, OSError):
                    pass
        except ImportError:
            pass

        # Brute force common paths
        for drive in "CDEFGH":
            for steam_dir in [
                f"{drive}:\\Program Files (x86)\\Steam",
                f"{drive}:\\Program Files\\Steam",
                f"{drive}:\\Steam",
                f"{drive}:\\SteamLibrary",
                f"{drive}:\\Games\\Steam",
                f"{drive}:\\Games\\SteamLibrary",
            ]:
                p = os.path.join(steam_dir, "steamapps", "common", "GarrysMod", "garrysmod", "addons")
                if os.path.isdir(p):
                    return p

    elif system == "Linux":
        home = os.path.expanduser("~")
        for p in [
            os.path.join(home, ".steam", "steam", "steamapps", "common", "GarrysMod", "garrysmod", "addons"),
            os.path.join(home, ".local", "share", "Steam", "steamapps", "common", "GarrysMod", "garrysmod", "addons"),
        ]:
            if os.path.isdir(p):
                return p

    elif system == "Darwin":
        home = os.path.expanduser("~")
        p = os.path.join(home, "Library", "Application Support", "Steam", "steamapps", "common", "GarrysMod", "garrysmod", "addons")
        if os.path.isdir(p):
            return p

    return None


def copy_addon(source_dir, target_dir):
    """Copy addon files to target directory."""
    copied = 0
    for folder in ["lua", "materials", "models", "sound", "resource"]:
        src = os.path.join(source_dir, folder)
        dst = os.path.join(target_dir, folder)
        if os.path.isdir(src):
            if os.path.isdir(dst):
                shutil.rmtree(dst)
            shutil.copytree(src, dst)
            file_count = sum(len(files) for _, _, files in os.walk(dst))
            print(f"  [OK] {folder}/ - {file_count} files copied")
            copied += file_count
    return copied


def main():
    print()
    print("=" * 60)
    print("  SMART MANIAC NPC - INSTALLER")
    print("=" * 60)
    print()

    # Find source directory (where this script is located)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    lua_dir = os.path.join(script_dir, "lua")

    if not os.path.isdir(lua_dir):
        print("[ERROR] 'lua' folder not found next to install.py!")
        print(f"  Script location: {script_dir}")
        print()
        print("  Make sure install.py is inside the addon folder")
        print("  that contains the 'lua' folder.")
        input("\nPress Enter to close...")
        sys.exit(1)

    print(f"[OK] Addon found: {script_dir}")
    print()

    # Find GMod
    addons_path = find_gmod_addons()

    if addons_path:
        print(f"[OK] Garry's Mod found: {addons_path}")
    else:
        print("[!] Garry's Mod NOT found automatically.")
        print()
        print("How to find your addons folder:")
        print("  1. Open Steam")
        print("  2. Right-click 'Garry's Mod' -> Properties")
        print("  3. Local Files -> Browse")
        print("  4. Open: garrysmod -> addons")
        print("  5. Copy path from address bar")
        print()
        addons_path = input("Paste addons folder path here: ").strip().strip('"').strip("'")
        print()

        if not addons_path or not os.path.isdir(addons_path):
            print(f"[ERROR] Folder not found: {addons_path}")
            print()
            print("=== MANUAL INSTALL ===")
            print(f"  1. Copy folder: {script_dir}")
            print(f"  2. Paste to: ...\\GarrysMod\\garrysmod\\addons\\")
            print(f"  3. Rename to: gmod-smart-maniac")
            input("\nPress Enter to close...")
            sys.exit(1)

    # Install
    target = os.path.join(addons_path, "gmod-smart-maniac")
    print()
    print(f"Installing to: {target}")
    print()

    # Remove old version
    if os.path.isdir(target):
        print("[*] Removing old version...")
        try:
            shutil.rmtree(target)
        except PermissionError:
            print("[ERROR] Cannot delete old version - files are in use.")
            print("  Close Garry's Mod and try again.")
            input("\nPress Enter to close...")
            sys.exit(1)

    # Create target
    try:
        os.makedirs(target, exist_ok=True)
    except PermissionError:
        print(f"[ERROR] No permission to create: {target}")
        print("  Try running as Administrator.")
        input("\nPress Enter to close...")
        sys.exit(1)

    # Copy files
    print("[*] Copying files...")
    try:
        copied = copy_addon(script_dir, target)
    except PermissionError:
        print("[ERROR] No permission to copy files.")
        print("  Try running as Administrator.")
        input("\nPress Enter to close...")
        sys.exit(1)
    except Exception as e:
        print(f"[ERROR] Failed to copy: {e}")
        input("\nPress Enter to close...")
        sys.exit(1)

    # Copy addon.json if exists
    addon_json = os.path.join(script_dir, "addon.json")
    if os.path.isfile(addon_json):
        shutil.copy2(addon_json, os.path.join(target, "addon.json"))

    # Verify
    check_file = os.path.join(target, "lua", "autorun", "server", "sv_smart_maniac_init.lua")
    print()
    if os.path.isfile(check_file):
        print("=" * 60)
        print("  [OK] SMART MANIAC INSTALLED SUCCESSFULLY!")
        print("=" * 60)
        print()
        print(f"  Installed to: {target}")
        print(f"  Files copied: {copied}")
        print()
        print("  === SETUP IN GARRY'S MOD ===")
        print()
        print("  1. Launch Garry's Mod")
        print("  2. Start a game (Singleplayer or Create Multiplayer)")
        print("  3. Open console (press ~ key)")
        print("  4. Type:")
        print()
        print("     sm_maniac_setup YOUR_OPENROUTER_KEY")
        print()
        print("  5. Get key: https://openrouter.ai/workspaces/default/keys")
        print("  6. Spawn maniac: sm_maniac_spawn")
        print("  7. Walk to maniac and press V to talk!")
        print()
        print("  === COMMANDS ===")
        print()
        print("  sm_maniac_spawn          - spawn maniac")
        print("  sm_maniac_test_openai    - test AI connection")
        print("  sm_maniac_voice_debug    - voice debug info")
        print("  sm_maniac_force_relay 1  - force SSL fix")
        print()
    else:
        print("[ERROR] Installation failed - key files missing.")
        print()
        print("=== MANUAL INSTALL ===")
        print(f"  1. Copy: {script_dir}")
        print(f"  2. To: {addons_path}")
        print(f"  3. Rename to: gmod-smart-maniac")
        print()

    input("Press Enter to close...")


if __name__ == "__main__":
    main()
