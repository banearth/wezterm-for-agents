@echo off
rem ============================================================
rem  One-click setup for the WezTerm config + snapshot tooling.
rem  Double-click this file to run.
rem
rem  It deploys wezterm.lua to %USERPROFILE%\.wezterm.lua
rem  (backing up any existing one) AND installs the 5-minute
rem  auto-snapshot scheduled task. (Config-only: run
rem  scripts\setup.ps1 -NoTask instead.)
rem
rem  All user-facing messages live in scripts\setup.ps1 so that
rem  non-ASCII text is handled with the right encoding. This .bat
rem  stays ASCII-only on purpose, to run on any Windows codepage.
rem ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup.ps1"
echo.
pause
