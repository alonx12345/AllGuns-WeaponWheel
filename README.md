# BioShock Infinite: Carry All Weapons + Weapon Wheel

Removes the two-weapon carrying limit in BioShock Infinite and adds a Burial at Sea style weapon wheel. Optionally replaces toggle aiming with hold-to-aim.

This public repository contains the installer and binary patch payloads from the mod package, made available for manual security testing by the Nexus Mods support team. Publication is not a security certification or an endorsement by Nexus Mods.

## Features

- Carry every weapon instead of being limited to two.
- Hold **E** to open a 13-slot weapon wheel titled **SELECT WEAPON**.
- Use the mouse wheel to cycle through carried weapons.
- Optionally aim only while the zoom key is held.
- Uses existing in-game assets, with no new art or sounds.

## Requirements

- BioShock Infinite, Steam version, with the stock file versions expected by the installer.
- Windows with PowerShell; PowerShell 5.1 on Windows 11 was used to build the mod.
- Close the game before installing or uninstalling.

The installer checks the hashes of the game files it patches. If your files do not match the expected versions, use Steam's **Verify integrity of game files** before trying again.

## Installation

1. Download `AllGuns-WeaponWheel.zip` from this repository's Releases page.
2. Close the game.
3. Extract the ZIP anywhere; the main game installation directory is convenient.
4. Double-click `Install.bat`.
5. The installer searches Steam libraries for the game, including libraries on other drives. If it cannot find the game, enter the installation path when prompted.
6. At **Enable hold-to-aim? [Y/n]**, choose **Y** for hold-to-aim or **N** to retain toggle aiming.
7. Start the game.

### Test 2: center icon correction

Test 2 fits the selected gun icon to the enlarged center area and centers it
within the wheel. Outer weapon slots, executable patches, and aiming behavior
are unchanged.

**Upgrading from Test 1:** close the game, run the Test 1 uninstaller, then
install Test 2. Do not delete the original backup before uninstalling. The
installer rejects the previous modified package rather than patching it as
though it were stock.

Geometry regression tests, installation, hold-to-aim switching in both
directions, TOC sizes, and full uninstall restoration passed. The corrected
mod was also installed locally and its file hashes verified. In-game visual
confirmation of this correction is still pending.

The original review package remains available under the `review-package`
release; Test 2 is published separately under `test-2-center-icon-fix`.

### Manual game path

Run from the extracted mod folder in Command Prompt:

```bat
powershell -ExecutionPolicy Bypass -File Install.ps1 -GameDir "D:\Games\BioShock Infinite"
```

### Changing the aim option

Run the installer again and choose the other option. To skip the question:

```bat
Install.bat -HoldToAim yes
Install.bat -HoldToAim no
```

## Uninstall

Close the game and double-click `Uninstall.bat`.

Original files are backed up in `BI-AllGuns-WeaponWheel-backup` inside the game folder and restored by the uninstaller. Steam's **Verify integrity of game files** is an alternative way to restore stock game files.

## Compatibility and limitations

- A Steam update or integrity verification can restore the original files; reinstall the mod afterwards.
- The **SELECT WEAPON** title is English only.
- Other mods modifying the same files may be incompatible:
  - `Binaries\Win32\BioShockInfinite.exe`
  - `XGame\CookedPCConsole_FR\Master_P.xxx`
  - `XGame\Localization\INT\Arc_GFxSharedMovies.INT`
  - `XGame\PCConsoleTOC*.txt`
- Please report bugs through this repository's Issues page.

## Package contents and review notes

The repository files match the Test 2 package. Compared with Test 1, only
`data/masterp.bin`, `data/manifest.json`, and the package instructions changed;
the installer scripts and other patch payloads are unchanged.

| File | Purpose |
| --- | --- |
| `Install.bat` | Starts PowerShell with `-NoProfile -ExecutionPolicy Bypass` and forwards installer arguments. |
| `Uninstall.bat` | Starts the same installer with `-Uninstall`. |
| `Install.ps1` | PowerShell installer with embedded C# patching and LZO processing code, compiled locally using `Add-Type`. |
| `data/manifest.json` | Expected input/output SHA-256 hashes, target paths, and patch metadata. |
| `data/exe.bin` | In-place executable patch records. |
| `data/int.bin` | Copy/literal operations for the English localization file. |
| `data/masterp.bin` | Package header edits and copy/literal operations for the weapon-wheel package changes. |
| `README.txt` | Package instructions, including the Test 2 upgrade notes. |

The installer applies patches to the user's own game files; the archive does not include the full game executable or full game packages. It reads the current-user Steam registry entry and Steam library configuration for game detection, creates backups, builds patched results in memory, and verifies expected result hashes before writing. Reviewers should examine both the installer and the binary payloads: readable installer code alone does not establish the safety of executable patches.

The Test 2 release ZIP:

```text
Filename: AllGuns-WeaponWheel.zip
Size: 57970 bytes
SHA-256: 33EBDFD55FEE6A41C78ABE49AE41CE7761D5A6C8F50822B55F2D091D3ABF0008
```

To verify the downloaded archive in PowerShell:

```powershell
Get-FileHash -LiteralPath ".\AllGuns-WeaponWheel.zip" -Algorithm SHA256
```

This repository contains the distributed patcher and payloads, not the original reverse-engineering or patch-generation scripts.

## Development background

The mod author reports that this mod was built with GitHub Copilot in VS Code and reverse engineering:

- Python scripts and Capstone were used to disassemble the game's 32-bit executable and locate weapon-limit logic, input handling, and weapon pickup checks.
- Small in-place machine-code patches implement the carry-limit change, scroll and E-key hooks, hold-to-aim input changes, and the owned-weapon pickup check, using unused space in the executable.
- Changes were tested manually in the game by the mod author.

Those in-game tests have not been independently repeated as part of publishing this repository. Test 2 changes the wheel movie's center-icon fit and placement; it does not change the installer or executable patches.
