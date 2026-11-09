@echo off
rem Art pipeline CLI wrapper for Windows.  Usage: tools\art\art.cmd validate
rem Set GODOT=C:\path\to\Godot_v4.3-stable_win64_console.exe if godot is not on PATH.
setlocal
set PROJECT=%~dp0..\..\godot
if "%GODOT%"=="" set GODOT=godot
if "%1"=="test" (
  "%GODOT%" --headless --path "%PROJECT%" -s res://scripts/art/tests/run_art_tests.gd
) else (
  "%GODOT%" --headless --path "%PROJECT%" -s res://scripts/art/tools/art_cli.gd -- %*
)
exit /b %ERRORLEVEL%
