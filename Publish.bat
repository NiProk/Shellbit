@echo off
chcp 65001 >nul
setlocal

rem ==================================================================
rem  Publish.bat - собрать программу и упаковать её в архив для раздачи:
rem  dist\Shellbit-<версия>-windows.zip
rem  Просто двойной щелчок.
rem
rem  Версия берётся из project.godot (application/config/version).
rem  Перед новым выпуском поменяйте её там: Проект - Настройки проекта -
rem  Application - Config - Version.
rem ==================================================================

cd /d "%~dp0"
set "ROOT=%CD%"

rem --- 1. Сборка (тот же Build.bat, но без пауз в конце) ---
set "SHELLBIT_QUIET=1"
call "%ROOT%\Build.bat" || goto :fail
cd /d "%ROOT%"

rem --- 2. Версия из project.godot ---
rem Строка там такая: config/version="0.1.0"  - берём то, что после знака =,
rem а %%~v убирает кавычки.
set "VER="
for /f "tokens=2 delims==" %%v in ('findstr /b /c:"config/version=" project.godot') do set "VER=%%~v"
if not defined VER set "VER=dev"

rem --- 3. Архив ---
if not exist dist mkdir dist
if not exist "dist\.gdignore" type nul > "dist\.gdignore"
set "ZIP=dist\Shellbit-%VER%-windows.zip"
if exist "%ZIP%" del "%ZIP%"
echo.
echo === Упаковываю %ZIP% ===
rem Compress-Archive - команда PowerShell, она есть в любой Windows 10/11.
rem В архив попадает папка Shellbit целиком: распаковал - и запускай.
powershell -NoProfile -Command "Compress-Archive -Path 'build\Shellbit' -DestinationPath '%ZIP%'" || goto :fail

echo.
echo === Готово: %ZIP% ===
explorer dist
pause
exit /b 0

:fail
echo.
echo === Выпуск не удался. Скопируйте текст выше и покажите Claude. ===
pause
exit /b 1
