BioShock Infinite - Carry All Guns + Burial at Sea style Weapon Wheel
=====================================================================

What it does
- You can carry every weapon at once (no 2-weapon limit).
- Hold E to open a 13-slot weapon wheel ("SELECT WEAPON"); mouse wheel also cycles weapons.
- Optional hold-to-aim: aim only while the zoom key (Z / middle mouse / thumb button) is held,
  instead of the original toggle. The installer asks; it is on by default.
- Uses only in-game assets.

Requirements
- Windows with PowerShell 5.1 or newer (built in to Windows 10/11).
- BioShock Infinite, Steam version (the installer checks file hashes and refuses to
  touch files that are not the expected stock versions, so nothing gets corrupted).

Install
1. Make sure the game is closed.
2. Extract this zip anywhere.
3. Double-click Install.bat.
   The game folder is found automatically (Steam). If it is not found you are asked for it, or run:
   powershell -ExecutionPolicy Bypass -File Install.ps1 -GameDir "D:\Games\BioShock Infinite"
4. Answer the hold-to-aim question (Y = hold to aim, N = original toggle aim). To skip the question
   add -HoldToAim yes or -HoldToAim no. To change the setting later, run the installer again.

Uninstall
- Double-click Uninstall.bat. The original files are restored from the backup folder
  "BI-AllGuns-WeaponWheel-backup" inside the game folder.
- Or use Steam: right-click the game > Properties > Installed Files > Verify integrity.

How it works
- The installer applies small binary patches
  (data\*.bin) to your copy of BioShockInfinite.exe, Master_P.xxx, Arc_GFxSharedMovies.INT and the
  PCConsoleTOC files, writes a backup first, and checks the SHA-256 of every result.
- A Steam update or "Verify integrity" restores the stock files; run Install.bat again afterwards.
- Do not use with other mods that change the same files.
- The "SELECT WEAPON" title text is added for English only.

Test 2 - center icon correction
- The selected gun icon now fits the enlarged center area and is centered.
- If Test 1 is installed, close the game and run its Uninstall.bat first,
  then run Install.bat from this package. Keep your original backup.
- Installer scripts, executable patches and aiming behavior are unchanged.
- Packaging/install checks passed; visual confirmation in game is still needed.
