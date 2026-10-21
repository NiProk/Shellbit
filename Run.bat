@echo off
chcp 65001 >nul
setlocal

rem ==================================================================
rem  Run.bat - запустить Shellbit из проекта, без открытия редактора.
rem  Просто двойной щелчок.
rem ==================================================================

cd /d "%~dp0"
set "ROOT=%CD%"

call "%ROOT%\tools\godot.bat" || goto :fail

rem start "" - запустить и сразу закрыть это окно, не дожидаясь игры.
start "" "%GODOT%" --path "%ROOT%"
exit /b 0

:fail
pause
exit /b 1
