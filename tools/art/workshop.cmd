@echo off
rem Opens the Creator Workshop.  Usage: tools\art\workshop.cmd   |   tools\art\workshop.cmd draw [ids...]
rem Set GODOT=C:\path\to\Godot_v4.3-stable_win64.exe if godot is not on PATH.
setlocal
set PROJECT=%~dp0..\..\godot
if "%GODOT%"=="" set GODOT=godot
if "%1"=="draw" (
  shift
  "%GODOT%" --path "%PROJECT%" -s res://scripts/art/tools/maker_export.gd -- %2 %3 %4 %5 %6 %7 %8 %9
) else (
  "%GODOT%" --path "%PROJECT%" res://scripts/art/workshop/creator_workshop.tscn -- %*
)
exit /b %ERRORLEVEL%
